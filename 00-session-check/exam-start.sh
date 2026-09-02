#!/usr/bin/env bash
# CKA 1세션 확인 실습 — 명령어(imperative)로 Pod / Deployment / Service 만들기
# 사용법: bash exam-start.sh [--hints]
set -euo pipefail

HINTS=false
SET="s"          # s = 1일차 숙제(S1~S3) / e = 오늘 시험(E1~E3) / all = 전체
for arg in "$@"; do
  case "$arg" in
    --hints) HINTS=true ;;
    --exam)  SET="e" ;;
    --all)   SET="all" ;;
  esac
done

WORK_DIR="$(cd "$(dirname "$0")" && pwd)/work"
mkdir -p "$WORK_DIR"

RED='\033[0;31m'; ORANGE='\033[0;33m'; GREEN='\033[0;32m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

sep() { echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"; }

echo ""
sep
if [[ "$SET" == "e" ]]; then
  echo -e "  ${BOLD}CKA 2세션 시험 — 네임스페이스 · ConfigMap · Secret${RESET}"
  echo -e "  kubectl create namespace · -n 지정 · NodePort · ConfigMap · Secret"
else
  echo -e "  ${BOLD}CKA 1세션 확인 실습 — 명령어로 만들 수 있는가${RESET}"
  echo -e "  kubectl run · kubectl label · kubectl create deployment · kubectl expose"
fi
sep

# ── 클러스터 연결 확인 ────────────────────────────────────────────
echo -e "\n${CYAN}[INFO] 현재 노드 상태:${RESET}"
kubectl get nodes -o wide 2>/dev/null || {
  echo -e "${RED}[ERROR] kubectl을 실행할 수 없습니다. kubeconfig를 확인하세요.${RESET}"
  exit 1
}

# ── 기존 리소스 정리 ─────────────────────────────────────────────
echo -e "\n${CYAN}[CLEANUP] 기존 실습 리소스를 정리합니다...${RESET}"
kubectl delete pod web-pod -n default --ignore-not-found 2>/dev/null || true
kubectl delete deployment web-app -n default --ignore-not-found 2>/dev/null || true
kubectl delete service web-svc -n default --ignore-not-found 2>/dev/null || true
kubectl delete pod svc-check -n default --ignore-not-found 2>/dev/null || true

if [[ "$SET" == "e" || "$SET" == "all" ]]; then
  # 시험(E1~E3) 리소스는 네임스페이스째 정리
  for ns in ops app; do
    if kubectl get namespace "$ns" &>/dev/null; then
      echo -e "${CYAN}[CLEANUP] 네임스페이스 ${ns} 삭제 중... (수십 초 걸릴 수 있음)${RESET}"
      kubectl delete namespace "$ns" --wait=true 2>/dev/null || true
    fi
  done
fi
echo -e "${GREEN}[CLEANUP] 완료${RESET}"

if [[ "$SET" == "s" || "$SET" == "all" ]]; then

echo ""
sep

# ════════════════════════════════════════════════════════════════
# P1: 명령어로 Pod 생성 + 명령어로 레이블 부착
# ════════════════════════════════════════════════════════════════
echo -e "\n${BOLD}${BLUE}[P1] 명령어로 Pod를 만들고, 명령어로 레이블을 붙인다${RESET}\n"
echo -e "${BOLD}문제:${RESET}"
echo -e "  1) ${BOLD}web-pod${RESET} Pod를 ${BOLD}kubectl run 명령어로${RESET} default 네임스페이스에 생성하시오."
echo -e "     - 이미지: ${BOLD}nginx:1.24${RESET}"
echo -e "     - 컨테이너 포트: ${BOLD}80${RESET} 노출"
echo -e "     - 환경변수: ${BOLD}APP_ENV=prod${RESET}"
echo -e "     - ${ORANGE}조건: YAML 파일을 만들지 말고 한 줄 명령어로 생성할 것${RESET}"
echo -e "       (kubectl run이 자동으로 붙이는 ${BOLD}run=web-pod${RESET} 레이블이 남아 있어야 함)"
echo ""
echo -e "  2) 생성이 끝난 뒤 ${BOLD}kubectl label 명령어로${RESET} 아래 레이블 2개를 추가하시오."
echo -e "     - ${BOLD}tier=frontend${RESET}"
echo -e "     - ${BOLD}env=production${RESET}"
echo ""
echo -e "  3) ${BOLD}env=production${RESET} 레이블이 붙은 Pod만 조회해 결과를 확인하시오."
echo ""
echo -e "${BOLD}검증 명령:${RESET}"
echo -e "  kubectl get pod web-pod --show-labels"
echo -e "  kubectl get pods -l env=production"

if $HINTS; then
  echo ""
  echo -e "${ORANGE}[HINT P1]${RESET}"
  echo -e "  # Pod 생성 (한 줄)"
  echo -e "  kubectl run web-pod --image=nginx:1.24 --port=80 --env=\"APP_ENV=prod\""
  echo ""
  echo -e "  # 레이블 추가 (한 번에 여러 개 가능)"
  echo -e "  kubectl label pod web-pod tier=frontend env=production"
  echo ""
  echo -e "  # 이미 있는 레이블 값을 바꿀 때는 --overwrite"
  echo -e "  kubectl label pod web-pod env=production --overwrite"
  echo ""
  echo -e "  # 레이블로 조회"
  echo -e "  kubectl get pods -l env=production"
fi

sep

# ════════════════════════════════════════════════════════════════
# P2: 명령어로 Deployment 생성 + 스케일
# ════════════════════════════════════════════════════════════════
echo -e "\n${BOLD}${ORANGE}[P2] 명령어로 Deployment를 조건에 맞게 만든다${RESET}\n"
echo -e "${BOLD}문제:${RESET}"
echo -e "  1) ${BOLD}web-app${RESET} Deployment를 ${BOLD}kubectl create deployment 명령어로${RESET} 생성하시오."
echo -e "     - 네임스페이스: default"
echo -e "     - 이미지: ${BOLD}nginx:1.24${RESET}"
echo -e "     - 레플리카: ${BOLD}3${RESET}"
echo -e "     - 컨테이너 포트: ${BOLD}80${RESET} 노출"
echo ""
echo -e "  2) 생성 후 ${BOLD}kubectl scale 명령어로${RESET} 레플리카를 ${BOLD}4${RESET}로 늘리시오."
echo ""
echo -e "  3) 모든 파드가 Ready 상태가 될 때까지 롤아웃 상태를 확인하시오."
echo ""
echo -e "${BOLD}검증 명령:${RESET}"
echo -e "  kubectl get deployment web-app"
echo -e "  kubectl rollout status deployment/web-app"
echo -e "  kubectl get pods -l app=web-app"

if $HINTS; then
  echo ""
  echo -e "${ORANGE}[HINT P2]${RESET}"
  echo -e "  # Deployment 생성 (--port로 containerPort까지 지정)"
  echo -e "  kubectl create deployment web-app --image=nginx:1.24 --replicas=3 --port=80"
  echo ""
  echo -e "  # 스케일"
  echo -e "  kubectl scale deployment web-app --replicas=4"
  echo ""
  echo -e "  # 롤아웃 확인"
  echo -e "  kubectl rollout status deployment/web-app"
  echo ""
  echo -e "  # 명령어를 YAML로 미리 보고 싶을 때 (실전 필수 기술)"
  echo -e "  kubectl create deployment web-app --image=nginx:1.24 --dry-run=client -o yaml"
fi

sep

# ════════════════════════════════════════════════════════════════
# P3: 명령어로 Service 붙이기
# ════════════════════════════════════════════════════════════════
echo -e "\n${BOLD}${GREEN}[P3] P2의 Deployment에 명령어로 Service를 붙인다${RESET}\n"
echo -e "${BOLD}문제:${RESET}"
echo -e "  1) P2에서 만든 ${BOLD}web-app${RESET} Deployment를 ${BOLD}kubectl expose 명령어로${RESET} 노출하시오."
echo -e "     - Service 이름: ${BOLD}web-svc${RESET}"
echo -e "     - 타입: ${BOLD}ClusterIP${RESET}"
echo -e "     - port: ${BOLD}80${RESET} → targetPort: ${BOLD}80${RESET}"
echo -e "     - selector는 Deployment의 레이블(${BOLD}app=web-app${RESET})과 일치해야 함"
echo ""
echo -e "  2) Service의 Endpoints에 ${BOLD}파드 IP 4개${RESET}가 모두 등록됐는지 확인하시오."
echo ""
echo -e "  3) 임시 파드에서 ${BOLD}web-svc${RESET} 이름으로 HTTP 접속이 되는지 실제로 확인하시오."
echo -e "     (채점 스크립트가 동일한 통신 테스트를 수행합니다)"
echo ""
echo -e "${BOLD}검증 명령:${RESET}"
echo -e "  kubectl get svc web-svc"
echo -e "  kubectl get endpoints web-svc"
echo -e "  kubectl run tmp --rm -it --image=busybox:1.36 --restart=Never -- wget -qO- web-svc"

if $HINTS; then
  echo ""
  echo -e "${ORANGE}[HINT P3]${RESET}"
  echo -e "  # Deployment를 그대로 노출 (selector 자동 설정)"
  echo -e "  kubectl expose deployment web-app --name=web-svc --port=80 --target-port=80 --type=ClusterIP"
  echo ""
  echo -e "  # Endpoints 확인 — 여기가 비어 있으면 selector가 틀린 것"
  echo -e "  kubectl get endpoints web-svc"
  echo -e "  kubectl describe svc web-svc"
  echo ""
  echo -e "  # 실제 통신 테스트"
  echo -e "  kubectl run tmp --rm -it --image=busybox:1.36 --restart=Never -- wget -qO- web-svc"
  echo ""
  echo -e "  ${BOLD}포인트:${RESET} expose는 대상 리소스의 레이블을 selector로 그대로 복사한다."
  echo -e "  Service가 있는데 Endpoints가 비어 있으면 99% selector ↔ 파드 레이블 불일치다."
fi

fi   # ── S1~S3 끝

if [[ "$SET" == "e" || "$SET" == "all" ]]; then

echo ""
sep
echo -e "  ${BOLD}오늘의 시험 — 2세션 범위${RESET}"
echo -e "  네임스페이스 지정 · NodePort · ConfigMap · Secret"
echo -e "  ${CYAN}제한 시간 권장: 25분${RESET}"
sep

# ════════════════════════════════════════════════════════════════
# E1: 특정 네임스페이스에 Deployment + NodePort Service
# ════════════════════════════════════════════════════════════════
echo -e "\n${BOLD}${BLUE}[E1] 네임스페이스를 지정해 Deployment 와 NodePort Service 만들기${RESET}\n"
echo -e "${BOLD}Task:${RESET}"
echo -e "  Create a namespace named ${BOLD}ops${RESET}."
echo -e "  In the ${BOLD}ops${RESET} namespace, create a Deployment named ${BOLD}cache-app${RESET}"
echo -e "  using image ${BOLD}nginx:1.24${RESET} with ${BOLD}2${RESET} replicas, exposing container port ${BOLD}80${RESET}."
echo -e "  Then expose it with a ${BOLD}NodePort${RESET} Service named ${BOLD}cache-svc${RESET}"
echo -e "  on port ${BOLD}80${RESET} → targetPort ${BOLD}80${RESET}, using nodePort ${BOLD}30090${RESET}."
echo ""
echo -e "${BOLD}조건 정리:${RESET}"
echo -e "  · namespace: ops            (직접 생성)"
echo -e "  · Deployment: cache-app / nginx:1.24 / replicas 2 / containerPort 80"
echo -e "  · Service: cache-svc / NodePort / 80 → 80 / nodePort ${BOLD}30090${RESET} (반드시 이 값)"
echo -e "  · 모든 리소스는 ${BOLD}default 가 아닌 ops${RESET} 네임스페이스에 있어야 한다"
echo ""
echo -e "${BOLD}검증 명령:${RESET}"
echo -e "  kubectl get deployment,svc -n ops"
echo -e "  kubectl get endpoints cache-svc -n ops    # 파드 IP 2개"
echo -e "  curl http://<NodeIP>:30090"

if $HINTS; then
  echo ""
  echo -e "${ORANGE}[HINT E1]${RESET}"
  echo -e "  kubectl create namespace ops"
  echo -e "  kubectl create deployment cache-app --image=nginx:1.24 --replicas=2 --port=80 -n ops"
  echo -e "  kubectl expose deployment cache-app --name=cache-svc \\"
  echo -e "    --port=80 --target-port=80 --type=NodePort -n ops"
  echo ""
  echo -e "  # expose 는 nodePort 값을 지정할 수 없다 → 만든 뒤 patch 하거나 처음부터 YAML 로 만든다"
  echo -e "  kubectl patch svc cache-svc -n ops \\"
  echo -e "    -p '{\"spec\":{\"ports\":[{\"port\":80,\"targetPort\":80,\"nodePort\":30090}]}}'"
  echo ""
  echo -e "  # 매번 -n ops 를 치기 귀찮으면 컨텍스트 기본 네임스페이스를 바꿔도 된다"
  echo -e "  kubectl config set-context --current --namespace=ops"
fi

sep

# ════════════════════════════════════════════════════════════════
# E2: ConfigMap — 환경변수 주입 + 볼륨 마운트
# ════════════════════════════════════════════════════════════════
echo -e "\n${BOLD}${ORANGE}[E2] ConfigMap 을 파드에 두 가지 방식으로 주입${RESET}\n"
echo -e "${BOLD}Task:${RESET}"
echo -e "  Create a namespace named ${BOLD}app${RESET}."
echo -e "  In the ${BOLD}app${RESET} namespace, create a ConfigMap named ${BOLD}app-config${RESET}"
echo -e "  with keys ${BOLD}APP_ENV=production${RESET} and ${BOLD}LOG_LEVEL=info${RESET}."
echo -e "  Then create a Pod named ${BOLD}config-pod${RESET} (image ${BOLD}busybox:1.36${RESET}, command ${BOLD}sleep 3600${RESET})"
echo -e "  that consumes the ConfigMap in ${BOLD}both${RESET} ways:"
echo -e "    (a) all keys injected as environment variables"
echo -e "    (b) the same ConfigMap mounted as a volume at ${BOLD}/etc/app-config${RESET}"
echo ""
echo -e "${BOLD}조건 정리:${RESET}"
echo -e "  · namespace: app            (직접 생성)"
echo -e "  · ConfigMap: app-config / APP_ENV=production / LOG_LEVEL=info"
echo -e "  · Pod: config-pod / busybox:1.36 / sleep 3600"
echo -e "  · 주입 방식 2가지: ${BOLD}envFrom${RESET} 전체 주입  +  ${BOLD}볼륨 마운트${RESET} /etc/app-config"
echo ""
echo -e "${BOLD}검증 명령:${RESET}"
echo -e "  kubectl exec config-pod -n app -- env | grep -E 'APP_ENV|LOG_LEVEL'"
echo -e "  kubectl exec config-pod -n app -- cat /etc/app-config/LOG_LEVEL"

if $HINTS; then
  echo ""
  echo -e "${ORANGE}[HINT E2]${RESET}"
  echo -e "  kubectl create namespace app"
  echo -e "  kubectl create configmap app-config -n app \\"
  echo -e "    --from-literal=APP_ENV=production --from-literal=LOG_LEVEL=info"
  echo ""
  echo -e "  # 파드는 envFrom + volume 둘 다 필요하므로 YAML 로 만든다"
  echo -e "  cat <<'EOF' | kubectl apply -f -"
  echo -e "  apiVersion: v1"
  echo -e "  kind: Pod"
  echo -e "  metadata:"
  echo -e "    name: config-pod"
  echo -e "    namespace: app"
  echo -e "  spec:"
  echo -e "    containers:"
  echo -e "    - name: config-pod"
  echo -e "      image: busybox:1.36"
  echo -e "      command: [\"sleep\", \"3600\"]"
  echo -e "      envFrom:"
  echo -e "      - configMapRef:"
  echo -e "          name: app-config"
  echo -e "      volumeMounts:"
  echo -e "      - name: config-vol"
  echo -e "        mountPath: /etc/app-config"
  echo -e "    volumes:"
  echo -e "    - name: config-vol"
  echo -e "      configMap:"
  echo -e "        name: app-config"
  echo -e "  EOF"
  echo ""
  echo -e "  ${BOLD}포인트:${RESET} 볼륨으로 마운트하면 ${BOLD}키 이름이 파일명${RESET}, 값이 파일 내용이 된다."
  echo -e "  env 방식은 파드 재시작이 필요하지만, 볼륨 방식은 kubelet 이 자동 갱신한다."
fi

sep

# ════════════════════════════════════════════════════════════════
# E3: Secret — 특정 키만 선택 주입
# ════════════════════════════════════════════════════════════════
echo -e "\n${BOLD}${GREEN}[E3] Secret 을 만들고 필요한 키만 골라 주입${RESET}\n"
echo -e "${BOLD}Task:${RESET}"
echo -e "  In the ${BOLD}app${RESET} namespace, create a generic Secret named ${BOLD}db-secret${RESET}"
echo -e "  with keys ${BOLD}DB_USER=admin${RESET} and ${BOLD}DB_PASSWORD=supersecret${RESET}."
echo -e "  Then create a Pod named ${BOLD}secret-pod${RESET} (image ${BOLD}busybox:1.36${RESET}, command ${BOLD}sleep 3600${RESET})"
echo -e "  that exposes ${BOLD}only the DB_PASSWORD key${RESET} as an environment variable named ${BOLD}DB_PASSWORD${RESET}."
echo -e "  ${ORANGE}DB_USER must NOT be injected into the Pod.${RESET}"
echo ""
echo -e "${BOLD}조건 정리:${RESET}"
echo -e "  · namespace: app            (E2 에서 만든 것 재사용)"
echo -e "  · Secret: db-secret / generic / DB_USER=admin / DB_PASSWORD=supersecret"
echo -e "  · Pod: secret-pod / busybox:1.36 / sleep 3600"
echo -e "  · 주입: ${BOLD}DB_PASSWORD 만${RESET} 환경변수로 (envFrom 전체 주입은 오답)"
echo ""
echo -e "${BOLD}검증 명령:${RESET}"
echo -e "  kubectl get secret db-secret -n app -o jsonpath='{.data.DB_PASSWORD}' | base64 -d"
echo -e "  kubectl exec secret-pod -n app -- env | grep DB_"
echo -e "  # DB_PASSWORD=supersecret 만 나와야 하고 DB_USER 는 없어야 한다"

if $HINTS; then
  echo ""
  echo -e "${ORANGE}[HINT E3]${RESET}"
  echo -e "  kubectl create secret generic db-secret -n app \\"
  echo -e "    --from-literal=DB_USER=admin --from-literal=DB_PASSWORD=supersecret"
  echo ""
  echo -e "  # 특정 키만 주입 → envFrom 이 아니라 env + secretKeyRef"
  echo -e "  cat <<'EOF' | kubectl apply -f -"
  echo -e "  apiVersion: v1"
  echo -e "  kind: Pod"
  echo -e "  metadata:"
  echo -e "    name: secret-pod"
  echo -e "    namespace: app"
  echo -e "  spec:"
  echo -e "    containers:"
  echo -e "    - name: secret-pod"
  echo -e "      image: busybox:1.36"
  echo -e "      command: [\"sleep\", \"3600\"]"
  echo -e "      env:"
  echo -e "      - name: DB_PASSWORD"
  echo -e "        valueFrom:"
  echo -e "          secretKeyRef:"
  echo -e "            name: db-secret"
  echo -e "            key: DB_PASSWORD"
  echo -e "  EOF"
  echo ""
  echo -e "  ${BOLD}포인트:${RESET} create secret 은 값을 자동으로 base64 인코딩한다."
  echo -e "  직접 YAML 의 data 필드에 쓸 때는 본인이 인코딩해야 하고, stringData 를 쓰면 자동 인코딩된다."
  echo -e "  base64 는 암호화가 아니다 — 누구나 디코딩할 수 있다."
fi

sep

fi   # ── E1~E3 끝


sep
echo ""
if [[ "$SET" == "e" ]]; then
  echo -e "${BOLD}시험 준비 완료!${RESET}  문제를 풀고 ${CYAN}bash verify.sh --exam${RESET} 으로 채점하세요."
else
  echo -e "${BOLD}실습 준비 완료!${RESET}  문제를 풀고 ${CYAN}bash verify.sh${RESET} 로 채점하세요."
fi
echo -e "힌트: ${CYAN}bash exam-start.sh --hints${RESET}   /   오늘 시험만: ${CYAN}bash exam-start.sh --exam${RESET}"
echo ""
