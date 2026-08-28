#!/usr/bin/env bash
# CKA 10강 실습 초기화 스크립트 — 패키지 관리 (Helm/Kustomize)
# 사용법: bash exam-start.sh [--hints]
set -uo pipefail

HINTS=false
for arg in "$@"; do [[ "$arg" == "--hints" ]] && HINTS=true; done

WORK_DIR="$(cd "$(dirname "$0")" && pwd)/work"
mkdir -p "$WORK_DIR"

echo "================================================="
echo " CKA 10강 실습: 패키지 관리 (Helm / Kustomize)"
echo "================================================="
echo ""

# ── 현재 클러스터 상태 확인 ──────────────────────────
echo "[INFO] 현재 클러스터 상태:"
kubectl get nodes --no-headers 2>/dev/null || {
  echo "[WARN] kubectl을 실행할 수 없습니다. kubeconfig를 확인하세요."
}
echo ""

# ── 기존 실습 결과물 정리 ─────────────────────────────
echo "[SETUP] 이전 실습 결과물 정리 중..."

# P1~P3: 기존 helm release 제거
if command -v helm &>/dev/null; then
  helm uninstall my-nginx --ignore-not-found 2>/dev/null || \
    helm delete my-nginx 2>/dev/null || true
  echo "  helm release 'my-nginx' 정리 완료"
else
  echo "  [WARN] helm 명령어를 찾을 수 없습니다."
fi

# P4: Kustomize 실습 디렉토리 정리
rm -rf /tmp/kustomize-lab 2>/dev/null || true
echo "  /tmp/kustomize-lab 정리 완료"

# P1에서 생성됐을 수 있는 nginx 관련 리소스 정리
kubectl delete deployment,service,configmap -l app.kubernetes.io/name=nginx \
  -n default --ignore-not-found 2>/dev/null || true

echo "[SETUP] 정리 완료"
echo ""

# ── Helm 환경 확인 ───────────────────────────────────
echo "[SETUP] Helm 환경 확인..."
if command -v helm &>/dev/null; then
  echo "  helm: $(helm version --short 2>/dev/null || echo 'version 확인 불가')"
  echo "  등록된 repo:"
  helm repo list 2>/dev/null || echo "  (등록된 repo 없음)"
else
  echo "  [WARN] helm이 설치되지 않았습니다."
  echo "  설치: curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash"
fi
echo ""

# ── kubectl -k 지원 확인 ─────────────────────────────
echo "[SETUP] kubectl kustomize 지원 확인..."
if kubectl version --client --short 2>/dev/null | grep -q "Client"; then
  echo "  kubectl kustomize: 지원됨 (kubectl -k 사용 가능)"
else
  echo "  kubectl kustomize 지원 여부를 수동으로 확인하세요."
fi
echo ""

echo "================================================="
echo " 실습 문제"
echo "================================================="
echo ""
echo "P1. bitnami repo를 추가하고 nginx를 my-nginx로 설치하라."
echo "    - helm repo add bitnami https://charts.bitnami.com/bitnami"
echo "    - helm install my-nginx bitnami/nginx"
echo "    - service.type=NodePort 로 설정"
echo ""
echo "P2. my-nginx를 replicaCount=3으로 업그레이드하라."
echo "    - helm upgrade my-nginx bitnami/nginx --set replicaCount=3"
echo ""
echo "P3. my-nginx를 revision 1로 롤백하라."
echo "    - helm history my-nginx 로 REVISION 확인 후"
echo "    - helm rollback my-nginx 1"
echo ""
echo "P4. Kustomize 디렉토리 구조를 생성하고 kubectl apply -k로 적용하라."
echo "    - 경로: /tmp/kustomize-lab/"
echo "    - base/deployment.yaml + base/kustomization.yaml"
echo "    - overlays/dev/kustomization.yaml (namePrefix: dev-)"
echo "    - kubectl apply -k /tmp/kustomize-lab/overlays/dev/"
echo ""

if $HINTS; then
  echo "================================================="
  echo " 힌트"
  echo "================================================="
  echo ""
  echo "[P1 힌트] helm repo add + install"
  echo "  helm repo add bitnami https://charts.bitnami.com/bitnami"
  echo "  helm repo update"
  echo "  helm install my-nginx bitnami/nginx --set service.type=NodePort"
  echo "  helm list    # 설치 확인"
  echo ""
  echo "[P2 힌트] helm upgrade"
  echo "  helm upgrade my-nginx bitnami/nginx --set replicaCount=3"
  echo "  kubectl get pods    # Pod 3개 확인"
  echo ""
  echo "[P3 힌트] helm rollback"
  echo "  helm history my-nginx    # REVISION 목록 확인"
  echo "  helm rollback my-nginx 1"
  echo "  helm history my-nginx    # REVISION 3 추가 확인"
  echo ""
  echo "[P4 힌트] Kustomize"
  echo "  mkdir -p /tmp/kustomize-lab/base /tmp/kustomize-lab/overlays/dev"
  echo ""
  echo "  # base/deployment.yaml 생성"
  echo "  kubectl create deployment myapp --image=nginx:1.24 \\"
  echo "    --dry-run=client -o yaml > /tmp/kustomize-lab/base/deployment.yaml"
  echo ""
  echo "  # base/kustomization.yaml"
  echo "  cat > /tmp/kustomize-lab/base/kustomization.yaml << 'EOF'"
  echo "  apiVersion: kustomize.config.k8s.io/v1beta1"
  echo "  kind: Kustomization"
  echo "  resources:"
  echo "    - deployment.yaml"
  echo "  EOF"
  echo ""
  echo "  # overlays/dev/kustomization.yaml"
  echo "  cat > /tmp/kustomize-lab/overlays/dev/kustomization.yaml << 'EOF'"
  echo "  apiVersion: kustomize.config.k8s.io/v1beta1"
  echo "  kind: Kustomization"
  echo "  resources:"
  echo "    - ../../base"
  echo "  namePrefix: dev-"
  echo "  EOF"
  echo ""
  echo "  # 적용"
  echo "  kubectl apply -k /tmp/kustomize-lab/overlays/dev/"
  echo "  kubectl get deployment | grep dev-myapp"
  echo ""
fi

echo "================================================="
echo " 채점 방법: bash verify.sh"
echo "================================================="
