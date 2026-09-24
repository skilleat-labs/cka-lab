#!/usr/bin/env bash
# CKA 4강 자동 채점 스크립트
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
echo " CKA 4강 채점"
echo "================================================="
echo ""

# ── P1: resource-pod Requests/Limits 검증 ────────────
echo "[P1] Resource Requests/Limits 설정 파드"

check "resource-pod 존재" \
  "kubectl get pod resource-pod -n default"

check_output "resource-pod Running 상태" \
  "kubectl get pod resource-pod -n default --no-headers" \
  "Running"

check_output "requests.cpu=100m 확인" \
  "kubectl get pod resource-pod -n default -o jsonpath='{.spec.containers[0].resources.requests.cpu}'" \
  "100m"

check_output "requests.memory=128Mi 확인" \
  "kubectl get pod resource-pod -n default -o jsonpath='{.spec.containers[0].resources.requests.memory}'" \
  "128Mi"

check_output "limits.cpu=200m 확인" \
  "kubectl get pod resource-pod -n default -o jsonpath='{.spec.containers[0].resources.limits.cpu}'" \
  "200m"

check_output "limits.memory=256Mi 확인" \
  "kubectl get pod resource-pod -n default -o jsonpath='{.spec.containers[0].resources.limits.memory}'" \
  "256Mi"

echo ""

# ── P2: ssd-pod Node Affinity (worker-1) 검증 ────────
echo "[P2] Node Affinity — worker-1(disktype=ssd)에 배치"

check "ssd-pod 존재" \
  "kubectl get pod ssd-pod -n default"

check_output "ssd-pod Running 상태" \
  "kubectl get pod ssd-pod -n default --no-headers" \
  "Running"

check_output "ssd-pod가 worker-1에 스케줄됨" \
  "kubectl get pod ssd-pod -n default -o jsonpath='{.spec.nodeName}'" \
  "worker-1"

check_output "nodeAffinity 설정 존재 (requiredDuring...)" \
  "kubectl get pod ssd-pod -n default -o jsonpath='{.spec.affinity.nodeAffinity}'" \
  "required"

echo ""

# ── P3: gpu-pod Taint Toleration (worker-2) 검증 ──────
echo "[P3] Taint Toleration — worker-2(dedicated=gpu:NoSchedule) 허용"

check "gpu-pod 존재" \
  "kubectl get pod gpu-pod -n default"

check_output "gpu-pod Running 상태" \
  "kubectl get pod gpu-pod -n default --no-headers" \
  "Running"

check_output "gpu-pod가 worker-2에 스케줄됨" \
  "kubectl get pod gpu-pod -n default -o jsonpath='{.spec.nodeName}'" \
  "worker-2"

check_output "toleration key=dedicated 존재" \
  "kubectl get pod gpu-pod -n default -o jsonpath='{.spec.tolerations}'" \
  "dedicated"

check_output "toleration effect=NoSchedule 존재" \
  "kubectl get pod gpu-pod -n default -o jsonpath='{.spec.tolerations}'" \
  "NoSchedule"

echo ""

# ── P4: nginx-hpa Deployment + HPA 검증 ──────────────
echo "[P4] HPA (HorizontalPodAutoscaler)"

check "nginx-hpa Deployment 존재" \
  "kubectl get deployment nginx-hpa -n default"

check_output "nginx-hpa Deployment READY" \
  "kubectl get deployment nginx-hpa -n default --no-headers" \
  "[0-9]/[0-9]"

check "HPA nginx-hpa 존재" \
  "kubectl get hpa nginx-hpa -n default"

check_output "HPA minReplicas=2 확인" \
  "kubectl get hpa nginx-hpa -n default -o jsonpath='{.spec.minReplicas}'" \
  "2"

check_output "HPA maxReplicas=10 확인" \
  "kubectl get hpa nginx-hpa -n default -o jsonpath='{.spec.maxReplicas}'" \
  "10"

# CPU target 확인 (averageUtilization=50)
HPA_CPU=$(kubectl get hpa nginx-hpa -n default -o jsonpath='{.spec.metrics[0].resource.target.averageUtilization}' 2>/dev/null || \
          kubectl get hpa nginx-hpa -n default -o jsonpath='{.spec.targetCPUUtilizationPercentage}' 2>/dev/null || \
          echo "0")
if [[ "$HPA_CPU" == "50" ]]; then
  echo "  [PASS] HPA CPU 목표 50% 확인"; ((PASS++))
else
  echo "  [FAIL] HPA CPU 목표 50% 아님 (실제: ${HPA_CPU}%)"; ((FAIL++))
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
