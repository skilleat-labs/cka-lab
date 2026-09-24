#!/usr/bin/env bash
# CKA 2강 실습 초기화 스크립트
# 사용법: bash exam-start.sh [--hints]
set -euo pipefail

HINTS=false
for arg in "$@"; do [[ "$arg" == "--hints" ]] && HINTS=true; done

WORK_DIR="$(cd "$(dirname "$0")" && pwd)/work"
mkdir -p "$WORK_DIR"

echo "================================================="
echo " CKA 2강 실습: 클러스터 직접 구축 — kubeadm"
echo "================================================="
echo ""

# ── 현재 클러스터 상태 확인 ──────────────────────────
echo "[INFO] 현재 노드 상태:"
kubectl get nodes -o wide 2>/dev/null || { echo "[ERROR] kubectl을 실행할 수 없습니다. kubeconfig를 확인하세요."; exit 1; }
echo ""

# ── P1 환경 준비: worker-2를 클러스터에서 제거 ────────
echo "[SETUP] P1 준비: worker-2를 클러스터에서 제거합니다..."

if kubectl get node worker-2 &>/dev/null; then
  kubectl drain worker-2 --ignore-daemonsets --delete-emptydir-data --force --timeout=60s 2>/dev/null || true
  kubectl delete node worker-2 2>/dev/null || true
  echo "[SETUP] worker-2 노드 제거 완료"
else
  echo "[INFO] worker-2가 이미 클러스터에 없습니다. 건너뜁니다."
fi

# worker-2에서 kubeadm reset (SSH 필요)
echo "[SETUP] worker-2에서 kubeadm reset 실행 중..."
ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 192.168.56.12 \
  "sudo kubeadm reset -f --cri-socket unix:///run/containerd/containerd.sock 2>/dev/null; \
   sudo rm -rf /etc/cni/net.d /root/.kube; \
   echo 'worker-2 reset 완료'" 2>/dev/null || {
  echo "[WARN] worker-2 SSH 접속 실패 또는 reset 오류. 수동으로 확인하세요."
}

echo ""
echo "================================================="
echo " 실습 문제"
echo "================================================="
echo ""
echo "P1. worker-2(192.168.56.12) 노드를 클러스터에 조인시켜라."
echo "    조인 후 'kubectl get node worker-2' 에서 Ready 상태여야 한다."
echo ""
echo "P2. control-plane 노드에서 crictl을 사용하여"
echo "    coredns 컨테이너의 로그를 /tmp/coredns.log 에 저장하라."
echo ""

if $HINTS; then
  echo "================================================="
  echo " 힌트"
  echo "================================================="
  echo ""
  echo "[P1 힌트]"
  echo "  1. control-plane에서 새 join 명령 생성:"
  echo "     kubeadm token create --print-join-command"
  echo "  2. 출력된 명령어를 worker-2에서 실행:"
  echo "     ssh 192.168.56.12"
  echo "     sudo kubeadm join 192.168.56.10:6443 --token <token> \\"
  echo "       --discovery-token-ca-cert-hash sha256:<hash>"
  echo ""
  echo "[P2 힌트]"
  echo "  1. crictl ps | grep coredns    # 컨테이너 ID 확인"
  echo "  2. sudo crictl logs <id> > /tmp/coredns.log 2>&1"
  echo ""
fi

echo "[INFO] 준비 완료. 'bash verify.sh' 로 채점하세요."
