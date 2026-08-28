#!/usr/bin/env bash
# CKA 5강 실습 채점 스크립트
# 사용법: bash verify.sh
set -uo pipefail

PASS=0
FAIL=0
TOTAL=0

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo "=========================================="
echo "  CKA 5강 실습 채점 — 스토리지"
echo "=========================================="
echo ""

# ── 헬퍼 함수 ──────────────────────────────────────────

check() {
  local desc="$1"
  local result="$2"   # "pass" or "fail"
  TOTAL=$((TOTAL + 1))
  if [[ "$result" == "pass" ]]; then
    echo -e "  ${GREEN}[PASS]${NC} $desc"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}[FAIL]${NC} $desc"
    FAIL=$((FAIL + 1))
  fi
}

check_output() {
  local desc="$1"
  local cmd="$2"
  local expected="$3"
  TOTAL=$((TOTAL + 1))
  local actual
  actual=$(eval "$cmd" 2>/dev/null || echo "")
  if echo "$actual" | grep -qF "$expected"; then
    echo -e "  ${GREEN}[PASS]${NC} $desc"
    PASS=$((PASS + 1))
  else
    echo -e "  ${RED}[FAIL]${NC} $desc"
    echo -e "         expected: ${YELLOW}$expected${NC}"
    echo -e "         actual  : ${YELLOW}$actual${NC}"
    FAIL=$((FAIL + 1))
  fi
}

# ──────────────────────────────────────────────────────
echo -e "${CYAN}▶ P1: PV + PVC 생성 & 바인딩${NC}"

# P1-1: data-pv 존재 여부
pv_exists=$(kubectl get pv data-pv --no-headers 2>/dev/null | wc -l | tr -d ' ')
check "PV data-pv 가 존재한다" "$([ "$pv_exists" -ge 1 ] && echo pass || echo fail)"

# P1-2: PV capacity 1Gi
check_output "data-pv capacity = 1Gi" \
  "kubectl get pv data-pv -o jsonpath='{.spec.capacity.storage}'" \
  "1Gi"

# P1-3: PV accessMode RWO
check_output "data-pv accessMode = ReadWriteOnce" \
  "kubectl get pv data-pv -o jsonpath='{.spec.accessModes[0]}'" \
  "ReadWriteOnce"

# P1-4: PV hostPath /tmp/k8s-data
check_output "data-pv hostPath = /tmp/k8s-data" \
  "kubectl get pv data-pv -o jsonpath='{.spec.hostPath.path}'" \
  "/tmp/k8s-data"

# P1-5: data-pvc 존재 여부
pvc_exists=$(kubectl get pvc data-pvc -n default --no-headers 2>/dev/null | wc -l | tr -d ' ')
check "PVC data-pvc 가 존재한다 (namespace: default)" "$([ "$pvc_exists" -ge 1 ] && echo pass || echo fail)"

# P1-6: data-pvc STATUS = Bound
check_output "data-pvc STATUS = Bound" \
  "kubectl get pvc data-pvc -n default -o jsonpath='{.status.phase}'" \
  "Bound"

echo ""

# ──────────────────────────────────────────────────────
echo -e "${CYAN}▶ P2: StorageClass + PVC${NC}"

# P2-1: local-storage StorageClass 존재
sc_exists=$(kubectl get storageclass local-storage --no-headers 2>/dev/null | wc -l | tr -d ' ')
check "StorageClass local-storage 가 존재한다" "$([ "$sc_exists" -ge 1 ] && echo pass || echo fail)"

# P2-2: provisioner 확인
check_output "local-storage provisioner = kubernetes.io/no-provisioner" \
  "kubectl get storageclass local-storage -o jsonpath='{.provisioner}'" \
  "kubernetes.io/no-provisioner"

# P2-3: sc-pvc 존재
scpvc_exists=$(kubectl get pvc sc-pvc -n default --no-headers 2>/dev/null | wc -l | tr -d ' ')
check "PVC sc-pvc 가 존재한다 (namespace: default)" "$([ "$scpvc_exists" -ge 1 ] && echo pass || echo fail)"

# P2-4: sc-pvc storageClassName = local-storage
check_output "sc-pvc storageClassName = local-storage" \
  "kubectl get pvc sc-pvc -n default -o jsonpath='{.spec.storageClassName}'" \
  "local-storage"

echo ""

# ──────────────────────────────────────────────────────
echo -e "${CYAN}▶ P3: StatefulSet + volumeClaimTemplates${NC}"

# P3-1: web-sts 존재
sts_exists=$(kubectl get statefulset web-sts -n default --no-headers 2>/dev/null | wc -l | tr -d ' ')
check "StatefulSet web-sts 가 존재한다 (namespace: default)" "$([ "$sts_exists" -ge 1 ] && echo pass || echo fail)"

# P3-2: replicas = 3
check_output "web-sts replicas = 3" \
  "kubectl get statefulset web-sts -n default -o jsonpath='{.spec.replicas}'" \
  "3"

# P3-3: image = nginx:1.24
check_output "web-sts 컨테이너 이미지 = nginx:1.24" \
  "kubectl get statefulset web-sts -n default -o jsonpath='{.spec.template.spec.containers[0].image}'" \
  "nginx:1.24"

# P3-4: volumeClaimTemplate 이름 = www-storage
check_output "volumeClaimTemplates[0].metadata.name = www-storage" \
  "kubectl get statefulset web-sts -n default -o jsonpath='{.spec.volumeClaimTemplates[0].metadata.name}'" \
  "www-storage"

# P3-5: www-storage-web-sts-0 PVC 존재
pvc0_exists=$(kubectl get pvc www-storage-web-sts-0 -n default --no-headers 2>/dev/null | wc -l | tr -d ' ')
check "PVC www-storage-web-sts-0 자동 생성됨" "$([ "$pvc0_exists" -ge 1 ] && echo pass || echo fail)"

# P3-6: www-storage-web-sts-1 PVC 존재
pvc1_exists=$(kubectl get pvc www-storage-web-sts-1 -n default --no-headers 2>/dev/null | wc -l | tr -d ' ')
check "PVC www-storage-web-sts-1 자동 생성됨" "$([ "$pvc1_exists" -ge 1 ] && echo pass || echo fail)"

# P3-7: www-storage-web-sts-2 PVC 존재
pvc2_exists=$(kubectl get pvc www-storage-web-sts-2 -n default --no-headers 2>/dev/null | wc -l | tr -d ' ')
check "PVC www-storage-web-sts-2 자동 생성됨" "$([ "$pvc2_exists" -ge 1 ] && echo pass || echo fail)"

echo ""

# ──────────────────────────────────────────────────────
echo -e "${CYAN}▶ P4: emptyDir 공유 볼륨 Pod${NC}"

# P4-1: shared-vol Pod 존재
pod_exists=$(kubectl get pod shared-vol -n default --no-headers 2>/dev/null | wc -l | tr -d ' ')
check "Pod shared-vol 이 존재한다 (namespace: default)" "$([ "$pod_exists" -ge 1 ] && echo pass || echo fail)"

# P4-2: Pod Running
check_output "shared-vol Pod STATUS = Running" \
  "kubectl get pod shared-vol -n default -o jsonpath='{.status.phase}'" \
  "Running"

# P4-3: 컨테이너 수 = 2
container_count=$(kubectl get pod shared-vol -n default -o jsonpath='{.spec.containers}' 2>/dev/null | python3 -c "import sys,json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")
check "shared-vol Pod 에 컨테이너가 2개 있다" "$([ "$container_count" -eq 2 ] && echo pass || echo fail)"

# P4-4: writer 컨테이너 존재
check_output "writer 컨테이너 존재 확인" \
  "kubectl get pod shared-vol -n default -o jsonpath='{.spec.containers[*].name}'" \
  "writer"

# P4-5: reader 컨테이너 존재
check_output "reader 컨테이너 존재 확인" \
  "kubectl get pod shared-vol -n default -o jsonpath='{.spec.containers[*].name}'" \
  "reader"

# P4-6: emptyDir 볼륨 존재
check_output "shared-vol emptyDir 볼륨 사용 확인" \
  "kubectl get pod shared-vol -n default -o jsonpath='{.spec.volumes[0].emptyDir}'" \
  "{}"

echo ""

# ──────────────────────────────────────────────────────
echo "=========================================="
echo -e "  결과: ${GREEN}PASS ${PASS}${NC} / ${RED}FAIL ${FAIL}${NC} / TOTAL ${TOTAL}"
echo "=========================================="
echo ""

if [ "$FAIL" -eq 0 ]; then
  echo -e "${GREEN}[완료] 모든 문제 통과! 5강 실습을 완료했습니다.${NC}"
  exit 0
else
  echo -e "${RED}[미완료] ${FAIL}개 항목 실패. 문제를 다시 확인하세요.${NC}"
  echo ""
  echo "도움말:"
  echo "  kubectl describe pvc <이름> -n default    # PVC 이벤트 확인"
  echo "  kubectl describe pv <이름>                # PV 상태 확인"
  echo "  kubectl get events -n default             # 네임스페이스 이벤트"
  echo "  bash exam-start.sh --hints                # YAML 힌트 보기"
  exit 1
fi
