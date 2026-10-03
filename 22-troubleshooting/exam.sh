#!/usr/bin/env bash
# CKA 22강 실습 — 트러블슈팅 (순차 진행형)
set -uo pipefail
source "$(cd "$(dirname "$0")/.." && pwd)/_lib/exam-lib.sh"

EXAM_TITLE="CKA 22강 실습 — 트러블슈팅 (CrashLoop · ImagePull · Endpoints · 노드 · 컨트롤플레인)"
EXAM_NQ=6

exam_cleanup() {
  kdel pod broken-pod fixed-pod pull-fail -n default
  kdel deployment target-app -n default
  kdel service target-svc -n default
  kdel pod -l cka-lab=q19-sched -n default
  kdel pod sched-test -n default
  echo "  broken-pod / fixed-pod / pull-fail / target-app / target-svc 삭제"
  # Q5 · Q6 에서 고장 낸 컨트롤플레인 매니페스트를 백업본으로 되돌린다
  cp_restore_all
}
exam_setup() {
  cat <<'YAML' | kubectl apply -f - &>/dev/null
apiVersion: v1
kind: Pod
metadata:
  name: broken-pod
  namespace: default
spec:
  containers:
  - name: app
    image: nginx:1.24
    command: ["invalid-command"]
YAML
  cat <<'YAML' | kubectl apply -f - &>/dev/null
apiVersion: v1
kind: Pod
metadata:
  name: pull-fail
  namespace: default
spec:
  containers:
  - name: app
    image: nginx:nonexistent-tag-xyz-9999
YAML
  kubectl create deployment target-app --image=nginx:1.24 --replicas=2 -n default &>/dev/null || true
  cat <<'YAML' | kubectl apply -f - &>/dev/null
apiVersion: v1
kind: Service
metadata:
  name: target-svc
  namespace: default
spec:
  selector:
    app: WRONG-LABEL
  ports:
  - port: 80
    targetPort: 80
YAML
  echo "  고장난 리소스 3종을 만들었다: broken-pod(CrashLoop) · pull-fail(ImagePull) · target-svc(빈 Endpoints)"
  echo ""
  echo -e "  ${ORANGE}${BOLD}[주의] Q5 · Q6 은 컨트롤플레인을 일부러 고장 냅니다.${RESET}"
  echo -e "  ${DIM}그 문제로 넘어가는 순간 kube-apiserver(Q5) · kube-scheduler(Q6) 매니페스트를 바꿉니다.${RESET}"
  echo -e "  ${DIM}Q4 까지 풀고 나면 ${BOLD}VM 스냅샷${RESET}${DIM} 을 먼저 찍으세요. 컨트롤플레인 노드에서 실행해야 합니다(sudo).${RESET}"
}

# ══════════════════════════════════════════════════════════════
q1_title() { echo "Diagnose a CrashLoopBackOff Pod"; }
q1_text() { cat <<'EOF'
The Pod broken-pod in the default namespace is in CrashLoopBackOff.

  1) find the cause (the events and the previous container log tell you)
  2) create a working Pod named fixed-pod with image nginx:1.24 that runs
     correctly

Leave broken-pod in place — it is the evidence.

Useful commands:
  kubectl describe pod broken-pod
  kubectl logs broken-pod --previous

Verify:
  kubectl get pod fixed-pod        -> Running
EOF
}
q1_title_ko() { echo "CrashLoopBackOff 진단"; }
q1_text_ko() { cat <<'EOF'
default 네임스페이스의 broken-pod 가 CrashLoopBackOff 상태다.

  1) 원인을 찾는다 (Events 와 이전 컨테이너 로그에 나온다)
  2) 정상 동작하는 fixed-pod 를 nginx:1.24 이미지로 만든다

broken-pod 는 증거이므로 그대로 둔다.

[진단]
  kubectl describe pod broken-pod
  kubectl logs broken-pod --previous

[확인]
  kubectl get pod fixed-pod        → Running
EOF
}
q1_grade() {
  check "fixed-pod 존재" "kubectl get pod fixed-pod -n default"
  wait_ready "fixed-pod" default
  check_output "fixed-pod Running" "kubectl get pod fixed-pod -n default -o jsonpath='{.status.phase}'" '^Running$'
  check_output "이미지 nginx:1.24" \
    "kubectl get pod fixed-pod -n default -o jsonpath='{.spec.containers[0].image}'" '^nginx:1\.24$'
  check_output "재시작 없이 안정적" \
    "kubectl get pod fixed-pod -n default -o jsonpath='{.status.containerStatuses[0].restartCount}'" '^[0-2]$'
  check "증거인 broken-pod 는 남겨 뒀다" "kubectl get pod broken-pod -n default"
}
q1_hint() { cat <<'EOF'
kubectl describe pod broken-pod | tail -20     # Events
kubectl logs broken-pod --previous             # 죽기 직전 로그
# command: ["invalid-command"] 처럼 실행할 수 없는 명령이 들어 있다

kubectl run fixed-pod --image=nginx:1.24 --restart=Never
EOF
}

# ══════════════════════════════════════════════════════════════
q2_title() { echo "Fix an ImagePullBackOff Pod"; }
q2_text() { cat <<'EOF'
The Pod pull-fail in the default namespace is in ImagePullBackOff.

Fix it so that a Pod named pull-fail runs image nginx:1.24 and reaches
Running state.

Note: the image of a running Pod cannot be edited in place for every field —
deleting and recreating it is the usual answer.

Verify:
  kubectl get pod pull-fail        -> Running
EOF
}
q2_title_ko() { echo "ImagePullBackOff 수정"; }
q2_text_ko() { cat <<'EOF'
default 네임스페이스의 pull-fail 파드가 ImagePullBackOff 상태다.

pull-fail 파드가 nginx:1.24 이미지로 Running 이 되도록 고치시오.

파드의 필드는 대부분 실행 중 수정할 수 없다 — 삭제 후 재생성이 보통의
정답이다.

[확인]
  kubectl get pod pull-fail        → Running
EOF
}
q2_grade() {
  check "파드 pull-fail 존재" "kubectl get pod pull-fail -n default"
  wait_ready "pull-fail" default
  check_output "Running" "kubectl get pod pull-fail -n default -o jsonpath='{.status.phase}'" '^Running$'
  check_output "이미지가 nginx:1.24" \
    "kubectl get pod pull-fail -n default -o jsonpath='{.spec.containers[0].image}'" '^nginx:1\.24$'
  check_output "컨테이너가 Ready" \
    "kubectl get pod pull-fail -n default -o jsonpath='{.status.containerStatuses[0].ready}'" '^true$'
}
q2_hint() { cat <<'EOF'
kubectl describe pod pull-fail | tail -15      # Events 에 pull 실패 이유

kubectl delete pod pull-fail
kubectl run pull-fail --image=nginx:1.24 --restart=Never

# 이미지만 바꾸는 방법도 있다
kubectl set image pod/pull-fail app=nginx:1.24
EOF
}

# ══════════════════════════════════════════════════════════════
q3_title() { echo "Service with empty Endpoints"; }
q3_text() { cat <<'EOF'
The Service target-svc has no Endpoints, although the Deployment
target-app is running with two Pods.

Diagnose the cause and fix the Service so that both Pod IPs appear in its
Endpoints. Do not change the Pod labels — fix the Service.

Useful commands:
  kubectl get endpoints target-svc
  kubectl get svc target-svc -o yaml
  kubectl get pods -l app=target-app --show-labels

Verify:
  kubectl get endpoints target-svc    -> two Pod IPs
EOF
}
q3_title_ko() { echo "Endpoints 가 비어 있는 Service"; }
q3_text_ko() { cat <<'EOF'
target-svc Service 의 Endpoints 가 비어 있다. target-app Deployment 는
파드 2개로 정상 실행 중이다.

원인을 진단하고, Endpoints 에 파드 IP 2개가 등록되도록 Service 를
고치시오. 파드 레이블을 바꾸지 말고 Service 를 고친다.

[진단]
  kubectl get endpoints target-svc
  kubectl get svc target-svc -o yaml
  kubectl get pods -l app=target-app --show-labels

[확인]
  kubectl get endpoints target-svc    → 파드 IP 2개
EOF
}
q3_grade() {
  check "Service target-svc 존재" "kubectl get service target-svc -n default"
  check_output "selector 가 app=target-app" \
    "kubectl get service target-svc -n default -o jsonpath='{.spec.selector.app}'" '^target-app$'
  check_output "Endpoints 에 파드 IP 2개" \
    "kubectl get endpoints target-svc -n default -o jsonpath='{.subsets[0].addresses[*].ip}' | wc -w" '^\s*2$'
  check_output "Deployment 파드 레이블은 그대로" \
    "kubectl get deployment target-app -n default -o jsonpath='{.spec.template.metadata.labels.app}'" '^target-app$'
  check_output "임시 파드에서 target-svc 로 실제 응답" \
    "kubectl run netchk-q3 -n default --rm -i --restart=Never --image=busybox:1.36 -- wget -qO- --timeout=5 http://target-svc 2>/dev/null" 'nginx'
}
q3_hint() { cat <<'EOF'
kubectl get svc target-svc -o yaml | grep -A3 selector      # app: WRONG-LABEL
kubectl get pods -l app=target-app --show-labels            # 실제 레이블

kubectl patch svc target-svc -p '{"spec":{"selector":{"app":"target-app"}}}'
kubectl get endpoints target-svc
EOF
}

# ══════════════════════════════════════════════════════════════
q4_title() { echo "Check node health"; }
q4_text() { cat <<'EOF'
Check the state of the cluster nodes and record what you found.

  1) at least two nodes must be Ready
  2) write the output of the node list, including the Conditions summary,
     into /tmp/node-report.txt

If a node is NotReady, recover it first (ssh into it and inspect kubelet),
then write the report.

Verify:
  kubectl get nodes
  cat /tmp/node-report.txt

NOTE: Q5 and Q6 break the control plane on purpose as soon as you move on.
      Take a VM snapshot before leaving this question.
EOF
}
q4_title_ko() { echo "노드 상태 점검"; }
q4_text_ko() { cat <<'EOF'
클러스터 노드 상태를 점검하고 결과를 기록하시오.

  1) Ready 노드가 최소 2개여야 한다
  2) 노드 목록과 Conditions 요약을 /tmp/node-report.txt 에 저장한다

NotReady 노드가 있으면 먼저 복구한 뒤(ssh 로 들어가 kubelet 확인)
리포트를 작성한다.

[확인]
  kubectl get nodes
  cat /tmp/node-report.txt

※ 다음 Q5 · Q6 은 넘어가는 순간 컨트롤플레인을 일부러 고장 낸다.
  이 문제를 떠나기 전에 VM 스냅샷을 먼저 찍어 둔다.
EOF
}
q4_grade() {
  local ready; ready=$(kubectl get nodes --no-headers 2>/dev/null | awk '$2=="Ready"' | wc -l | tr -d ' ')
  check_result "Ready 노드가 2개 이상 (현재 ${ready:-0}개)" \
    "$([[ "${ready:-0}" -ge 2 ]] && echo 0 || echo 1)" "NotReady 노드를 먼저 복구하세요"
  check "/tmp/node-report.txt 존재" "test -f /tmp/node-report.txt"
  check "/tmp/node-report.txt 가 비어 있지 않다" "test -s /tmp/node-report.txt"
  check_output "리포트에 노드 이름이 들어 있다" \
    "cat /tmp/node-report.txt 2>/dev/null" "$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo control)"
  check_output "리포트에 상태(Ready) 정보가 있다" \
    "cat /tmp/node-report.txt 2>/dev/null" 'Ready'
}
q4_hint() { cat <<'EOF'
kubectl get nodes -o wide
kubectl describe node <노드> | grep -A8 Conditions

{ kubectl get nodes -o wide; echo; kubectl describe nodes | grep -E '^Name:|Ready|MemoryPressure|DiskPressure'; } \
  > /tmp/node-report.txt
EOF
}

# ══════════════════════════════════════════════════════════════
# Q5 · Q6 — 컨트롤플레인 고장 (실제 시험에서 나온 유형)
#   엔진에는 문제별 setup 훅이 없다. exam_setup 에서 둘 다 고장 내면 Q1~Q4 를 풀 수 없고,
#   API 서버와 스케줄러가 동시에 죽는다. 그래서 goto_q 를 감싸서 "그 문제로 들어갈 때" 고장 낸다.
#   - Q5 에 들어가면: (스케줄러가 죽어 있으면 먼저 되돌리고) kube-apiserver 의 --etcd-servers 를 2380 으로
#   - Q6 에 들어가면: (API 서버가 죽어 있으면 먼저 되돌리고) kube-scheduler 의 requests.cpu 를 노드 CPU 의 4배로
#   - 원본은 manifests 디렉터리 밖 $CP_BK_DIR 에 둔다. clean / start / exam_cleanup 이 되돌린다.
#   한 번 고장 낸 문제는 다시 들어가도 또 고장 내지 않는다 (상대 문제가 되돌린 경우만 다시 고장 낸다).
#   컨트롤플레인 노드에서 root 또는 암호 없는 sudo 로 실행해야 한다 (19-node-ops 와 같은 sudo -n 패턴).
MF_DIR=/etc/kubernetes/manifests
APISERVER_MF="$MF_DIR/kube-apiserver.yaml"
SCHED_MF="$MF_DIR/kube-scheduler.yaml"
CP_BK_DIR=/var/tmp/cka-lab-backup/22-troubleshooting

_root() { if [[ "$(id -u)" == "0" ]]; then "$@"; else sudo -n "$@"; fi; }
cp_can_root() { _root true &>/dev/null; }

# API 서버가 응답하는가 — 죽어 있어도 오래 매달리지 않게 타임아웃을 건다
cp_api_up() { kubectl get --raw=/readyz --request-timeout=3s 2>/dev/null | grep -q '^ok$'; }
cp_sched_up() { [[ -n "$(_root crictl ps --name kube-scheduler -q 2>/dev/null)" ]]; }
cp_wait() {   # cp_wait api|sched up|down [최대초]
  local what="$1" want="$2" max="${3:-180}" t=0 fn="cp_api_up"
  [[ "$what" == sched ]] && fn="cp_sched_up"
  while :; do
    if [[ "$want" == up ]]; then "$fn" && return 0; else "$fn" || return 0; fi
    (( t >= max )) && return 1
    sleep 3; t=$((t+3))
  done
}

# "2" · "2000m" · "0.2" · "\"200m\"" → 밀리코어 정수. 모르는 형식이면 빈 값
to_milli() {
  local v="${1//[\"\' ]/}"
  if [[ "$v" =~ ^([0-9]+)m$ ]]; then echo "$((10#${BASH_REMATCH[1]}))"
  elif [[ "$v" =~ ^[0-9]+$ ]]; then echo "$((10#$v * 1000))"
  elif [[ "$v" =~ ^[0-9]*\.[0-9]+$ ]]; then awk -v x="$v" 'BEGIN{printf "%d", x*1000+0.5}'
  fi
}
# 컨트롤플레인 노드 이름 — 클러스터마다 다르므로 레이블로 찾는다
cp_node() {
  kubectl get nodes -l node-role.kubernetes.io/control-plane --request-timeout=5s \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null
}
# 컨트롤플레인 노드의 CPU capacity (밀리코어). API 가 안 되면 이 노드의 nproc 로
cp_cap_milli() {
  local n c; n=$(cp_node)
  [[ -n "$n" ]] && c=$(kubectl get node "$n" --request-timeout=5s -o jsonpath='{.status.capacity.cpu}' 2>/dev/null)
  c=$(to_milli "${c:-}")
  [[ -z "$c" ]] && c=$(( $(nproc 2>/dev/null || echo 2) * 1000 ))
  echo "$c"
}
# 매니페스트의 resources.requests.cpu (들여쓰기로 requests 블록을 찾는다 — limits 의 cpu 와 섞이지 않게)
sched_manifest_cpu() {
  _root awk '
    /^[[:space:]]*requests:[[:space:]]*$/ { inreq=1; ind=match($0,/[^ ]/); next }
    inreq { cur=match($0,/[^ ]/); if (cur<=ind) { inreq=0; next }
            if ($1=="cpu:") { v=$2; gsub(/["'\'']/,"",v); print v; exit } }
  ' "$SCHED_MF" 2>/dev/null
}

# 백업본으로 되돌린다. 실제로 파일을 바꿨으면 0. 백업은 지운다 (오래된 백업이 나중에 덮어쓰지 않게)
cp_restore_one() {   # cp_restore_one kube-apiserver|kube-scheduler
  local bk="$CP_BK_DIR/$1.yaml" mf="$MF_DIR/$1.yaml" rc=1
  _root test -f "$bk" 2>/dev/null || return 1
  if ! _root cmp -s "$bk" "$mf" 2>/dev/null; then
    _root cp "$bk" "$mf" && rc=0
  fi
  _root rm -f "$bk"
  return $rc
}
cp_restore_all() {
  cp_can_root || return 0
  _root test -d "$CP_BK_DIR" 2>/dev/null || return 0
  local api=1 sch=1 was_up=1
  cp_api_up && was_up=0
  cp_restore_one kube-apiserver && api=0
  cp_restore_one kube-scheduler && sch=0
  _root rm -f "$CP_BK_DIR"/.*.broken 2>/dev/null
  _root rmdir "$CP_BK_DIR" 2>/dev/null
  (( api == 0 || sch == 0 )) || return 0
  echo "  Q5/Q6 컨트롤플레인 매니페스트를 원본으로 되돌렸다 — 다시 뜰 때까지 기다린다 (최대 3분)"
  if (( api == 0 )); then
    (( was_up == 0 )) && cp_wait api down 40     # 아직 옛 컨테이너가 응답 중이면 재시작을 먼저 기다린다
    if cp_wait api up 180; then echo "  kube-apiserver 응답 확인"
    else echo -e "  ${RED}kube-apiserver 가 3분 안에 돌아오지 않았다${RESET} — sudo crictl ps -a --name kube-apiserver"; fi
  fi
  if (( sch == 0 )); then
    if cp_wait sched up 120; then echo "  kube-scheduler 실행 확인"
    else echo -e "  ${RED}kube-scheduler 가 2분 안에 뜨지 않았다${RESET} — sudo crictl ps -a --name kube-scheduler"; fi
  fi
}

# 원본을 백업하고, 백업본에서 고장 낸 사본을 만들어 매니페스트 위에 덮어쓴다.
# (sed -i 를 manifests 안에서 쓰면 임시 파일이 잠깐 그 디렉터리에 생긴다 — kubelet 이 읽을 수 있다)
cp_backup() {   # cp_backup kube-apiserver|kube-scheduler
  _root install -d -m 700 "$CP_BK_DIR" || return 1
  _root test -f "$CP_BK_DIR/$1.yaml" && return 0      # 되돌리지 않은 백업이 있으면 그게 원본이다
  _root cp "$MF_DIR/$1.yaml" "$CP_BK_DIR/$1.yaml"
}
cp_break_apiserver() {
  local bk="$CP_BK_DIR/kube-apiserver.yaml" tmp="$CP_BK_DIR/.kube-apiserver.broken"
  cp_backup kube-apiserver || { echo -e "  ${RED}kube-apiserver.yaml 을 백업하지 못했다${RESET}"; return 1; }
  if ! _root grep -qE -- '--etcd-servers=https://127\.0\.0\.1:2379([[:space:]]|$)' "$bk"; then
    echo -e "  ${RED}--etcd-servers=https://127.0.0.1:2379 가 매니페스트에 없다 — 외부 etcd 클러스터라 이 문제를 낼 수 없다${RESET}"
    _root rm -f "$bk"; return 1
  fi
  _root sed -E 's#(--etcd-servers=https://127\.0\.0\.1:)2379#\12380#' "$bk" | _root tee "$tmp" >/dev/null
  _root grep -q -- '--etcd-servers=https://127.0.0.1:2380' "$tmp" || { echo "  고장 사본을 만들지 못했다"; return 1; }
  _root cp "$tmp" "$APISERVER_MF" && _root rm -f "$tmp"
}
cp_break_scheduler() {
  local bk="$CP_BK_DIR/kube-scheduler.yaml" tmp="$CP_BK_DIR/.kube-scheduler.broken" big
  big=$(( $(cp_cap_milli) / 1000 * 4 )); (( big < 8 )) && big=8   # 노드 CPU 의 4배 — 어떤 파드를 쫓아내도 못 받아들인다
  cp_backup kube-scheduler || { echo -e "  ${RED}kube-scheduler.yaml 을 백업하지 못했다${RESET}"; return 1; }
  if ! _root grep -qE '^[[:space:]]+cpu:[[:space:]]' "$bk"; then
    echo -e "  ${RED}kube-scheduler.yaml 에 resources.requests.cpu 가 없다 — kubeadm 기본 매니페스트가 아니다${RESET}"
    _root rm -f "$bk"; return 1
  fi
  _root sed -E "0,/^([[:space:]]+)cpu:[[:space:]].*\$/s//\\1cpu: \"${big}\"/" "$bk" | _root tee "$tmp" >/dev/null
  _root grep -q "cpu: \"${big}\"" "$tmp" || { echo "  고장 사본을 만들지 못했다"; return 1; }
  _root cp "$tmp" "$SCHED_MF" && _root rm -f "$tmp"
}

cp_arm() {   # 문제에 들어갈 때 호출된다
  local n="$1"
  [[ "$n" == 5 || "$n" == 6 ]] || return 0
  [[ -n "$(state_get "q${n}_armed")" && -z "$(state_get "q${n}_restored")" ]] && return 0
  echo ""
  if ! cp_can_root || ! _root test -f "$APISERVER_MF" 2>/dev/null; then
    echo -e "  ${RED}${BOLD}[Q${n}] 고장을 준비하지 못했습니다.${RESET}"
    echo -e "  ${DIM}이 문제는 컨트롤플레인 노드에서, root 또는 암호 없는 sudo 로 실행해야 합니다.${RESET}"
    echo -e "  ${DIM}sudo 암호를 묻는 환경이면:${RESET} ${CYAN}sudo -v && bash exam.sh go ${n}${RESET}"
    return 0
  fi
  echo -e "  ${ORANGE}${BOLD}[Q${n}] 컨트롤플레인을 일부러 고장 냅니다 — VM 스냅샷을 찍어 두었나요?${RESET}"
  echo -e "  ${DIM}원본은 ${CP_BK_DIR}/ 에 백업합니다. 꼬이면:${RESET} ${CYAN}bash exam.sh clean${RESET} ${DIM}(원본 복원 + 기록 삭제)${RESET}"
  if [[ "$n" == 5 ]]; then
    # 두 곳을 동시에 고장 내지 않는다 — Q6 의 스케줄러가 아직 죽어 있으면 먼저 살린다
    if ! cp_sched_up && cp_restore_one kube-scheduler; then
      [[ -n "$(state_get q6_armed)" ]] && state_set q6_restored 1
      echo "  (Q6 의 스케줄러 고장이 남아 있어 원본으로 되돌렸습니다)"
      cp_wait sched up 120 || true
    fi
    cp_break_apiserver || return 0
    state_set q5_armed 1; state_set q5_restored ""
    echo "  kube-apiserver 매니페스트를 바꿨습니다. kubelet 이 반영할 때까지 기다립니다 (최대 90초)..."
    if cp_wait api down 90; then echo "  API 서버가 내려갔습니다."
    else echo "  아직 응답합니다 — kubelet 이 곧 반영합니다. 잠시 뒤 kubectl get nodes 를 해 보세요."; fi
  else
    # Q5 의 API 서버가 아직 죽어 있으면 먼저 살린다 (Q6 은 kubectl 이 돼야 풀 수 있다)
    if ! cp_api_up && cp_restore_one kube-apiserver; then
      [[ -n "$(state_get q5_armed)" ]] && state_set q5_restored 1
      echo "  (Q5 의 API 서버 고장이 남아 있어 원본으로 되돌렸습니다 — 다시 뜰 때까지 기다립니다)"
      if ! cp_wait api up 180; then
        echo -e "  ${RED}API 서버가 3분 안에 돌아오지 않아 Q6 고장은 내지 않았습니다.${RESET} 잠시 뒤 ${CYAN}bash exam.sh go 6${RESET}"
        return 0
      fi
    fi
    cp_break_scheduler || return 0
    state_set q6_armed 1; state_set q6_restored ""
    echo "  kube-scheduler 매니페스트를 바꿨습니다. kubelet 이 반영할 때까지 기다립니다 (최대 90초)..."
    if cp_wait sched down 90; then echo "  스케줄러가 내려갔습니다."
    else echo "  아직 실행 중입니다 — kubelet 이 곧 반영합니다."; fi
  fi
}

# 엔진의 goto_q(문제 이동 — go · next · check 만점 후 자동 이동 · skip)를 감싼다.
# _lib 는 건드리지 않는다. 문제 화면이 뜨기 전에 고장을 내 둔다.
eval "$(declare -f goto_q | sed '1s/^goto_q /_lib_goto_q /')"
goto_q() { cp_arm "$1"; _lib_goto_q "$1"; }

# ══════════════════════════════════════════════════════════════
q5_title() { echo "Repair the API server (kubectl refused)"; }
q5_text() { cat <<'EOF'
!! WARNING: this question breaks the control plane on purpose.
!!          Take a VM snapshot BEFORE you start. Work on the control plane node.
!!          `bash exam.sh clean` restores the original manifests from
!!          /var/tmp/cka-lab-backup/ if you get lost.

After a recent change on the control plane node, kubectl stopped working:

  The connection to the server <ip>:6443 was refused - did you specify the
  right host or port?

Find the cause and fix it so that the cluster works again.

  - the kube-apiserver static Pod must be Running again
  - fix the existing manifest — do not reinstall the cluster
  - keep any backup copies OUTSIDE /etc/kubernetes/manifests

Useful places:
  /etc/kubernetes/manifests/
  sudo crictl ps -a          sudo crictl logs <container-id>
  sudo journalctl -u kubelet

Verify:
  kubectl get nodes
  kubectl get pods -n kube-system -l component=kube-apiserver    -> Running
EOF
}
q5_title_ko() { echo "API 서버 복구 (kubectl connection refused)"; }
q5_text_ko() { cat <<'EOF'
!! 경고: 이 문제는 컨트롤플레인을 일부러 고장 낸다.
!!       시작 전에 반드시 VM 스냅샷을 찍는다. 컨트롤플레인 노드에서 푼다.
!!       꼬이면 bash exam.sh clean 이 /var/tmp/cka-lab-backup/ 의 원본으로
!!       되돌린다.

컨트롤플레인 노드에서 설정을 바꾼 뒤로 kubectl 이 동작하지 않는다.

  The connection to the server <ip>:6443 was refused - did you specify the
  right host or port?

원인을 찾아 클러스터가 다시 동작하도록 고치시오.

  - kube-apiserver 스태틱 파드가 다시 Running 이어야 한다
  - 기존 매니페스트를 고친다 — 클러스터를 다시 설치하지 않는다
  - 백업 사본은 /etc/kubernetes/manifests 밖에 둔다

[볼 곳]
  /etc/kubernetes/manifests/
  sudo crictl ps -a          sudo crictl logs <컨테이너ID>
  sudo journalctl -u kubelet

[확인]
  kubectl get nodes
  kubectl get pods -n kube-system -l component=kube-apiserver    → Running
EOF
}
q5_grade() {
  check "매니페스트의 --etcd-servers 가 https://127.0.0.1:2379" \
    "_root grep -qE -- '--etcd-servers=https://127\.0\.0\.1:2379([[:space:]]|\$)' '$APISERVER_MF'"
  check "kube-apiserver 컨테이너가 실행 중 (crictl)" \
    "_root crictl ps --name kube-apiserver -q 2>/dev/null | grep -q ."
  check_output "API 서버가 응답한다 (kubectl get --raw /readyz)" \
    "kubectl get --raw=/readyz --request-timeout=5s" '^ok$'
  check_output "kube-apiserver 스태틱 파드 Running" \
    "kubectl get pods -n kube-system -l component=kube-apiserver --request-timeout=5s -o jsonpath='{.items[*].status.phase}'" \
    '^Running( Running)*$'
  check_output "실행 중인 kube-apiserver 가 etcd 2379 로 붙어 있다" \
    "kubectl get pods -n kube-system -l component=kube-apiserver --request-timeout=5s -o jsonpath='{.items[0].spec.containers[0].command}'" \
    'etcd-servers=https://127\.0\.0\.1:2379"'
}
q5_hint() { cat <<'EOF'
kubectl get nodes                                  # refused → API 서버가 없다
sudo journalctl -u kubelet -n 20 --no-pager        # 6443 refused 는 '증상'이다 (kubelet 도 API 서버에 못 붙는다)
sudo crictl ps -a --name kube-apiserver            # Exited 가 반복된다
sudo crictl logs $(sudo crictl ps -a -q --name kube-apiserver | head -1) 2>&1 | tail -20
#   etcd 에 못 붙는다는 줄 → 어느 주소:포트로 붙으려 했나?

sudo grep -n etcd /etc/kubernetes/manifests/kube-apiserver.yaml
sudo grep -nE 'listen-client-urls|listen-peer-urls' /etc/kubernetes/manifests/etcd.yaml
#   2379 = 클라이언트용 (API 서버가 붙는 곳)   2380 = etcd 멤버끼리(peer)

sudo cp /etc/kubernetes/manifests/kube-apiserver.yaml /tmp/kube-apiserver.yaml.bak
sudo vi /etc/kubernetes/manifests/kube-apiserver.yaml     # --etcd-servers 포트를 고친다
watch -n2 'sudo crictl ps --name kube-apiserver'          # 1~2분 기다린다
kubectl get nodes
EOF
}

# ══════════════════════════════════════════════════════════════
q6_title() { echo "Fix the kube-scheduler CPU request"; }
q6_text() { cat <<'EOF'
!! WARNING: this question breaks the control plane on purpose.
!!          Take a VM snapshot BEFORE you start. Work on the control plane node.
!!          `bash exam.sh clean` restores the original manifests.

New Pods in the cluster stay Pending. The kube-scheduler is not running:
someone set the CPU request of the kube-scheduler static Pod far too high,
so the kubelet cannot admit it.

Set the CPU request (resources.requests.cpu) of the kube-scheduler to
10% of the CPU capacity of the control plane node.
  e.g. a node with 2 CPUs -> 200m

Do not change anything else in the manifest.

Verify:
  kubectl get pods -n kube-system -l component=kube-scheduler    -> Running
  a new Pod gets scheduled to a node
EOF
}
q6_title_ko() { echo "kube-scheduler CPU 요청 고치기 (노드 CPU 의 10%)"; }
q6_text_ko() { cat <<'EOF'
!! 경고: 이 문제는 컨트롤플레인을 일부러 고장 낸다.
!!       시작 전에 반드시 VM 스냅샷을 찍는다. 컨트롤플레인 노드에서 푼다.
!!       꼬이면 bash exam.sh clean 이 원본 매니페스트로 되돌린다.

새로 만든 파드가 모두 Pending 이다. kube-scheduler 가 실행되고 있지 않다.
누군가 kube-scheduler 스태틱 파드의 CPU 요청을 너무 크게 바꿔서 kubelet 이
파드를 받아들이지 못한다.

kube-scheduler 의 CPU 요청(resources.requests.cpu)을 컨트롤플레인 노드
CPU capacity 의 10% 로 맞추시오.
  예) CPU 2개인 노드 → 200m

매니페스트의 다른 부분은 바꾸지 않는다.

[확인]
  kubectl get pods -n kube-system -l component=kube-scheduler    → Running
  새 파드가 노드에 배치된다
EOF
}
q6_sched_probe() {   # 임시 파드를 만들어 실제로 스케줄되는지 본다 (pause 이미지 — kubeadm 노드에 이미 있다)
  local n="q6-sched-probe-$(date +%s)" rc=1
  kubectl run "$n" -n default --image=registry.k8s.io/pause:3.10 --restart=Never \
    --labels=cka-lab=q19-sched --request-timeout=5s &>/dev/null || return 1
  kubectl wait --for=condition=PodScheduled "pod/$n" -n default --timeout=40s &>/dev/null && rc=0
  kubectl delete pod "$n" -n default --wait=false --ignore-not-found &>/dev/null
  return $rc
}
q6_grade() {
  check "kube-scheduler 컨테이너가 실행 중 (crictl)" \
    "_root crictl ps --name kube-scheduler -q 2>/dev/null | grep -q ."
  check_output "kube-scheduler 스태틱 파드 Running" \
    "kubectl get pods -n kube-system -l component=kube-scheduler --request-timeout=5s -o jsonpath='{.items[*].status.phase}'" \
    '^Running( Running)*$'

  local capm want mf_v mf_m pod_v pod_m
  capm=$(cp_cap_milli); capm="${capm//[^0-9]/}"; capm="${capm:-0}"
  want=$(( capm / 10 ))
  mf_v=$(sched_manifest_cpu); mf_m=$(to_milli "$mf_v")
  check_result "매니페스트 requests.cpu = 노드 CPU(${capm}m)의 10% = ${want}m (현재: ${mf_v:-없음})" \
    "$([[ -n "$mf_m" && "$mf_m" == "$want" ]] && echo 0 || echo 1)" \
    "sudo grep -A3 requests $SCHED_MF"
  pod_v=$(kubectl get pods -n kube-system -l component=kube-scheduler --request-timeout=5s \
    -o jsonpath='{.items[0].spec.containers[0].resources.requests.cpu}' 2>/dev/null)
  pod_m=$(to_milli "$pod_v")
  check_result "실행 중인 스케줄러 파드의 requests.cpu = ${want}m (현재: ${pod_v:-없음})" \
    "$([[ -n "$pod_m" && "$pod_m" == "$want" ]] && echo 0 || echo 1)" \
    "kubelet 이 새 매니페스트로 파드를 다시 만들 때까지 30초쯤 기다린다"
  check "새 파드가 노드에 스케줄된다 (PodScheduled)" "q6_sched_probe"
}
q6_hint() { cat <<'EOF'
kubectl get pods -n kube-system -l component=kube-scheduler     # 없거나 Running 이 아니다
kubectl get events -n kube-system --field-selector reason=OutOfcpu
sudo journalctl -u kubelet --since "10 min ago" --no-pager | grep -iE 'outofcpu|enough resource' | tail -3

# 노드 CPU → 밀리코어 → 10%
kubectl get nodes -l node-role.kubernetes.io/control-plane \
  -o jsonpath='{.items[0].status.capacity.cpu}{"\n"}'          # 예: 2  → 2000m → 200m

sudo cp /etc/kubernetes/manifests/kube-scheduler.yaml /tmp/kube-scheduler.yaml.bak
sudo vi /etc/kubernetes/manifests/kube-scheduler.yaml
#   resources:
#     requests:
#       cpu: 200m        ← 계산한 값
watch -n2 'sudo crictl ps --name kube-scheduler'
kubectl get pods -n kube-system -l component=kube-scheduler
EOF
}

# clean · start 는 엔진이 먼저 kubectl get nodes 로 확인한다 — API 서버가 죽어 있으면 거기서 멈춘다.
# 그래서 엔진에 넘기기 전에 Q5 · Q6 의 고장부터 되돌린다.
case "${1:-}" in start|clean) cp_restore_all ;; esac

exam_main "$@"
