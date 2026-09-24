#!/usr/bin/env bash
# CKA 7강 실습 초기화 스크립트 — Ingress와 보안 기초
# 사용법: bash exam-start.sh [--hints]
set -euo pipefail

HINTS=false
for arg in "$@"; do [[ "$arg" == "--hints" ]] && HINTS=true; done

WORK_DIR="$(cd "$(dirname "$0")" && pwd)/work"
mkdir -p "$WORK_DIR"

echo "================================================="
echo " CKA 7강 실습: Ingress와 보안 기초"
echo "================================================="
echo ""

# ── 현재 클러스터 상태 확인 ──────────────────────────
echo "[INFO] 현재 노드 상태:"
kubectl get nodes -o wide 2>/dev/null || {
  echo "[ERROR] kubectl을 실행할 수 없습니다. kubeconfig를 확인하세요."
  exit 1
}
echo ""

# ── 기존 리소스 정리 ──────────────────────────────────
echo "[SETUP] 이전 실습 리소스 정리 중..."

# Ingress 정리
kubectl delete ingress web-ingress     -n default   --ignore-not-found 2>/dev/null || true
kubectl delete ingress host-ingress    -n default   --ignore-not-found 2>/dev/null || true
kubectl delete ingress tls-ingress     -n default   --ignore-not-found 2>/dev/null || true

# Deployment / Service 정리
kubectl delete deployment web1         -n default   --ignore-not-found 2>/dev/null || true
kubectl delete service    web1-svc     -n default   --ignore-not-found 2>/dev/null || true

# Secret 정리
kubectl delete secret tls-secret       -n default   --ignore-not-found 2>/dev/null || true

# production 네임스페이스 정리
kubectl delete networkpolicy --all     -n production --ignore-not-found 2>/dev/null || true
kubectl delete deployment secure-app   -n production --ignore-not-found 2>/dev/null || true
kubectl delete namespace production                  --ignore-not-found 2>/dev/null || true

# 임시 인증서 파일 정리
rm -f "$WORK_DIR/tls.crt" "$WORK_DIR/tls.key" 2>/dev/null || true

echo "[SETUP] 정리 완료"
echo ""

# ── IngressClass 확인 ─────────────────────────────────
echo "[INFO] 사용 가능한 IngressClass:"
kubectl get ingressclass 2>/dev/null || echo "  (IngressClass 없음 — nginx 컨트롤러 설치 여부 확인)"
echo ""

echo "================================================="
echo " 실습 문제"
echo "================================================="
echo ""

echo "P1. 기본 Ingress를 생성하라."
echo "    ① Deployment 생성:"
echo "       - name: web1 / namespace: default"
echo "       - image: nginx:1.24"
echo "    ② Service 생성:"
echo "       - name: web1-svc / type: ClusterIP"
echo "       - port: 80 → targetPort: 80"
echo "    ③ Ingress 생성:"
echo "       - name: web-ingress / namespace: default"
echo "       - ingressClassName: nginx"
echo "       - rules[0].http.paths[0].path: /web1"
echo "       - pathType: Prefix"
echo "       - backend.service.name: web1-svc / port: 80"
echo ""

echo "P2. 호스트 기반 Ingress를 생성하라."
echo "    - name: host-ingress / namespace: default"
echo "    - ingressClassName: nginx"
echo "    - rules[0].host: myapp.local"
echo "    - rules[0].http.paths[0].path: /"
echo "    - pathType: Prefix"
echo "    - backend.service.name: web1-svc / port: 80"
echo ""

echo "P3. TLS Ingress를 생성하라."
echo "    ① 자체 서명 인증서 생성 (openssl):"
echo "       - CN=myapp.local, 유효기간 365일"
echo "       - 출력: tls.key, tls.crt"
echo "    ② TLS Secret 생성:"
echo "       - name: tls-secret / type: kubernetes.io/tls"
echo "       - kubectl create secret tls tls-secret --cert=tls.crt --key=tls.key"
echo "    ③ TLS Ingress 생성:"
echo "       - name: tls-ingress / namespace: default"
echo "       - spec.tls[0].hosts: [myapp.local]"
echo "       - spec.tls[0].secretName: tls-secret"
echo "       - rules[0].host: myapp.local → web1-svc:80"
echo ""

echo "P4. NetworkPolicy로 production 네임스페이스를 격리하라."
echo "    ① namespace production 생성"
echo "    ② Deployment 생성:"
echo "       - name: secure-app / namespace: production"
echo "       - image: nginx:1.24"
echo "    ③ NetworkPolicy 생성 (Default Deny All Ingress):"
echo "       - name: default-deny-all / namespace: production"
echo "       - podSelector: {} (모든 Pod)"
echo "       - policyTypes: [Ingress]"
echo "    ④ NetworkPolicy 생성 (port 8080 허용):"
echo "       - name: allow-8080 / namespace: production"
echo "       - policyTypes: [Ingress]"
echo "       - ingress[0].ports[0].port: 8080"
echo ""

# ── 힌트 ──────────────────────────────────────────────
if $HINTS; then
  echo "================================================="
  echo " 힌트"
  echo "================================================="
  echo ""

  echo "[P1 힌트]"
  echo "  # Deployment 생성:"
  echo "  kubectl create deployment web1 --image=nginx:1.24"
  echo "  # Service 생성:"
  echo "  kubectl expose deployment web1 --name=web1-svc --port=80 --target-port=80"
  echo "  # Ingress YAML 핵심:"
  echo "  # spec:"
  echo "  #   ingressClassName: nginx"
  echo "  #   rules:"
  echo "  #   - http:"
  echo "  #       paths:"
  echo "  #       - path: /web1"
  echo "  #         pathType: Prefix"
  echo "  #         backend:"
  echo "  #           service:"
  echo "  #             name: web1-svc"
  echo "  #             port:"
  echo "  #               number: 80"
  echo ""

  echo "[P2 힌트]"
  echo "  # host 필드를 rules에 추가:"
  echo "  # spec:"
  echo "  #   rules:"
  echo "  #   - host: myapp.local"
  echo "  #     http:"
  echo "  #       paths:"
  echo "  #       - path: /"
  echo "  #         pathType: Prefix"
  echo "  #         backend:"
  echo "  #           service:"
  echo "  #             name: web1-svc"
  echo "  #             port: {number: 80}"
  echo "  # 확인:"
  echo "  kubectl get ingress host-ingress"
  echo "  kubectl describe ingress host-ingress  # HOSTS 컬럼 확인"
  echo ""

  echo "[P3 힌트]"
  echo "  # 인증서 생성:"
  echo "  openssl req -x509 -nodes -days 365 -newkey rsa:2048 \\"
  echo "    -keyout tls.key -out tls.crt -subj \"/CN=myapp.local\""
  echo "  # Secret 생성:"
  echo "  kubectl create secret tls tls-secret --cert=tls.crt --key=tls.key"
  echo "  # TLS Ingress YAML 핵심:"
  echo "  # spec:"
  echo "  #   tls:"
  echo "  #   - hosts: [myapp.local]"
  echo "  #     secretName: tls-secret"
  echo "  #   rules:"
  echo "  #   - host: myapp.local"
  echo "  #     ..."
  echo ""

  echo "[P4 힌트]"
  echo "  # 네임스페이스 생성:"
  echo "  kubectl create namespace production"
  echo "  # Deployment 생성:"
  echo "  kubectl create deployment secure-app --image=nginx:1.24 -n production"
  echo "  # Default Deny NetworkPolicy YAML 핵심:"
  echo "  # spec:"
  echo "  #   podSelector: {}  # 빈 셀렉터 = 모든 Pod"
  echo "  #   policyTypes: [Ingress]"
  echo "  #   # ingress 섹션 없음 = 전체 차단"
  echo "  # 8080 허용 NetworkPolicy:"
  echo "  # spec:"
  echo "  #   podSelector: {}"
  echo "  #   policyTypes: [Ingress]"
  echo "  #   ingress:"
  echo "  #   - ports:"
  echo "  #     - port: 8080"
  echo ""
fi

echo "[INFO] 준비 완료. 작업 디렉토리: $WORK_DIR"
echo "[INFO] 완료 후 'bash verify.sh' 로 채점하세요."
