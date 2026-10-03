#!/usr/bin/env bash
# CKA 2세션 시험 — 네임스페이스 지정 · NodePort · ConfigMap · 롤아웃/롤백
# 사용법: bash exam-start.sh [--hints]
set -euo pipefail

HINTS=false
for arg in "$@"; do [[ "$arg" == "--hints" ]] && HINTS=true; done

WORK_DIR="$(cd "$(dirname "$0")" && pwd)/work"
mkdir -p "$WORK_DIR"

RED='\033[0;31m'; ORANGE='\033[0;33m'; GREEN='\033[0;32m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

sep() { echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"; }

echo ""
sep
echo -e "  ${BOLD}CKA 2세션 시험${RESET}"
echo -e "  네임스페이스 지정 · Service NodePort · ConfigMap · Deployment 롤아웃/롤백"
echo -e "  ${CYAN}권장 제한 시간: 25분${RESET}"
sep

# ── 클러스터 연결 확인 ────────────────────────────────────────────
echo -e "\n${CYAN}[INFO] 현재 노드 상태:${RESET}"
kubectl get nodes -o wide 2>/dev/null || {
  echo -e "${RED}[ERROR] kubectl을 실행할 수 없습니다. kubeconfig를 확인하세요.${RESET}"
  exit 1
}

# ── 기존 리소스 정리 ─────────────────────────────────────────────
echo -e "\n${CYAN}[CLEANUP] 이전 시험 리소스를 정리합니다...${RESET}"
for ns in ops app; do
  if kubectl get namespace "$ns" &>/dev/null; then
    echo -e "${CYAN}  네임스페이스 ${ns} 삭제 중... (수십 초 걸릴 수 있음)${RESET}"
    kubectl delete namespace "$ns" --wait=true 2>/dev/null || true
  fi
done
echo -e "${GREEN}[CLEANUP] 완료${RESET}"

echo ""
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
# E3: Deployment 스케일 · 롤링 업데이트 · 롤백
# ════════════════════════════════════════════════════════════════
echo -e "\n${BOLD}${GREEN}[E3] Deployment 스케일 · 롤링 업데이트 · 롤백${RESET}\n"
echo -e "${BOLD}Task:${RESET}"
echo -e "  In the ${BOLD}app${RESET} namespace, create a Deployment named ${BOLD}frontend${RESET}"
echo -e "  using image ${BOLD}nginx:1.24${RESET} with ${BOLD}2${RESET} replicas."
echo -e "  Then perform the following operations in order:"
echo -e "    (a) scale the Deployment to ${BOLD}4${RESET} replicas"
echo -e "    (b) perform a rolling update to image ${BOLD}nginx:1.25${RESET} and wait until it completes"
echo -e "    (c) ${BOLD}roll back${RESET} to the previous revision"
echo -e "  After the rollback, the Deployment must be running ${BOLD}nginx:1.24${RESET} with ${BOLD}4${RESET} replicas."
echo ""
echo -e "${BOLD}조건 정리:${RESET}"
echo -e "  · namespace: app            (E2 에서 만든 것 재사용)"
echo -e "  · Deployment: frontend / 최초 nginx:1.24 / replicas 2"
echo -e "  · (a) replicas 4 로 스케일  →  (b) nginx:1.25 로 롤링 업데이트  →  (c) 롤백"
echo -e "  · 최종 상태: 이미지 ${BOLD}nginx:1.24${RESET} / replicas ${BOLD}4${RESET} / 전부 Ready"
echo -e "  · ${ORANGE}세 단계를 실제로 거쳐야 한다 — 처음부터 1.24 로 두고 스케일만 하면 오답${RESET}"
echo ""
echo -e "${BOLD}검증 명령:${RESET}"
echo -e "  kubectl get deployment frontend -n app"
echo -e "  kubectl rollout history deployment/frontend -n app   # 리비전 3개 이상"
echo -e "  kubectl get rs -n app                                # 이전 RS 가 남아 있어야 함"

if $HINTS; then
  echo ""
  echo -e "${ORANGE}[HINT E3]${RESET}"
  echo -e "  # 생성"
  echo -e "  kubectl create deployment frontend --image=nginx:1.24 --replicas=2 -n app"
  echo ""
  echo -e "  # (a) 스케일"
  echo -e "  kubectl scale deployment frontend --replicas=4 -n app"
  echo ""
  echo -e "  # (b) 롤링 업데이트 — 컨테이너 이름은 describe 로 확인 (create deployment 는 이미지명과 동일)"
  echo -e "  kubectl set image deployment/frontend nginx=nginx:1.25 -n app"
  echo -e "  kubectl rollout status deployment/frontend -n app"
  echo ""
  echo -e "  # (c) 롤백"
  echo -e "  kubectl rollout undo deployment/frontend -n app"
  echo -e "  kubectl rollout status deployment/frontend -n app"
  echo ""
  echo -e "  # 이력 확인 / 특정 리비전으로 롤백"
  echo -e "  kubectl rollout history deployment/frontend -n app"
  echo -e "  kubectl rollout undo deployment/frontend --to-revision=1 -n app"
  echo ""
  echo -e "  ${BOLD}포인트:${RESET} 롤백은 이전 ReplicaSet 을 다시 살리는 것이다."
  echo -e "  그래서 업데이트 후에도 예전 RS 가 replicas 0 인 채로 남아 있고, 이게 롤백의 재료다."
fi

sep



echo ""
echo -e "${BOLD}시험 시작!${RESET}  문제를 풀고 ${CYAN}bash verify.sh${RESET} 로 채점하세요."
echo -e "${ORANGE}※ 시험 중에는 --hints 를 사용하지 마세요 (정답 명령어가 출력됩니다).${RESET}"
echo ""
