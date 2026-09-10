#!/usr/bin/env bash
# CKA 3세션 시험 — Deployment+Service · StorageClass/PVC · Gateway API
# 사용법: bash exam-start.sh [--hints] [--skip-gateway]
#
# 이 스크립트가 환경을 전부 준비한다. 수강생은 문제만 풀면 된다.
#   · shop 네임스페이스 생성
#   · StorageClass exam-storage + hostPath PV 3개 생성
#   · Gateway API CRD + NGINX Gateway Fabric 설치 (GatewayClass: nginx)
set -uo pipefail

HINTS=false
SKIP_GW=false
for arg in "$@"; do
  case "$arg" in
    --hints)        HINTS=true ;;
    --skip-gateway) SKIP_GW=true ;;
  esac
done

WORK_DIR="$(cd "$(dirname "$0")" && pwd)/work"
mkdir -p "$WORK_DIR"
MODE_FILE="$WORK_DIR/.gateway-mode"

RED='\033[0;31m'; ORANGE='\033[0;33m'; GREEN='\033[0;32m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

sep() { echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"; }

NGF_VERSION="v2.7.0"
GW_CRD_KUSTOMIZE="https://github.com/nginx/nginx-gateway-fabric/config/crd/gateway-api/standard?ref=${NGF_VERSION}"
NGF_CRDS="https://raw.githubusercontent.com/nginx/nginx-gateway-fabric/${NGF_VERSION}/deploy/crds.yaml"
NGF_DEPLOY="https://raw.githubusercontent.com/nginx/nginx-gateway-fabric/${NGF_VERSION}/deploy/nodeport/deploy.yaml"

echo ""
sep
echo -e "  ${BOLD}CKA 3세션 시험${RESET}"
echo -e "  Deployment + Service · StorageClass/PVC · Gateway API 외부 노출"
echo -e "  ${CYAN}권장 제한 시간: 35분${RESET}"
sep

# ── 클러스터 연결 확인 ────────────────────────────────────────────
echo -e "\n${CYAN}[INFO] 현재 노드 상태:${RESET}"
kubectl get nodes -o wide 2>/dev/null || {
  echo -e "${RED}[ERROR] kubectl을 실행할 수 없습니다. kubeconfig를 확인하세요.${RESET}"
  exit 1
}

# ══════════════════════════════════════════════════════════════════
# 1. 이전 시험 리소스 정리
# ══════════════════════════════════════════════════════════════════
echo -e "\n${CYAN}[CLEANUP] 이전 시험 리소스를 정리합니다...${RESET}"

if kubectl get namespace shop &>/dev/null; then
  echo -e "${CYAN}  네임스페이스 shop 삭제 중... (수십 초 걸릴 수 있음)${RESET}"
  kubectl delete namespace shop --wait=true &>/dev/null || true
fi

# PVC가 사라진 뒤에 PV 정리
for i in 1 2 3; do
  kubectl delete pv "exam-pv-${i}" --ignore-not-found &>/dev/null || true
done
kubectl delete storageclass exam-storage --ignore-not-found &>/dev/null || true
echo -e "${GREEN}[CLEANUP] 완료${RESET}"

# ══════════════════════════════════════════════════════════════════
# 2. 네임스페이스 준비
# ══════════════════════════════════════════════════════════════════
echo -e "\n${CYAN}[SETUP 1/3] shop 네임스페이스 생성${RESET}"
kubectl create namespace shop &>/dev/null || true
echo -e "${GREEN}  shop 네임스페이스 준비 완료${RESET}"

# ══════════════════════════════════════════════════════════════════
# 3. StorageClass + hostPath PV 준비
# ══════════════════════════════════════════════════════════════════
echo -e "\n${CYAN}[SETUP 2/3] StorageClass 'exam-storage' 와 hostPath PV 3개 생성${RESET}"

kubectl apply -f - &>/dev/null <<'EOF'
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: exam-storage
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: Immediate
reclaimPolicy: Retain
EOF

for i in 1 2 3; do
  kubectl apply -f - &>/dev/null <<EOF
apiVersion: v1
kind: PersistentVolume
metadata:
  name: exam-pv-${i}
  labels:
    usage: exam
spec:
  capacity:
    storage: 2Gi
  accessModes:
  - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: exam-storage
  hostPath:
    path: /mnt/exam-data-${i}
    type: DirectoryOrCreate
EOF
done

SC_OK=$(kubectl get storageclass exam-storage -o jsonpath='{.metadata.name}' 2>/dev/null || echo "")
PV_CNT=$(kubectl get pv -l usage=exam --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [[ "$SC_OK" == "exam-storage" && "$PV_CNT" == "3" ]]; then
  echo -e "${GREEN}  StorageClass exam-storage + PV 3개(각 2Gi) 준비 완료${RESET}"
else
  echo -e "${RED}  [ERROR] 스토리지 환경 준비 실패 (SC:${SC_OK:-없음} / PV:${PV_CNT}개)${RESET}"
  echo -e "${ORANGE}  Q2를 풀 수 없습니다. 클러스터 권한을 확인하세요.${RESET}"
fi

# ══════════════════════════════════════════════════════════════════
# 4. Gateway API + NGINX Gateway Fabric 설치
# ══════════════════════════════════════════════════════════════════
GW_MODE="none"

if $SKIP_GW; then
  echo -e "\n${ORANGE}[SETUP 3/3] --skip-gateway 지정됨 — Gateway API 설치를 건너뜁니다${RESET}"
else
  echo -e "\n${CYAN}[SETUP 3/3] Gateway API + NGINX Gateway Fabric 설치${RESET}"

  if kubectl get gatewayclass nginx &>/dev/null && \
     kubectl get deployment -n nginx-gateway &>/dev/null; then
    echo -e "${GREEN}  이미 설치되어 있습니다. 재설치를 건너뜁니다.${RESET}"
    GW_MODE="full"
  else
    echo -e "${CYAN}  (1/3) Gateway API CRD 설치 중...${RESET}"
    if kubectl kustomize "$GW_CRD_KUSTOMIZE" 2>/dev/null | kubectl apply -f - &>/dev/null; then
      echo -e "${GREEN}       Gateway API CRD 설치 완료${RESET}"
      GW_MODE="crds"
    else
      echo -e "${RED}       Gateway API CRD 설치 실패 (인터넷 연결 확인)${RESET}"
    fi

    if [[ "$GW_MODE" == "crds" ]]; then
      echo -e "${CYAN}  (2/3) NGINX Gateway Fabric CRD 설치 중...${RESET}"
      kubectl apply --server-side -f "$NGF_CRDS" &>/dev/null || true

      echo -e "${CYAN}  (3/3) NGINX Gateway Fabric 배포 중 (NodePort 모드)...${RESET}"
      kubectl create namespace nginx-gateway &>/dev/null || true
      if kubectl apply -f "$NGF_DEPLOY" &>/dev/null; then
        echo -e "${CYAN}       컨트롤러가 Ready 될 때까지 대기 중... (최대 3분)${RESET}"
        if kubectl wait --for=condition=Available deployment --all \
             -n nginx-gateway --timeout=180s &>/dev/null; then
          echo -e "${GREEN}       NGINX Gateway Fabric 준비 완료 (GatewayClass: nginx)${RESET}"
          GW_MODE="full"
        else
          echo -e "${ORANGE}       컨트롤러가 아직 Ready 되지 않았습니다.${RESET}"
          echo -e "${ORANGE}       kubectl get pods -n nginx-gateway 로 상태를 확인하세요.${RESET}"
        fi
      else
        echo -e "${RED}       NGINX Gateway Fabric 배포 실패${RESET}"
      fi
    fi
  fi
fi

echo "$GW_MODE" > "$MODE_FILE"

case "$GW_MODE" in
  full) echo -e "${GREEN}  → Q3를 전부 풀 수 있습니다 (설정 + 실제 외부 접속 검증).${RESET}" ;;
  crds) echo -e "${ORANGE}  → CRD만 설치됨. Q3의 리소스 작성은 가능하지만 실제 트래픽 검증은 채점에서 제외됩니다.${RESET}" ;;
  none) echo -e "${ORANGE}  → Gateway API 미설치. Q3는 채점에서 제외됩니다. (Q1·Q2만 채점)${RESET}" ;;
esac

echo ""
sep

# ══════════════════════════════════════════════════════════════════
# Q1
# ══════════════════════════════════════════════════════════════════
echo -e "\n${BOLD}${BLUE}[Q1] Deployment 를 만들고 Service 로 연결${RESET}\n"
echo -e "${BOLD}Task:${RESET}"
echo -e "  In the ${BOLD}shop${RESET} namespace, create a Deployment named ${BOLD}shop-web${RESET}"
echo -e "  using image ${BOLD}nginx:1.24${RESET} with ${BOLD}2${RESET} replicas, exposing container port ${BOLD}80${RESET}."
echo -e "  Expose it with a ${BOLD}ClusterIP${RESET} Service named ${BOLD}shop-svc${RESET} on port ${BOLD}80${RESET} → targetPort ${BOLD}80${RESET}."
echo -e "  The Service must actually route traffic to both pods."
echo ""
echo -e "${BOLD}조건 정리:${RESET}"
echo -e "  · namespace: shop            (이미 생성되어 있음)"
echo -e "  · Deployment: shop-web / nginx:1.24 / replicas 2 / containerPort 80"
echo -e "  · Service: shop-svc / ClusterIP / 80 → 80"
echo -e "  · Endpoints 에 파드 IP 2개가 등록되어야 한다"
echo ""
echo -e "${BOLD}검증 명령:${RESET}"
echo -e "  kubectl get deployment,svc,endpoints -n shop"
echo -e "  kubectl run tmp -n shop --rm -it --image=busybox:1.36 --restart=Never -- wget -qO- http://shop-svc"

if $HINTS; then
  echo ""
  echo -e "${ORANGE}[HINT Q1]${RESET}"
  echo -e "  kubectl create deployment shop-web --image=nginx:1.24 --replicas=2 --port=80 -n shop"
  echo -e "  kubectl expose deployment shop-web --name=shop-svc --port=80 --target-port=80 --type=ClusterIP -n shop"
  echo ""
  echo -e "  # Endpoints 가 비어 있으면 selector 와 파드 레이블이 어긋난 것"
  echo -e "  kubectl get endpoints shop-svc -n shop"
fi

sep

# ══════════════════════════════════════════════════════════════════
# Q2
# ══════════════════════════════════════════════════════════════════
echo -e "\n${BOLD}${ORANGE}[Q2] 주어진 StorageClass 로 PVC 를 만들어 Deployment 에 연결${RESET}\n"
echo -e "${BOLD}Task:${RESET}"
echo -e "  A StorageClass named ${BOLD}exam-storage${RESET} already exists in the cluster."
echo -e "  In the ${BOLD}shop${RESET} namespace, create a PersistentVolumeClaim named ${BOLD}shop-data${RESET}"
echo -e "  that requests ${BOLD}1Gi${RESET} with access mode ${BOLD}ReadWriteOnce${RESET} using that StorageClass."
echo -e "  Then mount it into the ${BOLD}shop-web${RESET} Deployment at ${BOLD}/data${RESET}."
echo -e "  The PVC must reach ${BOLD}Bound${RESET} state and the pods must be running with the volume mounted."
echo ""
echo -e "${BOLD}조건 정리:${RESET}"
echo -e "  · PVC: shop-data / storageClassName ${BOLD}exam-storage${RESET} / 1Gi / ReadWriteOnce"
echo -e "  · shop-web Deployment 에 마운트 — mountPath ${BOLD}/data${RESET}"
echo -e "  · PVC 상태가 ${BOLD}Bound${RESET} 여야 하고, 파드가 정상 기동해야 한다"
echo -e "  · ${ORANGE}주의: /usr/share/nginx/html 이 아니라 /data 에 마운트할 것 (Q1 검증이 깨진다)${RESET}"
echo ""
echo -e "${BOLD}검증 명령:${RESET}"
echo -e "  kubectl get sc,pv,pvc -n shop"
echo -e "  kubectl describe pvc shop-data -n shop        # Pending 이면 여기서 원인 확인"
echo -e "  kubectl exec -n shop deploy/shop-web -- df -h /data"

if $HINTS; then
  echo ""
  echo -e "${ORANGE}[HINT Q2]${RESET}"
  echo -e "  # PVC 생성"
  echo -e "  cat <<'EOF' | kubectl apply -f -"
  echo -e "  apiVersion: v1"
  echo -e "  kind: PersistentVolumeClaim"
  echo -e "  metadata:"
  echo -e "    name: shop-data"
  echo -e "    namespace: shop"
  echo -e "  spec:"
  echo -e "    storageClassName: exam-storage"
  echo -e "    accessModes: [\"ReadWriteOnce\"]"
  echo -e "    resources:"
  echo -e "      requests:"
  echo -e "        storage: 1Gi"
  echo -e "  EOF"
  echo ""
  echo -e "  # Deployment 에 볼륨 연결 — kubectl edit 로 spec.template.spec 에 추가"
  echo -e "  kubectl edit deployment shop-web -n shop"
  echo -e "  #   volumes:"
  echo -e "  #   - name: data"
  echo -e "  #     persistentVolumeClaim:"
  echo -e "  #       claimName: shop-data"
  echo -e "  #   containers 아래:"
  echo -e "  #     volumeMounts:"
  echo -e "  #     - name: data"
  echo -e "  #       mountPath: /data"
  echo ""
  echo -e "  ${BOLD}포인트:${RESET} 이 StorageClass 는 미리 만들어둔 hostPath PV(2Gi × 3)를 사용한다."
  echo -e "  요청 용량이 PV 용량보다 크면 Bound 되지 않는다. accessModes 도 일치해야 한다."
fi

sep

# ══════════════════════════════════════════════════════════════════
# Q3
# ══════════════════════════════════════════════════════════════════
echo -e "\n${BOLD}${GREEN}[Q3] Gateway API 로 외부에 노출${RESET}\n"

if [[ "$GW_MODE" == "none" ]]; then
  echo -e "${ORANGE}  Gateway API 가 설치되지 않아 이 문제는 건너뜁니다.${RESET}"
  echo -e "${ORANGE}  인터넷 연결 후 bash exam-start.sh 를 다시 실행하세요.${RESET}"
else
  echo -e "${BOLD}Task:${RESET}"
  echo -e "  The GatewayClass ${BOLD}nginx${RESET} is already installed in the cluster."
  echo -e "  In the ${BOLD}shop${RESET} namespace, create a Gateway named ${BOLD}shop-gw${RESET}"
  echo -e "  using that GatewayClass, with a listener named ${BOLD}http${RESET} on port ${BOLD}80${RESET} (protocol HTTP)."
  echo -e "  Create an HTTPRoute named ${BOLD}shop-route${RESET} attached to that Gateway,"
  echo -e "  routing all traffic (path prefix ${BOLD}/${RESET}) to the ${BOLD}shop-svc${RESET} Service on port ${BOLD}80${RESET}."
  echo -e "  Finally, expose the Gateway outside the cluster on ${BOLD}nodePort 30081${RESET}"
  echo -e "  so that ${BOLD}curl http://<NodeIP>:30081${RESET} returns the nginx page."
  echo ""
  echo -e "${BOLD}조건 정리:${RESET}"
  echo -e "  · Gateway: shop-gw / gatewayClassName ${BOLD}nginx${RESET} / listener http · port 80 · HTTP"
  echo -e "  · HTTPRoute: shop-route / parentRef ${BOLD}shop-gw${RESET} / backendRef ${BOLD}shop-svc${RESET}:80"
  echo -e "  · 외부 노출: Gateway 가 만든 Service 를 ${BOLD}NodePort 30081${RESET} 로 변경"
  echo -e "  · ${ORANGE}힌트: Gateway 를 만들면 컨트롤러가 shop 네임스페이스에 Service 를 자동 생성한다.${RESET}"
  echo -e "    ${ORANGE}kubectl get svc -n shop 으로 찾아서 nodePort 를 30081 로 바꾸면 된다.${RESET}"
  echo -e "  · ${ORANGE}접속이 안 되면 externalTrafficPolicy 를 확인할 것 — Local 이면 게이트웨이${RESET}"
  echo -e "    ${ORANGE}파드가 떠 있는 노드의 IP 로만 응답한다 (kubectl get pods -n shop -o wide).${RESET}"
  echo ""
  echo -e "${BOLD}검증 명령:${RESET}"
  echo -e "  kubectl get gateway,httproute -n shop"
  echo -e "  kubectl describe gateway shop-gw -n shop      # Accepted / Programmed 확인"
  echo -e "  kubectl get svc -n shop"
  echo -e "  curl http://<NodeIP>:30081"

  if $HINTS; then
    echo ""
    echo -e "${ORANGE}[HINT Q3]${RESET}"
    echo -e "  cat <<'EOF' | kubectl apply -f -"
    echo -e "  apiVersion: gateway.networking.k8s.io/v1"
    echo -e "  kind: Gateway"
    echo -e "  metadata:"
    echo -e "    name: shop-gw"
    echo -e "    namespace: shop"
    echo -e "  spec:"
    echo -e "    gatewayClassName: nginx"
    echo -e "    listeners:"
    echo -e "    - name: http"
    echo -e "      port: 80"
    echo -e "      protocol: HTTP"
    echo -e "      allowedRoutes:"
    echo -e "        namespaces:"
    echo -e "          from: Same"
    echo -e "  ---"
    echo -e "  apiVersion: gateway.networking.k8s.io/v1"
    echo -e "  kind: HTTPRoute"
    echo -e "  metadata:"
    echo -e "    name: shop-route"
    echo -e "    namespace: shop"
    echo -e "  spec:"
    echo -e "    parentRefs:"
    echo -e "    - name: shop-gw"
    echo -e "    rules:"
    echo -e "    - matches:"
    echo -e "      - path:"
    echo -e "          type: PathPrefix"
    echo -e "          value: /"
    echo -e "      backendRefs:"
    echo -e "      - name: shop-svc"
    echo -e "        port: 80"
    echo -e "  EOF"
    echo ""
    echo -e "  # Gateway 가 만든 Service 확인 (이름: <게이트웨이이름>-nginx → shop-gw-nginx)"
    echo -e "  kubectl get svc -n shop"
    echo -e "  # 이미 NodePort 타입이지만 포트가 랜덤 배정되어 있다 → 30081 로 변경"
    echo -e "  kubectl patch svc <서비스이름> -n shop -p \\"
    echo -e "    '{\"spec\":{\"type\":\"NodePort\",\"ports\":[{\"name\":\"http\",\"port\":80,\"targetPort\":80,\"nodePort\":30081}]}}'"
    echo ""
    echo -e "  # 노드 IP 확인 후 접속"
    echo -e "  kubectl get nodes -o wide"
    echo -e "  curl http://192.168.56.10:30081"
    echo ""
    echo -e "  ${BOLD}포인트:${RESET} Ingress 는 컨트롤러마다 annotation 이 달랐지만,"
    echo -e "  Gateway API 는 GatewayClass → Gateway → HTTPRoute 로 역할이 분리된 표준 규격이다."
  fi
fi

sep
echo ""
echo -e "${BOLD}시험 시작!${RESET}  문제를 풀고 ${CYAN}bash verify.sh${RESET} 로 채점하세요."
echo -e "${ORANGE}※ 시험 중에는 --hints 를 사용하지 마세요 (정답이 출력됩니다).${RESET}"
echo ""
