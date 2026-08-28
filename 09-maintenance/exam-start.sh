#!/usr/bin/env bash
# CKA 9강 실습 초기화 스크립트 — 클러스터 유지보수
# 사용법: bash exam-start.sh [--hints]
set -uo pipefail

HINTS=false
for arg in "$@"; do [[ "$arg" == "--hints" ]] && HINTS=true; done

WORK_DIR="$(cd "$(dirname "$0")" && pwd)/work"
mkdir -p "$WORK_DIR"

echo "================================================="
echo " CKA 9강 실습: 클러스터 유지보수"
echo "================================================="
echo ""

# ── 현재 클러스터 상태 확인 ──────────────────────────
echo "[INFO] 현재 노드 상태:"
kubectl get nodes -o wide 2>/dev/null || {
  echo "[WARN] kubectl을 실행할 수 없습니다. kubeconfig를 확인하세요."
}
echo ""

# ── 기존 실습 결과물 정리 ─────────────────────────────
echo "[SETUP] 이전 실습 결과물 정리 중..."

# P1: worker-2가 cordon/drain 된 상태라면 uncordon
kubectl uncordon worker-2 2>/dev/null || true

# P2: 이전 etcd 백업 파일 제거
rm -f /tmp/etcd-backup.db 2>/dev/null || true

echo "[SETUP] 정리 완료"
echo ""

# ── P2 환경: etcd 접속 정보 확인 ─────────────────────
echo "[SETUP] etcd 접속 환경 확인..."
if command -v etcdctl &>/dev/null; then
  echo "  etcdctl: $(etcdctl version 2>/dev/null | head -1)"
else
  echo "  [WARN] etcdctl 명령어를 찾을 수 없습니다."
  echo "  etcdctl이 PATH에 있는지 확인하세요 (보통 /usr/local/bin/etcdctl)"
fi

if [ -f /etc/kubernetes/pki/etcd/ca.crt ]; then
  echo "  etcd 인증서: /etc/kubernetes/pki/etcd/ 확인됨"
else
  echo "  [WARN] etcd 인증서 경로(/etc/kubernetes/pki/etcd/)를 찾을 수 없습니다."
  echo "  이 실습은 control-plane 노드에서 실행해야 합니다."
fi
echo ""

echo "================================================="
echo " 실습 문제"
echo "================================================="
echo ""
echo "P1. worker-2 노드를 drain하고 작업 완료 후 uncordon 하라."
echo "    - DaemonSet 파드 무시 (--ignore-daemonsets)"
echo "    - emptyDir 데이터 삭제 허용 (--delete-emptydir-data)"
echo "    - drain 완료 후 kubectl uncordon worker-2 실행"
echo ""
echo "P2. etcd 스냅샷을 /tmp/etcd-backup.db에 저장하라."
echo "    - ETCDCTL_API=3 환경 변수 필요"
echo "    - --endpoints=https://127.0.0.1:2379"
echo "    - TLS 인증서: /etc/kubernetes/pki/etcd/ 하위"
echo "    - 백업 후 snapshot status로 검증"
echo ""
echo "P3. kubeadm upgrade plan을 실행하여 업그레이드 가능한 버전을 확인하라."
echo "    - 현재 버전과 업그레이드 가능 버전을 파악"
echo ""
echo "P4. kubeadm certs check-expiration으로 인증서 만료 날짜를 확인하라."
echo "    - 각 인증서의 만료일과 남은 기간(RESIDUAL TIME) 확인"
echo ""

if $HINTS; then
  echo "================================================="
  echo " 힌트"
  echo "================================================="
  echo ""
  echo "[P1 힌트] drain / uncordon"
  echo "  # worker-2 drain (DaemonSet 무시, emptyDir 허용)"
  echo "  kubectl drain worker-2 --ignore-daemonsets --delete-emptydir-data"
  echo ""
  echo "  # 상태 확인 (SchedulingDisabled 표시)"
  echo "  kubectl get nodes"
  echo ""
  echo "  # 작업 완료 후 uncordon"
  echo "  kubectl uncordon worker-2"
  echo ""
  echo "[P2 힌트] etcd 백업"
  echo "  # API 버전 고정 (v3 필수)"
  echo "  export ETCDCTL_API=3"
  echo ""
  echo "  # 스냅샷 저장"
  echo "  etcdctl snapshot save /tmp/etcd-backup.db \\"
  echo "    --endpoints=https://127.0.0.1:2379 \\"
  echo "    --cacert=/etc/kubernetes/pki/etcd/ca.crt \\"
  echo "    --cert=/etc/kubernetes/pki/etcd/server.crt \\"
  echo "    --key=/etc/kubernetes/pki/etcd/server.key"
  echo ""
  echo "  # 검증"
  echo "  etcdctl snapshot status /tmp/etcd-backup.db --write-out=table"
  echo ""
  echo "[P3 힌트] 업그레이드 계획"
  echo "  kubeadm upgrade plan"
  echo ""
  echo "[P4 힌트] 인증서 만료 확인"
  echo "  kubeadm certs check-expiration"
  echo ""
fi

echo "================================================="
echo " 채점 방법: bash verify.sh"
echo "================================================="
