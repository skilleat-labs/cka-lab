#!/usr/bin/env bash
# CKA 8강 자동 채점 스크립트 — RBAC와 보안
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
echo " CKA 8강 채점 — RBAC와 보안"
echo "================================================="
echo ""

# ── P1: ServiceAccount + Pod ──────────────────────────
echo "[P1] ServiceAccount 생성 및 Pod 적용"

check "my-sa ServiceAccount 존재 (default)" \
  "kubectl get serviceaccount my-sa -n default"

check_output "my-sa SA kind 확인" \
  "kubectl get serviceaccount my-sa -n default -o jsonpath='{.kind}'" \
  "ServiceAccount"

check "sa-test Pod 존재 (default)" \
  "kubectl get pod sa-test -n default"

check_output "sa-test Pod Running 상태" \
  "kubectl get pod sa-test -n default --no-headers" \
  "Running"

check_output "sa-test Pod serviceAccountName=my-sa 확인" \
  "kubectl get pod sa-test -n default -o jsonpath='{.spec.serviceAccountName}'" \
  "my-sa"

echo ""

# ── P2: Role + RoleBinding ────────────────────────────
echo "[P2] Role + RoleBinding — pods 읽기 권한"

check "pod-reader Role 존재 (default)" \
  "kubectl get role pod-reader -n default"

check_output "pod-reader Role에 pods 리소스 포함" \
  "kubectl get role pod-reader -n default -o jsonpath='{.rules[0].resources}'" \
  "pods"

check_output "pod-reader Role verbs에 get 포함" \
  "kubectl get role pod-reader -n default -o jsonpath='{.rules[0].verbs}'" \
  "get"

check_output "pod-reader Role verbs에 list 포함" \
  "kubectl get role pod-reader -n default -o jsonpath='{.rules[0].verbs}'" \
  "list"

check_output "pod-reader Role verbs에 watch 포함" \
  "kubectl get role pod-reader -n default -o jsonpath='{.rules[0].verbs}'" \
  "watch"

check "pod-reader-binding RoleBinding 존재 (default)" \
  "kubectl get rolebinding pod-reader-binding -n default"

check_output "pod-reader-binding roleRef.name=pod-reader" \
  "kubectl get rolebinding pod-reader-binding -n default -o jsonpath='{.roleRef.name}'" \
  "pod-reader"

check_output "pod-reader-binding subjects에 my-sa 포함" \
  "kubectl get rolebinding pod-reader-binding -n default -o jsonpath='{.subjects[*].name}'" \
  "my-sa"

echo ""

# ── P3: ClusterRole + ClusterRoleBinding ──────────────
echo "[P3] ClusterRole + ClusterRoleBinding — nodes 조회 권한"

check "node-reader ClusterRole 존재" \
  "kubectl get clusterrole node-reader"

check_output "node-reader ClusterRole에 nodes 리소스 포함" \
  "kubectl get clusterrole node-reader -o jsonpath='{.rules[0].resources}'" \
  "nodes"

check_output "node-reader ClusterRole verbs에 get 포함" \
  "kubectl get clusterrole node-reader -o jsonpath='{.rules[0].verbs}'" \
  "get"

check_output "node-reader ClusterRole verbs에 list 포함" \
  "kubectl get clusterrole node-reader -o jsonpath='{.rules[0].verbs}'" \
  "list"

check_output "node-reader ClusterRole verbs에 watch 포함" \
  "kubectl get clusterrole node-reader -o jsonpath='{.rules[0].verbs}'" \
  "watch"

check "node-reader-binding ClusterRoleBinding 존재" \
  "kubectl get clusterrolebinding node-reader-binding"

check_output "node-reader-binding roleRef.name=node-reader" \
  "kubectl get clusterrolebinding node-reader-binding -o jsonpath='{.roleRef.name}'" \
  "node-reader"

check_output "node-reader-binding subjects에 my-sa 포함" \
  "kubectl get clusterrolebinding node-reader-binding -o jsonpath='{.subjects[*].name}'" \
  "my-sa"

check_output "node-reader-binding subjects namespace=default" \
  "kubectl get clusterrolebinding node-reader-binding -o jsonpath='{.subjects[*].namespace}'" \
  "default"

echo ""

# ── P4: 권한 검증 ─────────────────────────────────────
echo "[P4] kubectl auth can-i 권한 검증"

CAN_I_PODS=$(kubectl auth can-i get pods \
  --as=system:serviceaccount:default:my-sa \
  -n default 2>/dev/null || echo "no")
if [[ "$CAN_I_PODS" == "yes" ]]; then
  echo "  [PASS] my-sa: pods get 권한 있음 (yes)"; ((PASS++))
else
  echo "  [FAIL] my-sa: pods get 권한 없음 (기대: yes, 실제: ${CAN_I_PODS})"; ((FAIL++))
fi

CAN_I_PODS_LIST=$(kubectl auth can-i list pods \
  --as=system:serviceaccount:default:my-sa \
  -n default 2>/dev/null || echo "no")
if [[ "$CAN_I_PODS_LIST" == "yes" ]]; then
  echo "  [PASS] my-sa: pods list 권한 있음 (yes)"; ((PASS++))
else
  echo "  [FAIL] my-sa: pods list 권한 없음 (기대: yes, 실제: ${CAN_I_PODS_LIST})"; ((FAIL++))
fi

CAN_I_NODES=$(kubectl auth can-i get nodes \
  --as=system:serviceaccount:default:my-sa 2>/dev/null || echo "no")
if [[ "$CAN_I_NODES" == "yes" ]]; then
  echo "  [PASS] my-sa: nodes get 권한 있음 (yes)"; ((PASS++))
else
  echo "  [FAIL] my-sa: nodes get 권한 없음 (기대: yes, 실제: ${CAN_I_NODES})"; ((FAIL++))
fi

# 최소 권한 확인: cluster-admin 없어야 함
CAN_I_ADMIN=$(kubectl auth can-i '*' '*' \
  --as=system:serviceaccount:default:my-sa 2>/dev/null || echo "no")
if [[ "$CAN_I_ADMIN" == "no" ]]; then
  echo "  [PASS] my-sa: cluster-admin 권한 없음 (최소 권한 원칙)"; ((PASS++))
else
  echo "  [WARN] my-sa: cluster-admin 권한 있음 — 최소 권한 원칙 위반 가능성"; ((FAIL++))
fi

echo ""
echo "================================================="
echo " 결과: ${PASS}개 통과 / $((PASS + FAIL))개 전체"
if [[ $FAIL -eq 0 ]]; then
  echo " 전체 통과! 8강 실습 완료."
else
  echo " ${FAIL}개 미통과 — 위 항목을 확인하세요."
fi
echo "================================================="
