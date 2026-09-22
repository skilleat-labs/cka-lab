#!/usr/bin/env bash
# CKA 2강 실습 — 클러스터 구축과 노드 조인 (순차 진행형)
set -uo pipefail
source "$(cd "$(dirname "$0")/.." && pwd)/_lib/exam-lib.sh"

EXAM_TITLE="CKA 2강 실습 — 클러스터 구축 · 노드 조인"
EXAM_NQ=2

exam_cleanup() {
  echo "  (노드는 자동으로 제거하지 않는다 — 다시 조인 연습을 하려면"
  echo "   control-plane 에서 kubectl delete node worker-2,"
  echo "   worker-2 에서 sudo kubeadm reset -f 를 직접 실행한다)"
  rm -f /tmp/coredns.log 2>/dev/null || true
}
exam_setup() { echo "  (미리 만들어둘 것 없음)"; }

# ══════════════════════════════════════════════════════════════
q1_title() { echo "Join the worker node to the cluster"; }
q1_text() { cat <<'EOF'
Join the node worker-2 (192.168.56.12) to the cluster.

  - on the control plane, print a fresh join command with
    kubeadm token create --print-join-command
  - run that command on worker-2 with sudo
  - the node must reach Ready state and run the same minor version as the
    other nodes

Verify:
  kubectl get nodes -o wide
EOF
}
q1_title_ko() { echo "워커 노드를 클러스터에 조인"; }
q1_text_ko() { cat <<'EOF'
worker-2(192.168.56.12) 노드를 클러스터에 조인시키시오.

  - control-plane 에서 kubeadm token create --print-join-command 로
    조인 명령을 새로 뽑는다
  - 그 명령을 worker-2 에서 sudo 로 실행한다
  - 노드가 Ready 가 되고, 다른 노드와 같은 마이너 버전이어야 한다

[확인]
  kubectl get nodes -o wide
EOF
}
q1_grade() {
  check "worker-2 노드가 클러스터에 있다" "kubectl get node worker-2"
  check_output "worker-2 가 Ready" \
    "kubectl get node worker-2 --no-headers" '\sReady\s'
  check_output "kubelet 버전이 v1.x 로 보고된다" \
    "kubectl get node worker-2 --no-headers -o wide" 'v1\.'
  check_output "control-plane 과 같은 마이너 버전" \
    "kubectl get nodes --no-headers -o custom-columns=V:.status.nodeInfo.kubeletVersion | sed 's/\.[0-9]*$//' | sort -u | wc -l" '^\s*1$'
}
q1_hint() { cat <<'EOF'
# control-plane 에서
kubeadm token create --print-join-command

# worker-2 에서 (위 출력을 그대로, sudo 를 붙여서)
sudo kubeadm join 192.168.56.10:6443 --token ... --discovery-token-ca-cert-hash sha256:...

# 이미 조인했다가 다시 하려면 worker-2 에서
sudo kubeadm reset -f && sudo rm -rf /etc/cni/net.d
EOF
}

# ══════════════════════════════════════════════════════════════
q2_title() { echo "Collect container logs with crictl"; }
q2_text() { cat <<'EOF'
On the control plane node, use crictl (not kubectl) to save the log of a
running coredns container to /tmp/coredns.log.

  - find the container id with crictl ps
  - write the log of that container into /tmp/coredns.log
  - the file must not be empty

Verify:
  ls -l /tmp/coredns.log
  head /tmp/coredns.log
EOF
}
q2_title_ko() { echo "crictl 로 컨테이너 로그 수집"; }
q2_text_ko() { cat <<'EOF'
control-plane 노드에서 kubectl 이 아니라 crictl 을 사용해
실행 중인 coredns 컨테이너의 로그를 /tmp/coredns.log 에 저장하시오.

  - crictl ps 로 컨테이너 ID 를 찾는다
  - 그 컨테이너의 로그를 /tmp/coredns.log 에 쓴다
  - 파일이 비어 있으면 안 된다

[확인]
  ls -l /tmp/coredns.log
  head /tmp/coredns.log
EOF
}
q2_grade() {
  check "/tmp/coredns.log 파일 존재" "test -f /tmp/coredns.log"
  check "/tmp/coredns.log 가 비어 있지 않다" "test -s /tmp/coredns.log"
  check_output "CoreDNS 로그 내용으로 보인다" \
    "cat /tmp/coredns.log 2>/dev/null | head -50" 'CoreDNS|coredns|plugin|linux/amd64'
}
q2_hint() { cat <<'EOF'
sudo crictl ps | grep coredns          # 컨테이너 ID 확인 (맨 앞 열)
sudo crictl logs <컨테이너ID> > /tmp/coredns.log 2>&1

# 한 줄로
sudo crictl logs "$(sudo crictl ps -q --name coredns | head -1)" > /tmp/coredns.log 2>&1
EOF
}

exam_main "$@"
