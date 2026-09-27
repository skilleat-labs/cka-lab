#!/usr/bin/env bash
# CKA 특강 실습 — 노드 안에서 푸는 문제 3종 (순차 진행형)
set -uo pipefail
source "$(cd "$(dirname "$0")/.." && pwd)/_lib/exam-lib.sh"

EXAM_TITLE="CKA 특강 실습 — 노드 운영 (drain/uncordon · etcd 백업 · 업그레이드 확인)"
EXAM_NQ=4

# 작업 대상 워커. 노드 이름은 클러스터마다 다르므로(worker1 · worker-1 · node01 …)
# 고정하지 않고 컨트롤플레인이 아닌 첫 노드를 찾아 쓴다. TARGET_NODE 로 직접 지정해도 된다.
TARGET_NODE="${TARGET_NODE:-$(kubectl get nodes --no-headers \
  -l '!node-role.kubernetes.io/control-plane' \
  -o custom-columns=:metadata.name 2>/dev/null | head -1 | tr -d ' ')}"
TARGET_NODE="${TARGET_NODE:-worker-1}"

exam_cleanup() {
  kubectl uncordon "$TARGET_NODE" &>/dev/null || true
  kdel deployment drain-demo -n default
  rm -f /tmp/etcd-snapshot.db /tmp/etcd-status.txt /tmp/upgrade-plan.txt /tmp/kubelet-version.txt
  # Q4 에서 만든 static pod — 매니페스트를 치우면 kubelet 이 파드를 거둬간다
  ( rm -f /etc/kubernetes/manifests/static-web.yaml 2>/dev/null \
    || sudo -n rm -f /etc/kubernetes/manifests/static-web.yaml 2>/dev/null ) || true
  echo "  $TARGET_NODE uncordon · drain-demo 및 /tmp 답안 파일 삭제"
}
exam_setup() {
  if ! kubectl get node "$TARGET_NODE" &>/dev/null; then
    echo ""
    echo -e "  ${RED}${BOLD}[중단] 노드 '$TARGET_NODE' 를 찾을 수 없습니다.${RESET}"
    echo -e "  ${DIM}이 상태로는 Q1(drain)을 풀 수 없습니다 — 배치할 노드가 없습니다.${RESET}"
    echo -e "  현재 노드: ${CYAN}$(kubectl get nodes --no-headers -o custom-columns=:metadata.name 2>/dev/null | tr '\n' ' ')${RESET}"
    echo -e "  다시 실행: ${CYAN}TARGET_NODE=<위 이름 중 하나> bash exam.sh start${RESET}"
    echo ""
    return 0
  fi
  kubectl create deployment drain-demo --image=nginx:1.24 --replicas=4 &>/dev/null
  wait_ready "-l app=drain-demo" default >/dev/null 2>&1 || true
  drain_mark "app=drain-demo" "$TARGET_NODE"      # 지금 이 노드에 몇 개 있는지 적어 둔다
  echo "  drain-demo (4 레플리카) 배치 · 대상 노드: $TARGET_NODE"
  echo "  $TARGET_NODE 의 파드 $(cat work/.drain-before 2>/dev/null || echo 0)개 — drain 하면 비워져야 한다"
  etcd_tool_check
}

# ══════════════════════════════════════════════════════════════
q1_title() { echo "Drain a node and bring it back"; }
q1_text() { cat <<'EOF'
A worker node needs maintenance. (this cluster: $TARGET_NODE)

  1) mark the node so no new Pods are scheduled on it AND
     evict the Pods already running there
     (ignore DaemonSet-managed Pods, and delete Pods using emptyDir)
     If a Pod has no controller, drain refuses to evict it — deal with that too.

  2) confirm the node shows SchedulingDisabled

  3) then bring it back so it can accept Pods again

At the end the node must be Ready WITHOUT SchedulingDisabled.

Verify:
  kubectl get nodes
EOF
}
q1_title_ko() { echo "노드를 비우고 되돌리기"; }
q1_text_ko() { cat <<'EOF'
워커 노드 한 대를 점검해야 한다. (이 클러스터에서는 $TARGET_NODE)

  1) 그 노드에 새 파드가 배치되지 않게 하고,
     이미 돌고 있는 파드도 다른 노드로 옮긴다
     (DaemonSet 파드는 무시하고, emptyDir 을 쓰는 파드는 삭제 허용)
     컨트롤러가 없는 단독 파드가 있으면 drain 이 거부한다 — 그것도 처리한다

  2) 노드가 SchedulingDisabled 로 보이는지 확인한다

  3) 점검이 끝났다고 보고, 다시 배치를 받을 수 있게 되돌린다

마지막 상태는 Ready 이고 SchedulingDisabled 가 아니어야 한다.

[확인]
  kubectl get nodes
EOF
}
q1_grade() {
  local exists; exists=$(kubectl get node "$TARGET_NODE" -o name 2>/dev/null)
  local nodes; nodes=$(kubectl get nodes --no-headers -o custom-columns=:metadata.name 2>/dev/null | tr '\n' ' ')
  check_result "노드 $TARGET_NODE 가 있다" "$([[ -n "$exists" ]] && echo 0 || echo 1)" \
    "$([[ -n "$exists" ]] || echo "이 클러스터의 노드: ${nodes:-조회 실패} → TARGET_NODE=<이름> bash exam.sh start")"

  # 노드가 없으면 나머지는 판정할 수 없다. 여기서 빠져나가지 않으면
  # unschedulable 이 빈 값이라 'cordon 아님' 으로 읽혀 엉뚱하게 통과한다.
  if [[ -z "$exists" ]]; then
    local why="노드를 찾지 못해 판정할 수 없다"
    check_result "Ready 상태다" 1 "$why"
    check_result "SchedulingDisabled 가 풀려 있다 (uncordon 됨)" 1 "$why"
    check_result "drain 으로 파드가 실제로 비워졌다" 1 "$why"
    return
  fi

  check_output "Ready 상태다" \
    "kubectl get node $TARGET_NODE -o jsonpath='{range .status.conditions[?(@.type==\"Ready\")]}{.status}{end}'" '^True$'
  check_result "SchedulingDisabled 가 풀려 있다 (uncordon 됨)" \
    "$([[ "$(kubectl get node "$TARGET_NODE" -o jsonpath='{.spec.unschedulable}' 2>/dev/null)" != "true" ]] && echo 0 || echo 1)" \
    "아직 cordon 상태다 — kubectl uncordon $TARGET_NODE"
  check_result "drain 으로 파드가 실제로 비워졌다" \
    "$(drain_moved "app=drain-demo" "$TARGET_NODE" && echo 0 || echo 1)" \
    "$TARGET_NODE 에 drain-demo 파드가 아직 남아 있다 — cordon 만 하면 파드는 그대로다"
}
q1_hint() { cat <<'EOF'
kubectl drain <노드> --ignore-daemonsets --delete-emptydir-data
kubectl get nodes                # <노드>   Ready,SchedulingDisabled

# "cannot delete Pods that declare no controller" 가 나오면
#   Deployment 나 ReplicaSet 없이 혼자 뜬 파드가 있다는 뜻이다.
#   drain 은 그런 파드를 함부로 지우지 않는다 — 옮겨 줄 컨트롤러가 없으니
#   지우면 그대로 사라지기 때문이다. 알고도 진행하려면 --force 를 붙인다.
kubectl drain <노드> --ignore-daemonsets --delete-emptydir-data --force

#   어떤 파드가 걸렸는지 먼저 보고 싶으면
kubectl get pods -A --field-selector spec.nodeName=<노드> -o wide

kubectl uncordon <노드>
kubectl get nodes                # <노드>   Ready

# drain 은 cordon + 파드 퇴거를 한 번에 한다.
# 중간에 실패해도 cordon 은 이미 걸려 있다 — SchedulingDisabled 인데 파드는
# 그대로인 상태가 그것이다. 원인을 고치고 drain 을 다시 치면 된다.
# 이 명령은 kubectl 이므로 노드 안이 아니라 밖(control-plane)에서 친다.
EOF
}

# ══════════════════════════════════════════════════════════════
q2_title() { echo "Back up etcd"; }
q2_text() { cat <<'EOF'
On the control plane node, take an etcd snapshot and save it to
/tmp/etcd-snapshot.db

Use the certificates that kube-apiserver uses:
  --cacert   /etc/kubernetes/pki/etcd/ca.crt
  --cert     /etc/kubernetes/pki/etcd/server.crt
  --key      /etc/kubernetes/pki/etcd/server.key

Then verify the snapshot and save the verification output to
/tmp/etcd-status.txt

Verify:
  ls -l /tmp/etcd-snapshot.db
  cat /tmp/etcd-status.txt
EOF
}
q2_title_ko() { echo "etcd 백업"; }
q2_text_ko() { cat <<'EOF'
컨트롤플레인 노드에서 etcd 스냅샷을 떠서
/tmp/etcd-snapshot.db 에 저장한다.

kube-apiserver 가 쓰는 인증서를 그대로 쓴다.
  --cacert   /etc/kubernetes/pki/etcd/ca.crt
  --cert     /etc/kubernetes/pki/etcd/server.crt
  --key      /etc/kubernetes/pki/etcd/server.key

그리고 스냅샷이 제대로 떠졌는지 확인한 출력을
/tmp/etcd-status.txt 에 저장한다.

[확인]
  ls -l /tmp/etcd-snapshot.db
  cat /tmp/etcd-status.txt
EOF
}
q2_grade() {
  check "/tmp/etcd-snapshot.db 가 있다" "test -s /tmp/etcd-snapshot.db"
  local sz; sz=$(wc -c < /tmp/etcd-snapshot.db 2>/dev/null | tr -d ' '); sz="${sz//[^0-9]/}"; sz="${sz:-0}"
  check_result "스냅샷 크기가 그럴듯하다 (1MB 이상)" \
    "$([[ "$sz" -ge 1048576 ]] && echo 0 || echo 1)" \
    "현재 ${sz} 바이트 — 너무 작으면 백업이 실패한 것이다"
  check "/tmp/etcd-status.txt 가 있다" "test -s /tmp/etcd-status.txt"
  check_output "status 출력에 해시가 있다" "cat /tmp/etcd-status.txt 2>/dev/null" '[0-9a-fA-F]{6,}'
  check_output "status 출력에 키 개수가 있다" "cat /tmp/etcd-status.txt 2>/dev/null" '[0-9]+'
}
q2_hint() { cat <<'EOF'
sudo ETCDCTL_API=3 etcdctl snapshot save /tmp/etcd-snapshot.db \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key

sudo ETCDCTL_API=3 etcdctl snapshot status /tmp/etcd-snapshot.db \
  --write-out=table | sudo tee /tmp/etcd-status.txt

# sudo 를 빼면 인증서를 못 읽어 permission denied 가 난다.
# 파일 소유자가 root 라 채점이 못 읽으면: sudo chmod 644 /tmp/etcd-snapshot.db /tmp/etcd-status.txt

# ETCDCTL_API=3 은 etcd 3.4 부터 기본값이라 사실 없어도 된다.
# 다만 붙여도 무해하고 시험 자료가 대부분 붙이므로, 습관으로 두는 편이 안전하다.

# etcdctl 이 호스트에 없으면 (kubeadm 은 etcd 가 static pod 로만 있다):
#   sudo apt-get install -y etcd-client
# 또는 etcd 파드 안의 것을 쓴다 — 이때는 저장 경로도 파드 안이므로 주의한다
#   kubectl -n kube-system exec -i etcd-$(hostname) -- etcdctl --cacert=... --cert=... --key=... member list
EOF
}

# ══════════════════════════════════════════════════════════════
q3_title() { echo "Check what an upgrade would do"; }
q3_text() { cat <<'EOF'
Before upgrading a cluster you check what the upgrade would change.

  1) on the control plane node, run the kubeadm command that shows the
     upgrade plan, and save its output to /tmp/upgrade-plan.txt

  2) write the kubelet version of every node to /tmp/kubelet-version.txt

Do NOT actually upgrade anything.

Verify:
  cat /tmp/upgrade-plan.txt
  cat /tmp/kubelet-version.txt
EOF
}
q3_title_ko() { echo "업그레이드하면 무엇이 바뀌는지 확인"; }
q3_text_ko() { cat <<'EOF'
클러스터를 올리기 전에는 무엇이 바뀌는지 먼저 확인한다.

  1) 컨트롤플레인 노드에서 업그레이드 계획을 보여 주는 kubeadm 명령을
     실행하고, 그 출력을 /tmp/upgrade-plan.txt 에 저장한다

  2) 모든 노드의 kubelet 버전을 /tmp/kubelet-version.txt 에 저장한다

실제로 업그레이드하지는 않는다.

[확인]
  cat /tmp/upgrade-plan.txt
  cat /tmp/kubelet-version.txt
EOF
}
q3_grade() {
  check "/tmp/upgrade-plan.txt 가 있다" "test -s /tmp/upgrade-plan.txt"
  check_output "kubeadm upgrade plan 의 출력이다" "cat /tmp/upgrade-plan.txt 2>/dev/null" 'upgrade|UPGRADE|COMPONENT|CURRENT'
  check "/tmp/kubelet-version.txt 가 있다" "test -s /tmp/kubelet-version.txt"
  check_output "버전 문자열이 있다" "cat /tmp/kubelet-version.txt 2>/dev/null" 'v1\.[0-9]+'
  local nodes lines
  nodes=$(kubectl get nodes --no-headers 2>/dev/null | wc -l | tr -d ' ')
  lines=$(grep -c 'v1\.' /tmp/kubelet-version.txt 2>/dev/null)
  lines="${lines//[^0-9]/}"; lines="${lines:-0}"
  check_result "노드 수만큼 버전이 적혀 있다" \
    "$([[ "$nodes" -gt 0 && "$lines" -ge "$nodes" ]] && echo 0 || echo 1)" \
    "노드 ${nodes}개 / 버전 ${lines}개"
}
q3_hint() { cat <<'EOF'
sudo kubeadm upgrade plan | sudo tee /tmp/upgrade-plan.txt

kubectl get nodes -o custom-columns='NAME:.metadata.name,KUBELET:.status.nodeInfo.kubeletVersion' \
  --no-headers > /tmp/kubelet-version.txt

# upgrade plan 은 읽기만 한다 — 실제로 바꾸는 것은 upgrade apply 다.
EOF
}

# ══════════════════════════════════════════════════════════════
q4_title() { echo "Create a static Pod"; }
q4_text() { cat <<'EOF'
The control plane components run as static Pods. Make one yourself to see
how they work.

On the control plane node, create a static Pod:

  name        static-web
  image       nginx:1.24
  namespace   default

Put it where the kubelet looks for static Pod manifests
(/etc/kubernetes/manifests). Do NOT use kubectl to create it.

Note what the Pod is called once it appears — the node name is appended.

Verify:
  kubectl get pods -o wide | grep static-web
  kubectl delete pod static-web-<node>     # it comes back within seconds
EOF
}
q4_title_ko() { echo "static pod 만들어 보기"; }
q4_text_ko() { cat <<'EOF'
컨트롤플레인 구성 요소가 static pod 로 돈다. 직접 하나 만들어 보면
어떻게 동작하는지 알 수 있다.

컨트롤플레인 노드에서 static pod 를 만든다.

  이름          static-web
  이미지        nginx:1.24
  네임스페이스  default

kubelet 이 static pod 매니페스트를 찾는 곳(/etc/kubernetes/manifests)에
파일을 둔다. kubectl 로 만들지 않는다.

파드가 뜬 뒤 이름이 어떻게 되는지 보라 — 뒤에 노드 이름이 붙는다.

[확인]
  kubectl get pods -o wide | grep static-web
  kubectl delete pod static-web-<노드>     # 몇 초 뒤 되살아난다
EOF
}
q4_grade() {
  local pod; pod=$(kubectl get pods -n default -o name 2>/dev/null | grep static-web | head -1)
  pod="${pod#pod/}"
  local owner; owner=$(kubectl get pod "${pod:-none}" -n default -o jsonpath='{.metadata.ownerReferences[0].kind}' 2>/dev/null)

  # 매니페스트 파일 확인. 다만 폴더가 root 전용이라 못 읽을 수 있으므로,
  # 그럴 때는 '소유자가 Node' 라는 사실로 대신 판정한다 (kubelet 이 파일로 띄웠다는 증거다).
  local mf=/etc/kubernetes/manifests/static-web.yaml seen=1
  ( test -f "$mf" || sudo -n test -f "$mf" ) 2>/dev/null && seen=0
  check_result "매니페스트를 두어 만들었다 (kubectl 로 만든 것이 아니다)" \
    "$([[ "$seen" == "0" || "$owner" == "Node" ]] && echo 0 || echo 1)" \
    "$([[ "$seen" == "0" ]] && echo "$mf 확인" || echo "파일도 못 찾고 소유자도 Node 가 아니다")"
  check_result "static-web 파드가 떠 있다" "$([[ -n "$pod" ]] && echo 0 || echo 1)" "${pod:-찾지 못함}"
  check_result "이름 뒤에 노드 이름이 붙어 있다" \
    "$([[ "$pod" =~ ^static-web-.+ ]] && echo 0 || echo 1)" \
    "실제 이름: ${pod:-없음} (static pod 는 이름 뒤에 노드 이름이 붙는다)"
  check_output "이미지가 nginx:1.24" \
    "kubectl get pod ${pod:-none} -n default -o jsonpath='{.spec.containers[0].image}' 2>/dev/null" '^nginx:1\.24$'
  # static pod 는 Node 가 소유자다 (API 서버에 보이는 것은 읽기용 복제본)
  check_output "소유자가 Node 다 — 진짜 static pod" \
    "kubectl get pod ${pod:-none} -n default -o jsonpath='{.metadata.ownerReferences[0].kind}' 2>/dev/null" '^Node$'
  wait_ready "${pod:-none}" default
  check_output "Running 상태" \
    "kubectl get pod ${pod:-none} -n default -o jsonpath='{.status.phase}' 2>/dev/null" '^Running$'
}
q4_hint() { cat <<'EOF'
# YAML 골격은 dry-run 으로 뽑는다
kubectl run static-web --image=nginx:1.24 $do > /tmp/sw.yaml

# 그 파일을 kubelet 이 보는 폴더로 옮긴다 (kubectl apply 하지 않는다)
sudo cp /tmp/sw.yaml /etc/kubernetes/manifests/static-web.yaml

# 몇 초 뒤 뜬다. 이름 뒤에 노드 이름이 붙는다
kubectl get pods -o wide | grep static-web
#   static-web-control-plane   1/1   Running

# 지워 보면 되살아난다 — kubelet 이 파일을 다시 읽기 때문이다
kubectl delete pod static-web-control-plane
kubectl get pods | grep static-web

# 진짜로 없애려면 파일을 치운다
sudo rm /etc/kubernetes/manifests/static-web.yaml
EOF
}

exam_main "$@"
