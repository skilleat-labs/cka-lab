#!/usr/bin/env bash
# ============================================================
# CKA Mock Exam 1-1 — 자동 채점 스크립트
# 실행: bash verify.sh
# ============================================================
set -uo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

SCORE=0
TOTAL=100
PASS=0
FAIL=0
NS=retail

hr() { printf '%0.s─' {1..70}; echo; }

check() {
  local desc="$1" pts="$2" result="$3"
  if [ "$result" -eq 0 ]; then
    echo -e "  ${GREEN}PASS${NC} [+${pts}점] ${desc}"
    SCORE=$((SCORE + pts)); PASS=$((PASS + 1))
  else
    echo -e "  ${RED}FAIL${NC} [ 0점] ${desc}"
    FAIL=$((FAIL + 1))
  fi
}

check_output() {
  local desc="$1" pts="$2" actual="$3" expected="$4"
  if echo "$actual" | grep -qE "$expected" 2>/dev/null; then
    echo -e "  ${GREEN}PASS${NC} [+${pts}점] ${desc}"
    SCORE=$((SCORE + pts)); PASS=$((PASS + 1))
  else
    echo -e "  ${RED}FAIL${NC} [ 0점] ${desc}  (기대: '${expected}', 실제: '${actual}')"
    FAIL=$((FAIL + 1))
  fi
}

echo -e "${BOLD}${BLUE}"
hr
echo "  CKA Mock Exam 1-1 — 채점 결과"
hr
echo -e "${NC}"

# ─────────────────────────────────────────────────────────────
echo -e "${BOLD}Q1. Deployment 생성 [15점]${NC}"
hr

DEP=$(kubectl get deployment store-front -n $NS -o name 2>/dev/null || echo '')
check "Deployment store-front 가 retail 네임스페이스에 존재" 4 $([ -n "$DEP" ] && echo 0 || echo 1)

check_output "이미지: nginx:1.25" 4 \
  "$(kubectl get deployment store-front -n $NS -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || echo '')" \
  "^nginx:1\.25$"

check_output "containerPort 80" 2 \
  "$(kubectl get deployment store-front -n $NS -o jsonpath='{.spec.template.spec.containers[0].ports[0].containerPort}' 2>/dev/null || echo '')" \
  "^80$"

READY=$(kubectl get deployment store-front -n $NS -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo '0')
check "Ready 복제본 4개" 5 $([ "$READY" = "4" ] && echo 0 || echo 1)

echo ""

# ─────────────────────────────────────────────────────────────
echo -e "${BOLD}Q2. Service 생성 [10점]${NC}"
hr

SVC_TYPE=$(kubectl get svc store-svc -n $NS -o jsonpath='{.spec.type}' 2>/dev/null || echo '')
check "Service store-svc 존재 + ClusterIP 타입" 3 $([ "$SVC_TYPE" = "ClusterIP" ] && echo 0 || echo 1)

check_output "port 8080" 2 \
  "$(kubectl get svc store-svc -n $NS -o jsonpath='{.spec.ports[0].port}' 2>/dev/null || echo '')" "^8080$"

check_output "targetPort 80" 2 \
  "$(kubectl get svc store-svc -n $NS -o jsonpath='{.spec.ports[0].targetPort}' 2>/dev/null || echo '')" "^80$"

EP_CNT=$(kubectl get endpoints store-svc -n $NS -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null | wc -w | tr -d ' ')
check "Endpoints 에 Pod IP 4개 등록" 3 $([ "$EP_CNT" = "4" ] && echo 0 || echo 1)

echo ""

# ─────────────────────────────────────────────────────────────
echo -e "${BOLD}Q3. ConfigMap + Pod [10점]${NC}"
hr

check_output "ConfigMap store-config / APP_MODE=staging" 2 \
  "$(kubectl get configmap store-config -n $NS -o jsonpath='{.data.APP_MODE}' 2>/dev/null || echo '')" "^staging$"

check_output "ConfigMap store-config / APP_PORT=9090" 2 \
  "$(kubectl get configmap store-config -n $NS -o jsonpath='{.data.APP_PORT}' 2>/dev/null || echo '')" "^9090$"

POD_STATUS=$(kubectl get pod store-cfg -n $NS -o jsonpath='{.status.phase}' 2>/dev/null || echo '')
check "store-cfg Running" 2 $([ "$POD_STATUS" = "Running" ] && echo 0 || echo 1)

check_output "store-cfg 내부 APP_MODE=staging (실제 exec)" 2 \
  "$(kubectl exec store-cfg -n $NS -- printenv APP_MODE 2>/dev/null || echo '')" "^staging$"

check_output "store-cfg 내부 APP_PORT=9090 (실제 exec)" 2 \
  "$(kubectl exec store-cfg -n $NS -- printenv APP_PORT 2>/dev/null || echo '')" "^9090$"

echo ""

# ─────────────────────────────────────────────────────────────
echo -e "${BOLD}Q4. PV + PVC [15점]${NC}"
hr

check_output "PV report-pv 용량 1Gi" 3 \
  "$(kubectl get pv report-pv -o jsonpath='{.spec.capacity.storage}' 2>/dev/null || echo '')" "^1Gi$"

check_output "PV accessMode ReadWriteMany" 3 \
  "$(kubectl get pv report-pv -o jsonpath='{.spec.accessModes[0]}' 2>/dev/null || echo '')" "^ReadWriteMany$"

check_output "PV hostPath /tmp/report-data" 2 \
  "$(kubectl get pv report-pv -o jsonpath='{.spec.hostPath.path}' 2>/dev/null || echo '')" "^/tmp/report-data$"

check_output "PV storageClassName local-manual" 2 \
  "$(kubectl get pv report-pv -o jsonpath='{.spec.storageClassName}' 2>/dev/null || echo '')" "^local-manual$"

PVC_STATUS=$(kubectl get pvc report-pvc -n $NS -o jsonpath='{.status.phase}' 2>/dev/null || echo '')
check "PVC report-pvc STATUS=Bound (retail 네임스페이스)" 5 $([ "$PVC_STATUS" = "Bound" ] && echo 0 || echo 1)

echo ""

# ─────────────────────────────────────────────────────────────
echo -e "${BOLD}Q5. RBAC [15점]${NC}"
hr

SA=$(kubectl get serviceaccount deploy-sa -n $NS -o name 2>/dev/null || echo '')
check "ServiceAccount deploy-sa 존재" 2 $([ -n "$SA" ] && echo 0 || echo 1)

ROLE_JSON=$(kubectl get role deploy-reader -n $NS -o json 2>/dev/null || echo '{}')
ROLE_VERBS=$(echo "$ROLE_JSON" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(" ".join(v for r in d.get("rules",[]) for v in r.get("verbs",[])))' 2>/dev/null || echo '')
ROLE_RES=$(echo "$ROLE_JSON" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(" ".join(v for r in d.get("rules",[]) for v in r.get("resources",[])))' 2>/dev/null || echo '')
ROLE_GRP=$(echo "$ROLE_JSON" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(" ".join(v for r in d.get("rules",[]) for v in r.get("apiGroups",[])))' 2>/dev/null || echo '')

check_output "Role deploy-reader 리소스: deployments" 2 "$ROLE_RES" "deployments"
check_output "Role deploy-reader apiGroup: apps" 2 "$ROLE_GRP" "apps"
check_output "Role verbs 에 get·list·watch 포함" 2 "$ROLE_VERBS" "get.*list.*watch|list.*get.*watch|watch.*get.*list|get.*watch.*list|list.*watch.*get|watch.*list.*get"

RB=$(kubectl get rolebinding deploy-reader-rb -n $NS -o name 2>/dev/null || echo '')
check "RoleBinding deploy-reader-rb 존재" 2 $([ -n "$RB" ] && echo 0 || echo 1)

AUTH_DEP=$(kubectl auth can-i list deployments --as=system:serviceaccount:$NS:deploy-sa -n $NS 2>/dev/null || echo 'no')
check "권한 검증: list deployments = yes" 3 $([ "$AUTH_DEP" = "yes" ] && echo 0 || echo 1)

AUTH_POD=$(kubectl auth can-i list pods --as=system:serviceaccount:$NS:deploy-sa -n $NS 2>/dev/null || echo 'yes')
# SA·RoleBinding 이 실제로 있을 때만 "과잉 권한 없음"을 인정한다
check "권한 검증: list pods = no (필요한 권한만 부여)" 2 \
  $([ -n "$SA" ] && [ -n "$RB" ] && [ "$AUTH_POD" = "no" ] && echo 0 || echo 1)

echo ""

# ─────────────────────────────────────────────────────────────
echo -e "${BOLD}Q6. 노드 drain [10점]${NC}"
hr

WORKER2=$(kubectl get node worker-2 -o name 2>/dev/null || echo '')
if [ -z "$WORKER2" ]; then
  echo -e "  ${YELLOW}SKIP${NC} [worker-2 노드가 이 클러스터에 없음]"
  SCORE=$((SCORE + 10)); PASS=$((PASS + 1))
else
  UNSCHED=$(kubectl get node worker-2 -o jsonpath='{.spec.unschedulable}' 2>/dev/null || echo '')
  check "worker-2 스케줄 가능 (uncordon 완료)" 5 $([ "$UNSCHED" != "true" ] && echo 0 || echo 1)
  NODE_READY=$(kubectl get node worker-2 -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo '')
  check "worker-2 Ready 상태" 5 $([ "$NODE_READY" = "True" ] && echo 0 || echo 1)
fi

echo ""

# ─────────────────────────────────────────────────────────────
echo -e "${BOLD}Q7. Pod 트러블슈팅 [25점]${NC}"
hr

BROKEN_STATUS=$(kubectl get pod web-broken -n $NS -o jsonpath='{.status.phase}' 2>/dev/null || echo '')
check "web-broken STATUS=Running" 13 $([ "$BROKEN_STATUS" = "Running" ] && echo 0 || echo 1)

check_output "web-broken 이미지가 nginx:1.24 로 수정됨" 12 \
  "$(kubectl get pod web-broken -n $NS -o jsonpath='{.spec.containers[0].image}' 2>/dev/null || echo 'nginz:1.24')" \
  "^nginx:1\.24$"

echo ""

# ─────────────────────────────────────────────────────────────
echo -e "${BOLD}${CYAN}"
hr
printf "  최종 점수: %d / %d 점\n" "$SCORE" "$TOTAL"
printf "  통과: %d항목  실패: %d항목\n" "$PASS" "$FAIL"
hr
echo -e "${NC}"

if [ "$SCORE" -ge 66 ]; then
  echo -e "${BOLD}${GREEN}  합격 기준(66점) 통과! CKA 합격권입니다. ${NC}"
else
  echo -e "${BOLD}${RED}  합격 기준(66점) 미달. 틀린 문제를 복습하세요.${NC}"
fi
echo ""

exit $FAIL
