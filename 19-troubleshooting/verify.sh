#!/usr/bin/env bash
# CKA 11강 자동 채점
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
  local out; out=$(eval "$cmd" 2>/dev/null || true)
  if echo "$out" | grep -q "$expect"; then
    echo "  [PASS] $desc"; ((PASS++))
  else
    echo "  [FAIL] $desc (기대: '$expect', 실제: '$(echo "$out" | head -1)')"; ((FAIL++))
  fi
}

echo "================================================="
echo " CKA 11강 채점"
echo "================================================="
echo ""

echo "[P1] CrashLoopBackOff 수정 — fixed-pod 생성"
check "fixed-pod 존재" "kubectl get pod fixed-pod -n default"
check_output "fixed-pod Running" "kubectl get pod fixed-pod -n default --no-headers" "Running"
check_output "fixed-pod image nginx:1.24" \
  "kubectl get pod fixed-pod -n default -o jsonpath='{.spec.containers[0].image}'" "nginx:1.24"

echo ""
echo "[P2] ImagePullBackOff 수정 — pull-fail Pod 정상화"
check "pull-fail Pod 존재" "kubectl get pod pull-fail -n default"
check_output "pull-fail Running" "kubectl get pod pull-fail -n default --no-headers" "Running"

echo ""
echo "[P3] Service Endpoint 수정 — target-svc"
check "target-svc 존재" "kubectl get svc target-svc -n default"
EP=$(kubectl get endpoints target-svc -n default -o jsonpath='{.subsets[0].addresses}' 2>/dev/null || echo "")
if [[ -n "$EP" && "$EP" != "null" && "$EP" != "[]" ]]; then
  echo "  [PASS] target-svc Endpoints 등록됨"; ((PASS++))
else
  echo "  [FAIL] target-svc Endpoints 비어있음 (selector 확인 필요)"; ((FAIL++))
fi

echo ""
echo "[P4] 클러스터 노드 상태"
READY_NODES=$(kubectl get nodes --no-headers 2>/dev/null | grep -c " Ready " || echo 0)
if [[ "$READY_NODES" -ge 2 ]]; then
  echo "  [PASS] Ready 노드 ${READY_NODES}개 이상"; ((PASS++))
else
  echo "  [FAIL] Ready 노드 ${READY_NODES}개 (최소 2개 필요)"; ((FAIL++))
fi

echo ""
echo "================================================="
echo " 결과: ${PASS}개 통과 / $((PASS + FAIL))개 전체"
[[ $FAIL -eq 0 ]] && echo " 전체 통과!" || echo " ${FAIL}개 미통과"
echo "================================================="
