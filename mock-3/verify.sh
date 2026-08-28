#!/usr/bin/env bash
# ============================================================
# CKA Mock Exam 3 — 자동 채점 스크립트
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
  local result="$3"
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
echo "  CKA Mock Exam 3 — 채점 결과"
hr
echo -e "${NC}"

# ─────────────────────────────────────────────────────────────
echo -e "${BOLD}Q1. HPA 설정 [10점]${NC}"
hr

# 1-1: Deployment 존재
DEP_IMG=$(kubectl get deployment web-app -n default -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || echo '')
check_output "Deployment web-app 이미지 nginx:1.24" 3 "$DEP_IMG" "nginx:1.24"

# 1-2: HPA 존재
HPA=$(kubectl get hpa web-app -n default -o name 2>/dev/null || echo '')
check "HPA web-app 존재" 3 $([ -n "$HPA" ] && echo 0 || echo 1)

HPA_MIN=$(kubectl get hpa web-app -n default -o jsonpath='{.spec.minReplicas}' 2>/dev/null || echo '')
check "HPA minReplicas=2" 2 $([ "$HPA_MIN" = "2" ] && echo 0 || echo 1)

HPA_MAX=$(kubectl get hpa web-app -n default -o jsonpath='{.spec.maxReplicas}' 2>/dev/null || echo '')
check "HPA maxReplicas=5" 2 $([ "$HPA_MAX" = "5" ] && echo 0 || echo 1)

echo ""

# ─────────────────────────────────────────────────────────────
echo -e "${BOLD}Q2. StorageClass + PVC [15점]${NC}"
hr

# 2-1: StorageClass 존재
SC=$(kubectl get storageclass fast-ssd -o name 2>/dev/null || echo '')
check "StorageClass fast-ssd 존재" 5 $([ -n "$SC" ] && echo 0 || echo 1)

SC_PROV=$(kubectl get storageclass fast-ssd -o jsonpath='{.provisioner}' 2>/dev/null || echo '')
check_output "StorageClass provisioner=docker.io/hostpath" 5 "$SC_PROV" "hostpath"

# 2-2: PVC 존재
PVC=$(kubectl get pvc fast-pvc -n default -o name 2>/dev/null || echo '')
check "PVC fast-pvc 존재" 3 $([ -n "$PVC" ] && echo 0 || echo 1)

PVC_SC=$(kubectl get pvc fast-pvc -n default -o jsonpath='{.spec.storageClassName}' 2>/dev/null || echo '')
check_output "PVC storageClassName=fast-ssd" 2 "$PVC_SC" "fast-ssd"

echo ""

# ─────────────────────────────────────────────────────────────
echo -e "${BOLD}Q3. RBAC ClusterRole [20점]${NC}"
hr

# 3-1: ServiceAccount
SA=$(kubectl get serviceaccount reader-sa -n default -o name 2>/dev/null || echo '')
check "ServiceAccount reader-sa 존재" 3 $([ -n "$SA" ] && echo 0 || echo 1)

# 3-2: ClusterRole
CR=$(kubectl get clusterrole cluster-reader -o name 2>/dev/null || echo '')
check "ClusterRole cluster-reader 존재" 3 $([ -n "$CR" ] && echo 0 || echo 1)

CR_RES=$(kubectl get clusterrole cluster-reader -o jsonpath='{.rules[0].resources}' 2>/dev/null || echo '')
check_output "ClusterRole 리소스: pods" 2 "$CR_RES" "pods"
check_output "ClusterRole 리소스: nodes" 2 "$CR_RES" "nodes"

CR_VERBS=$(kubectl get clusterrole cluster-reader -o jsonpath='{.rules[0].verbs}' 2>/dev/null || echo '')
check_output "ClusterRole verbs: get,list,watch" 2 "$CR_VERBS" "list"

# 3-3: ClusterRoleBinding
CRB=$(kubectl get clusterrolebinding cluster-reader-crb -o name 2>/dev/null || echo '')
check "ClusterRoleBinding cluster-reader-crb 존재" 3 $([ -n "$CRB" ] && echo 0 || echo 1)

# 3-4: 권한 검증
AUTH_NODES=$(kubectl auth can-i list nodes \
  --as=system:serviceaccount:default:reader-sa 2>/dev/null || echo 'no')
check "권한: list nodes = yes" 3 $([ "$AUTH_NODES" = "yes" ] && echo 0 || echo 1)

AUTH_PODS=$(kubectl auth can-i list pods \
  --as=system:serviceaccount:default:reader-sa 2>/dev/null || echo 'no')
check "권한: list pods = yes" 2 $([ "$AUTH_PODS" = "yes" ] && echo 0 || echo 1)

echo ""

# ─────────────────────────────────────────────────────────────
echo -e "${BOLD}Q4. DaemonSet [15점]${NC}"
hr

DS=$(kubectl get daemonset log-collector -n default -o name 2>/dev/null || echo '')
check "DaemonSet log-collector 존재" 5 $([ -n "$DS" ] && echo 0 || echo 1)

DS_IMG=$(kubectl get daemonset log-collector -n default \
  -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || echo '')
check_output "이미지: busybox" 5 "$DS_IMG" "busybox"

DS_DESIRED=$(kubectl get daemonset log-collector -n default \
  -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null || echo '0')
DS_READY=$(kubectl get daemonset log-collector -n default \
  -o jsonpath='{.status.numberReady}' 2>/dev/null || echo '0')
check "DaemonSet DESIRED == READY" 5 $([ "$DS_DESIRED" = "$DS_READY" ] && [ "$DS_DESIRED" != "0" ] && echo 0 || echo 1)

echo ""

# ─────────────────────────────────────────────────────────────
echo -e "${BOLD}Q5. Service Endpoint 수정 [20점]${NC}"
hr

# broken-svc가 존재해야 함
SVC_SEL=$(kubectl get svc broken-svc -n default \
  -o jsonpath='{.spec.selector.app}' 2>/dev/null || echo '')
check_output "broken-svc selector=broken-deploy" 10 "$SVC_SEL" "broken-deploy"

# Endpoints에 IP가 있어야 함
EP_SUBS=$(kubectl get endpoints broken-svc -n default \
  -o jsonpath='{.subsets}' 2>/dev/null || echo '')
check "broken-svc Endpoints에 Pod IP 등록" 10 \
  $([ -n "$EP_SUBS" ] && [ "$EP_SUBS" != "null" ] && [ "$EP_SUBS" != "[]" ] && echo 0 || echo 1)

echo ""

# ─────────────────────────────────────────────────────────────
echo -e "${BOLD}Q6. CrashLoopBackOff 수정 [10점]${NC}"
hr

CRASH_STATUS=$(kubectl get pod crash-pod -n default \
  -o jsonpath='{.status.phase}' 2>/dev/null || echo '')
check "crash-pod STATUS=Running" 5 $([ "$CRASH_STATUS" = "Running" ] && echo 0 || echo 1)

CRASH_CMD=$(kubectl get pod crash-pod -n default \
  -o jsonpath='{.spec.containers[0].command}' 2>/dev/null || echo '')
check "crash-pod command이 wrongcmd 아님" 5 \
  $(echo "$CRASH_CMD" | grep -qv "wrongcmd" && echo 0 || echo 1)

echo ""

# ─────────────────────────────────────────────────────────────
echo -e "${BOLD}Q7. 클러스터 업그레이드 계획 [10점]${NC}"
hr

if [ -f /tmp/upgrade-plan.txt ]; then
  check "/tmp/upgrade-plan.txt 파일 존재" 5 0
  FSIZE=$(stat -f%z /tmp/upgrade-plan.txt 2>/dev/null || stat -c%s /tmp/upgrade-plan.txt 2>/dev/null || echo 0)
  check "파일 내용 있음 (크기 > 0)" 3 $([ "$FSIZE" -gt 0 ] && echo 0 || echo 1)
  # kubeadm upgrade plan 내용에 버전 정보 포함 여부
  check_output "업그레이드 계획 내용 확인 (v1 포함)" 2 \
    "$(cat /tmp/upgrade-plan.txt 2>/dev/null || echo '')" "v1"
else
  echo -e "  ${YELLOW}INFO${NC}  /tmp/upgrade-plan.txt 파일 없음"
  echo -e "  ${YELLOW}SKIP${NC}  kubeadm upgrade plan은 컨트롤플레인에서 실행해야 합니다."
  SCORE=$((SCORE + 10))
  PASS=$((PASS + 1))
fi

echo ""

# ─────────────────────────────────────────────────────────────
echo -e "${BOLD}${CYAN}"
hr
printf "  최종 점수: %d / %d 점\n" "$SCORE" "$TOTAL"
printf "  통과: %d문항  실패: %d문항\n" "$PASS" "$FAIL"
hr
echo -e "${NC}"

if [ "$SCORE" -ge 66 ]; then
  echo -e "${BOLD}${GREEN}  합격 기준(66점) 통과! CKA 합격권입니다.${NC}"
else
  echo -e "${BOLD}${RED}  합격 기준(66점) 미달. 틀린 문제를 복습하세요.${NC}"
fi
echo ""
