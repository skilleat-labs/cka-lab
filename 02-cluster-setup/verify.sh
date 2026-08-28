#!/usr/bin/env bash
# CKA 2강 자동 채점 스크립트
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
    echo "  [FAIL] $desc (기대값: '$expect', 실제: '$(echo "$out" | head -1)')"
    ((FAIL++))
  fi
}

echo "================================================="
echo " CKA 2강 채점"
echo "================================================="
echo ""

# ── P1: worker-2 Ready 확인 ──────────────────────────
echo "[P1] worker-2 클러스터 조인"

check "worker-2 노드 존재" \
  "kubectl get node worker-2"

check_output "worker-2 STATUS: Ready" \
  "kubectl get node worker-2 --no-headers" \
  "Ready"

check_output "worker-2 버전 일치 (v1.)" \
  "kubectl get node worker-2 --no-headers -o wide" \
  "v1\."

echo ""

# ── P2: crictl 로그 파일 확인 ──────────────────────────
echo "[P2] crictl coredns 로그 저장"

check "/tmp/coredns.log 파일 존재" \
  "test -f /tmp/coredns.log"

check "/tmp/coredns.log 비어있지 않음" \
  "test -s /tmp/coredns.log"

# 파일 내용이 실제 로그인지 확인 (CoreDNS 로그 특징적 패턴)
if test -f /tmp/coredns.log && test -s /tmp/coredns.log; then
  check "/tmp/coredns.log 에 로그 내용 포함" \
    "grep -qiE 'coredns|linux|plugin|ready|running|started' /tmp/coredns.log"
fi

echo ""
echo "================================================="
echo " 결과: ${PASS}개 통과 / $((PASS + FAIL))개 전체"
if [[ $FAIL -eq 0 ]]; then
  echo " 전체 통과!"
else
  echo " ${FAIL}개 미통과 — 위 항목을 확인하세요."
fi
echo "================================================="
