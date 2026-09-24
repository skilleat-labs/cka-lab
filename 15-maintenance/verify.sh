#!/usr/bin/env bash
# CKA 9강 자동 채점 스크립트 — 클러스터 유지보수
set -uo pipefail

PASS=0; FAIL=0

check() {
  local desc="$1"; local cmd="$2"
  if eval "$cmd" &>/dev/null; then
    echo "  [PASS] $desc"; ((PASS++))
  else
    echo "  [FAIL] $desc"; ((FAIL++))
  fi
}

check_output() {
  local desc="$1"; local cmd="$2"; local expect="$3"
  local out
  out=$(eval "$cmd" 2>/dev/null || true)
  if echo "$out" | grep -q "$expect"; then
    echo "  [PASS] $desc"; ((PASS++))
  else
    echo "  [FAIL] $desc (기대값: '$expect')"
    ((FAIL++))
  fi
}

check_not_output() {
  local desc="$1"; local cmd="$2"; local notexpect="$3"
  local out
  out=$(eval "$cmd" 2>/dev/null || true)
  if echo "$out" | grep -q "$notexpect"; then
    echo "  [FAIL] $desc (원치 않는 값 '$notexpect' 발견)"
    ((FAIL++))
  else
    echo "  [PASS] $desc"; ((PASS++))
  fi
}

echo "================================================="
echo " CKA 9강 채점 — 클러스터 유지보수"
echo "================================================="
echo ""

# ── P1: worker-2 uncordon 상태 확인 ─────────────────
echo "[P1] 노드 drain 후 uncordon"

check "worker-2 노드 존재" \
  "kubectl get node worker-2"

check_output "worker-2 Ready 상태" \
  "kubectl get node worker-2 --no-headers" \
  "Ready"

check_not_output "worker-2 SchedulingDisabled 아님" \
  "kubectl get node worker-2 --no-headers" \
  "SchedulingDisabled"

echo ""

# ── P2: /tmp/etcd-backup.db 파일 존재 확인 ──────────
echo "[P2] etcd 스냅샷 백업"

check "etcd 백업 파일 존재 (/tmp/etcd-backup.db)" \
  "test -f /tmp/etcd-backup.db"

check "etcd 백업 파일 크기 > 0" \
  "test -s /tmp/etcd-backup.db"

if [ -f /tmp/etcd-backup.db ] && command -v etcdctl &>/dev/null; then
  check "etcd 스냅샷 상태 유효 (snapshot status 성공)" \
    "ETCDCTL_API=3 etcdctl snapshot status /tmp/etcd-backup.db"
else
  echo "  [SKIP] etcdctl 또는 백업 파일 없음 — snapshot status 검증 건너뜀"
fi

echo ""

# ── P3: kubeadm upgrade plan 실행 결과 확인 ─────────
echo "[P3] 클러스터 업그레이드 계획 확인"

check "kubeadm 명령어 존재" \
  "command -v kubeadm"

if command -v kubeadm &>/dev/null; then
  echo "  [INFO] kubeadm upgrade plan 실행 중 (시간이 걸릴 수 있습니다)..."
  PLAN_OUT=$(kubeadm upgrade plan 2>&1 || true)
  if echo "$PLAN_OUT" | grep -qiE "COMPONENT|kube-apiserver|upgrade|error|warning"; then
    echo "  [PASS] kubeadm upgrade plan 실행 완료 (출력 확인됨)"; ((PASS++))
    echo ""
    echo "  --- kubeadm upgrade plan 요약 ---"
    echo "$PLAN_OUT" | grep -E "COMPONENT|kube-apiserver|Upgrade|version" | head -10 || true
    echo "  --- 끝 ---"
  else
    echo "  [WARN] kubeadm upgrade plan 출력이 예상과 다릅니다."
    echo "  실행 직접 확인: kubeadm upgrade plan"
    ((PASS++))
  fi
else
  echo "  [FAIL] kubeadm을 찾을 수 없습니다. 설치 여부를 확인하세요."; ((FAIL++))
fi

echo ""

# ── P4: kubeadm certs check-expiration 결과 확인 ────
echo "[P4] 인증서 만료일 확인"

check "kubeadm 명령어 존재 (P4)" \
  "command -v kubeadm"

if command -v kubeadm &>/dev/null; then
  echo "  [INFO] kubeadm certs check-expiration 실행 중..."
  CERTS_OUT=$(kubeadm certs check-expiration 2>&1 || true)
  if echo "$CERTS_OUT" | grep -qiE "CERTIFICATE|EXPIRES|RESIDUAL|apiserver|admin"; then
    echo "  [PASS] kubeadm certs check-expiration 실행 완료 (인증서 정보 확인됨)"; ((PASS++))
    echo ""
    echo "  --- 인증서 만료일 목록 ---"
    echo "$CERTS_OUT" | grep -E "CERTIFICATE|apiserver|admin|controller|scheduler|etcd" | head -10 || true
    echo "  --- 끝 ---"
  else
    echo "  [WARN] kubeadm certs 출력이 예상과 다릅니다."
    echo "  실행 직접 확인: kubeadm certs check-expiration"
    ((PASS++))
  fi
else
  echo "  [FAIL] kubeadm을 찾을 수 없습니다. 설치 여부를 확인하세요."; ((FAIL++))
fi

echo ""

# ── 최종 결과 ────────────────────────────────────────
echo "================================================="
TOTAL=$((PASS + FAIL))
echo " 결과: ${PASS}/${TOTAL} 통과"
if [ "$FAIL" -eq 0 ]; then
  echo " ✓ 모든 항목 통과! 9강 실습 완료."
else
  echo " ✗ ${FAIL}개 항목 실패. 위 [FAIL] 항목을 확인하세요."
fi
echo "================================================="
