#!/usr/bin/env bash
# CKA 3세션 시험 — 순차 진행형
# 사용법: bash exam.sh start → 풀고 → bash exam.sh check → ...
# 환경 준비(StorageClass·PV·Gateway API 설치)는 start 에서 자동으로 한다.
set -uo pipefail
source "$(cd "$(dirname "$0")/.." && pwd)/_lib/exam-lib.sh"

EXAM_TITLE="CKA 3세션 시험 — Deployment+Service · StorageClass/PVC · Gateway API"
EXAM_NQ=3

NGF_VERSION="v2.7.0"
GW_CRD_KUSTOMIZE="https://github.com/nginx/nginx-gateway-fabric/config/crd/gateway-api/standard?ref=${NGF_VERSION}"
NGF_CRDS="https://raw.githubusercontent.com/nginx/nginx-gateway-fabric/${NGF_VERSION}/deploy/crds.yaml"
NGF_DEPLOY="https://raw.githubusercontent.com/nginx/nginx-gateway-fabric/${NGF_VERSION}/deploy/nodeport/deploy.yaml"
MODE_FILE="$WORK_DIR/.gateway-mode"
gw_mode() { cat "$MODE_FILE" 2>/dev/null || echo none; }

exam_cleanup() {
  if kubectl get namespace shop &>/dev/null; then
    echo "  네임스페이스 shop 삭제 중... (수십 초 걸릴 수 있음)"
    kubectl delete namespace shop --wait=true &>/dev/null || true
  fi
  for i in 1 2 3; do kubectl delete pv "exam-pv-${i}" --ignore-not-found &>/dev/null || true; done
  kdel storageclass exam-storage
  rm -f "$MODE_FILE"
  echo "  shop 네임스페이스 · exam-storage · exam-pv-1~3 삭제"
  echo "  (Gateway API 컨트롤러는 남겨둠 — 완전 제거: kubectl delete ns nginx-gateway)"
}

exam_setup() {
  # 2) 네임스페이스
  kubectl create namespace shop &>/dev/null || true
  echo "  shop 네임스페이스 생성"

  # 3) StorageClass + hostPath PV 3개
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
  labels: { usage: exam }
spec:
  capacity: { storage: 2Gi }
  accessModes: [ReadWriteOnce]
  persistentVolumeReclaimPolicy: Retain
  storageClassName: exam-storage
  hostPath: { path: /mnt/exam-data-${i}, type: DirectoryOrCreate }
EOF
  done
  echo "  StorageClass exam-storage + PV 3개(2Gi) 생성"

  # 4) Gateway API + NGINX Gateway Fabric
  local mode="none"
  if kubectl get gatewayclass nginx &>/dev/null && kubectl get deployment -n nginx-gateway &>/dev/null; then
    echo "  Gateway API 이미 설치됨 — 건너뜀"; mode="full"
  else
    echo "  Gateway API CRD 설치 중..."
    if kubectl kustomize "$GW_CRD_KUSTOMIZE" 2>/dev/null | kubectl apply -f - &>/dev/null; then
      mode="crds"
      kubectl apply --server-side -f "$NGF_CRDS" &>/dev/null || true
      kubectl create namespace nginx-gateway &>/dev/null || true
      echo "  NGINX Gateway Fabric 배포 중 (최대 3분)..."
      if kubectl apply -f "$NGF_DEPLOY" &>/dev/null && \
         kubectl wait --for=condition=Available deployment --all -n nginx-gateway --timeout=180s &>/dev/null; then
        mode="full"; echo "  NGINX Gateway Fabric 준비 완료 (GatewayClass: nginx)"
      else
        echo "  컨트롤러가 아직 Ready 되지 않음 — kubectl get pods -n nginx-gateway 로 확인"
      fi
    else
      echo "  Gateway API CRD 설치 실패 (인터넷 연결 확인)"
    fi
  fi

  # 5) 데이터 플레인을 DaemonSet 으로 (모든 노드에서 접속되도록)
  if [[ "$mode" == "full" ]]; then
    local patch='{"spec":{"kubernetes":{"deployment":null,"daemonSet":{"patches":[{"type":"StrategicMerge","value":{"spec":{"template":{"spec":{"tolerations":[{"key":"node-role.kubernetes.io/control-plane","operator":"Exists","effect":"NoSchedule"}]}}}}}]}}}}'
    local pn pns; pn=$(kubectl get gatewayclass nginx -o jsonpath='{.spec.parametersRef.name}' 2>/dev/null); pns=$(kubectl get gatewayclass nginx -o jsonpath='{.spec.parametersRef.namespace}' 2>/dev/null)
    if [[ -n "$pn" && -n "$pns" ]]; then
      kubectl patch nginxproxy "$pn" -n "$pns" --type=merge -p "$patch" &>/dev/null && echo "  게이트웨이 데이터 플레인 → DaemonSet 전환"
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
      kubectl patch gatewayclass nginx --type=merge -p '{"spec":{"parametersRef":{"group":"gateway.nginx.org","kind":"NginxProxy","name":"exam-proxy-config","namespace":"nginx-gateway"}}}' &>/dev/null && echo "  게이트웨이 데이터 플레인 → DaemonSet 전환"
    fi
  fi
  echo "$mode" > "$MODE_FILE"
  case "$mode" in
    full) echo "  → Q3 전부 채점 가능" ;;
    crds) echo "  → CRD 만 설치됨. Q3 리소스 작성은 채점되지만 실제 트래픽 검증은 제외" ;;
    none) echo "  → Gateway API 미설치. Q3 는 리소스 채점 불가" ;;
  esac
}

# ══════════════════════════════════════════════════════════════
q1_title() { echo "Deployment and Service in the shop namespace"; }
q1_text() { cat <<'EOF'
In the shop namespace, create a Deployment named shop-web using image
nginx:1.24 with 2 replicas, exposing container port 80.

Expose it with a ClusterIP Service named shop-svc on port 80 -> targetPort 80.
The Service must actually route traffic to both pods.

Conditions:
  namespace       shop  (already created)
  Deployment      shop-web / nginx:1.24 / replicas 2 / port 80
  Service         shop-svc / ClusterIP / 80 -> 80
  Both Pod IPs must be registered in the Endpoints.

Verify:
  kubectl get deployment,svc,endpoints -n shop
  kubectl run tmp -n shop --rm -it --image=busybox:1.36 --restart=Never -- wget -qO- http://shop-svc
EOF
}
q1_title_ko() { echo "Deployment 를 만들고 Service 로 연결"; }
q1_text_ko() { cat <<'EOF'
In the shop namespace, create a Deployment named shop-web using image
nginx:1.24 with 2 replicas, exposing container port 80.

Expose it with a ClusterIP Service named shop-svc on port 80 → targetPort 80.
The Service must actually route traffic to both pods.

[조건]
  namespace       shop  (이미 생성되어 있음)
  Deployment      shop-web / nginx:1.24 / replicas 2 / port 80
  Service         shop-svc / ClusterIP / 80 → 80
  Endpoints 에 파드 IP 2개가 등록되어야 한다

[확인]
  kubectl get deployment,svc,endpoints -n shop
  kubectl run tmp -n shop --rm -it --image=busybox:1.36 --restart=Never -- wget -qO- http://shop-svc
EOF
}
q1_hint() { cat <<'EOF'
kubectl create deployment shop-web --image=nginx:1.24 --replicas=2 --port=80 -n shop
kubectl expose deployment shop-web --name=shop-svc --port=80 --target-port=80 --type=ClusterIP -n shop
EOF
}
q1_grade() {
  check "shop-web Deployment 가 shop 네임스페이스에 존재한다" "kubectl get deployment shop-web -n shop"
  check_output "shop-web 이미지가 nginx:1.24 이다" \
    "kubectl get deployment shop-web -n shop -o jsonpath='{.spec.template.spec.containers[0].image}'" "^nginx:1\.24$"
  check_output "shop-web replicas 가 2 이다" \
    "kubectl get deployment shop-web -n shop -o jsonpath='{.spec.replicas}'" "^2$"
  wait_ready "-l app=shop-web" shop || true
  check_output "shop-web 파드 2개가 모두 Ready 이다" \
    "kubectl get deployment shop-web -n shop -o jsonpath='{.status.readyReplicas}'" "^2$"
  check_output "shop-web containerPort 80 이 노출되어 있다" \
    "kubectl get deployment shop-web -n shop -o jsonpath='{.spec.template.spec.containers[0].ports[0].containerPort}'" "^80$"
  check "shop-svc Service 가 shop 네임스페이스에 존재한다" "kubectl get service shop-svc -n shop"
  check_output "shop-svc 타입이 ClusterIP 이다" \
    "kubectl get service shop-svc -n shop -o jsonpath='{.spec.type}'" "^ClusterIP$"
  check_output "shop-svc port 가 80 이다" \
    "kubectl get service shop-svc -n shop -o jsonpath='{.spec.ports[0].port}'" "^80$"
  check_output "shop-svc targetPort 가 80 이다" \
    "kubectl get service shop-svc -n shop -o jsonpath='{.spec.ports[0].targetPort}'" "^80$"
  local ep; ep=$(kubectl get endpoints shop-svc -n shop -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null | wc -w | tr -d ' ')
  check_result "shop-svc Endpoints 에 파드 IP 2개가 등록되어 있다" "$([[ "$ep" == "2" ]] && echo 0 || echo 1)" "실제: ${ep}개"
  kubectl delete pod svc-probe -n shop --ignore-not-found &>/dev/null || true
  local out; out=$(kubectl run svc-probe -n shop --image=busybox:1.36 --restart=Never --rm -i --timeout=90s --command -- wget -qO- --timeout=5 http://shop-svc 2>/dev/null || echo "")
  kubectl delete pod svc-probe -n shop --ignore-not-found &>/dev/null || true
  check_result "클러스터 내부에서 http://shop-svc 접속 성공 (실제 통신 검증)" "$(echo "$out" | grep -qi nginx && echo 0 || echo 1)"
}

# ══════════════════════════════════════════════════════════════
q2_title() { echo "PVC from a StorageClass, mounted into the Deployment"; }
q2_text() { cat <<'EOF'
A StorageClass named exam-storage already exists in the cluster.

In the shop namespace, create a PersistentVolumeClaim named shop-data that
requests 1Gi with access mode ReadWriteOnce using that StorageClass.

Then mount it into the shop-web Deployment at /data.
The PVC must reach Bound state and the pods must be running with the volume
mounted.

Conditions:
  PVC             shop-data / storageClassName exam-storage / 1Gi / ReadWriteOnce
  mount           into the shop-web Deployment at mountPath /data
  Careful: mount at /data, not at /usr/share/nginx/html.

Verify:
  kubectl get sc,pv,pvc -n shop
  kubectl describe pvc shop-data -n shop
  kubectl exec -n shop deploy/shop-web -- df -h /data
EOF
}
q2_title_ko() { echo "StorageClass 로 PVC 만들어 Deployment 에 연결"; }
q2_text_ko() { cat <<'EOF'
A StorageClass named exam-storage already exists in the cluster.

In the shop namespace, create a PersistentVolumeClaim named shop-data that
requests 1Gi with access mode ReadWriteOnce using that StorageClass.

Then mount it into the shop-web Deployment at /data.
The PVC must reach Bound state and the pods must be running with the volume
mounted.

[조건]
  PVC             shop-data / storageClassName exam-storage / 1Gi / ReadWriteOnce
  마운트          shop-web Deployment 에 mountPath /data
  주의: /usr/share/nginx/html 이 아니라 /data 에 마운트할 것

[확인]
  kubectl get sc,pv,pvc -n shop
  kubectl describe pvc shop-data -n shop
  kubectl exec -n shop deploy/shop-web -- df -h /data
EOF
}
q2_hint() { cat <<'EOF'
# PVC
apiVersion: v1
kind: PersistentVolumeClaim
metadata: { name: shop-data, namespace: shop }
spec:
  storageClassName: exam-storage
  accessModes: ["ReadWriteOnce"]
  resources: { requests: { storage: 1Gi } }

# Deployment 에 볼륨 추가 (컨테이너 이름은 nginx)
kubectl patch deployment shop-web -n shop -p '{"spec":{"template":{"spec":{"volumes":[{"name":"data","persistentVolumeClaim":{"claimName":"shop-data"}}],"containers":[{"name":"nginx","volumeMounts":[{"name":"data","mountPath":"/data"}]}]}}}}'
EOF
}
q2_grade() {
  check "shop-data PVC 가 shop 네임스페이스에 존재한다" "kubectl get pvc shop-data -n shop"
  check_output "shop-data 가 exam-storage StorageClass 를 사용한다" \
    "kubectl get pvc shop-data -n shop -o jsonpath='{.spec.storageClassName}'" "^exam-storage$"
  check_output "shop-data accessModes 가 ReadWriteOnce 이다" \
    "kubectl get pvc shop-data -n shop -o jsonpath='{.spec.accessModes[0]}'" "^ReadWriteOnce$"
  check_output "shop-data 요청 용량이 1Gi 이다" \
    "kubectl get pvc shop-data -n shop -o jsonpath='{.spec.resources.requests.storage}'" "^1Gi$"
  check_output "shop-data 가 Bound 상태이다" \
    "kubectl get pvc shop-data -n shop -o jsonpath='{.status.phase}'" "^Bound$"
  check_output "shop-data 가 exam-pv-* PV 에 바인딩되었다" \
    "kubectl get pvc shop-data -n shop -o jsonpath='{.spec.volumeName}'" "^exam-pv-[123]$"
  check_output "shop-web Deployment 가 shop-data PVC 를 볼륨으로 참조한다" \
    "kubectl get deployment shop-web -n shop -o jsonpath='{.spec.template.spec.volumes[*].persistentVolumeClaim.claimName}'" "shop-data"
  check_output "shop-web 컨테이너가 /data 에 마운트하고 있다" \
    "kubectl get deployment shop-web -n shop -o jsonpath='{.spec.template.spec.containers[0].volumeMounts[*].mountPath}'" "/data"
  wait_ready "-l app=shop-web" shop || true
  local pod out=""; pod=$(kubectl get pods -n shop -l app=shop-web -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
  [[ -n "$pod" ]] && out=$(kubectl exec "$pod" -n shop -- sh -c 'echo mounted > /data/.probe && cat /data/.probe' 2>/dev/null || echo "")
  check_result "파드 내부 /data 에 실제로 쓰고 읽을 수 있다 (실제 마운트 검증)" "$([[ "$out" == "mounted" ]] && echo 0 || echo 1)"
}

# ══════════════════════════════════════════════════════════════
q3_title() { echo "Expose the application with Gateway API"; }
q3_text() { cat <<'EOF'
The GatewayClass nginx is already installed in the cluster.

In the shop namespace, create a Gateway named shop-gw using that
GatewayClass, with a listener named http on port 80 (protocol HTTP).

Create an HTTPRoute named shop-route attached to that Gateway, routing all
traffic (path prefix /) to the shop-svc Service on port 80.

Finally, expose the Gateway outside the cluster on nodePort 30081 so that
curl http://<NodeIP>:30081 returns the nginx page.

Conditions:
  Gateway         shop-gw / gatewayClassName nginx / listener http, port 80, HTTP
  HTTPRoute       shop-route / parentRef shop-gw / backendRef shop-svc:80
  external access change the Service created by the Gateway (shop-gw-nginx)
                  to nodePort 30081

Verify:
  kubectl get gateway,httproute -n shop
  kubectl describe gateway shop-gw -n shop
  kubectl get svc -n shop
  curl http://<NodeIP>:30081
EOF
}
q3_title_ko() { echo "Gateway API 로 외부에 노출"; }
q3_text_ko() { cat <<'EOF'
The GatewayClass nginx is already installed in the cluster.

In the shop namespace, create a Gateway named shop-gw using that
GatewayClass, with a listener named http on port 80 (protocol HTTP).

Create an HTTPRoute named shop-route attached to that Gateway, routing all
traffic (path prefix /) to the shop-svc Service on port 80.

Finally, expose the Gateway outside the cluster on nodePort 30081 so that
curl http://<NodeIP>:30081 returns the nginx page.

[조건]
  Gateway         shop-gw / gatewayClassName nginx / listener http · port 80 · HTTP
  HTTPRoute       shop-route / parentRef shop-gw / backendRef shop-svc:80
  외부 노출       Gateway 가 만든 Service(shop-gw-nginx) 를 nodePort 30081 로 변경

[확인]
  kubectl get gateway,httproute -n shop
  kubectl describe gateway shop-gw -n shop
  kubectl get svc -n shop
  curl http://<NodeIP>:30081
EOF
}
q3_hint() { cat <<'EOF'
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata: { name: shop-gw, namespace: shop }
spec:
  gatewayClassName: nginx
  listeners:
  - { name: http, port: 80, protocol: HTTP, allowedRoutes: { namespaces: { from: Same } } }
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata: { name: shop-route, namespace: shop }
spec:
  parentRefs: [ { name: shop-gw } ]
  rules:
  - matches: [ { path: { type: PathPrefix, value: / } } ]
    backendRefs: [ { name: shop-svc, port: 80 } ]

# 30초쯤 뒤 자동 생성된 Service 확인 후 nodePort 변경
kubectl get svc -n shop
kubectl patch svc shop-gw-nginx -n shop --type=json -p='[{"op":"add","path":"/spec/ports/0/nodePort","value":30081}]'
EOF
}
q3_grade() {
  local mode; mode=$(gw_mode)
  if [[ "$mode" == "none" ]]; then
    check_result "Gateway API 가 설치되어 있다" 1 "미설치 — 인터넷 연결 후 bash exam.sh start 재실행"
    return
  fi
  check "shop-gw Gateway 가 shop 네임스페이스에 존재한다" "kubectl get gateway shop-gw -n shop"
  check_output "shop-gw 의 gatewayClassName 이 nginx 이다" \
    "kubectl get gateway shop-gw -n shop -o jsonpath='{.spec.gatewayClassName}'" "^nginx$"
  check_output "shop-gw 리스너 포트가 80 이다" \
    "kubectl get gateway shop-gw -n shop -o jsonpath='{.spec.listeners[0].port}'" "^80$"
  check_output "shop-gw 리스너 프로토콜이 HTTP 이다" \
    "kubectl get gateway shop-gw -n shop -o jsonpath='{.spec.listeners[0].protocol}'" "^HTTP$"
  check "shop-route HTTPRoute 가 shop 네임스페이스에 존재한다" "kubectl get httproute shop-route -n shop"
  check_output "shop-route 가 shop-gw Gateway 에 연결되어 있다" \
    "kubectl get httproute shop-route -n shop -o jsonpath='{.spec.parentRefs[*].name}'" "shop-gw"
  check_output "shop-route 의 backendRef 가 shop-svc 이다" \
    "kubectl get httproute shop-route -n shop -o jsonpath='{.spec.rules[0].backendRefs[0].name}'" "^shop-svc$"
  check_output "shop-route 의 backendRef 포트가 80 이다" \
    "kubectl get httproute shop-route -n shop -o jsonpath='{.spec.rules[0].backendRefs[0].port}'" "^80$"
  [[ "$mode" != "full" ]] && { echo -e "  ${DIM}(컨트롤러 미설치 — 상태·트래픽 검증 생략)${RESET}"; return; }
  check_output "shop-gw 가 컨트롤러에 의해 Accepted 되었다" \
    "kubectl get gateway shop-gw -n shop -o jsonpath='{.status.conditions[?(@.type==\"Accepted\")].status}'" "True"
  check_output "shop-route 의 참조가 정상 해석되었다 (ResolvedRefs)" \
    "kubectl get httproute shop-route -n shop -o jsonpath='{.status.parents[0].conditions[?(@.type==\"ResolvedRefs\")].status}'" "True"
  local np; np=$(kubectl get svc -n shop -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.spec.type}{" "}{.spec.ports[*].nodePort}{"\n"}{end}' 2>/dev/null | awk '$2=="NodePort" && $0 ~ /30081/ {print $1}' | head -1)
  check_result "nodePort 30081 로 노출된 Service 가 있다${np:+ ($np)}" "$([[ -n "$np" ]] && echo 0 || echo 1)" "kubectl get svc -n shop 확인"
  local ip hit="" resp
  for ip in $(kubectl get nodes -o jsonpath='{range .items[*]}{.status.addresses[?(@.type=="InternalIP")].address}{"\n"}{end}' 2>/dev/null); do
    [[ -z "$ip" ]] && continue
    if command -v curl &>/dev/null; then resp=$(curl -s --max-time 5 "http://${ip}:30081" 2>/dev/null || echo ""); else resp=$(wget -qO- --timeout=5 "http://${ip}:30081" 2>/dev/null || echo ""); fi
    echo "$resp" | grep -qi nginx && { hit="$ip"; break; }
  done
  check_result "외부에서 http://<NodeIP>:30081 접속 성공 (실제 트래픽 검증)${hit:+ — $hit}" "$([[ -n "$hit" ]] && echo 0 || echo 1)" "nodePort / Programmed / externalTrafficPolicy 확인"
}

exam_main "$@"
