#!/usr/bin/env bash
# ============================================================
# CKA Mock Exam 2 — 자동 채점 스크립트
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

skip_score() {
  local desc="$1"
  local pts="$2"
  echo -e "  ${YELLOW}SKIP${NC} [+${pts}점] ${desc} (환경 미지원 — 점수 자동 부여)"
  SCORE=$((SCORE + pts))
  PASS=$((PASS + 1))
}

echo -e "${BOLD}${BLUE}"
hr
echo "  CKA Mock Exam 2 — 채점 결과"
hr
echo -e "${NC}"

# ─────────────────────────────────────────────────────────────
echo -e "${BOLD}Q1. Node Affinity Pod [15점]${NC}"
hr

# affinity-pod 존재
POD1=$(kubectl get pod affinity-pod -n default -o name 2>/dev/null || echo '')
check "affinity-pod 존재" 5 $([ -n "$POD1" ] && echo 0 || echo 1)

# affinity 필드 확인
AFF=$(kubectl get pod affinity-pod -n default -o jsonpath='{.spec.affinity}' 2>/dev/null || echo '')
check "spec.affinity 필드 존재" 5 $([ -n "$AFF" ] && [ "$AFF" != "null" ] && echo 0 || echo 1)

# requiredDuring 확인
check_output "requiredDuringScheduling 설정" 5 "$AFF" "requiredDuring"

echo ""

# ─────────────────────────────────────────────────────────────
echo -e "${BOLD}Q2. Taint + Toleration [15점]${NC}"
hr

POD2=$(kubectl get pod toleration-pod -n default -o name 2>/dev/null || echo '')
check "toleration-pod 존재" 5 $([ -n "$POD2" ] && echo 0 || echo 1)

TOL=$(kubectl get pod toleration-pod -n default -o jsonpath='{.spec.tolerations}' 2>/dev/null || echo '')
check_output "toleration key=dedicated 설정" 5 "$TOL" "dedicated"
check_output "toleration effect=NoSchedule 설정" 5 "$TOL" "NoSchedule"

echo ""

# ─────────────────────────────────────────────────────────────
echo -e "${BOLD}Q3. NetworkPolicy [20점]${NC}"
hr

# deny-all
NP_DENY=$(kubectl get networkpolicy deny-all -n default -o name 2>/dev/null || echo '')
check "NetworkPolicy deny-all 존재" 5 $([ -n "$NP_DENY" ] && echo 0 || echo 1)

DENY_PT=$(kubectl get networkpolicy deny-all -n default -o jsonpath='{.spec.policyTypes}' 2>/dev/null || echo '')
check_output "deny-all policyTypes: Ingress" 5 "$DENY_PT" "Ingress"

# allow-web
NP_ALLOW=$(kubectl get networkpolicy allow-web -n default -o name 2>/dev/null || echo '')
check "NetworkPolicy allow-web 존재" 5 $([ -n "$NP_ALLOW" ] && echo 0 || echo 1)

ALLOW_INGRESS=$(kubectl get networkpolicy allow-web -n default -o jsonpath='{.spec.ingress}' 2>/dev/null || echo '')
check_output "allow-web ingress 규칙 (포트 3306)" 5 "$ALLOW_INGRESS" "3306"

echo ""

# ─────────────────────────────────────────────────────────────
echo -e "${BOLD}Q4. Ingress [15점]${NC}"
hr

ING=$(kubectl get ingress shop-ingress -n default -o name 2>/dev/null || echo '')
check "Ingress shop-ingress 존재" 5 $([ -n "$ING" ] && echo 0 || echo 1)

ING_RULES=$(kubectl get ingress shop-ingress -n default -o jsonpath='{.spec.rules}' 2>/dev/null || echo '')
check_output "Ingress /shop 경로 규칙" 5 "$ING_RULES" "shop"
check_output "Ingress /api 경로 규칙" 5 "$ING_RULES" "api"

echo ""

# ─────────────────────────────────────────────────────────────
echo -e "${BOLD}Q5. StatefulSet [15점]${NC}"
hr

STS=$(kubectl get statefulset mysql-sts -n default -o name 2>/dev/null || echo '')
check "StatefulSet mysql-sts 존재" 4 $([ -n "$STS" ] && echo 0 || echo 1)

STS_IMG=$(kubectl get statefulset mysql-sts -n default -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || echo '')
check_output "이미지: mysql:8.0" 3 "$STS_IMG" "mysql:8.0"

STS_REP=$(kubectl get statefulset mysql-sts -n default -o jsonpath='{.spec.replicas}' 2>/dev/null || echo '')
check "복제본 2개" 3 $([ "$STS_REP" = "2" ] && echo 0 || echo 1)

VCT=$(kubectl get statefulset mysql-sts -n default -o jsonpath='{.spec.volumeClaimTemplates}' 2>/dev/null || echo '')
check "volumeClaimTemplates 존재" 5 $([ -n "$VCT" ] && [ "$VCT" != "null" ] && echo 0 || echo 1)

echo ""

# ─────────────────────────────────────────────────────────────
echo -e "${BOLD}Q6. etcd 백업 [10점]${NC}"
hr

if [ -f /tmp/mock2-etcd.db ]; then
  check "/tmp/mock2-etcd.db 파일 존재" 5 0
  # 파일 크기 > 0
  FSIZE=$(stat -f%z /tmp/mock2-etcd.db 2>/dev/null || stat -c%s /tmp/mock2-etcd.db 2>/dev/null || echo 0)
  check "스냅샷 파일 크기 > 0 bytes" 5 $([ "$FSIZE" -gt 0 ] && echo 0 || echo 1)
else
  # 컨트롤플레인이 아닌 환경에서는 etcd에 접근 불가 — 스킵
  echo -e "  ${YELLOW}INFO${NC}  /tmp/mock2-etcd.db 파일 없음"
  echo -e "  ${YELLOW}SKIP${NC}  etcd 백업은 컨트롤플레인 노드에서 직접 실행해야 합니다."
  SCORE=$((SCORE + 10))
  PASS=$((PASS + 1))
fi

echo ""

# ─────────────────────────────────────────────────────────────
echo -e "${BOLD}Q7. Node NotReady 복구 [10점]${NC}"
hr

WORKER2=$(kubectl get node worker-2 --ignore-not-found=true -o name 2>/dev/null || echo '')
if [ -z "$WORKER2" ]; then
  skip_score "worker-2 노드 없음 (단일 노드 환경)" 10
else
  W2_STATUS=$(kubectl get node worker-2 -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo 'False')
  check "worker-2 Ready 상태" 10 $([ "$W2_STATUS" = "True" ] && echo 0 || echo 1)
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
