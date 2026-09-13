#!/usr/bin/env bash
# CKA 4세션 시험 채점 스크립트
# 사용법: bash verify.sh
set -uo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; ORANGE='\033[0;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

PASS=0; FAIL=0; TOTAL=0

sep() { echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"; }

check() {
  local desc="$1"; local cmd="$2"
  TOTAL=$((TOTAL+1))
  if eval "$cmd" &>/dev/null; then
    echo -e "  ${GREEN}[PASS]${RESET} $desc"; PASS=$((PASS+1))
  else
    echo -e "  ${RED}[FAIL]${RESET} $desc"; FAIL=$((FAIL+1))
  fi
}

check_output() {
  local desc="$1"; local cmd="$2"; local pattern="$3"
  TOTAL=$((TOTAL+1))
  local out
  out=$(eval "$cmd" 2>/dev/null || echo "")
  if echo "$out" | grep -qE "$pattern"; then
    echo -e "  ${GREEN}[PASS]${RESET} $desc"; PASS=$((PASS+1))
  else
    echo -e "  ${RED}[FAIL]${RESET} $desc  ${ORANGE}(기대: $pattern / 실제: '${out}')${RESET}"
    FAIL=$((FAIL+1))
  fi
}

# 파드가 Ready 될 때까지 대기 (최대 40초)
wait_ready() {
  local sel="$1" ns="$2" i
  # 파드가 아예 없으면 기다리지 않는다
  [[ -z "$(kubectl get pods -n "$ns" $sel -o name 2>/dev/null)" ]] && return 1
  for i in $(seq 1 20); do
    local r
    r=$(kubectl get pods -n "$ns" $sel -o jsonpath='{range .items[*]}{.status.containerStatuses[0].ready}{"\n"}{end}' 2>/dev/null | sort -u | tr -d '\n')
    [[ "$r" == "true" ]] && return 0
    sleep 2
  done
  return 1
}

echo ""
sep
echo -e "  ${BOLD}CKA 4세션 시험 채점${RESET}"
sep

# ════════════════════════════════════════════════════════════════
# Q1: PVC → Deployment YAML 에서 바로 연결
# ════════════════════════════════════════════════════════════════
echo -e "\n${BOLD}${BLUE}[Q1] PVC 생성 + Deployment YAML 에서 바로 연결${RESET}"

check \
  "api-data PVC 가 api 네임스페이스에 존재한다" \
  "kubectl get pvc api-data -n api"

check_output \
  "api-data 가 api-storage StorageClass 를 사용한다" \
  "kubectl get pvc api-data -n api -o jsonpath='{.spec.storageClassName}'" \
  "^api-storage$"

check_output \
  "api-data accessModes 가 ReadWriteOnce 이다" \
  "kubectl get pvc api-data -n api -o jsonpath='{.spec.accessModes[0]}'" \
  "^ReadWriteOnce$"

check_output \
  "api-data 요청 용량이 1Gi 이다" \
  "kubectl get pvc api-data -n api -o jsonpath='{.spec.resources.requests.storage}'" \
  "^1Gi$"

check_output \
  "api-data 가 Bound 상태이다" \
  "kubectl get pvc api-data -n api -o jsonpath='{.status.phase}'" \
  "^Bound$"

check \
  "api-server Deployment 가 api 네임스페이스에 존재한다" \
  "kubectl get deployment api-server -n api"

check_output \
  "api-server 이미지가 nginx:1.24 이다" \
  "kubectl get deployment api-server -n api -o jsonpath='{.spec.template.spec.containers[0].image}'" \
  "^nginx:1\.24$"

wait_ready "-l app=api-server" api || true

check_output \
  "api-server 파드가 Ready 이다" \
  "kubectl get deployment api-server -n api -o jsonpath='{.status.readyReplicas}'" \
  "^1$"

check_output \
  "api-server 가 api-data PVC 를 볼륨으로 참조한다" \
  "kubectl get deployment api-server -n api -o jsonpath='{.spec.template.spec.volumes[*].persistentVolumeClaim.claimName}'" \
  "api-data"

check_output \
  "api-server 컨테이너가 /var/www/data 에 마운트하고 있다" \
  "kubectl get deployment api-server -n api -o jsonpath='{.spec.template.spec.containers[0].volumeMounts[*].mountPath}'" \
  "/var/www/data"

# YAML 에서 바로 연결했는지 — 생성 후 수정하면 revision 이 2 이상이 된다
REV=$(kubectl get deployment api-server -n api -o jsonpath='{.metadata.annotations.deployment\.kubernetes\.io/revision}' 2>/dev/null || echo "")
TOTAL=$((TOTAL+1))
if [[ "$REV" == "1" ]]; then
  echo -e "  ${GREEN}[PASS]${RESET} Deployment 를 볼륨 포함 상태로 한 번에 생성했다 (revision 1)"
  PASS=$((PASS+1))
else
  echo -e "  ${RED}[FAIL]${RESET} Deployment 를 볼륨 포함 상태로 한 번에 생성했다  ${ORANGE}(revision ${REV:-없음} — 생성 후 수정한 흔적)${RESET}"
  FAIL=$((FAIL+1))
fi

# 실제 마운트 검증
TOTAL=$((TOTAL+1))
POD=$(kubectl get pods -n api -l app=api-server -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
PROBE=""
if [[ -n "$POD" ]]; then
  PROBE=$(kubectl exec "$POD" -n api -- sh -c 'echo mounted > /var/www/data/.probe && cat /var/www/data/.probe' 2>/dev/null || echo "")
fi
if echo "$PROBE" | grep -q "^mounted$"; then
  echo -e "  ${GREEN}[PASS]${RESET} 파드 내부 /var/www/data 에 실제로 쓰고 읽을 수 있다 (실제 마운트 검증)"
  PASS=$((PASS+1))
else
  echo -e "  ${RED}[FAIL]${RESET} 파드 내부 /var/www/data 에 실제로 쓰고 읽을 수 있다  ${ORANGE}(볼륨 미마운트 또는 파드 없음)${RESET}"
  FAIL=$((FAIL+1))
fi

echo ""
sep

# ════════════════════════════════════════════════════════════════
# Q2: Requests / Limits
# ════════════════════════════════════════════════════════════════
echo -e "\n${BOLD}${ORANGE}[Q2] Requests / Limits 추가${RESET}"

check \
  "api-worker Deployment 가 api 네임스페이스에 존재한다" \
  "kubectl get deployment api-worker -n api"

check_output \
  "requests.cpu 가 100m 이다" \
  "kubectl get deployment api-worker -n api -o jsonpath='{.spec.template.spec.containers[0].resources.requests.cpu}'" \
  "^100m$"

check_output \
  "requests.memory 가 128Mi 이다" \
  "kubectl get deployment api-worker -n api -o jsonpath='{.spec.template.spec.containers[0].resources.requests.memory}'" \
  "^128Mi$"

check_output \
  "limits.cpu 가 200m 이다" \
  "kubectl get deployment api-worker -n api -o jsonpath='{.spec.template.spec.containers[0].resources.limits.cpu}'" \
  "^200m$"

check_output \
  "limits.memory 가 256Mi 이다" \
  "kubectl get deployment api-worker -n api -o jsonpath='{.spec.template.spec.containers[0].resources.limits.memory}'" \
  "^256Mi$"

wait_ready "-l app=api-worker" api || true

check_output \
  "api-worker 파드 2개가 모두 Ready 이다 (롤아웃 완료)" \
  "kubectl get deployment api-worker -n api -o jsonpath='{.status.readyReplicas}'" \
  "^2$"

# 실제 실행 중인 파드에 반영됐는지 (스펙이 아니라 구동 중인 파드)
check_output \
  "실행 중인 파드에 limits.memory 256Mi 가 실제 반영되어 있다" \
  "kubectl get pods -n api -l app=api-worker -o jsonpath='{range .items[*]}{.spec.containers[0].resources.limits.memory}{\"\\n\"}{end}' | sort -u | tr -d '\\n'" \
  "^256Mi$"

check_output \
  "파드 QoS 클래스가 Burstable 이다 (requests < limits)" \
  "kubectl get pods -n api -l app=api-worker -o jsonpath='{range .items[*]}{.status.qosClass}{\"\\n\"}{end}' | sort -u | tr -d '\\n'" \
  "^Burstable$"

echo ""
sep

# ════════════════════════════════════════════════════════════════
# Q3: Probe
# ════════════════════════════════════════════════════════════════
echo -e "\n${BOLD}${GREEN}[Q3] Liveness / Readiness Probe${RESET}"

check \
  "health-pod Pod 가 api 네임스페이스에 존재한다" \
  "kubectl get pod health-pod -n api"

check_output \
  "health-pod 이미지가 nginx:1.24 이다" \
  "kubectl get pod health-pod -n api -o jsonpath='{.spec.containers[0].image}'" \
  "^nginx:1\.24$"

check_output \
  "livenessProbe 가 httpGet path / 이다" \
  "kubectl get pod health-pod -n api -o jsonpath='{.spec.containers[0].livenessProbe.httpGet.path}'" \
  "^/$"

check_output \
  "livenessProbe 포트가 80 이다" \
  "kubectl get pod health-pod -n api -o jsonpath='{.spec.containers[0].livenessProbe.httpGet.port}'" \
  "^80$"

check_output \
  "livenessProbe initialDelaySeconds 가 5 이다" \
  "kubectl get pod health-pod -n api -o jsonpath='{.spec.containers[0].livenessProbe.initialDelaySeconds}'" \
  "^5$"

check_output \
  "livenessProbe periodSeconds 가 10 이다" \
  "kubectl get pod health-pod -n api -o jsonpath='{.spec.containers[0].livenessProbe.periodSeconds}'" \
  "^10$"

check_output \
  "livenessProbe failureThreshold 가 3 이다" \
  "kubectl get pod health-pod -n api -o jsonpath='{.spec.containers[0].livenessProbe.failureThreshold}'" \
  "^3$"

check_output \
  "readinessProbe 가 httpGet path / 이다" \
  "kubectl get pod health-pod -n api -o jsonpath='{.spec.containers[0].readinessProbe.httpGet.path}'" \
  "^/$"

check_output \
  "readinessProbe 포트가 80 이다" \
  "kubectl get pod health-pod -n api -o jsonpath='{.spec.containers[0].readinessProbe.httpGet.port}'" \
  "^80$"

check_output \
  "readinessProbe initialDelaySeconds 가 3 이다" \
  "kubectl get pod health-pod -n api -o jsonpath='{.spec.containers[0].readinessProbe.initialDelaySeconds}'" \
  "^3$"

check_output \
  "readinessProbe periodSeconds 가 5 이다" \
  "kubectl get pod health-pod -n api -o jsonpath='{.spec.containers[0].readinessProbe.periodSeconds}'" \
  "^5$"

# 실제 동작 — Ready 이고 재시작이 없어야 probe 가 정상 통과 중인 것
if kubectl get pod health-pod -n api &>/dev/null; then
  for i in $(seq 1 15); do
    [[ "$(kubectl get pod health-pod -n api -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null)" == "true" ]] && break
    sleep 2
  done
fi

check_output \
  "health-pod 가 Ready 상태이다 (readinessProbe 통과)" \
  "kubectl get pod health-pod -n api -o jsonpath='{.status.containerStatuses[0].ready}'" \
  "^true$"

check_output \
  "health-pod 재시작 횟수가 0 이다 (livenessProbe 통과)" \
  "kubectl get pod health-pod -n api -o jsonpath='{.status.containerStatuses[0].restartCount}'" \
  "^0$"

echo ""
sep

# ════════════════════════════════════════════════════════════════
# 최종 결과
# ════════════════════════════════════════════════════════════════
echo ""
echo -e "  ${BOLD}채점 결과:  PASS ${PASS} / TOTAL ${TOTAL}${RESET}"
echo ""

if [[ $FAIL -eq 0 ]]; then
  echo -e "  ${GREEN}${BOLD}전 항목 통과! PVC 연결·리소스 제한·Probe 모두 정확합니다.${RESET}"
else
  echo -e "  ${RED}${BOLD}실패 항목: ${FAIL}개${RESET}"
  echo -e "  위 [FAIL] 항목을 수정하고 다시 ${CYAN}bash verify.sh${RESET} 를 실행하세요."
  echo -e "  ${ORANGE}복습이 필요하면: bash exam-start.sh --hints${RESET}"
fi

echo ""
sep
echo ""

exit $FAIL
