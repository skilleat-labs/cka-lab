#!/usr/bin/env python3
"""
cka-lab 웹 패널 — exam.sh 를 브라우저에서 돌린다.

  python3 web/server.py                 # 192.168.56.x 를 찾아 8080 으로 띄움
  python3 web/server.py --port 9000
  python3 web/server.py --host 0.0.0.0  # 모든 인터페이스 (주의: 아래)

표준 라이브러리만 쓴다 (pip 설치 없음). 채점은 각 세트의 exam.sh 가 그대로 한다 —
이 서버는 명령을 대신 실행하고 work/.progress · work/.last-check.jsonl 을 읽을 뿐이다.

※ 인증이 없다. 실습 VM 안에서만 띄우고, 공인 IP 나 포트포워딩으로 외부에 열지 않는다.
   (채점 스크립트는 클러스터를 바꾸는 명령을 실행한다)
"""
import argparse
import json
import os
import re
import subprocess
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))  # practice/
WEB = os.path.join(ROOT, "web")
ANSI = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")

# exam.sh 에 넘길 수 있는 명령 — 화이트리스트
SAFE_CMDS = {"start", "check", "skip", "finish", "status", "clean", "reset"}
DESTRUCTIVE = {"start", "clean", "reset"}  # 진행 기록·클러스터 리소스를 지운다

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
    m = {"id": set_id, "title": set_id, "nq": 0, "unit": "항목", "titles": {}, "hasHint": {}}
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


def state(set_id):
    m = meta(set_id)
    pr = progress(set_id)
    nq = m["nq"]
    cur = int(pr.get("current") or 0)
    rows, sum_p, sum_t = [], 0, 0
    for i in range(1, nq + 1):
        rec = pr.get(f"q{i}")
        row = {
            "n": i, "title": m["titles"].get(str(i), ""),
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
        "now": int(time.time()),
    }
    if cur and cur <= nq:
        rc, out = run_exam(set_id, "qtext", str(cur), timeout=30)
        title, _, body = out.partition("---8<---")
        st["question"] = {"n": cur, "title": title.strip(), "body": body.strip("\n")}
    return st


# ── 작업(job) — 오래 걸리는 명령을 백그라운드로 ──────────────────────
def start_job(set_id, cmd):
    with _job_lock:
        for j in _jobs.values():
            if not j["done"]:
                return None, "이미 실행 중인 명령이 있습니다 (%s %s)" % (j["set"], j["cmd"])
        _job_seq[0] += 1
        jid = _job_seq[0]
        job = {"id": jid, "set": set_id, "cmd": cmd, "output": "",
               "done": False, "rc": None, "started": time.time()}
        _jobs[jid] = job

    def work():
        try:
            args = ["hinttext"] if cmd == "hint" else [cmd]
            rc, out = run_exam(set_id, *args)
            job["rc"], job["output"] = rc, out
        except subprocess.TimeoutExpired:
            job["rc"], job["output"] = -1, "시간 초과 — 터미널에서 직접 확인하세요."
        except Exception as e:  # noqa: BLE001
            job["rc"], job["output"] = -1, "실행 실패: %s" % e
        finally:
            job["done"] = True

    threading.Thread(target=work, daemon=True).start()
    return jid, None


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
                return self._json(state(s))
            if u.path == "/api/job":
                jid = int((q.get("id") or ["0"])[0])
                j = _jobs.get(jid)
                if not j:
                    return self._json({"error": "없는 작업"}, 404)
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
            jid, err = start_job(s, cmd)
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


def main():
    ap = argparse.ArgumentParser(description="cka-lab 웹 패널")
    ap.add_argument("--host", default=None, help="바인드 주소 (기본: 192.168.56.x 자동 탐지)")
    ap.add_argument("--port", type=int, default=8080)
    a = ap.parse_args()
    host = a.host or guess_host()
    srv = ThreadingHTTPServer((host, a.port), Handler)
    shown = host if host != "0.0.0.0" else guess_host()
    print("cka-lab 웹 패널")
    print("  주소   http://%s:%d   ← 맥/윈도우 브라우저에서 열기" % (shown, a.port))
    print("  세트   %s" % ", ".join(list_sets()))
    print("  주의   인증이 없습니다. 실습 VM 안에서만 쓰고 외부에 열지 마세요.")
    print("  종료   Ctrl+C")
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        print("\n종료합니다.")


if __name__ == "__main__":
    main()
