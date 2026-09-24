#!/usr/bin/env python3
"""
cka-lab 웹 패널 — exam.sh 를 브라우저에서 돌린다.

  python3 web/server.py                 # 192.168.56.x 를 찾아 8080 으로 띄움
  python3 web/server.py --port 9000
  python3 web/server.py --host 0.0.0.0  # 모든 인터페이스 (주의: 아래)
  python3 web/server.py --no-shell      # 브라우저 터미널 끄기 (문제·채점 패널만)

표준 라이브러리만 쓴다 (pip 설치 없음). 채점은 각 세트의 exam.sh 가 그대로 한다 —
이 서버는 명령을 대신 실행하고 work/.progress · work/.last-check.jsonl 을 읽을 뿐이다.

브라우저 안에 터미널(/ws)이 들어 있다 — 실제 셸이다. 그래서 더더욱,
※ 인증이 없다. 실습 VM 안에서만 띄우고, 공인 IP 나 포트포워딩으로 외부에 열지 않는다.
   (브라우저를 여는 사람이 곧 이 VM 의 셸을 쓰는 사람이 된다)
   공용 환경이라면 --no-shell 로 터미널을 끄고 문제·채점 패널만 쓴다.
"""
import argparse
import base64
import errno
import fcntl
import hashlib
import json
import os
import pty
import re
import select
import signal
import struct
import subprocess
import tempfile
import termios
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))  # practice/
WEB = os.path.join(ROOT, "web")
ANSI = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")

# exam.sh 에 넘길 수 있는 명령 — 화이트리스트
SAFE_CMDS = {"start", "check", "skip", "finish", "status", "clean", "reset", "go"}
DESTRUCTIVE = {"start", "clean", "reset"}  # 진행 기록·클러스터 리소스를 지운다

SHELL_ON = True          # --no-shell 로 끈다
_meta_cache = {}
_job_lock = threading.Lock()   # 클러스터가 하나라 명령도 한 번에 하나씩
_jobs = {}
_job_seq = [0]


# ── 세트 ────────────────────────────────────────────────────────────
def list_sets():
    out = []
    for name in sorted(os.listdir(ROOT)):
        d = os.path.join(ROOT, name)
        if name.startswith((".", "_")) or not os.path.isdir(d):
            continue
        if os.path.isfile(os.path.join(d, "exam.sh")):
            out.append(name)
    return out


def run_exam_stream(set_id, args, job, timeout=900):
    """exam.sh 를 실행하면서 나오는 줄을 그때그때 job["output"] 에 붙인다."""
    d = os.path.join(ROOT, set_id)
    p = subprocess.Popen(["bash", "exam.sh", *args], cwd=d,
                         stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                         text=True, errors="replace", bufsize=1)
    job["proc"] = p
    for line in p.stdout:
        job["output"] += ANSI.sub("", line)
    p.stdout.close()
    return p.wait(timeout=timeout)


def run_exam(set_id, *args, timeout=900):
    """exam.sh 를 실행하고 (rc, 출력) 을 돌려준다."""
    d = os.path.join(ROOT, set_id)
    p = subprocess.run(
        ["bash", "exam.sh", *args], cwd=d, timeout=timeout,
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, errors="replace",
    )
    return p.returncode, ANSI.sub("", p.stdout)


def meta(set_id):
    """세트 제목·문항수·단위·문제 제목. exam.sh 가 바뀌면 다시 읽는다."""
    path = os.path.join(ROOT, set_id, "exam.sh")
    stamp = os.path.getmtime(path)
    hit = _meta_cache.get(set_id)
    if hit and hit[0] == stamp:
        return hit[1]
    rc, out = run_exam(set_id, "meta", timeout=30)
    m = {"id": set_id, "title": set_id, "nq": 0, "unit": "항목",
         "titles": {}, "titlesKo": {}, "hasHint": {}, "hasKo": {}}
    for line in out.splitlines():
        if "=" not in line:
            continue
        k, v = line.split("=", 1)
        if k == "title":
            m["title"] = v
        elif k == "nq":
            m["nq"] = int(v or 0)
        elif k == "unit":
            m["unit"] = v
        elif k.endswith("_title") and k.startswith("q"):
            m["titles"][k[1:-6]] = v
        elif k.endswith("_titleKo") and k.startswith("q"):
            m["titlesKo"][k[1:-8]] = v
        elif k.endswith("_hasKo"):
            m["hasKo"][k[1:-6]] = True
        elif k.endswith("_hasHint"):
            m["hasHint"][k[1:-8]] = True
    _meta_cache[set_id] = (stamp, m)
    return m


def progress(set_id):
    """work/.progress 를 key=value 로 읽는다."""
    path = os.path.join(ROOT, set_id, "work", ".progress")
    d = {}
    if os.path.isfile(path):
        for line in open(path, encoding="utf-8", errors="replace"):
            if "=" in line:
                k, v = line.rstrip("\n").split("=", 1)
                d[k] = v
    return d


def last_items(set_id):
    """직전 채점의 항목별 결과. 첫 줄의 {"q":N} 으로 몇 번 문제 것인지 구분한다."""
    path = os.path.join(ROOT, set_id, "work", ".last-check.jsonl")
    items, qn = [], 0
    if os.path.isfile(path):
        for line in open(path, encoding="utf-8", errors="replace"):
            line = line.strip()
            if not line:
                continue
            try:
                o = json.loads(line)
            except ValueError:
                continue
            if "q" in o and "desc" not in o:
                qn = int(o["q"])
            else:
                items.append(o)
    return qn, items


def state(set_id, lang="en"):
    lang = "ko" if lang == "ko" else "en"
    m = meta(set_id)
    pr = progress(set_id)
    nq = m["nq"]
    cur = int(pr.get("current") or 0)
    rows, sum_p, sum_t = [], 0, 0
    for i in range(1, nq + 1):
        rec = pr.get(f"q{i}")
        row = {
            "n": i,
            "title": (m["titlesKo"] if lang == "ko" else m["titles"]).get(str(i))
                     or m["titles"].get(str(i), ""),
            "pass": None, "total": None, "elapsed": None,
            "tries": int(pr.get(f"q{i}_tries") or 0),
            "skipped": bool(pr.get(f"q{i}_skipped")),
            "hint": bool(pr.get(f"q{i}_hint")),
            "current": i == cur,
        }
        if rec:
            head, _, el = rec.partition(":")
            p, _, t = head.partition("/")
            row["pass"], row["total"], row["elapsed"] = int(p), int(t), int(el or 0)
            sum_p += row["pass"]
            sum_t += row["total"]
        rows.append(row)

    items_q, items = last_items(set_id)
    st = {
        "id": set_id, "title": m["title"], "nq": nq, "unit": m["unit"],
        "current": cur, "rows": rows, "sum": sum_p, "total": sum_t,
        "started": int(pr.get("started") or 0),
        "finished": int(pr.get("finished") or 0),
        "done": bool(cur and cur > nq),
        "hasHint": bool(m["hasHint"].get(str(cur))),
        "items": items if items_q == cur else [],   # 지난 문제의 결과는 보여주지 않는다
        "lang": lang,
        "hasKo": bool(m["hasKo"].get(str(cur))),
        "now": int(time.time()),
    }
    if cur and cur <= nq:
        rc, out = run_exam(set_id, "qtext", str(cur), lang, timeout=30)
        title, _, body = out.partition("---8<---")
        st["question"] = {"n": cur, "title": title.strip(), "body": body.strip("\n")}
    return st


# ── 작업(job) — 오래 걸리는 명령을 백그라운드로 ──────────────────────
def start_job(set_id, cmd, arg=None):
    with _job_lock:
        for j in _jobs.values():
            if not j["done"]:
                return None, "이미 실행 중인 명령이 있습니다 (%s %s)" % (j["set"], j["cmd"])
        _job_seq[0] += 1
        jid = _job_seq[0]
        job = {"id": jid, "set": set_id, "cmd": cmd, "arg": arg, "output": "",
               "done": False, "rc": None, "started": time.time()}
        _jobs[jid] = job

    def work():
        try:
            args = ["hinttext"] if cmd == "hint" else ([cmd, arg] if arg else [cmd])
            job["rc"] = run_exam_stream(set_id, args, job)
        except subprocess.TimeoutExpired:
            job["rc"], job["output"] = -1, "시간 초과 — 터미널에서 직접 확인하세요."
        except Exception as e:  # noqa: BLE001
            job["rc"], job["output"] = -1, "실행 실패: %s" % e
        finally:
            job["done"] = True

    threading.Thread(target=work, daemon=True).start()
    return jid, None


# ── 브라우저 터미널 (WebSocket + PTY, 표준 라이브러리만) ─────────────
WS_GUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"


def ws_accept(key):
    return base64.b64encode(hashlib.sha1((key + WS_GUID).encode()).digest()).decode()


def ws_frame(payload, opcode=0x2):
    """서버 → 브라우저 프레임 (마스킹 없음)."""
    n = len(payload)
    head = bytes([0x80 | opcode])
    if n < 126:
        head += bytes([n])
    elif n < 65536:
        head += bytes([126]) + struct.pack(">H", n)
    else:
        head += bytes([127]) + struct.pack(">Q", n)
    return head + payload


def ws_parse(buf):
    """브라우저 → 서버 프레임을 꺼낸다. (frames, 남은 버퍼)"""
    out = []
    while True:
        if len(buf) < 2:
            return out, buf
        b0, b1 = buf[0], buf[1]
        opcode = b0 & 0x0F
        masked = b1 & 0x80
        ln = b1 & 0x7F
        i = 2
        if ln == 126:
            if len(buf) < i + 2:
                return out, buf
            ln = struct.unpack(">H", buf[i:i + 2])[0]; i += 2
        elif ln == 127:
            if len(buf) < i + 8:
                return out, buf
            ln = struct.unpack(">Q", buf[i:i + 8])[0]; i += 8
        if masked:
            if len(buf) < i + 4:
                return out, buf
            mask = buf[i:i + 4]; i += 4
        if len(buf) < i + ln:
            return out, buf
        data = bytearray(buf[i:i + ln])
        if masked:
            for k in range(ln):
                data[k] ^= mask[k % 4]
        out.append((opcode, bytes(data)))
        buf = buf[i + ln:]


def set_winsize(fd, rows, cols):
    try:
        fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))
    except Exception:  # noqa: BLE001
        pass


def serve_shell(handler, cwd, set_id=""):
    """브라우저와 셸(PTY)을 연결한다. 이 연결이 끊기면 셸도 끝난다."""
    key = handler.headers.get("Sec-WebSocket-Key")
    if not key:
        return handler._send(400, "websocket only", "text/plain; charset=utf-8")
    handler.connection.sendall((
        "HTTP/1.1 101 Switching Protocols\r\n"
        "Upgrade: websocket\r\n"
        "Connection: Upgrade\r\n"
        "Sec-WebSocket-Accept: %s\r\n\r\n" % ws_accept(key)).encode())

    # 패널이 고른 세트를 적어 두는 파일 — 셸이 프롬프트마다 읽어 따라간다
    ptr = tempfile.NamedTemporaryFile("w", prefix="cka-set-", delete=False)
    ptr.write(set_id); ptr.close()

    pid, fd = pty.fork()
    if pid == 0:                                   # 자식 — 셸이 된다
        try:
            os.chdir(cwd)
        except Exception:  # noqa: BLE001
            pass
        os.environ["TERM"] = "xterm-256color"
        os.environ["CKA_SET_FILE"] = ptr.name
        os.environ["CKA_ROOT"] = ROOT
        rc = os.path.join(ROOT, "_lib", "exam-shellrc.sh")   # 자동완성·alias k·$do
        try:
            if os.path.isfile(rc):
                os.execvp("bash", ["bash", "--rcfile", rc, "-i"])
            os.execvp("bash", ["bash", "-l"])
        except Exception:  # noqa: BLE001
            os.execvp("/bin/sh", ["/bin/sh"])
        os._exit(1)

    sock = handler.connection
    sock.settimeout(None)
    buf = b""
    try:
        while True:
            r, _, _ = select.select([fd, sock], [], [], 60)
            if fd in r:
                try:
                    data = os.read(fd, 65536)
                except OSError:
                    break
                if not data:
                    break
                sock.sendall(ws_frame(data))
            if sock in r:
                try:
                    chunk = sock.recv(65536)
                except OSError:
                    break
                if not chunk:
                    break
                buf += chunk
                frames, buf = ws_parse(buf)
                for op, payload in frames:
                    if op == 0x8:                  # close
                        raise StopIteration
                    if op == 0x9:                  # ping
                        sock.sendall(ws_frame(payload, 0xA))
                    elif op == 0x1:                # text = 제어 (창 크기 · 세트 이동)
                        try:
                            m = json.loads(payload.decode("utf-8", "replace"))
                            if "r" in m:
                                set_winsize(fd, int(m.get("r", 24)), int(m.get("c", 80)))
                            if m.get("cd") in list_sets():
                                with open(ptr.name, "w") as f:
                                    f.write(m["cd"])
                                # 셸이 놀고 있고 입력 중인 줄도 없으면 빈 엔터로 즉시 반영
                                if m.get("idle") and os.tcgetpgrp(fd) == pid:
                                    os.write(fd, b"\n")
                        except Exception:  # noqa: BLE001
                            pass
                    else:                          # binary = 키 입력
                        os.write(fd, payload)
    except (StopIteration, BrokenPipeError, ConnectionResetError, OSError):
        pass
    finally:
        try:
            os.close(fd)
        except OSError:
            pass
        try:
            os.unlink(ptr.name)
        except OSError:
            pass
        for sig in (signal.SIGHUP, signal.SIGKILL):
            try:
                os.kill(pid, sig)
            except OSError:
                break
            time.sleep(0.1)
            if os.waitpid(pid, os.WNOHANG)[0]:
                break
        try:
            os.waitpid(pid, os.WNOHANG)
        except OSError:
            pass
        handler.close_connection = True


# ── HTTP ────────────────────────────────────────────────────────────
class Handler(BaseHTTPRequestHandler):
    server_version = "cka-lab-panel"

    def log_message(self, fmt, *args):   # 접속 로그는 조용히
        pass

    def _send(self, code, body, ctype="application/json; charset=utf-8"):
        data = body if isinstance(body, bytes) else body.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data)

    def _json(self, obj, code=200):
        self._send(code, json.dumps(obj, ensure_ascii=False))

    def _set_param(self, q):
        s = (q.get("set") or [""])[0]
        if s not in list_sets():
            return None
        return s

    def do_GET(self):
        u = urlparse(self.path)
        q = parse_qs(u.query)
        try:
            if u.path == "/ws":
                if not SHELL_ON:
                    return self._send(403, "터미널이 꺼져 있습니다 (--no-shell)", "text/plain; charset=utf-8")
                s = self._set_param(q)
                return serve_shell(self, os.path.join(ROOT, s) if s else ROOT, s or "")
            if u.path.startswith("/vendor/"):
                name = os.path.basename(u.path)
                path = os.path.join(WEB, "vendor", name)
                if not os.path.isfile(path):
                    return self._send(404, "not found", "text/plain; charset=utf-8")
                ctype = "text/css; charset=utf-8" if name.endswith(".css") else "application/javascript; charset=utf-8"
                with open(path, "rb") as f:
                    return self._send(200, f.read(), ctype)
            if u.path == "/api/config":
                return self._json({"shell": SHELL_ON})
            if u.path in ("/", "/index.html"):
                with open(os.path.join(WEB, "app.html"), "rb") as f:
                    return self._send(200, f.read(), "text/html; charset=utf-8")
            if u.path == "/api/sets":
                out = []
                for s in list_sets():
                    m = meta(s)
                    pr = progress(s)
                    cur = int(pr.get("current") or 0)
                    out.append({"id": s, "title": m["title"], "nq": m["nq"],
                                "unit": m["unit"], "current": cur,
                                "running": bool(cur and cur <= m["nq"]),
                                "done": bool(cur and cur > m["nq"])})
                return self._json(out)
            if u.path == "/api/state":
                s = self._set_param(q)
                if not s:
                    return self._json({"error": "알 수 없는 세트"}, 404)
                return self._json(state(s, (q.get("lang") or ["en"])[0]))
            if u.path == "/api/job":
                jid = int((q.get("id") or ["0"])[0])
                j = _jobs.get(jid)
                if not j:
                    return self._json({"error": "없는 작업"}, 404)
                # wait=1 이면 새 출력이 생기거나 작업이 끝날 때까지 기다렸다 답한다
                if (q.get("wait") or ["0"])[0] == "1":
                    since = int((q.get("since") or ["0"])[0])
                    deadline = time.time() + 20
                    while (not j["done"] and len(j["output"]) <= since
                           and time.time() < deadline):
                        time.sleep(0.04)
                return self._json({k: j[k] for k in ("id", "set", "cmd", "output", "done", "rc")})
            return self._send(404, "not found", "text/plain; charset=utf-8")
        except Exception as e:  # noqa: BLE001
            return self._json({"error": str(e)}, 500)

    def do_POST(self):
        u = urlparse(self.path)
        if u.path != "/api/run":
            return self._send(404, "not found", "text/plain; charset=utf-8")
        try:
            n = int(self.headers.get("Content-Length") or 0)
            body = json.loads(self.rfile.read(n) or b"{}")
            s, cmd = body.get("set"), body.get("cmd")
            if s not in list_sets():
                return self._json({"error": "알 수 없는 세트"}, 400)
            if cmd not in SAFE_CMDS | {"hint"}:
                return self._json({"error": "허용되지 않은 명령"}, 400)
            if cmd in DESTRUCTIVE and not body.get("confirm"):
                return self._json({"error": "확인이 필요한 명령입니다"}, 400)
            arg = None
            if cmd == "go":                      # 문제 번호로 이동
                try:
                    n = int(body.get("arg"))
                except (TypeError, ValueError):
                    return self._json({"error": "문제 번호가 필요합니다"}, 400)
                if not 1 <= n <= max(1, meta(s)["nq"]):
                    return self._json({"error": "범위 밖의 문제 번호"}, 400)
                arg = str(n)
            jid, err = start_job(s, cmd, arg)
            if err:
                return self._json({"error": err}, 409)
            return self._json({"job": jid})
        except Exception as e:  # noqa: BLE001
            return self._json({"error": str(e)}, 500)


def guess_host():
    """VirtualBox 호스트온리(192.168.56.x) 주소를 찾는다."""
    try:
        out = subprocess.run(["ip", "-4", "-o", "addr"], stdout=subprocess.PIPE,
                             text=True, timeout=5).stdout
        m = re.search(r"\b(192\.168\.56\.\d+)\b", out)
        if m:
            return m.group(1)
    except Exception:  # noqa: BLE001
        pass
    return "0.0.0.0"


def port_owner(port):
    """그 포트를 듣고 있는 (pid, 명령이름) — 못 찾으면 (None, None)."""
    for cmd in (["ss", "-ltnp"], ["netstat", "-ltnp"],
                ["lsof", "-nP", "-iTCP:%d" % port, "-sTCP:LISTEN"]):
        try:
            out = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                                 text=True, timeout=5).stdout
        except Exception:  # noqa: BLE001
            continue
        for line in out.splitlines():
            if not re.search(r"[:.]%d\b" % port, line):
                continue
            m = re.search(r'\("([^"]+)",pid=(\d+)', line)     # ss:      ("python3",pid=123
            if m:
                return int(m.group(2)), m.group(1)
            m = re.search(r"\s(\d+)/(\S+)\s*$", line)         # netstat: 123/python3
            if m:
                return int(m.group(1)), m.group(2)
            m = re.match(r"(\S+)\s+(\d+)\s", line)            # lsof:    Python 123 ...
            if m and m.group(2).isdigit() and "LISTEN" in line:
                return int(m.group(2)), m.group(1)
    return None, None


def is_our_panel(pid):
    """그 프로세스가 이 패널 서버인가 (엉뚱한 것을 죽이지 않으려고 확인)."""
    cmd = ""
    try:
        with open("/proc/%d/cmdline" % pid, "rb") as f:
            cmd = f.read().decode(errors="replace").replace("\0", " ")
    except OSError:                                   # /proc 이 없는 환경(macOS 등)
        try:
            cmd = subprocess.run(["ps", "-p", str(pid), "-o", "args="],
                                 stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                                 text=True, timeout=5).stdout
        except Exception:  # noqa: BLE001
            return False
    return "server.py" in cmd and "python" in cmd.lower()


def bind_or_explain(host, port, shown, replace):
    """포트가 이미 쓰이고 있으면 무엇을 하면 되는지 알려 주고 끝낸다."""
    try:
        return ThreadingHTTPServer((host, port), Handler)
    except OSError as e:
        if e.errno != errno.EADDRINUSE:
            raise
    pid, name = port_owner(port)
    if replace and pid and is_our_panel(pid):
        print("%d 번 포트의 이전 패널(pid %d)을 종료합니다." % (port, pid))
        try:
            os.kill(pid, signal.SIGTERM)
        except OSError as e:  # noqa: BLE001
            print("  종료 실패: %s" % e)
        else:
            for _ in range(20):                    # 최대 2초 기다린다
                time.sleep(0.1)
                try:
                    return ThreadingHTTPServer((host, port), Handler)
                except OSError:
                    continue
        print("  포트가 풀리지 않았습니다.")

    print("%d 번 포트를 이미 누가 쓰고 있습니다." % port)
    if pid:
        print("  쓰는 프로세스: %s (pid %d)%s"
              % (name or "?", pid, " — 이 패널 서버입니다" if is_our_panel(pid) else ""))
    print()
    if pid and is_our_panel(pid):
        print("  패널이 이미 떠 있습니다. 브라우저에서 그냥 여세요:")
        print("      http://%s:%d" % (shown, port))
        print("  다시 띄우고 싶으면:   python3 web/server.py --replace")
    else:
        print("  다른 프로그램이 쓰고 있습니다. 포트를 바꿔 띄우세요:")
        print("      python3 web/server.py --port %d" % (port + 1))
    raise SystemExit(1)


def main():
    ap = argparse.ArgumentParser(description="cka-lab 웹 패널")
    ap.add_argument("--host", default=None, help="바인드 주소 (기본: 192.168.56.x 자동 탐지)")
    ap.add_argument("--port", type=int, default=8080)
    ap.add_argument("--no-shell", action="store_true", help="브라우저 터미널 끄기")
    ap.add_argument("--replace", action="store_true",
                    help="같은 포트에 이미 떠 있는 패널을 종료하고 새로 띄운다")
    a = ap.parse_args()
    global SHELL_ON
    SHELL_ON = not a.no_shell
    host = a.host or guess_host()
    shown = host if host != "0.0.0.0" else guess_host()
    srv = bind_or_explain(host, a.port, shown, a.replace)
    print("cka-lab 웹 패널")
    print("  주소   http://%s:%d   ← 맥/윈도우 브라우저에서 열기" % (shown, a.port))
    print("  세트   %s" % ", ".join(list_sets()))
    print("  터미널 %s" % ("브라우저 안에 있음 (실제 셸)" if SHELL_ON else "꺼짐 (--no-shell)"))
    print("  주의   인증이 없습니다. 실습 VM 안에서만 쓰고 외부에 열지 마세요.")
    print("  종료   Ctrl+C")
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        print("\n종료합니다.")


if __name__ == "__main__":
    main()
