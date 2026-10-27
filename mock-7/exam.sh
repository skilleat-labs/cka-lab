#!/usr/bin/env bash
# CKA Mock Exam 7 — 스토리지 · NetworkPolicy · Gateway API · 자원 · 우선순위 (100점 · 5문항)
# 사용법: bash exam.sh start → 풀고 → bash exam.sh check → ...
#
# 목적: 실제로 "돌아가는지" 까지 보는 다섯 문제.
#   Q1 StorageClass 로 PVC → Deployment 마운트 · Q2 NetworkPolicy(네임스페이스 AND 파드)
#   Q3 Gateway API 경로 라우팅 · Q4 ResourceQuota 에 막힌 Deployment 에 requests/limits
#   Q5 PriorityClass 로 선점(preemption)
# Gateway API 컨트롤러(NGINX Gateway Fabric)는 start 가 없으면 설치한다 — VM 에서 인터넷이 돼야 한다.
# 문제마다 네임스페이스가 따로라 순서와 상관없이 풀 수 있다.
set -uo pipefail
EXAM_UNIT="점"
source "$(cd "$(dirname "$0")/.." && pwd)/_lib/exam-lib.sh"

EXAM_TITLE="CKA Mock Exam 7 — 스토리지 · NetworkPolicy · Gateway API · 자원 · 우선순위 (100점 · 5문항)"
EXAM_NQ=5
EXAM_LIMIT_MIN="${EXAM_LIMIT_MIN:-40}"   # 제한시간(분) — 0 이면 무제한

# ── Q3: Gateway API + NGINX Gateway Fabric (08-ingress · tutoring/session-3 과 같은 버전·방식) ──
NGF_VERSION="v2.7.0"
GW_CRD_KUSTOMIZE="https://github.com/nginx/nginx-gateway-fabric/config/crd/gateway-api/standard?ref=${NGF_VERSION}"
NGF_CRDS="https://raw.githubusercontent.com/nginx/nginx-gateway-fabric/${NGF_VERSION}/deploy/crds.yaml"
NGF_DEPLOY="https://raw.githubusercontent.com/nginx/nginx-gateway-fabric/${NGF_VERSION}/deploy/nodeport/deploy.yaml"
MODE_FILE="$WORK_DIR/.gateway-mode"
gw_mode() { cat "$MODE_FILE" 2>/dev/null || echo none; }
Q3_HOST=portal.example.local

# ── Q5: 노드에 붙이는 가짜 장치(확장 리소스). 실제 CPU·메모리를 잡지 않고 "자리 2개" 를 만든다
ACCEL="example.com/accelerator"
ACCEL_JP='example\.com/accelerator'
ACCEL_PATCH_PATH="example.com~1accelerator"
ACCEL_NODE_FILE="$WORK_DIR/.accel-node"
accel_node() { cat "$ACCEL_NODE_FILE" 2>/dev/null; }

NAMESPACES="media orders web-team qa-team portal batch ml"

# "지우고 다시 만들기" 를 잡으려고 start 때 Deployment uid 를 적어 둔다
save_uid() { kubectl -n "$1" get deployment "$2" -o jsonpath='{.metadata.uid}' > "$WORK_DIR/.uid-$1-$2" 2>/dev/null || true; }
same_uid() {
  local want now; want=$(cat "$WORK_DIR/.uid-$1-$2" 2>/dev/null)
  now=$(kubectl -n "$1" get deployment "$2" -o jsonpath='{.metadata.uid}' 2>/dev/null)
  [[ -n "$want" && "$want" == "$now" ]]
}

accel_remove() {
  local n
  for n in $(kubectl get nodes -o jsonpath="{range .items[*]}{.metadata.name}={.status.capacity.${ACCEL_JP}}{\"\\n\"}{end}" 2>/dev/null \
             | awk -F= '$2!=""{print $1}'); do
    kubectl patch node "$n" --subresource=status --type=json \
      -p "[{\"op\":\"remove\",\"path\":\"/status/capacity/${ACCEL_PATCH_PATH}\"}]" &>/dev/null \
      && echo "  노드 $n 에서 $ACCEL 제거"
    kubectl patch node "$n" --subresource=status --type=json \
      -p "[{\"op\":\"remove\",\"path\":\"/status/allocatable/${ACCEL_PATCH_PATH}\"}]" &>/dev/null || true
  done
}

exam_cleanup() {
  local ns
  for ns in $NAMESPACES; do
    kubectl get namespace "$ns" &>/dev/null && kubectl delete namespace "$ns" --wait=false &>/dev/null
  done
  kdel pv media-pv-1 media-pv-2 archive-pv-1
  kdel storageclass media-store media-archive
  kdel priorityclass ml-batch inference-critical
  accel_remove
  rm -f "$MODE_FILE" "$ACCEL_NODE_FILE" "$WORK_DIR"/.uid-*
  for ns in $NAMESPACES; do
    kubectl wait --for=delete namespace/"$ns" --timeout=90s &>/dev/null || true
  done
  echo "  media · orders · web-team · qa-team · portal · batch · ml 네임스페이스"
  echo "  PV media-pv-1·2 · archive-pv-1 / StorageClass media-store · media-archive / PriorityClass ml-batch · inference-critical 삭제"
  echo "  (Gateway API 컨트롤러는 남겨둠 — 완전 제거: kubectl delete ns nginx-gateway)"
}

setup_gateway_api() {
  # 08-ingress 의 q5_setup_gateway_api 와 같은 절차 — 이미 설치돼 있으면 건너뛴다
  local mode="none"
  if kubectl get gatewayclass nginx &>/dev/null \
     && [[ -n "$(kubectl -n nginx-gateway get deploy -o name 2>/dev/null)" ]] \
     && kubectl -n nginx-gateway wait --for=condition=Available deploy --all --timeout=60s &>/dev/null; then
    echo "  Q3  Gateway API 이미 설치됨 — 건너뜀"; mode="full"
  else
    echo "  Q3  Gateway API CRD 설치 중..."
    if kubectl kustomize "$GW_CRD_KUSTOMIZE" 2>/dev/null | kubectl apply -f - &>/dev/null; then
      mode="crds"
      kubectl apply --server-side -f "$NGF_CRDS" &>/dev/null || true
      kubectl create namespace nginx-gateway &>/dev/null || true
      echo "  Q3  NGINX Gateway Fabric 배포 중 (최대 3분)..."
      if kubectl apply -f "$NGF_DEPLOY" &>/dev/null && \
         kubectl wait --for=condition=Available deployment --all -n nginx-gateway --timeout=180s &>/dev/null; then
        mode="full"; echo "  Q3  NGINX Gateway Fabric 준비 완료 (GatewayClass: nginx)"
      else
        echo "  Q3  컨트롤러가 아직 Ready 되지 않음 — kubectl get pods -n nginx-gateway 로 확인"
      fi
    else
      echo "  Q3  Gateway API CRD 설치 실패 (인터넷 연결 확인)"
    fi
  fi

  # 데이터 플레인을 DaemonSet 으로 (모든 노드의 NodePort 로 접속되도록)
  if [[ "$mode" == "full" ]]; then
    local patch='{"spec":{"kubernetes":{"deployment":null,"daemonSet":{"patches":[{"type":"StrategicMerge","value":{"spec":{"template":{"spec":{"tolerations":[{"key":"node-role.kubernetes.io/control-plane","operator":"Exists","effect":"NoSchedule"}]}}}}}]}}}}'
    local pn pns; pn=$(kubectl get gatewayclass nginx -o jsonpath='{.spec.parametersRef.name}' 2>/dev/null); pns=$(kubectl get gatewayclass nginx -o jsonpath='{.spec.parametersRef.namespace}' 2>/dev/null)
    if [[ -n "$pn" && -n "$pns" ]]; then
      kubectl patch nginxproxy "$pn" -n "$pns" --type=merge -p "$patch" &>/dev/null && echo "  Q3  게이트웨이 데이터 플레인 → DaemonSet"
    else
      kubectl apply -f - &>/dev/null <<'EOF'
apiVersion: gateway.nginx.org/v1alpha2
kind: NginxProxy
metadata: { name: exam-proxy-config, namespace: nginx-gateway }
spec:
  kubernetes:
    daemonSet:
      patches:
      - type: StrategicMerge
        value:
          spec:
            template:
              spec:
                tolerations:
                - { key: node-role.kubernetes.io/control-plane, operator: Exists, effect: NoSchedule }
EOF
      kubectl patch gatewayclass nginx --type=merge -p '{"spec":{"parametersRef":{"group":"gateway.nginx.org","kind":"NginxProxy","name":"exam-proxy-config","namespace":"nginx-gateway"}}}' &>/dev/null && echo "  Q3  게이트웨이 데이터 플레인 → DaemonSet"
    fi
  fi
  echo "$mode" > "$MODE_FILE"
  case "$mode" in
    full) echo "  Q3  → 전부 채점 가능" ;;
    crds) echo -e "  ${ORANGE}Q3  → CRD 만 설치됨. 리소스 작성은 채점되지만 상태·트래픽 검증은 제외${RESET}" ;;
    none) echo -e "  ${RED}Q3  → Gateway API 미설치. 인터넷 연결 후 bash exam.sh start 를 다시${RESET}" ;;
  esac
}

exam_setup() {
  # ── Q1: StorageClass 두 개(하나는 미끼) + 미리 만든 PV + 볼륨 없는 Deployment
  #   hostPath 경로는 시작할 때마다 바꾼다 — 지난 시도에 써 둔 index.html 이 남아 통과되지 않게
  local media_dir="/mnt/mock7-media-$(date +%s)"
  cat <<YAML | kubectl apply -f - &>/dev/null
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata: { name: media-store }
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: WaitForFirstConsumer
reclaimPolicy: Retain
---
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata: { name: media-archive }
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: Immediate
reclaimPolicy: Retain
---
apiVersion: v1
kind: PersistentVolume
metadata: { name: media-pv-1 }
spec:
  capacity: { storage: 1Gi }
  accessModes: [ReadWriteOnce]
  persistentVolumeReclaimPolicy: Retain
  storageClassName: media-store
  hostPath: { path: ${media_dir}-1, type: DirectoryOrCreate }
---
apiVersion: v1
kind: PersistentVolume
metadata: { name: media-pv-2 }
spec:
  capacity: { storage: 2Gi }
  accessModes: [ReadWriteOnce]
  persistentVolumeReclaimPolicy: Retain
  storageClassName: media-store
  hostPath: { path: ${media_dir}-2, type: DirectoryOrCreate }
---
apiVersion: v1
kind: PersistentVolume
metadata: { name: archive-pv-1 }
spec:
  capacity: { storage: 1Gi }
  accessModes: [ReadWriteOnce]
  persistentVolumeReclaimPolicy: Retain
  storageClassName: media-archive
  hostPath: { path: ${media_dir}-archive, type: DirectoryOrCreate }
---
apiVersion: v1
kind: Namespace
metadata: { name: media }
---
apiVersion: apps/v1
kind: Deployment
metadata: { name: media-web, namespace: media, labels: { app: media-web } }
spec:
  replicas: 1
  selector: { matchLabels: { app: media-web } }
  template:
    metadata: { labels: { app: media-web } }
    spec:
      containers:
        - name: web
          image: nginx:1.27
          ports: [ { containerPort: 80 } ]
YAML
  save_uid media media-web
  echo "  Q1  StorageClass media-store · media-archive, PV 3개, media/media-web 배치"

  # ── Q2: 보호할 api + 이미 있는 '전부 허용' 정책 + 접속을 시도할 파드 네 개
  cat <<'YAML' | kubectl apply -f - &>/dev/null
apiVersion: v1
kind: Namespace
metadata: { name: orders }
---
apiVersion: v1
kind: Namespace
metadata: { name: web-team, labels: { team: web } }
---
apiVersion: v1
kind: Namespace
metadata: { name: qa-team, labels: { team: qa } }
---
apiVersion: apps/v1
kind: Deployment
metadata: { name: api, namespace: orders, labels: { app: api } }
spec:
  replicas: 1
  selector: { matchLabels: { app: api } }
  template:
    metadata: { labels: { app: api } }
    spec:
      containers:
        - name: nginx
          image: nginx:1.27
          ports: [ { containerPort: 80 } ]
---
apiVersion: v1
kind: Service
metadata: { name: api, namespace: orders }
spec:
  selector: { app: api }
  ports: [ { port: 80, targetPort: 80 } ]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: legacy-open, namespace: orders }
spec:
  podSelector: { matchLabels: { app: api } }
  policyTypes: [Ingress]
  ingress:
    - {}
---
apiVersion: v1
kind: Pod
metadata: { name: monitor, namespace: orders, labels: { app: monitor } }
spec:
  terminationGracePeriodSeconds: 1
  containers: [ { name: c, image: busybox:1.36, command: ["sh", "-c", "sleep 36000"] } ]
---
apiVersion: v1
kind: Pod
metadata: { name: frontend, namespace: web-team, labels: { app: frontend } }
spec:
  terminationGracePeriodSeconds: 1
  containers: [ { name: c, image: busybox:1.36, command: ["sh", "-c", "sleep 36000"] } ]
---
apiVersion: v1
kind: Pod
metadata: { name: batch, namespace: web-team, labels: { app: batch } }
spec:
  terminationGracePeriodSeconds: 1
  containers: [ { name: c, image: busybox:1.36, command: ["sh", "-c", "sleep 36000"] } ]
---
apiVersion: v1
kind: Pod
metadata: { name: frontend, namespace: qa-team, labels: { app: frontend } }
spec:
  terminationGracePeriodSeconds: 1
  containers: [ { name: c, image: busybox:1.36, command: ["sh", "-c", "sleep 36000"] } ]
YAML
  echo "  Q2  orders/api(+Service, 정책 legacy-open) · orders/monitor · web-team/frontend · web-team/batch · qa-team/frontend 배치"

  # ── Q3: 컨트롤러 + 백엔드 두 개 (경로와 상관없이 자기 이름을 돌려준다)
  setup_gateway_api
  cat <<'YAML' | kubectl apply -f - &>/dev/null
apiVersion: v1
kind: Namespace
metadata: { name: portal }
---
apiVersion: v1
kind: ConfigMap
metadata: { name: portal-main-conf, namespace: portal }
data:
  default.conf: |
    server { listen 80; location / { default_type text/plain; return 200 "portal-main $request_uri\n"; } }
---
apiVersion: v1
kind: ConfigMap
metadata: { name: portal-api-conf, namespace: portal }
data:
  default.conf: |
    server { listen 80; location / { default_type text/plain; return 200 "portal-api $request_uri\n"; } }
---
apiVersion: apps/v1
kind: Deployment
metadata: { name: portal-main, namespace: portal, labels: { app: portal-main } }
spec:
  replicas: 1
  selector: { matchLabels: { app: portal-main } }
  template:
    metadata: { labels: { app: portal-main } }
    spec:
      containers:
        - name: nginx
          image: nginx:1.27
          ports: [ { containerPort: 80 } ]
          volumeMounts: [ { name: conf, mountPath: /etc/nginx/conf.d } ]
      volumes: [ { name: conf, configMap: { name: portal-main-conf } } ]
---
apiVersion: apps/v1
kind: Deployment
metadata: { name: portal-api, namespace: portal, labels: { app: portal-api } }
spec:
  replicas: 1
  selector: { matchLabels: { app: portal-api } }
  template:
    metadata: { labels: { app: portal-api } }
    spec:
      containers:
        - name: nginx
          image: nginx:1.27
          ports: [ { containerPort: 80 } ]
          volumeMounts: [ { name: conf, mountPath: /etc/nginx/conf.d } ]
      volumes: [ { name: conf, configMap: { name: portal-api-conf } } ]
---
apiVersion: v1
kind: Service
metadata: { name: portal-main, namespace: portal }
spec:
  selector: { app: portal-main }
  ports: [ { port: 80, targetPort: 80 } ]
---
apiVersion: v1
kind: Service
metadata: { name: portal-api, namespace: portal }
spec:
  selector: { app: portal-api }
  ports: [ { port: 80, targetPort: 80 } ]
YAML
  echo "  Q3  portal/portal-main · portal/portal-api (+Service) 배치"

  # ── Q4: requests/limits 를 강제하는 ResourceQuota + 자원 설정 없는 2컨테이너 Deployment (파드 0개)
  cat <<'YAML' | kubectl apply -f - &>/dev/null
apiVersion: v1
kind: Namespace
metadata: { name: batch }
---
apiVersion: v1
kind: ResourceQuota
metadata: { name: batch-quota, namespace: batch }
spec:
  hard:
    requests.cpu: 500m
    requests.memory: 512Mi
    limits.cpu: "1"
    limits.memory: 1Gi
    pods: "5"
---
apiVersion: apps/v1
kind: Deployment
metadata: { name: worker, namespace: batch, labels: { app: worker } }
spec:
  replicas: 3
  selector: { matchLabels: { app: worker } }
  template:
    metadata: { labels: { app: worker } }
    spec:
      terminationGracePeriodSeconds: 1
      containers:
        - name: app
          image: busybox:1.36
          command: ["sh", "-c", "while true; do echo working; sleep 10; done"]
        - name: log-agent
          image: busybox:1.36
          command: ["sh", "-c", "sleep 36000"]
YAML
  save_uid batch worker
  echo "  Q4  batch/batch-quota · batch/worker (replicas 3, 지금 파드 0개) 배치"

  # ── Q5: 노드 하나에 가짜 장치 2개 → 우선순위 낮은 trainer 가 다 쓰고, inference 는 Pending
  local node
  node=$(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}|{.spec.taints[*].effect}|{.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}' 2>/dev/null \
         | awk -F'|' '$3=="True" && $2 !~ /NoSchedule|NoExecute/ {print $1}' | head -1)
  [[ -z "$node" ]] && node=$(kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}|{.status.conditions[?(@.type=="Ready")].status}{"\n"}{end}' 2>/dev/null \
         | awk -F'|' '$2=="True"{print $1}' | head -1)
  echo "$node" > "$ACCEL_NODE_FILE"
  if [[ -n "$node" ]] && kubectl patch node "$node" --subresource=status --type=json \
       -p "[{\"op\":\"add\",\"path\":\"/status/capacity/${ACCEL_PATCH_PATH}\",\"value\":\"2\"}]" &>/dev/null; then
    local i
    for i in $(seq 1 15); do
      [[ "$(kubectl get node "$node" -o jsonpath="{.status.allocatable.${ACCEL_JP}}" 2>/dev/null)" == "2" ]] && break
      sleep 2
    done
    echo "  Q5  노드 $node 에 $ACCEL 2개 추가"
  else
    echo -e "  ${RED}Q5  노드에 $ACCEL 을 붙이지 못했습니다 — kubectl 1.27 이상(--subresource) 인지 확인${RESET}"
  fi
  cat <<YAML | kubectl apply -f - &>/dev/null
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata: { name: ml-batch }
value: 100
description: "existing — offline training"
---
apiVersion: v1
kind: Namespace
metadata: { name: ml }
---
apiVersion: apps/v1
kind: Deployment
metadata: { name: trainer, namespace: ml, labels: { app: trainer } }
spec:
  replicas: 2
  selector: { matchLabels: { app: trainer } }
  template:
    metadata: { labels: { app: trainer } }
    spec:
      priorityClassName: ml-batch
      terminationGracePeriodSeconds: 1
      tolerations: [ { key: node-role.kubernetes.io/control-plane, operator: Exists, effect: NoSchedule } ]
      containers:
        - name: train
          image: busybox:1.36
          command: ["sh", "-c", "sleep 36000"]
          resources:
            requests: { cpu: 10m, memory: 16Mi, ${ACCEL}: "1" }
            limits:   { ${ACCEL}: "1" }
YAML
  kubectl -n ml rollout status deployment trainer --timeout=60s &>/dev/null || true
  cat <<YAML | kubectl apply -f - &>/dev/null
apiVersion: apps/v1
kind: Deployment
metadata: { name: inference, namespace: ml, labels: { app: inference } }
spec:
  replicas: 1
  selector: { matchLabels: { app: inference } }
  template:
    metadata: { labels: { app: inference } }
    spec:
      terminationGracePeriodSeconds: 1
      tolerations: [ { key: node-role.kubernetes.io/control-plane, operator: Exists, effect: NoSchedule } ]
      containers:
        - name: serve
          image: busybox:1.36
          command: ["sh", "-c", "sleep 36000"]
          resources:
            requests: { cpu: 10m, memory: 16Mi, ${ACCEL}: "1" }
            limits:   { ${ACCEL}: "1" }
YAML
  save_uid ml trainer
  save_uid ml inference
  echo "  Q5  PriorityClass ml-batch(100), ml/trainer 2개 Running · ml/inference Pending"
  return 0
}

# ══════════════════════════════════════════════════════════════
# Q1 — StorageClass 로 PVC 를 만들어 Deployment 에 마운트
# ══════════════════════════════════════════════════════════════
q1_title() { echo "PVC from a StorageClass, mounted into a Deployment [20 pts]"; }
q1_text() { cat <<'EOF'
The StorageClass media-store and some PersistentVolumes already exist.

  (a) In the media namespace, create a PVC named media-data
        storageClassName   media-store
        request            1Gi
        access mode        ReadWriteOnce

  (b) Mount it into the EXISTING Deployment media-web (container web)
      at /usr/share/nginx/html. Do not delete the Deployment.

  (c) Through the running Pod, create the file
      /usr/share/nginx/html/index.html containing exactly:  media-ok

Do not create any PV and do not set volumeName in the PVC.
The PVC must be Bound and the Pod must be Running.

Verify:
  kubectl get sc,pv
  kubectl -n media get pvc media-data
  kubectl -n media exec deploy/media-web -c web -- df -h /usr/share/nginx/html
EOF
}
q1_title_ko() { echo "StorageClass 로 PVC 만들어 Deployment 에 마운트 [20점]"; }
q1_text_ko() { cat <<'EOF'
StorageClass media-store 와 PersistentVolume 몇 개가 이미 있다.

  (a) media 네임스페이스에 PVC media-data 를 만든다
        storageClassName   media-store
        요청 용량          1Gi
        접근 모드          ReadWriteOnce

  (b) 이미 있는 Deployment media-web(컨테이너 web)에
      /usr/share/nginx/html 로 마운트한다. Deployment 를 지우지 않는다.

  (c) 실행 중인 파드 안에서 /usr/share/nginx/html/index.html 을 만들고
      내용을 정확히  media-ok  로 한다.

PV 는 만들지 않고, PVC 에 volumeName 도 적지 않는다.
PVC 는 Bound, 파드는 Running 이어야 한다.

[확인]
  kubectl get sc,pv
  kubectl -n media get pvc media-data
  kubectl -n media exec deploy/media-web -c web -- df -h /usr/share/nginx/html
EOF
}
q1_hint() { cat <<'EOF'
kubectl get sc media-store      # VOLUMEBINDINGMODE 가 WaitForFirstConsumer
                                # → 파드가 PVC 를 쓰기 전까지 PVC 가 Pending 인 것이 정상이다

apiVersion: v1
kind: PersistentVolumeClaim
metadata: { name: media-data, namespace: media }
spec:
  storageClassName: media-store
  accessModes: [ReadWriteOnce]
  resources: { requests: { storage: 1Gi } }

kubectl -n media edit deployment media-web
# spec.template.spec 아래
#   volumes:
#     - name: data
#       persistentVolumeClaim: { claimName: media-data }
# containers[web] 아래
#   volumeMounts:
#     - { name: data, mountPath: /usr/share/nginx/html }

kubectl -n media rollout status deployment media-web
kubectl -n media exec deploy/media-web -c web -- sh -c 'echo media-ok > /usr/share/nginx/html/index.html'
EOF
}
q1_grade() {
  local PVC="kubectl -n media get pvc media-data -o jsonpath"
  local DEP="kubectl -n media get deployment media-web -o jsonpath"
  check "PVC media-data 존재" "kubectl -n media get pvc media-data" 2
  check_output "storageClassName media-store" "$PVC='{.spec.storageClassName}'" '^media-store$' 3
  check_output "1Gi · ReadWriteOnce" "$PVC='{.spec.resources.requests.storage}/{.spec.accessModes[0]}'" '^1Gi/ReadWriteOnce$' 2
  check_output "Bound — media-store 의 PV(media-pv-*) 에 붙었다" \
    "$PVC='{.status.phase}/{.spec.volumeName}'" '^Bound/media-pv-[12]$' 3
  check_output "Deployment 볼륨이 PVC media-data 를 가리킨다" \
    "$DEP='{.spec.template.spec.volumes[*].persistentVolumeClaim.claimName}'" '(^| )media-data( |$)' 2
  # 마운트한 볼륨 이름이 실제로 media-data 를 가리키는 볼륨인지까지 본다
  local vol mnt
  vol=$(kubectl -n media get deployment media-web -o jsonpath='{range .spec.template.spec.volumes[*]}{.name}={.persistentVolumeClaim.claimName}{"\n"}{end}' 2>/dev/null | awk -F= '$2=="media-data"{print $1}' | head -1)
  mnt=$(kubectl -n media get deployment media-web -o jsonpath='{range .spec.template.spec.containers[?(@.name=="web")].volumeMounts[*]}{.name}={.mountPath}{"\n"}{end}' 2>/dev/null)
  check_result "컨테이너 web 이 그 볼륨을 /usr/share/nginx/html 에 마운트" \
    "$([[ -n "$vol" ]] && grep -qx "${vol}=/usr/share/nginx/html" <<< "$mnt" && echo 0 || echo 1)" "현재 web 의 마운트: $(echo $mnt)" 2
  check_result "Deployment 를 지우고 다시 만들지 않았다" "$(same_uid media media-web && echo 0 || echo 1)" "uid 가 바뀌었다 — 지문 위반" 1
  wait_ready "-l app=media-web" media || true
  check_output "파드가 Ready" "$DEP='{.status.readyReplicas}/{.status.updatedReplicas}'" '^1/1$' 1
  check_output "파드 안에서 /usr/share/nginx/html 이 실제로 마운트돼 있다" \
    "kubectl -n media exec deploy/media-web -c web -- sh -c 'grep \" /usr/share/nginx/html \" /proc/mounts'" 'nginx/html' 2
  check_output "index.html 내용이 media-ok" \
    "kubectl -n media exec deploy/media-web -c web -- cat /usr/share/nginx/html/index.html" '^media-ok$' 2
}

# ══════════════════════════════════════════════════════════════
# Q2 — NetworkPolicy: 네임스페이스 AND 파드
# ══════════════════════════════════════════════════════════════
q2_title() { echo "NetworkPolicy: frontend of the web team only [20 pts]"; }
q2_text() { cat <<'EOF'
The Deployment api (label app=api) in the orders namespace is exposed by
the Service api on port 80.

Create a NetworkPolicy named api-allow-frontend in the orders namespace:
  - applies to Pods labelled app=api
  - allows ingress on TCP 80 ONLY from Pods labelled app=frontend
    that run in namespaces labelled team=web

After you are done, NOTHING else may reach api. Review the NetworkPolicies
that already exist in the orders namespace.

Test Pods already exist:
  web-team/frontend   (ns team=web, app=frontend)  -> must reach api
  web-team/batch      (ns team=web, app=batch)     -> must be blocked
  qa-team/frontend    (ns team=qa,  app=frontend)  -> must be blocked
  orders/monitor      (same ns,     app=monitor)   -> must be blocked

Verify:
  kubectl get ns --show-labels
  kubectl -n orders get networkpolicy
  kubectl -n web-team exec frontend -- wget -qO- -T 3 http://api.orders
  kubectl -n qa-team  exec frontend -- wget -qO- -T 3 http://api.orders
EOF
}
q2_title_ko() { echo "NetworkPolicy — web 팀의 frontend 만 [20점]"; }
q2_text_ko() { cat <<'EOF'
orders 네임스페이스의 Deployment api(레이블 app=api)는
Service api 의 80 포트로 노출돼 있다.

orders 네임스페이스에 NetworkPolicy api-allow-frontend 를 만든다.
  - 대상: app=api 파드
  - 허용: team=web 레이블이 붙은 네임스페이스에서 도는
          app=frontend 파드가 보내는 TCP 80 만

끝나면 그 밖의 어떤 트래픽도 api 에 닿으면 안 된다.
orders 네임스페이스에 이미 있는 NetworkPolicy 도 살펴본다.

테스트 파드가 이미 있다.
  web-team/frontend   (ns team=web, app=frontend)  → 닿아야 한다
  web-team/batch      (ns team=web, app=batch)     → 막혀야 한다
  qa-team/frontend    (ns team=qa,  app=frontend)  → 막혀야 한다
  orders/monitor      (같은 ns,     app=monitor)   → 막혀야 한다

[확인]
  kubectl get ns --show-labels
  kubectl -n orders get networkpolicy
  kubectl -n web-team exec frontend -- wget -qO- -T 3 http://api.orders
  kubectl -n qa-team  exec frontend -- wget -qO- -T 3 http://api.orders
EOF
}
q2_hint() { cat <<'EOF'
# from 의 '한 항목' 안에 둘을 같이 쓰면 AND (그 네임스페이스의 그 파드)
#   - namespaceSelector: ...
#     podSelector: ...
# 대시(-)를 둘 다 붙이면 항목이 두 개 → OR (그 네임스페이스의 모든 파드 + 같은 ns 의 frontend)
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: api-allow-frontend, namespace: orders }
spec:
  podSelector: { matchLabels: { app: api } }
  policyTypes: [Ingress]
  ingress:
    - from:
        - namespaceSelector: { matchLabels: { team: web } }
          podSelector: { matchLabels: { app: frontend } }
      ports: [ { protocol: TCP, port: 80 } ]

# 정책은 '더해진다'. legacy-open 의 ingress: [{}] 가 남아 있으면 전부 열려 있다
kubectl -n orders get networkpolicy legacy-open -o yaml
EOF
}
q2_grade() {
  local NP="kubectl -n orders get networkpolicy api-allow-frontend -o jsonpath"
  check "api-allow-frontend 존재" "kubectl -n orders get networkpolicy api-allow-frontend" 2
  check_output "대상이 app=api" "$NP='{.spec.podSelector.matchLabels.app}'" '^api$' 2
  check_output "policyTypes 에 Ingress" "$NP='{.spec.policyTypes[*]}'" '(^| )Ingress( |$)' 1
  check_output "같은 from 항목에 namespaceSelector team=web 과 podSelector app=frontend (AND)" \
    "$NP='{range .spec.ingress[*].from[*]}{.namespaceSelector.matchLabels.team}/{.podSelector.matchLabels.app}{\"\\n\"}{end}'" '^web/frontend$' 2
  check_output "허용 포트 TCP 80" "$NP='{.spec.ingress[*].ports[*].port}'" '(^| )80( |$)' 1

  wait_ready "-l app=api" orders || true
  local probe='wget -qO- -T 3 http://api.orders.svc.cluster.local 2>/dev/null'
  local a b c d
  a=$(kubectl -n web-team exec frontend -- sh -c "$probe" 2>/dev/null)
  b=$(kubectl -n web-team exec batch    -- sh -c "$probe" 2>/dev/null)
  c=$(kubectl -n qa-team  exec frontend -- sh -c "$probe" 2>/dev/null)
  d=$(kubectl -n orders   exec monitor  -- sh -c "$probe" 2>/dev/null)
  local served=1; echo "$a" | grep -qi nginx && served=0
  check_result "web-team/frontend → api 응답 (허용)" "$served" "응답 없음 — 허용 규칙 · 네임스페이스 레이블 · api 파드 확인" 4
  # 허용 경로가 살아 있을 때만 '막힘' 을 믿는다 (api 가 죽어서 안 닿는 것과 구분)
  check_result "web-team/batch → api 차단 (같은 팀, 다른 파드)" \
    "$([[ $served == 0 ]] && ! echo "$b" | grep -qi nginx && echo 0 || echo 1)" "batch 가 닿는다 — from 항목이 둘로 나뉘었거나(OR) legacy-open 이 남아 있다" 2
  check_result "qa-team/frontend → api 차단 (다른 팀)" \
    "$([[ $served == 0 ]] && ! echo "$c" | grep -qi nginx && echo 0 || echo 1)" "qa 가 닿는다 — namespaceSelector 를 확인하거나 legacy-open 을 확인" 3
  check_result "orders/monitor → api 차단 (같은 네임스페이스)" \
    "$([[ $served == 0 ]] && ! echo "$d" | grep -qi nginx && echo 0 || echo 1)" "monitor 가 닿는다 — 정책은 더해진다. legacy-open 이 api 를 열어 두고 있다" 3
}

# ══════════════════════════════════════════════════════════════
# Q3 — Gateway API 경로 라우팅
# ══════════════════════════════════════════════════════════════
q3_title() { echo "Gateway API: route by path [20 pts]"; }
q3_text() { cat <<'EOF'
A Gateway API controller is installed and provides the GatewayClass nginx.
In the portal namespace, the Services portal-main and portal-api (port 80)
already exist.

  (1) Create a Gateway named portal-gw in portal
        gatewayClassName   nginx
        listener           name http, port 80, protocol HTTP

  (2) Create an HTTPRoute named portal-route in portal
        parentRefs         portal-gw
        hostnames          portal.example.local
        rules              path prefix /api  -> Service portal-api, port 80
                           path prefix /     -> Service portal-main, port 80

The controller creates a Service for the Gateway. Requests sent to it with
Host portal.example.local must be routed as above.

Verify:
  kubectl -n portal get gateway,httproute
  kubectl -n portal get svc            # the Service created for portal-gw (NodePort)
  curl -H 'Host: portal.example.local' http://<NodeIP>:<nodePort>/api/orders   -> portal-api ...
  curl -H 'Host: portal.example.local' http://<NodeIP>:<nodePort>/             -> portal-main ...
EOF
}
q3_title_ko() { echo "Gateway API — 경로로 나누기 [20점]"; }
q3_text_ko() { cat <<'EOF'
Gateway API 컨트롤러가 설치돼 있고 GatewayClass nginx 를 제공한다.
portal 네임스페이스에 Service portal-main 과 portal-api(포트 80)가 이미 있다.

  (1) portal 에 Gateway portal-gw 를 만든다
        gatewayClassName   nginx
        리스너             이름 http, 포트 80, 프로토콜 HTTP

  (2) portal 에 HTTPRoute portal-route 를 만든다
        parentRefs         portal-gw
        hostnames          portal.example.local
        규칙               경로 접두사 /api  → Service portal-api, 포트 80
                           경로 접두사 /     → Service portal-main, 포트 80

컨트롤러가 Gateway 용 Service 를 만든다. 그 Service 로 Host 가
portal.example.local 인 요청을 보내면 위처럼 나뉘어야 한다.

[확인]
  kubectl -n portal get gateway,httproute
  kubectl -n portal get svc            # portal-gw 용으로 생긴 Service (NodePort)
  curl -H 'Host: portal.example.local' http://<NodeIP>:<nodePort>/api/orders   → portal-api ...
  curl -H 'Host: portal.example.local' http://<NodeIP>:<nodePort>/             → portal-main ...
EOF
}
q3_hint() { cat <<'EOF'
kubectl get gatewayclass                  # nginx 가 ACCEPTED True 인지

apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata: { name: portal-gw, namespace: portal }
spec:
  gatewayClassName: nginx
  listeners:
    - { name: http, port: 80, protocol: HTTP }
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata: { name: portal-route, namespace: portal }
spec:
  parentRefs: [ { name: portal-gw } ]
  hostnames: [ portal.example.local ]
  rules:
    - matches: [ { path: { type: PathPrefix, value: /api } } ]
      backendRefs: [ { name: portal-api, port: 80 } ]
    - matches: [ { path: { type: PathPrefix, value: / } } ]
      backendRefs: [ { name: portal-main, port: 80 } ]

# 더 긴 접두사가 먼저 이긴다 — 규칙 순서와 상관없이 /api 는 portal-api 로 간다
kubectl -n portal describe gateway portal-gw     # Programmed True 인지
kubectl -n portal get svc                        # 80:3xxxx/TCP 의 3xxxx 가 nodePort
EOF
}
q3_grade() {
  local mode; mode=$(gw_mode)
  if [[ "$mode" == "none" ]]; then
    check_result "Gateway API 가 설치되어 있다" 1 "미설치 — 인터넷 연결 후 bash exam.sh start 재실행" 20
    return
  fi
  local GW="kubectl -n portal get gateway portal-gw -o jsonpath"
  local RT="kubectl -n portal get httproute portal-route -o jsonpath"
  check "Gateway portal-gw 존재" "kubectl -n portal get gateway portal-gw" 2
  check_output "gatewayClassName nginx" "$GW='{.spec.gatewayClassName}'" '^nginx$' 1
  check_output "리스너 http · 80 · HTTP" \
    "$GW='{range .spec.listeners[*]}{.name}/{.port}/{.protocol}{\"\\n\"}{end}'" '^http/80/HTTP$' 1
  check "HTTPRoute portal-route 존재" "kubectl -n portal get httproute portal-route" 2
  check_output "parentRefs 가 portal-gw" "$RT='{.spec.parentRefs[*].name}'" '(^| )portal-gw( |$)' 1
  check_output "hostnames 에 portal.example.local" "$RT='{.spec.hostnames[*]}'" '(^| )portal\.example\.local( |$)' 1
  local rules="$RT='{range .spec.rules[*]}{.matches[0].path.value}={.backendRefs[0].name}:{.backendRefs[0].port}{\"\\n\"}{end}'"
  check_output "규칙 /api → portal-api:80" "$rules" '^/api=portal-api:80$' 2
  check_output "규칙 / → portal-main:80" "$rules" '^/?=portal-main:80$' 1

  [[ "$mode" != "full" ]] && { echo -e "  ${DIM}(컨트롤러 미설치 — 상태·트래픽 검증 생략)${RESET}"; return; }

  check_output "Gateway Accepted" "$GW='{.status.conditions[?(@.type==\"Accepted\")].status}'" 'True' 1
  check_output "Gateway Programmed" "$GW='{.status.conditions[?(@.type==\"Programmed\")].status}'" 'True' 1
  check_output "HTTPRoute 가 Gateway 에 Accepted" "$RT='{.status.parents[*].conditions[?(@.type==\"Accepted\")].status}'" 'True' 1
  check_output "HTTPRoute 백엔드 참조가 해석됨 (ResolvedRefs)" "$RT='{.status.parents[*].conditions[?(@.type==\"ResolvedRefs\")].status}'" 'True' 1

  # ── 실제 트래픽 — Gateway 가 만든 Service 의 80 NodePort 로
  local port ip hit="" api="" main="" other=""
  port=$(kubectl -n portal get svc -l gateway.networking.k8s.io/gateway-name=portal-gw \
           -o jsonpath='{.items[0].spec.ports[?(@.port==80)].nodePort}' 2>/dev/null)
  port="${port//[^0-9]/}"
  if [[ -n "$port" ]] && command -v curl &>/dev/null; then
    for ip in $(kubectl get nodes -o jsonpath='{range .items[*]}{.status.addresses[?(@.type=="InternalIP")].address}{"\n"}{end}' 2>/dev/null); do
      [[ -z "$ip" ]] && continue
      main=$(curl -s --max-time 5 -H "Host: $Q3_HOST" "http://${ip}:${port}/" 2>/dev/null || true)
      [[ "$main" == portal-* ]] || continue
      hit="$ip"
      api=$(curl -s --max-time 5 -H "Host: $Q3_HOST" "http://${ip}:${port}/api/orders" 2>/dev/null || true)
      other=$(curl -s --max-time 5 -H "Host: other.example.local" "http://${ip}:${port}/" 2>/dev/null || true)
      break
    done
  fi
  local where="${hit:+ — $hit:$port}"
  local why="${port:+NodePort $port 응답 없음 — }kubectl -n portal get svc · describe gateway portal-gw 확인"
  check_result "/api/orders → portal-api${where}" "$([[ "$api" == portal-api* ]] && echo 0 || echo 1)" \
    "$([[ -n "$hit" ]] && echo "응답: ${api:-없음}" || echo "$why")" 2
  check_result "/ → portal-main${where}" "$([[ "$main" == portal-main* ]] && echo 0 || echo 1)" \
    "$([[ -n "$hit" ]] && echo "응답: ${main:-없음}" || echo "$why")" 2
  check_result "다른 Host(other.example.local)는 portal 로 가지 않는다 (hostnames)" \
    "$([[ -n "$hit" && "$other" != portal-* ]] && echo 0 || echo 1)" \
    "$([[ -n "$hit" ]] && echo "hostnames 가 비어 있으면 모든 Host 가 들어온다" || echo "$why")" 1
}

# ══════════════════════════════════════════════════════════════
# Q4 — ResourceQuota 에 막힌 Deployment 에 requests/limits
# ══════════════════════════════════════════════════════════════
q4_title() { echo "Fit a Deployment into a ResourceQuota [20 pts]"; }
q4_text() { cat <<'EOF'
In the batch namespace, the Deployment worker (replicas 3) has NO running
Pods. A ResourceQuota named batch-quota exists in the namespace.

Find out why, then set resources on the Deployment so that all 3 replicas
run. Use exactly these values:

  container app        requests  cpu 100m  memory 128Mi
                       limits    cpu 200m  memory 256Mi
  container log-agent  requests  cpu 50m   memory 32Mi
                       limits    cpu 100m  memory 64Mi

Do not change or delete the ResourceQuota, do not change replicas, and do
not delete the Deployment.

Verify:
  kubectl -n batch describe rs -l app=worker | grep -i -A3 events
  kubectl -n batch get deploy worker
  kubectl -n batch describe resourcequota batch-quota
EOF
}
q4_title_ko() { echo "ResourceQuota 안에 Deployment 넣기 [20점]"; }
q4_text_ko() { cat <<'EOF'
batch 네임스페이스의 Deployment worker(replicas 3)에 실행 중인 파드가 없다.
이 네임스페이스에는 ResourceQuota batch-quota 가 있다.

이유를 찾고, Deployment 에 자원 설정을 넣어 3개가 모두 뜨게 한다.
값은 정확히 아래대로 쓴다.

  컨테이너 app         requests  cpu 100m  memory 128Mi
                       limits    cpu 200m  memory 256Mi
  컨테이너 log-agent   requests  cpu 50m   memory 32Mi
                       limits    cpu 100m  memory 64Mi

ResourceQuota 는 바꾸거나 지우지 않는다. replicas 도 바꾸지 않고,
Deployment 를 지우지도 않는다.

[확인]
  kubectl -n batch describe rs -l app=worker | grep -i -A3 events
  kubectl -n batch get deploy worker
  kubectl -n batch describe resourcequota batch-quota
EOF
}
q4_hint() { cat <<'EOF'
kubectl -n batch describe rs -l app=worker
#   Error creating: pods "..." is forbidden: failed quota: batch-quota:
#   must specify limits.cpu for: app,log-agent; ...
# → 쿼터가 requests/limits 를 잡고 있으면 '모든 컨테이너' 가 값을 적어야 파드가 만들어진다

kubectl -n batch set resources deployment worker -c app \
  --requests=cpu=100m,memory=128Mi --limits=cpu=200m,memory=256Mi
kubectl -n batch set resources deployment worker -c log-agent \
  --requests=cpu=50m,memory=32Mi --limits=cpu=100m,memory=64Mi
kubectl -n batch rollout status deployment worker

# 파드 3개 = requests 450m / 480Mi, limits 900m / 960Mi → 쿼터(500m / 512Mi, 1 / 1Gi) 안
EOF
}
q4_grade() {
  local DEP="kubectl -n batch get deployment worker -o jsonpath"
  local app='{.spec.template.spec.containers[?(@.name=="app")].resources'
  local agt='{.spec.template.spec.containers[?(@.name=="log-agent")].resources'
  check_output "app requests cpu 100m · memory 128Mi" \
    "$DEP='${app}.requests.cpu}/${app}.requests.memory}'" '^100m/128Mi$' 2
  check_output "app limits cpu 200m · memory 256Mi" \
    "$DEP='${app}.limits.cpu}/${app}.limits.memory}'" '^200m/256Mi$' 2
  check_output "log-agent requests cpu 50m · memory 32Mi" \
    "$DEP='${agt}.requests.cpu}/${agt}.requests.memory}'" '^50m/32Mi$' 2
  check_output "log-agent limits cpu 100m · memory 64Mi" \
    "$DEP='${agt}.limits.cpu}/${agt}.limits.memory}'" '^100m/64Mi$' 2
  check_output "ResourceQuota 는 그대로 (500m / 512Mi / 1 / 1Gi / pods 5)" \
    "kubectl -n batch get resourcequota batch-quota -o jsonpath='{.spec.hard.requests\.cpu}/{.spec.hard.requests\.memory}/{.spec.hard.limits\.cpu}/{.spec.hard.limits\.memory}/{.spec.hard.pods}'" \
    '^500m/512Mi/1/1Gi/5$' 2
  check_result "Deployment 를 지우지 않았고 replicas 3 그대로" \
    "$(same_uid batch worker && [[ "$(kubectl -n batch get deployment worker -o jsonpath='{.spec.replicas}' 2>/dev/null)" == 3 ]] && echo 0 || echo 1)" \
    "uid 가 바뀌었거나 replicas 가 3 이 아니다" 1
  wait_ready "-l app=worker" batch || true
  check_output "파드 3개가 Ready" "$DEP='{.status.readyReplicas}/{.status.updatedReplicas}'" '^3/3$' 4
  local qos
  qos=$(kubectl -n batch get pods -l app=worker --field-selector=status.phase=Running \
        -o jsonpath='{range .items[*]}{.metadata.deletionTimestamp}|{.status.qosClass}{"\n"}{end}' 2>/dev/null \
        | awk -F'|' '$1==""{print $2}' | sort -u | tr '\n' ' ')
  check_result "Running 파드가 모두 QoS Burstable (현재: ${qos:-없음})" \
    "$([[ "$qos" == "Burstable " ]] && echo 0 || echo 1)" "requests 와 limits 가 다르면 Burstable" 2
  check_output "쿼터 사용량 requests.cpu 450m · requests.memory 480Mi" \
    "kubectl -n batch get resourcequota batch-quota -o jsonpath='{.status.used.requests\.cpu}/{.status.used.requests\.memory}'" \
    '^450m/480Mi$' 3
}

# ══════════════════════════════════════════════════════════════
# Q5 — PriorityClass 로 선점
# ══════════════════════════════════════════════════════════════
q5_title() { echo "Let a Pending Pod in with a PriorityClass [20 pts]"; }
q5_text() { cat <<'EOF'
In the ml namespace, the Pod of the Deployment inference stays Pending.
It needs one example.com/accelerator, and only one node has two of them,
both used by the Deployment trainer (PriorityClass ml-batch, value 100).

  (a) Create a PriorityClass named inference-critical
        value              1000000
        preemptionPolicy   PreemptLowerPriority
        globalDefault      false
        description        latency-sensitive inference

  (b) Make the Deployment inference use it.

The inference Pod must become Running by preempting a trainer Pod.
Do NOT touch trainer (no scaling, no editing, no deleting its Pods) and do
not delete either Deployment.

Verify:
  kubectl -n ml get pods -o wide
  kubectl -n ml get pods -o custom-columns=NAME:.metadata.name,PRIORITY:.spec.priority,STATUS:.status.phase
  kubectl -n ml get events --field-selector reason=Preempted
EOF
}
q5_title_ko() { echo "PriorityClass 로 Pending 파드 밀어 넣기 [20점]"; }
q5_text_ko() { cat <<'EOF'
ml 네임스페이스의 Deployment inference 파드가 Pending 에 멈춰 있다.
이 파드는 example.com/accelerator 1개가 필요한데, 그것을 2개 가진 노드는
하나뿐이고 둘 다 Deployment trainer(PriorityClass ml-batch, 값 100)가 쓰고 있다.

  (a) PriorityClass inference-critical 을 만든다
        value              1000000
        preemptionPolicy   PreemptLowerPriority
        globalDefault      false
        description        latency-sensitive inference

  (b) Deployment inference 가 이 PriorityClass 를 쓰게 한다.

inference 파드가 trainer 파드 하나를 밀어내고(선점) Running 이 되어야 한다.
trainer 는 건드리지 않는다 (scale · 수정 · 파드 삭제 금지).
두 Deployment 모두 지우지 않는다.

[확인]
  kubectl -n ml get pods -o wide
  kubectl -n ml get pods -o custom-columns=NAME:.metadata.name,PRIORITY:.spec.priority,STATUS:.status.phase
  kubectl -n ml get events --field-selector reason=Preempted
EOF
}
q5_hint() { cat <<'EOF'
kubectl -n ml describe pod -l app=inference | tail -5    # Insufficient example.com/accelerator

apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata: { name: inference-critical }
value: 1000000
preemptionPolicy: PreemptLowerPriority
globalDefault: false
description: "latency-sensitive inference"

# 파드 속성이므로 spec.template.spec 아래
kubectl -n ml patch deployment inference \
  -p '{"spec":{"template":{"spec":{"priorityClassName":"inference-critical"}}}}'

# 스케줄러가 우선순위 낮은 trainer 파드 하나를 내보낸다.
# trainer 는 replicas 2 를 맞추려고 새 파드를 만들지만 자리가 없어 Pending — 정상이다
kubectl -n ml get pods -o wide -w
EOF
}
q5_grade() {
  local node; node=$(accel_node)
  local PC="kubectl get priorityclass inference-critical -o jsonpath"
  check "PriorityClass inference-critical 존재" "kubectl get priorityclass inference-critical" 2
  check_output "value 1000000" "$PC='{.value}'" '^1000000$' 2
  check_output "preemptionPolicy PreemptLowerPriority" "$PC='{.preemptionPolicy}'" '^PreemptLowerPriority$' 1
  check_output "globalDefault 가 아니다" "$PC='{.globalDefault}'" '^(false)?$' 1
  check_output "inference 템플릿에 priorityClassName: inference-critical" \
    "kubectl -n ml get deployment inference -o jsonpath='{.spec.template.spec.priorityClassName}'" '^inference-critical$' 3

  wait_ready "-l app=inference" ml || true
  # 롤아웃 중 지우는 중(deletionTimestamp)인 옛 파드는 빼고 본다 — 한 줄에 "지우는중|단계|우선순위|노드"
  local live run
  live=$(kubectl -n ml get pods -l app=inference \
         -o jsonpath='{range .items[*]}{.metadata.deletionTimestamp}|{.status.phase}|{.spec.priority}|{.spec.nodeName}{"\n"}{end}' 2>/dev/null \
         | awk -F'|' '$1==""')
  run=$(awk -F'|' '$2=="Running"' <<< "$live")
  check_result "inference 파드가 priority 1000000 으로 Running" \
    "$([[ -n "$run" ]] && awk -F'|' '$3!="1000000"{bad=1} END{exit bad}' <<< "$run" && echo 0 || echo 1)" \
    "현재: $(awk -F'|' '{printf "%s(priority %s) ", $2, $3}' <<< "$live")" 4
  check_result "장치가 있는 노드(${node:-?})에서 돈다" \
    "$([[ -n "$run" && -n "$node" ]] && awk -F'|' -v n="$node" '$4!=n{bad=1} END{exit bad}' <<< "$run" && echo 0 || echo 1)" \
    "현재 노드: $(awk -F'|' '{printf "%s ", $4}' <<< "$run")" 1

  check_output "trainer 는 그대로 (replicas 2 · ml-batch)" \
    "kubectl -n ml get deployment trainer -o jsonpath='{.spec.replicas}/{.spec.template.spec.priorityClassName}'" '^2/ml-batch$' 2
  check_result "두 Deployment 를 지우고 다시 만들지 않았다" \
    "$(same_uid ml trainer && same_uid ml inference && echo 0 || echo 1)" "uid 가 바뀌었다 — 지문 위반" 1
  local tr
  tr=$(kubectl -n ml get pods -l app=trainer \
       -o jsonpath='{range .items[*]}{.metadata.deletionTimestamp}|{.status.phase}{"\n"}{end}' 2>/dev/null \
       | awk -F'|' '$1==""{print $2}' | sort | uniq -c | awk '{printf "%s%s %s", (NR>1 ? " · " : ""), $2, $1}')
  check_result "trainer 하나가 밀려났다 — Running 1 · Pending 1 (현재: ${tr:-없음})" \
    "$([[ "$tr" == "Pending 1 · Running 1" ]] && echo 0 || echo 1)" "inference 가 아직 못 들어갔거나 trainer 를 건드렸다" 3
}

exam_main "$@"
