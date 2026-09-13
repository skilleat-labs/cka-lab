#!/usr/bin/env bash
# CKA 4세션 시험 — PVC를 Deployment YAML에서 바로 연결 · Requests/Limits · Probe
# 사용법: bash exam-start.sh [--hints]
#
# 이 스크립트가 환경을 전부 준비한다. 수강생은 문제만 풀면 된다.
#   · api 네임스페이스 생성
#   · StorageClass api-storage + hostPath PV 3개 생성
#   · Q2용 Deployment api-worker 미리 생성 (리소스 제한 없음 — 수강생이 추가)
set -uo pipefail

HINTS=false
for arg in "$@"; do [[ "$arg" == "--hints" ]] && HINTS=true; done

WORK_DIR="$(cd "$(dirname "$0")" && pwd)/work"
mkdir -p "$WORK_DIR"

RED='\033[0;31m'; ORANGE='\033[0;33m'; GREEN='\033[0;32m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'

sep() { echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"; }

echo ""
sep
echo -e "  ${BOLD}CKA 4세션 시험${RESET}"
echo -e "  PVC 를 Deployment YAML 에서 바로 연결 · Requests/Limits · Probe"
echo -e "  ${CYAN}권장 제한 시간: 30분${RESET}"
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

if kubectl get namespace api &>/dev/null; then
  echo -e "${CYAN}  네임스페이스 api 삭제 중... (수십 초 걸릴 수 있음)${RESET}"
  kubectl delete namespace api --wait=true &>/dev/null || true
fi

for i in 1 2 3; do
  kubectl delete pv "api-pv-${i}" --ignore-not-found &>/dev/null || true
done
kubectl delete storageclass api-storage --ignore-not-found &>/dev/null || true
echo -e "${GREEN}[CLEANUP] 완료${RESET}"

# ══════════════════════════════════════════════════════════════════
# 2. 네임스페이스
# ══════════════════════════════════════════════════════════════════
echo -e "\n${CYAN}[SETUP 1/3] api 네임스페이스 생성${RESET}"
kubectl create namespace api &>/dev/null || true
echo -e "${GREEN}  api 네임스페이스 준비 완료${RESET}"

# ══════════════════════════════════════════════════════════════════
# 3. StorageClass + hostPath PV
# ══════════════════════════════════════════════════════════════════
echo -e "\n${CYAN}[SETUP 2/3] StorageClass 'api-storage' 와 hostPath PV 3개 생성${RESET}"

kubectl apply -f - &>/dev/null <<'EOF'
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: api-storage
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: Immediate
reclaimPolicy: Retain
EOF

for i in 1 2 3; do
  kubectl apply -f - &>/dev/null <<EOF
apiVersion: v1
kind: PersistentVolume
metadata:
  name: api-pv-${i}
  labels:
    usage: api-exam
spec:
  capacity:
    storage: 2Gi
  accessModes:
  - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  storageClassName: api-storage
  hostPath:
    path: /mnt/api-data-${i}
    type: DirectoryOrCreate
EOF
done

SC_OK=$(kubectl get storageclass api-storage -o jsonpath='{.metadata.name}' 2>/dev/null || echo "")
PV_CNT=$(kubectl get pv -l usage=api-exam --no-headers 2>/dev/null | wc -l | tr -d ' ')
if [[ "$SC_OK" == "api-storage" && "$PV_CNT" == "3" ]]; then
  echo -e "${GREEN}  StorageClass api-storage + PV 3개(각 2Gi) 준비 완료${RESET}"
else
  echo -e "${RED}  [ERROR] 스토리지 환경 준비 실패 (SC:${SC_OK:-없음} / PV:${PV_CNT}개)${RESET}"
fi

# ══════════════════════════════════════════════════════════════════
# 4. Q2용 Deployment 미리 생성 (리소스 제한 없음)
# ══════════════════════════════════════════════════════════════════
echo -e "\n${CYAN}[SETUP 3/3] Q2용 Deployment 'api-worker' 생성 (리소스 제한 없음)${RESET}"

kubectl apply -f - &>/dev/null <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-worker
  namespace: api
  labels:
    app: api-worker
spec:
  replicas: 2
  selector:
    matchLabels:
      app: api-worker
  template:
    metadata:
      labels:
        app: api-worker
    spec:
      containers:
      - name: worker
        image: nginx:1.24
        ports:
        - containerPort: 80
EOF

if kubectl get deployment api-worker -n api &>/dev/null; then
  echo -e "${GREEN}  api-worker Deployment 준비 완료 (replicas 2, 컨테이너 이름 worker)${RESET}"
else
  echo -e "${RED}  [ERROR] api-worker 생성 실패${RESET}"
fi

echo ""
sep

# ══════════════════════════════════════════════════════════════════
# Q1
# ══════════════════════════════════════════════════════════════════
echo -e "\n${BOLD}${BLUE}[Q1] PVC 를 만들고 Deployment YAML 에서 바로 연결${RESET}\n"
echo -e "${BOLD}Task:${RESET}"
echo -e "  A StorageClass named ${BOLD}api-storage${RESET} already exists in the cluster."
echo -e "  In the ${BOLD}api${RESET} namespace, create a PersistentVolumeClaim named ${BOLD}api-data${RESET}"
echo -e "  that requests ${BOLD}1Gi${RESET} with access mode ${BOLD}ReadWriteOnce${RESET} using that StorageClass."
echo -e "  Then create a Deployment named ${BOLD}api-server${RESET} (image ${BOLD}nginx:1.24${RESET}, ${BOLD}1${RESET} replica)"
echo -e "  whose manifest ${BOLD}already includes${RESET} the PVC as a volume, mounted at ${BOLD}/var/www/data${RESET}."
echo -e "  The Deployment must be created ${BOLD}with the volume from the start${RESET} — do not add it afterwards."
echo ""
echo -e "${BOLD}조건 정리:${RESET}"
echo -e "  · PVC: api-data / storageClassName ${BOLD}api-storage${RESET} / 1Gi / ReadWriteOnce"
echo -e "  · Deployment: api-server / nginx:1.24 / replicas 1"
echo -e "  · Deployment YAML 안에 volumes + volumeMounts 를 ${BOLD}처음부터${RESET} 포함해 생성"
echo -e "  · mountPath: ${BOLD}/var/www/data${RESET}"
echo -e "  · ${ORANGE}주의: Deployment 를 먼저 만들고 나중에 볼륨을 추가하면 오답 처리된다${RESET}"
echo -e "    ${ORANGE}(채점 스크립트가 Deployment 의 revision 이 1 인지 확인한다)${RESET}"
echo ""
echo -e "${BOLD}검증 명령:${RESET}"
echo -e "  kubectl get pvc api-data -n api                # Bound 확인"
echo -e "  kubectl rollout history deployment/api-server -n api   # REVISION 1 만 있어야 함"
echo -e "  kubectl exec -n api deploy/api-server -- df -h /var/www/data"

if $HINTS; then
  echo ""
  echo -e "${ORANGE}[HINT Q1]${RESET}"
  echo -e "  # 1) PVC"
  echo -e "  cat <<'EOF' | kubectl apply -f -"
  echo -e "  apiVersion: v1"
  echo -e "  kind: PersistentVolumeClaim"
  echo -e "  metadata:"
  echo -e "    name: api-data"
  echo -e "    namespace: api"
  echo -e "  spec:"
  echo -e "    storageClassName: api-storage"
  echo -e "    accessModes: [\"ReadWriteOnce\"]"
  echo -e "    resources:"
  echo -e "      requests:"
  echo -e "        storage: 1Gi"
  echo -e "  EOF"
  echo ""
  echo -e "  # 2) Deployment 뼈대를 뽑아서 볼륨을 넣은 뒤 apply"
  echo -e "  kubectl create deployment api-server --image=nginx:1.24 --replicas=1 -n api \\"
  echo -e "    --dry-run=client -o yaml > api-server.yaml"
  echo -e "  # api-server.yaml 의 spec.template.spec 에 추가:"
  echo -e "  #   volumes:"
  echo -e "  #   - name: data"
  echo -e "  #     persistentVolumeClaim:"
  echo -e "  #       claimName: api-data"
  echo -e "  #   containers[0] 에 추가:"
  echo -e "  #     volumeMounts:"
  echo -e "  #     - name: data"
  echo -e "  #       mountPath: /var/www/data"
  echo -e "  kubectl apply -f api-server.yaml"
  echo ""
  echo -e "  ${BOLD}포인트:${RESET} --dry-run=client -o yaml 로 뼈대를 뽑고 수정해서 apply 하는 것이"
  echo -e "  시험에서 YAML 을 다루는 표준 방법이다. 만든 뒤 edit 하면 revision 이 올라간다."
fi

sep

# ══════════════════════════════════════════════════════════════════
# Q2
# ══════════════════════════════════════════════════════════════════
echo -e "\n${BOLD}${ORANGE}[Q2] 기존 Deployment 에 Requests / Limits 추가${RESET}\n"
echo -e "${BOLD}Task:${RESET}"
echo -e "  A Deployment named ${BOLD}api-worker${RESET} already exists in the ${BOLD}api${RESET} namespace"
echo -e "  with ${BOLD}2${RESET} replicas and ${BOLD}no${RESET} resource requests or limits."
echo -e "  Update it so that its container (${BOLD}worker${RESET}) has:"
echo -e "    · requests:  cpu ${BOLD}100m${RESET}, memory ${BOLD}128Mi${RESET}"
echo -e "    · limits:    cpu ${BOLD}200m${RESET}, memory ${BOLD}256Mi${RESET}"
echo -e "  All pods must be rolled out and Ready with the new resource settings."
echo ""
echo -e "${BOLD}조건 정리:${RESET}"
echo -e "  · 대상: api 네임스페이스의 api-worker Deployment (이미 존재, 컨테이너 이름 worker)"
echo -e "  · requests: cpu 100m / memory 128Mi"
echo -e "  · limits:   cpu 200m / memory 256Mi"
echo -e "  · 변경 후 파드 2개가 모두 새 설정으로 Ready 여야 한다"
echo ""
echo -e "${BOLD}검증 명령:${RESET}"
echo -e "  kubectl get deployment api-worker -n api -o jsonpath='{.spec.template.spec.containers[0].resources}'"
echo -e "  kubectl get pods -n api -l app=api-worker -o jsonpath='{.items[*].status.qosClass}'   # Burstable"
echo -e "  kubectl describe pod -n api -l app=api-worker | grep -A4 Limits"

if $HINTS; then
  echo ""
  echo -e "${ORANGE}[HINT Q2]${RESET}"
  echo -e "  # 가장 빠른 방법 — 한 줄"
  echo -e "  kubectl set resources deployment api-worker -n api \\"
  echo -e "    --requests=cpu=100m,memory=128Mi --limits=cpu=200m,memory=256Mi"
  echo -e "  kubectl rollout status deployment/api-worker -n api"
  echo ""
  echo -e "  # 또는 kubectl edit deployment api-worker -n api 에서 containers[0] 아래에:"
  echo -e "  #   resources:"
  echo -e "  #     requests:"
  echo -e "  #       cpu: 100m"
  echo -e "  #       memory: 128Mi"
  echo -e "  #     limits:"
  echo -e "  #       cpu: 200m"
  echo -e "  #       memory: 256Mi"
  echo ""
  echo -e "  ${BOLD}포인트:${RESET} requests 는 스케줄링 기준(노드에 이만큼 남아야 배치), limits 는 상한."
  echo -e "  requests < limits 면 QoS 는 Burstable, 둘이 같으면 Guaranteed, 없으면 BestEffort."
fi

sep

# ══════════════════════════════════════════════════════════════════
# Q3
# ══════════════════════════════════════════════════════════════════
echo -e "\n${BOLD}${GREEN}[Q3] 조건에 맞는 Liveness / Readiness Probe 작성${RESET}\n"
echo -e "${BOLD}Task:${RESET}"
echo -e "  In the ${BOLD}api${RESET} namespace, create a Pod named ${BOLD}health-pod${RESET} using image ${BOLD}nginx:1.24${RESET}"
echo -e "  with the following probes configured on its container:"
echo -e "    · livenessProbe:   HTTP GET on path ${BOLD}/${RESET} port ${BOLD}80${RESET},"
echo -e "                       initialDelaySeconds ${BOLD}5${RESET}, periodSeconds ${BOLD}10${RESET}, failureThreshold ${BOLD}3${RESET}"
echo -e "    · readinessProbe:  HTTP GET on path ${BOLD}/${RESET} port ${BOLD}80${RESET},"
echo -e "                       initialDelaySeconds ${BOLD}3${RESET}, periodSeconds ${BOLD}5${RESET}"
echo -e "  The Pod must become ${BOLD}Ready${RESET} and must ${BOLD}not restart${RESET}."
echo ""
echo -e "${BOLD}조건 정리:${RESET}"
echo -e "  · Pod: health-pod / nginx:1.24 / namespace api"
echo -e "  · livenessProbe:  httpGet / :80 · initialDelaySeconds 5 · periodSeconds 10 · failureThreshold 3"
echo -e "  · readinessProbe: httpGet / :80 · initialDelaySeconds 3 · periodSeconds 5"
echo -e "  · 파드가 Ready 상태이고 재시작 횟수가 0 이어야 한다"
echo ""
echo -e "${BOLD}검증 명령:${RESET}"
echo -e "  kubectl get pod health-pod -n api            # READY 1/1, RESTARTS 0"
echo -e "  kubectl describe pod health-pod -n api | grep -E 'Liveness|Readiness'"

if $HINTS; then
  echo ""
  echo -e "${ORANGE}[HINT Q3]${RESET}"
  echo -e "  kubectl run health-pod --image=nginx:1.24 -n api --dry-run=client -o yaml > health-pod.yaml"
  echo -e "  # containers[0] 에 추가:"
  echo -e "  #   livenessProbe:"
  echo -e "  #     httpGet:"
  echo -e "  #       path: /"
  echo -e "  #       port: 80"
  echo -e "  #     initialDelaySeconds: 5"
  echo -e "  #     periodSeconds: 10"
  echo -e "  #     failureThreshold: 3"
  echo -e "  #   readinessProbe:"
  echo -e "  #     httpGet:"
  echo -e "  #       path: /"
  echo -e "  #       port: 80"
  echo -e "  #     initialDelaySeconds: 3"
  echo -e "  #     periodSeconds: 5"
  echo -e "  kubectl apply -f health-pod.yaml"
  echo ""
  echo -e "  ${BOLD}포인트:${RESET} liveness 실패 → 컨테이너 재시작. readiness 실패 → Service 트래픽에서 제외(재시작 안 함)."
  echo -e "  probe 경로나 포트를 잘못 쓰면 파드가 계속 재시작되거나 Ready 가 되지 않는다."
fi

sep
echo ""
echo -e "${BOLD}시험 시작!${RESET}  문제를 풀고 ${CYAN}bash verify.sh${RESET} 로 채점하세요."
echo -e "${ORANGE}※ 시험 중에는 --hints 를 사용하지 마세요 (정답이 출력됩니다).${RESET}"
echo ""
