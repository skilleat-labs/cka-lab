#!/usr/bin/env bash
# ============================================================
# CKA Mock Exam 1 — 자동 채점 스크립트
# 실행: bash verify.sh
# ============================================================
set -uo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

SCORE=0
TOTAL=100
PASS=0
FAIL=0

hr() { printf '%0.s─' {1..70}; echo; }

check() {
  local desc="$1"
  local pts="$2"
  local result="$3"   # 0=pass, else fail
  if [ "$result" -eq 0 ]; then
    echo -e "  ${GREEN}PASS${NC} [+${pts}점] ${desc}"
    SCORE=$((SCORE + pts))
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}FAIL${NC} [ 0점] ${desc}"
    FAIL=$((FAIL + 1))
  fi
}

check_output() {
  local desc="$1"
  local pts="$2"
  local actual="$3"
  local expected="$4"
  if echo "$actual" | grep -q "$expected" 2>/dev/null; then
    echo -e "  ${GREEN}PASS${NC} [+${pts}점] ${desc}"
    SCORE=$((SCORE + pts))
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}FAIL${NC} [ 0점] ${desc}  (기대: '${expected}', 실제: '${actual}')"
    FAIL=$((FAIL + 1))
  fi
}

echo -e "${BOLD}${BLUE}"
hr
echo "  CKA Mock Exam 1 — 채점 결과"
hr
echo -e "${NC}"

# ─────────────────────────────────────────────────────────────
echo -e "${BOLD}Q1. Deployment 생성 [15점]${NC}"
hr

# 1-1: Deployment 존재 여부
DEP_JSON=$(kubectl get deployment nginx-deploy -n default -o json 2>/dev/null || echo '{}')
check "Deployment nginx-deploy 존재" 5 \
  $([ "$(echo "$DEP_JSON" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("metadata",{}).get("name",""))' 2>/dev/null)" = "nginx-deploy" ] && echo 0 || echo 1)

# 1-2: 이미지 확인
check_output "이미지: nginx:1.24" 5 \
  "$(kubectl get deployment nginx-deploy -n default -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || echo '')" \
  "nginx:1.24"

# 1-3: replicas=3, Ready
READY=$(kubectl get deployment nginx-deploy -n default -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo '0')
check "Ready 복제본 3개" 5 $([ "$READY" = "3" ] && echo 0 || echo 1)

echo ""

# ─────────────────────────────────────────────────────────────
echo -e "${BOLD}Q2. Service 생성 [10점]${NC}"
hr

# 2-1: Service 존재
SVC_TYPE=$(kubectl get svc nginx-svc -n default -o jsonpath='{.spec.type}' 2>/dev/null || echo '')
check "Service nginx-svc 존재 + ClusterIP 타입" 5 \
  $([ "$SVC_TYPE" = "ClusterIP" ] && echo 0 || echo 1)

# 2-2: Endpoints에 Pod IP 있음
EP=$(kubectl get endpoints nginx-svc -n default -o jsonpath='{.subsets}' 2>/dev/null || echo '')
check "Endpoints에 Pod IP 등록됨" 5 \
  $([ -n "$EP" ] && [ "$EP" != "null" ] && echo 0 || echo 1)

echo ""

# ─────────────────────────────────────────────────────────────
echo -e "${BOLD}Q3. ConfigMap + Pod [10점]${NC}"
hr

# 3-1: ConfigMap 존재 + 키 확인
CM_VAL=$(kubectl get configmap app-config -n default -o jsonpath='{.data.APP_ENV}' 2>/dev/null || echo '')
check_output "ConfigMap app-config / APP_ENV=prod" 3 "$CM_VAL" "prod"

CM_PORT=$(kubectl get configmap app-config -n default -o jsonpath='{.data.APP_PORT}' 2>/dev/null || echo '')
check_output "ConfigMap app-config / APP_PORT=8080" 2 "$CM_PORT" "8080"

# 3-2: Pod Running
POD_STATUS=$(kubectl get pod config-pod -n default -o jsonpath='{.status.phase}' 2>/dev/null || echo '')
check "config-pod Running" 3 $([ "$POD_STATUS" = "Running" ] && echo 0 || echo 1)

# 3-3: 환경변수 주입 확인
ENV_VAL=$(kubectl exec config-pod -n default -- printenv APP_ENV 2>/dev/null || echo '')
check_output "config-pod 내부 APP_ENV=prod" 2 "$ENV_VAL" "prod"

echo ""

# ─────────────────────────────────────────────────────────────
echo -e "${BOLD}Q4. PV + PVC [15점]${NC}"
hr

# 4-1: PV 존재 및 스펙
PV_CAP=$(kubectl get pv task-pv -o jsonpath='{.spec.capacity.storage}' 2>/dev/null || echo '')
check_output "PV task-pv 용량 500Mi" 4 "$PV_CAP" "500Mi"

PV_AM=$(kubectl get pv task-pv -o jsonpath='{.spec.accessModes[0]}' 2>/dev/null || echo '')
check_output "PV accessMode ReadWriteOnce" 3 "$PV_AM" "ReadWriteOnce"

PV_PATH=$(kubectl get pv task-pv -o jsonpath='{.spec.hostPath.path}' 2>/dev/null || echo '')
check_output "PV hostPath /tmp/task-data" 2 "$PV_PATH" "/tmp/task-data"

# 4-2: PVC Bound
PVC_STATUS=$(kubectl get pvc task-pvc -n default -o jsonpath='{.status.phase}' 2>/dev/null || echo '')
check "PVC task-pvc STATUS=Bound" 6 $([ "$PVC_STATUS" = "Bound" ] && echo 0 || echo 1)

echo ""

# ─────────────────────────────────────────────────────────────
echo -e "${BOLD}Q5. RBAC [15점]${NC}"
hr

# 5-1: ServiceAccount 존재
SA=$(kubectl get serviceaccount app-sa -n default -o name 2>/dev/null || echo '')
check "ServiceAccount app-sa 존재" 3 $([ -n "$SA" ] && echo 0 || echo 1)

# 5-2: Role 존재 + verbs 확인
ROLE_VERBS=$(kubectl get role app-role -n default -o jsonpath='{.rules[0].verbs}' 2>/dev/null || echo '')
check_output "Role app-role verbs에 get 포함" 3 "$ROLE_VERBS" "get"
check_output "Role app-role verbs에 list 포함" 2 "$ROLE_VERBS" "list"

ROLE_RES=$(kubectl get role app-role -n default -o jsonpath='{.rules[0].resources}' 2>/dev/null || echo '')
check_output "Role app-role 리소스: pods" 2 "$ROLE_RES" "pods"

# 5-3: RoleBinding 존재
RB=$(kubectl get rolebinding app-rb -n default -o name 2>/dev/null || echo '')
check "RoleBinding app-rb 존재" 2 $([ -n "$RB" ] && echo 0 || echo 1)

# 5-4: 권한 검증
AUTH=$(kubectl auth can-i list pods --as=system:serviceaccount:default:app-sa -n default 2>/dev/null || echo 'no')
check "권한 검증: list pods = yes" 3 $([ "$AUTH" = "yes" ] && echo 0 || echo 1)

echo ""

# ─────────────────────────────────────────────────────────────
echo -e "${BOLD}Q6. 노드 drain [10점]${NC}"
hr

# worker-1이 존재하는지 확인
WORKER1=$(kubectl get node worker-1 -o name 2>/dev/null || echo '')
if [ -z "$WORKER1" ]; then
  echo -e "  ${YELLOW}SKIP${NC} [worker-1 노드가 이 클러스터에 없음. 단일 노드 환경에서는 건너뜁니다.]"
  SCORE=$((SCORE + 10))
  PASS=$((PASS + 1))
else
  NODE_STATUS=$(kubectl get node worker-1 -o jsonpath='{.spec.unschedulable}' 2>/dev/null || echo '')
  check "worker-1 스케줄 가능 (uncordon 완료)" 10 \
    $([ "$NODE_STATUS" != "true" ] && echo 0 || echo 1)
fi

echo ""

# ─────────────────────────────────────────────────────────────
echo -e "${BOLD}Q7. Pod 트러블슈팅 [25점]${NC}"
hr

# 7-1: broken-app Running
BROKEN_STATUS=$(kubectl get pod broken-app -n default -o jsonpath='{.status.phase}' 2>/dev/null || echo '')
check "broken-app STATUS=Running" 15 $([ "$BROKEN_STATUS" = "Running" ] && echo 0 || echo 1)

# 7-2: 이미지가 broken이 아님
BROKEN_IMG=$(kubectl get pod broken-app -n default -o jsonpath='{.spec.containers[0].image}' 2>/dev/null || echo 'nginx:broken')
check "broken-app 이미지가 nginx:broken 아님" 10 \
  $([ "$BROKEN_IMG" != "nginx:broken" ] && echo 0 || echo 1)

echo ""

# ─────────────────────────────────────────────────────────────
echo -e "${BOLD}${CYAN}"
hr
printf "  최종 점수: %d / %d 점\n" "$SCORE" "$TOTAL"
printf "  통과: %d문항  실패: %d문항\n" "$PASS" "$FAIL"
hr
echo -e "${NC}"

if [ "$SCORE" -ge 66 ]; then
  echo -e "${BOLD}${GREEN}  합격 기준(66점) 통과! CKA 합격권입니다. ${NC}"
else
  echo -e "${BOLD}${RED}  합격 기준(66점) 미달. 틀린 문제를 복습하세요.${NC}"
fi
echo ""
