#!/usr/bin/env bash
# CKA 10강 자동 채점 스크립트 — 패키지 관리 (Helm/Kustomize)
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
    echo "  [FAIL] $desc (기대값: '$expect', 실제: '$(echo "$out" | head -2)')"
    ((FAIL++))
  fi
}

echo "================================================="
echo " CKA 10강 채점 — 패키지 관리 (Helm / Kustomize)"
echo "================================================="
echo ""

# ── P1: helm release my-nginx 확인 ──────────────────
echo "[P1] helm install my-nginx"

if ! command -v helm &>/dev/null; then
  echo "  [FAIL] helm 명령어를 찾을 수 없습니다."; ((FAIL++))
else
  check_output "helm release 'my-nginx' 존재 (deployed 상태)" \
    "helm list --all-namespaces" \
    "my-nginx"

  check_output "my-nginx Release STATUS: deployed" \
    "helm list --all-namespaces --filter my-nginx" \
    "deployed"

  # Service 확인
  NGINX_SVC=$(kubectl get svc --all-namespaces -l app.kubernetes.io/name=nginx \
    --no-headers 2>/dev/null | head -1 || true)
  if [ -n "$NGINX_SVC" ]; then
    echo "  [PASS] nginx Service 존재"; ((PASS++))
  else
    echo "  [FAIL] nginx Service를 찾을 수 없습니다."; ((FAIL++))
  fi
fi

echo ""

# ── P2: helm upgrade — replicaCount=3 확인 ──────────
echo "[P2] helm upgrade my-nginx (replicaCount=3)"

if ! command -v helm &>/dev/null; then
  echo "  [FAIL] helm 명령어를 찾을 수 없습니다."; ((FAIL++))
else
  # helm list의 REVISION이 2 이상인지 확인
  REVISION=$(helm list --all-namespaces --filter my-nginx --output json 2>/dev/null \
    | python3 -c "import sys,json; releases=json.load(sys.stdin); print(releases[0]['revision'] if releases else '0')" 2>/dev/null || echo "0")
  if [ "${REVISION:-0}" -ge 2 ] 2>/dev/null; then
    echo "  [PASS] helm Release REVISION >= 2 (upgrade 실행됨)"; ((PASS++))
  else
    echo "  [FAIL] helm Release REVISION이 2 이상이어야 합니다 (현재: ${REVISION:-?})"; ((FAIL++))
  fi

  # nginx Deployment의 replicas 확인
  NGINX_DEPLOY=$(kubectl get deployment --all-namespaces -l app.kubernetes.io/name=nginx \
    --no-headers 2>/dev/null | awk '{print $1, $2}' | head -1 || true)
  if [ -n "$NGINX_DEPLOY" ]; then
    NS=$(echo "$NGINX_DEPLOY" | awk '{print $1}')
    DEPLOY=$(echo "$NGINX_DEPLOY" | awk '{print $2}')
    REPLICAS=$(kubectl get deployment "$DEPLOY" -n "$NS" \
      -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
    if [ "${REPLICAS:-0}" -ge 3 ] 2>/dev/null; then
      echo "  [PASS] nginx Deployment replicas >= 3 (현재: ${REPLICAS})"; ((PASS++))
    else
      echo "  [FAIL] nginx Deployment replicas가 3 이상이어야 합니다 (현재: ${REPLICAS:-?})"; ((FAIL++))
    fi
  else
    echo "  [FAIL] nginx Deployment를 찾을 수 없습니다."; ((FAIL++))
  fi
fi

echo ""

# ── P3: helm rollback 확인 ───────────────────────────
echo "[P3] helm rollback my-nginx 1"

if ! command -v helm &>/dev/null; then
  echo "  [FAIL] helm 명령어를 찾을 수 없습니다."; ((FAIL++))
else
  # REVISION이 3 이상이어야 함 (install=1, upgrade=2, rollback=3)
  REVISION=$(helm list --all-namespaces --filter my-nginx --output json 2>/dev/null \
    | python3 -c "import sys,json; releases=json.load(sys.stdin); print(releases[0]['revision'] if releases else '0')" 2>/dev/null || echo "0")
  if [ "${REVISION:-0}" -ge 3 ] 2>/dev/null; then
    echo "  [PASS] helm Release REVISION >= 3 (rollback 실행됨)"; ((PASS++))
  else
    echo "  [FAIL] helm Release REVISION이 3 이상이어야 합니다 (현재: ${REVISION:-?})"; ((FAIL++))
  fi

  # helm history에 rollback 기록이 있는지 확인
  HISTORY=$(helm history my-nginx --max 10 2>/dev/null || true)
  if echo "$HISTORY" | grep -qiE "rollback|Rollback"; then
    echo "  [PASS] helm history에 rollback 기록 존재"; ((PASS++))
  else
    # REVISION 수가 3 이상이면 OK로 처리
    if [ "${REVISION:-0}" -ge 3 ] 2>/dev/null; then
      echo "  [PASS] helm history REVISION 3개 이상 확인 (rollback 실행 간주)"; ((PASS++))
    else
      echo "  [FAIL] helm history에 rollback 기록이 없습니다."; ((FAIL++))
    fi
  fi
fi

echo ""

# ── P4: Kustomize 구조 및 적용 확인 ─────────────────
echo "[P4] Kustomize base + overlay 구성"

check "overlays/dev/kustomization.yaml 파일 존재" \
  "test -f /tmp/kustomize-lab/overlays/dev/kustomization.yaml"

check "base/kustomization.yaml 파일 존재" \
  "test -f /tmp/kustomize-lab/base/kustomization.yaml"

check_output "overlays/dev/kustomization.yaml에 namePrefix 포함" \
  "cat /tmp/kustomize-lab/overlays/dev/kustomization.yaml 2>/dev/null" \
  "namePrefix"

# kubectl apply -k 결과로 dev-myapp Deployment 존재 확인
KUSTOMIZE_DEPLOY=$(kubectl get deployment --all-namespaces \
  --no-headers 2>/dev/null | grep "dev-" | head -1 || true)
if [ -n "$KUSTOMIZE_DEPLOY" ]; then
  echo "  [PASS] dev- prefix Deployment 존재 (Kustomize 적용 확인됨)"; ((PASS++))
else
  echo "  [WARN] dev- prefix Deployment를 찾을 수 없습니다."
  echo "         kubectl apply -k /tmp/kustomize-lab/overlays/dev/ 를 실행했는지 확인하세요."
  echo "         (파일 구조만 정상이면 PASS로 인정)"
  # 파일 구조가 올바른 경우 크레딧 부여
  if [ -f /tmp/kustomize-lab/overlays/dev/kustomization.yaml ] && \
     [ -f /tmp/kustomize-lab/base/kustomization.yaml ]; then
    ((PASS++))
  else
    ((FAIL++))
  fi
fi

echo ""

# ── 최종 결과 ────────────────────────────────────────
echo "================================================="
TOTAL=$((PASS + FAIL))
echo " 결과: ${PASS}/${TOTAL} 통과"
if [ "$FAIL" -eq 0 ]; then
  echo " ✓ 모든 항목 통과! 10강 실습 완료."
else
  echo " ✗ ${FAIL}개 항목 실패. 위 [FAIL] 항목을 확인하세요."
fi
echo "================================================="
