#!/usr/bin/env bash
# CKA 특강 실습 — 노드 안에서 푸는 문제 3종 (순차 진행형)
set -uo pipefail
source "$(cd "$(dirname "$0")/.." && pwd)/_lib/exam-lib.sh"

EXAM_TITLE="CKA 특강 실습 — 노드 운영 (drain/uncordon · etcd 백업 · 업그레이드 확인)"
EXAM_NQ=3

# 작업 대상 워커. 다른 이름이면 TARGET_NODE 로 바꿔 쓴다.
TARGET_NODE="${TARGET_NODE:-worker1}"

exam_cleanup() {
  kubectl uncordon "$TARGET_NODE" &>/dev/null || true
  kdel deployment drain-demo -n default
  rm -f /tmp/etcd-snapshot.db /tmp/etcd-status.txt /tmp/upgrade-plan.txt /tmp/kubelet-version.txt
  echo "  $TARGET_NODE uncordon · drain-demo 및 /tmp 답안 파일 삭제"
}
exam_setup() {
  if ! kubectl get node "$TARGET_NODE" &>/dev/null; then
    echo "  [주의] 노드 '$TARGET_NODE' 를 찾을 수 없습니다."
    echo "         TARGET_NODE=<노드이름> bash exam.sh start 로 다시 실행하세요."
    echo "         현재 노드: $(kubectl get nodes --no-headers -o custom-columns=:metadata.name 2>/dev/null | tr '\n' ' ')"
    return 0
  fi
  kubectl create deployment drain-demo --image=nginx:1.24 --replicas=3 &>/dev/null
  echo "  drain-demo (3 레플리카) 배치 · 대상 노드: $TARGET_NODE"
}

# ══════════════════════════════════════════════════════════════
q1_title() { echo "Drain a node and bring it back"; }
q1_text() { cat <<'EOF'
A worker node needs maintenance.

  1) mark the node so no new Pods are scheduled on it AND
     evict the Pods already running there
     (ignore DaemonSet-managed Pods, and delete Pods using emptyDir)

  2) confirm the node shows SchedulingDisabled

  3) then bring it back so it can accept Pods again

At the end the node must be Ready WITHOUT SchedulingDisabled.

Verify:
  kubectl get nodes
EOF
}
q1_title_ko() { echo "노드를 비우고 되돌리기"; }
q1_text_ko() { cat <<'EOF'
워커 노드 한 대를 점검해야 한다.

  1) 그 노드에 새 파드가 배치되지 않게 하고,
     이미 돌고 있는 파드도 다른 노드로 옮긴다
     (DaemonSet 파드는 무시하고, emptyDir 을 쓰는 파드는 삭제 허용)

  2) 노드가 SchedulingDisabled 로 보이는지 확인한다

  3) 점검이 끝났다고 보고, 다시 배치를 받을 수 있게 되돌린다

마지막 상태는 Ready 이고 SchedulingDisabled 가 아니어야 한다.

[확인]
  kubectl get nodes
EOF
}
q1_grade() {
  check "노드 $TARGET_NODE 가 있다" "kubectl get node $TARGET_NODE"
  check_output "Ready 상태다" \
    "kubectl get node $TARGET_NODE -o jsonpath='{range .status.conditions[?(@.type==\"Ready\")]}{.status}{end}'" '^True$'
  check_result "SchedulingDisabled 가 풀려 있다 (uncordon 됨)" \
    "$([[ "$(kubectl get node "$TARGET_NODE" -o jsonpath='{.spec.unschedulable}' 2>/dev/null)" != "true" ]] && echo 0 || echo 1)" \
    "아직 cordon 상태다 — kubectl uncordon $TARGET_NODE"
  check_result "drain 을 거친 흔적이 있다 (한 번이라도 cordon 됐다)" \
    "$(kubectl get events -A --field-selector reason=NodeNotSchedulable 2>/dev/null | grep -q "$TARGET_NODE" && echo 0 || echo 1)" \
    "cordon/drain 이벤트를 찾지 못했다 — drain 을 실제로 실행했는지 확인"
}
q1_hint() { cat <<'EOF'
kubectl drain worker1 --ignore-daemonsets --delete-emptydir-data
kubectl get nodes                # worker1   Ready,SchedulingDisabled

kubectl uncordon worker1
kubectl get nodes                # worker1   Ready

# drain 은 cordon + 파드 퇴거를 한 번에 한다.
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
  lines=$(grep -c 'v1\.' /tmp/kubelet-version.txt 2>/dev/null || echo 0)
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

exam_main "$@"
