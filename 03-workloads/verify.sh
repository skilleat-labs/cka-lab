#!/usr/bin/env bash
# CKA 3강 자동 채점 스크립트
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
echo " CKA 3강 채점"
echo "================================================="
echo ""

# ── P1: Deployment web-app 검증 ──────────────────────
echo "[P1] Deployment 생성 · Scale · Update · Rollback"

check "web-app Deployment 존재" \
  "kubectl get deployment web-app -n default"

check_output "web-app READY 상태" \
  "kubectl get deployment web-app -n default --no-headers" \
  "[0-9]/[0-9]"

# rollout history에 nginx:1.25로 업데이트했다가 롤백한 이력 확인
# (revision 이 2개 이상이면 update + rollback이 있었음을 의미)
check_output "rollout revision 2개 이상 (업데이트+롤백 수행)" \
  "kubectl rollout history deployment/web-app -n default" \
  "REVISION"

# 최종 이미지가 nginx:1.24인지 확인 (롤백 후)
check_output "rollback 후 이미지 nginx:1.24 확인" \
  "kubectl get deployment web-app -n default -o jsonpath='{.spec.template.spec.containers[0].image}'" \
  "nginx:1.24"

echo ""

# ── P2: ConfigMap + 파드 envFrom 검증 ────────────────
echo "[P2] ConfigMap 생성 + 파드에 환경변수 주입"

check "ConfigMap db-config 존재" \
  "kubectl get configmap db-config -n default"

check_output "db-config에 DB_HOST=mysql 포함" \
  "kubectl get configmap db-config -n default -o jsonpath='{.data.DB_HOST}'" \
  "mysql"

check_output "db-config에 DB_PORT=3306 포함" \
  "kubectl get configmap db-config -n default -o jsonpath='{.data.DB_PORT}'" \
  "3306"

check "파드 db-client 존재" \
  "kubectl get pod db-client -n default"

check_output "db-client 파드 Running" \
  "kubectl get pod db-client -n default --no-headers" \
  "Running"

check_output "파드 내 DB_HOST 환경변수 주입 확인" \
  "kubectl exec db-client -n default -- env 2>/dev/null" \
  "DB_HOST=mysql"

check_output "파드 내 DB_PORT 환경변수 주입 확인" \
  "kubectl exec db-client -n default -- env 2>/dev/null" \
  "DB_PORT=3306"

echo ""

# ── P3: CronJob date-printer 검증 ────────────────────
echo "[P3] CronJob 생성 (매 분마다 date 출력)"

check "CronJob date-printer 존재" \
  "kubectl get cronjob date-printer -n default"

check_output "schedule */1 * * * * 설정 확인" \
  "kubectl get cronjob date-printer -n default -o jsonpath='{.spec.schedule}'" \
  "\*/1 \* \* \* \*"

check_output "image busybox 확인" \
  "kubectl get cronjob date-printer -n default -o jsonpath='{.spec.jobTemplate.spec.template.spec.containers[0].image}'" \
  "busybox"

# 최소 1개의 Job이 실행됐는지 확인 (1분 이상 지난 경우)
CRONJOB_JOBS=$(kubectl get jobs -n default --no-headers 2>/dev/null | grep "date-printer" | wc -l || echo 0)
if [[ "$CRONJOB_JOBS" -ge 1 ]]; then
  echo "  [PASS] date-printer Job 실행 이력 있음 (${CRONJOB_JOBS}개)"; ((PASS++))
else
  echo "  [WARN] date-printer Job 아직 실행 안됨 (1~2분 대기 후 재확인)"; ((FAIL++))
fi

echo ""

# ── P4: DaemonSet node-exporter 검증 ─────────────────
echo "[P4] DaemonSet node-exporter (monitoring 네임스페이스)"

check "monitoring 네임스페이스 존재" \
  "kubectl get namespace monitoring"

check "DaemonSet node-exporter 존재" \
  "kubectl get daemonset node-exporter -n monitoring"

check_output "image prom/node-exporter 확인" \
  "kubectl get daemonset node-exporter -n monitoring -o jsonpath='{.spec.template.spec.containers[0].image}'" \
  "node-exporter"

check_output "hostNetwork: true 설정 확인" \
  "kubectl get daemonset node-exporter -n monitoring -o jsonpath='{.spec.template.spec.hostNetwork}'" \
  "true"

# DESIRED 수 > 0 (최소 1개 노드에 배포)
DESIRED=$(kubectl get daemonset node-exporter -n monitoring -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null || echo 0)
READY=$(kubectl get daemonset node-exporter -n monitoring -o jsonpath='{.status.numberReady}' 2>/dev/null || echo 0)
if [[ "$READY" -ge 1 ]]; then
  echo "  [PASS] node-exporter Pod Running ($READY/$DESIRED 노드)"; ((PASS++))
else
  echo "  [FAIL] node-exporter Pod Running 아님 (Ready: $READY / Desired: $DESIRED)"; ((FAIL++))
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
