#!/usr/bin/env bash
# CKA 8강 실습 — Ingress 와 네임스페이스 격리 (순차 진행형)
set -uo pipefail
source "$(cd "$(dirname "$0")/.." && pwd)/_lib/exam-lib.sh"

EXAM_TITLE="CKA 8강 실습 — Ingress (경로·호스트·TLS) · 네임스페이스 격리 · Gateway API 이전"
EXAM_NQ=5

# ── Q5: Gateway API + NGINX Gateway Fabric (tutoring/session-3 과 같은 버전·방식) ──
NGF_VERSION="v2.7.0"
GW_CRD_KUSTOMIZE="https://github.com/nginx/nginx-gateway-fabric/config/crd/gateway-api/standard?ref=${NGF_VERSION}"
NGF_CRDS="https://raw.githubusercontent.com/nginx/nginx-gateway-fabric/${NGF_VERSION}/deploy/crds.yaml"
NGF_DEPLOY="https://raw.githubusercontent.com/nginx/nginx-gateway-fabric/${NGF_VERSION}/deploy/nodeport/deploy.yaml"
MODE_FILE="$WORK_DIR/.gateway-mode"
gw_mode() { cat "$MODE_FILE" 2>/dev/null || echo none; }

Q5_NS=ing-migrate
Q5_HOST=shop.example.local

exam_cleanup() {
  kdel ingress web-ingress host-ingress tls-ingress -n default
  kdel deployment web1 -n default
  kdel service web1-svc -n default
  kdel secret tls-secret -n default
  kdel namespace production
  # Q5 — Gateway·HTTPRoute·Ingress·Secret·백엔드가 전부 이 네임스페이스 안에 있다
  kdel namespace "$Q5_NS"
  rm -f "$MODE_FILE"
  echo "  web1 / web1-svc / ingress 3종 / tls-secret / production ns 삭제"
  echo "  $Q5_NS 네임스페이스 삭제 (Gateway · HTTPRoute · Ingress · Secret · 백엔드)"
  echo "  (Gateway API 컨트롤러는 남겨둠 — 완전 제거: kubectl delete ns nginx-gateway)"
}

q5_setup_gateway_api() {
  # tutoring/session-3 의 4)·5) 와 같은 절차 — 이미 설치돼 있으면 건너뛴다
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

  # 데이터 플레인을 DaemonSet 으로 (모든 노드에서 접속되도록)
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
    full) echo "  → Q5 전부 채점 가능" ;;
    crds) echo "  → CRD 만 설치됨. Q5 리소스 작성은 채점되지만 상태·트래픽 검증은 제외" ;;
    none) echo "  → Gateway API 미설치. Q5 는 리소스 채점 불가" ;;
  esac
}

q5_setup_ingress() {
  kubectl create namespace "$Q5_NS" &>/dev/null || true

  # 백엔드 — /api/ 로 들어오면 shop-api-ok 를 돌려준다 (트래픽 검증용 표식)
  kubectl apply -f - &>/dev/null <<EOF
apiVersion: apps/v1
kind: Deployment
metadata: { name: shop-api, namespace: ${Q5_NS}, labels: { app: shop-api } }
spec:
  replicas: 1
  selector: { matchLabels: { app: shop-api } }
  template:
    metadata: { labels: { app: shop-api } }
    spec:
      containers:
      - name: nginx
        image: nginx:1.27
        ports: [ { containerPort: 80 } ]
        command: ["sh", "-c", "mkdir -p /usr/share/nginx/html/api && echo shop-api-ok > /usr/share/nginx/html/api/index.html && exec nginx -g 'daemon off;'"]
---
apiVersion: v1
kind: Service
metadata: { name: shop-api-svc, namespace: ${Q5_NS} }
spec:
  selector: { app: shop-api }
  ports: [ { name: http, port: 8080, targetPort: 80 } ]
EOF

  # 자체 서명 인증서 → TLS Secret
  local d; d=$(mktemp -d)
  if openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
       -keyout "$d/tls.key" -out "$d/tls.crt" \
       -subj "/CN=${Q5_HOST}" -addext "subjectAltName=DNS:${Q5_HOST}" &>/dev/null; then
    kubectl create secret tls shop-tls-cert -n "$Q5_NS" --cert="$d/tls.crt" --key="$d/tls.key" &>/dev/null
  else
    echo "  [주의] openssl 로 인증서를 만들지 못했습니다 — Secret shop-tls-cert 없음"
  fi
  rm -rf "$d"

  # 옮겨야 할 기존 Ingress (host + TLS + 경로)
  kubectl apply -f - &>/dev/null <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata: { name: shop-ingress, namespace: ${Q5_NS} }
spec:
  ingressClassName: nginx
  tls:
  - hosts: [ ${Q5_HOST} ]
    secretName: shop-tls-cert
  rules:
  - host: ${Q5_HOST}
    http:
      paths:
      - path: /api
        pathType: Prefix
        backend:
          service: { name: shop-api-svc, port: { number: 8080 } }
EOF
  echo "  Q5: $Q5_NS 네임스페이스 · shop-api(+shop-api-svc:8080) · Secret shop-tls-cert · Ingress shop-ingress 생성"
}

exam_setup() {
  echo "  (Q1~Q4 는 미리 만들어둘 것 없음 — Ingress 컨트롤러가 설치돼 있어야 실제 접속 테스트가 된다)"
  q5_setup_gateway_api
  q5_setup_ingress
}

# ══════════════════════════════════════════════════════════════
q1_title() { echo "Path based Ingress"; }
q1_text() { cat <<'EOF'
In the default namespace:

  1) create a Deployment named web1 with image nginx:1.24
  2) expose it with a ClusterIP Service named web1-svc, port 80 -> 80
  3) create an Ingress named web-ingress

     ingressClassName   nginx
     path               /web1   (pathType Prefix)
     backend            web1-svc port 80

Verify:
  kubectl get ingress web-ingress
  kubectl describe ingress web-ingress
EOF
}
q1_title_ko() { echo "경로 기반 Ingress"; }
q1_text_ko() { cat <<'EOF'
default 네임스페이스에서:

  1) web1 Deployment 를 nginx:1.24 이미지로 만든다
  2) web1-svc ClusterIP Service 로 노출한다 (port 80 → 80)
  3) web-ingress Ingress 를 만든다

     ingressClassName   nginx
     경로               /web1   (pathType Prefix)
     백엔드             web1-svc 포트 80

[확인]
  kubectl get ingress web-ingress
  kubectl describe ingress web-ingress
EOF
}
q1_grade() {
  check "Deployment web1 존재" "kubectl get deployment web1 -n default"
  check_output "이미지 nginx:1.24" \
    "kubectl get deployment web1 -n default -o jsonpath='{.spec.template.spec.containers[0].image}'" '^nginx:1\.24$'
  wait_ready "-l app=web1" default
  check "Service web1-svc 존재" "kubectl get service web1-svc -n default"
  check_output "타입 ClusterIP" "kubectl get service web1-svc -n default -o jsonpath='{.spec.type}'" '^ClusterIP$'
  check_output "Endpoints 에 파드 IP 등록" \
    "kubectl get endpoints web1-svc -n default -o jsonpath='{.subsets[0].addresses[0].ip}'" '[0-9]'
  check "Ingress web-ingress 존재" "kubectl get ingress web-ingress -n default"
  check_output "ingressClassName nginx" \
    "kubectl get ingress web-ingress -n default -o jsonpath='{.spec.ingressClassName}'" '^nginx$'
  check_output "경로 /web1" \
    "kubectl get ingress web-ingress -n default -o jsonpath='{.spec.rules[0].http.paths[0].path}'" '^/web1$'
  check_output "pathType Prefix" \
    "kubectl get ingress web-ingress -n default -o jsonpath='{.spec.rules[0].http.paths[0].pathType}'" '^Prefix$'
  check_output "백엔드 web1-svc:80" \
    "kubectl get ingress web-ingress -n default -o jsonpath='{.spec.rules[0].http.paths[0].backend.service.name}:{.spec.rules[0].http.paths[0].backend.service.port.number}'" '^web1-svc:80$'
}
q1_hint() { cat <<'EOF'
kubectl create deployment web1 --image=nginx:1.24
kubectl expose deployment web1 --name=web1-svc --port=80 --target-port=80

kubectl create ingress web-ingress --class=nginx --rule="/web1*=web1-svc:80"
# 또는 YAML 로 pathType: Prefix 를 명시한다
kubectl describe ingress web-ingress
EOF
}

# ══════════════════════════════════════════════════════════════
q2_title() { echo "Host based Ingress"; }
q2_text() { cat <<'EOF'
In the default namespace, create an Ingress named host-ingress.

  ingressClassName   nginx
  host               myapp.local
  path               /   (pathType Prefix)
  backend            web1-svc port 80

Verify:
  kubectl get ingress host-ingress
  curl -H "Host: myapp.local" http://<NodeIP>:<ingress-port>/
EOF
}
q2_title_ko() { echo "호스트 기반 Ingress"; }
q2_text_ko() { cat <<'EOF'
default 네임스페이스에 host-ingress Ingress 를 만드시오.

  ingressClassName   nginx
  호스트             myapp.local
  경로               /   (pathType Prefix)
  백엔드             web1-svc 포트 80

[확인]
  kubectl get ingress host-ingress
  curl -H "Host: myapp.local" http://<NodeIP>:<ingress-port>/
EOF
}
q2_grade() {
  check "Ingress host-ingress 존재" "kubectl get ingress host-ingress -n default"
  check_output "ingressClassName nginx" \
    "kubectl get ingress host-ingress -n default -o jsonpath='{.spec.ingressClassName}'" '^nginx$'
  check_output "host myapp.local" \
    "kubectl get ingress host-ingress -n default -o jsonpath='{.spec.rules[0].host}'" '^myapp\.local$'
  check_output "경로 /" \
    "kubectl get ingress host-ingress -n default -o jsonpath='{.spec.rules[0].http.paths[0].path}'" '^/$'
  check_output "pathType Prefix" \
    "kubectl get ingress host-ingress -n default -o jsonpath='{.spec.rules[0].http.paths[0].pathType}'" '^Prefix$'
  check_output "백엔드 web1-svc:80" \
    "kubectl get ingress host-ingress -n default -o jsonpath='{.spec.rules[0].http.paths[0].backend.service.name}:{.spec.rules[0].http.paths[0].backend.service.port.number}'" '^web1-svc:80$'
}
q2_hint() { cat <<'EOF'
kubectl create ingress host-ingress --class=nginx --rule="myapp.local/*=web1-svc:80"

# 호스트 헤더로 확인 (DNS 없이)
curl -H "Host: myapp.local" http://<NodeIP>:<ingress-nodeport>/
EOF
}

# ══════════════════════════════════════════════════════════════
q3_title() { echo "TLS Ingress with a self-signed certificate"; }
q3_text() { cat <<'EOF'
  1) create a self-signed certificate with openssl
     CN=myapp.local, valid for 365 days, files tls.key and tls.crt

  2) create a TLS Secret named tls-secret from those files
     (type kubernetes.io/tls)

  3) create an Ingress named tls-ingress in the default namespace
     tls[0].hosts        [myapp.local]
     tls[0].secretName   tls-secret
     rule                host myapp.local -> web1-svc:80

Verify:
  kubectl get secret tls-secret
  kubectl get ingress tls-ingress
EOF
}
q3_title_ko() { echo "자체 서명 인증서로 TLS Ingress"; }
q3_text_ko() { cat <<'EOF'
  1) openssl 로 자체 서명 인증서를 만든다
     CN=myapp.local, 유효기간 365일, 파일 tls.key / tls.crt

  2) 그 파일로 tls-secret TLS Secret 을 만든다
     (타입 kubernetes.io/tls)

  3) default 네임스페이스에 tls-ingress 를 만든다
     tls[0].hosts        [myapp.local]
     tls[0].secretName   tls-secret
     규칙                host myapp.local → web1-svc:80

[확인]
  kubectl get secret tls-secret
  kubectl get ingress tls-ingress
EOF
}
q3_grade() {
  check "Secret tls-secret 존재" "kubectl get secret tls-secret -n default"
  check_output "타입 kubernetes.io/tls" \
    "kubectl get secret tls-secret -n default -o jsonpath='{.type}'" '^kubernetes.io/tls$'
  check_output "tls.crt 가 들어 있다" \
    "kubectl get secret tls-secret -n default -o jsonpath='{.data.tls\.crt}'" '.'
  check_output "tls.key 가 들어 있다" \
    "kubectl get secret tls-secret -n default -o jsonpath='{.data.tls\.key}'" '.'
  check "Ingress tls-ingress 존재" "kubectl get ingress tls-ingress -n default"
  check_output "tls.secretName 이 tls-secret" \
    "kubectl get ingress tls-ingress -n default -o jsonpath='{.spec.tls[0].secretName}'" '^tls-secret$'
  check_output "tls.hosts 에 myapp.local" \
    "kubectl get ingress tls-ingress -n default -o jsonpath='{.spec.tls[0].hosts[*]}'" 'myapp\.local'
  check_output "규칙 백엔드가 web1-svc" \
    "kubectl get ingress tls-ingress -n default -o jsonpath='{.spec.rules[0].http.paths[0].backend.service.name}'" '^web1-svc$'
}
q3_hint() { cat <<'EOF'
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout tls.key -out tls.crt -subj "/CN=myapp.local/O=myapp.local"

kubectl create secret tls tls-secret --cert=tls.crt --key=tls.key

#   spec:
#     tls:
#     - hosts: [myapp.local]
#       secretName: tls-secret
#     rules:
#     - host: myapp.local
#       http: { paths: [{ path: /, pathType: Prefix,
#               backend: { service: { name: web1-svc, port: { number: 80 } } } }] }
EOF
}

# ══════════════════════════════════════════════════════════════
q4_title() { echo "Isolate a namespace with NetworkPolicies"; }
q4_text() { cat <<'EOF'
  1) create a namespace named production

  2) create a Deployment named secure-app in it (image nginx:1.24)

  3) create a NetworkPolicy named default-deny-all in production
     podSelector   {}   (all Pods)
     policyTypes   Ingress
     no ingress rules -> everything is denied

  4) create a NetworkPolicy named allow-8080 in production
     policyTypes   Ingress
     allow         TCP port 8080

Verify:
  kubectl get networkpolicy -n production
  kubectl describe networkpolicy default-deny-all -n production
EOF
}
q4_title_ko() { echo "NetworkPolicy 로 네임스페이스 격리"; }
q4_text_ko() { cat <<'EOF'
  1) production 네임스페이스를 만든다

  2) 그 안에 secure-app Deployment 를 만든다 (이미지 nginx:1.24)

  3) production 에 default-deny-all NetworkPolicy 를 만든다
     podSelector   {}   (모든 파드)
     policyTypes   Ingress
     ingress 규칙 없음 → 전부 차단

  4) production 에 allow-8080 NetworkPolicy 를 만든다
     policyTypes   Ingress
     허용          TCP 8080 포트

[확인]
  kubectl get networkpolicy -n production
  kubectl describe networkpolicy default-deny-all -n production
EOF
}
q4_grade() {
  check "네임스페이스 production 존재" "kubectl get namespace production"
  check "Deployment secure-app 존재" "kubectl get deployment secure-app -n production"
  check_output "이미지 nginx:1.24" \
    "kubectl get deployment secure-app -n production -o jsonpath='{.spec.template.spec.containers[0].image}'" '^nginx:1\.24$'
  check "NetworkPolicy default-deny-all 존재" "kubectl get networkpolicy default-deny-all -n production"
  check_output "podSelector 가 비어 있다 (전체 적용)" \
    "kubectl get networkpolicy default-deny-all -n production -o jsonpath='{.spec.podSelector}'" '^\{\}$'
  check_output "policyTypes 에 Ingress" \
    "kubectl get networkpolicy default-deny-all -n production -o jsonpath='{.spec.policyTypes}'" 'Ingress'
  check_result "default-deny-all 에 ingress 규칙이 없다 (전부 차단)" \
    "$([[ -z "$(kubectl get networkpolicy default-deny-all -n production -o jsonpath='{.spec.ingress}' 2>/dev/null)" ]] && echo 0 || echo 1)" \
    "ingress 항목이 있으면 기본 거부가 아니다"
  check "NetworkPolicy allow-8080 존재" "kubectl get networkpolicy allow-8080 -n production"
  check_output "allow-8080 이 포트 8080 허용" \
    "kubectl get networkpolicy allow-8080 -n production -o jsonpath='{.spec.ingress[0].ports[0].port}'" '^8080$'
}
q4_hint() { cat <<'EOF'
kubectl create namespace production
kubectl create deployment secure-app -n production --image=nginx:1.24

# 기본 거부 — ingress 를 아예 쓰지 않는다
#   spec: { podSelector: {}, policyTypes: [Ingress] }

# 포트 허용
#   spec:
#     podSelector: {}
#     policyTypes: [Ingress]
#     ingress:
#     - ports: [{ protocol: TCP, port: 8080 }]
EOF
}

# ══════════════════════════════════════════════════════════════
q5_title() { echo "Migrate an Ingress to Gateway API (HTTPS)"; }
q5_text() { cat <<'EOF'
In the namespace ing-migrate, an Ingress named shop-ingress exposes the
application over HTTPS. Migrate it to Gateway API, then remove the Ingress.

Inspect the existing Ingress first:
  kubectl get ingress shop-ingress -n ing-migrate -o yaml

  1) create a Gateway named shop-gateway in ing-migrate

     gatewayClassName   nginx
     listener           name https, port 443, protocol HTTPS
     hostname           the same host as the Ingress
     tls                terminate with the TLS Secret the Ingress uses

  2) create an HTTPRoute named shop-route in ing-migrate

     parentRefs         shop-gateway
     hostnames          the same host as the Ingress
     rule               the same path (PathPrefix) and the same
                        backend Service and port as the Ingress

  3) delete the Ingress shop-ingress
     (keep the Service and the Secret)

Verify:
  kubectl get gateway,httproute -n ing-migrate
  kubectl describe gateway shop-gateway -n ing-migrate
  kubectl get ingress -n ing-migrate
EOF
}
q5_title_ko() { echo "Ingress 를 Gateway API 로 옮기기 (HTTPS)"; }
q5_text_ko() { cat <<'EOF'
ing-migrate 네임스페이스의 shop-ingress Ingress 가 애플리케이션을 HTTPS 로
노출하고 있다. 이것을 Gateway API 로 옮긴 뒤 Ingress 를 삭제하시오.

먼저 기존 Ingress 를 확인한다:
  kubectl get ingress shop-ingress -n ing-migrate -o yaml

  1) ing-migrate 에 shop-gateway Gateway 를 만든다

     gatewayClassName   nginx
     리스너             이름 https, 포트 443, 프로토콜 HTTPS
     hostname           Ingress 와 같은 호스트
     tls                Ingress 가 쓰는 TLS Secret 으로 종료(Terminate)

  2) ing-migrate 에 shop-route HTTPRoute 를 만든다

     parentRefs         shop-gateway
     hostnames          Ingress 와 같은 호스트
     규칙               Ingress 와 같은 경로(PathPrefix)와
                        같은 백엔드 Service · 포트

  3) shop-ingress Ingress 를 삭제한다
     (Service 와 Secret 은 남겨 둔다)

[확인]
  kubectl get gateway,httproute -n ing-migrate
  kubectl describe gateway shop-gateway -n ing-migrate
  kubectl get ingress -n ing-migrate
EOF
}
q5_grade() {
  local mode ns="$Q5_NS"; mode=$(gw_mode)
  if [[ "$mode" == "none" ]]; then
    check_result "Gateway API 가 설치되어 있다" 1 "미설치 — 인터넷 연결 후 bash exam.sh start 재실행"
    return
  fi
  local GW="kubectl get gateway shop-gateway -n $ns -o jsonpath"
  local RT="kubectl get httproute shop-route -n $ns -o jsonpath"

  # ── Gateway 스펙
  check "Gateway shop-gateway 존재" "kubectl get gateway shop-gateway -n $ns"
  check_output "gatewayClassName nginx" "$GW='{.spec.gatewayClassName}'" '^nginx$'
  check_output "리스너 https 가 포트 443 · HTTPS" \
    "$GW='{.spec.listeners[?(@.name==\"https\")].port}/{.spec.listeners[?(@.name==\"https\")].protocol}'" '^443/HTTPS$'
  check_output "리스너 hostname $Q5_HOST" \
    "$GW='{.spec.listeners[?(@.name==\"https\")].hostname}'" '^shop\.example\.local$'
  check_output "리스너 TLS 인증서가 Secret shop-tls-cert" \
    "$GW='{.spec.listeners[?(@.name==\"https\")].tls.certificateRefs[*].name}'" '(^| )shop-tls-cert( |$)'
  check_output "TLS 모드 Terminate (생략하면 기본값)" \
    "$GW='{.spec.listeners[?(@.name==\"https\")].tls.mode}'" '^(Terminate)?$'

  # ── HTTPRoute 스펙
  check "HTTPRoute shop-route 존재" "kubectl get httproute shop-route -n $ns"
  check_output "parentRefs 가 shop-gateway" "$RT='{.spec.parentRefs[*].name}'" '(^| )shop-gateway( |$)'
  check_output "hostnames 에 $Q5_HOST" "$RT='{.spec.hostnames[*]}'" '(^| )shop\.example\.local( |$)'
  check_output "경로 매치 PathPrefix /api" \
    "$RT='{range .spec.rules[*].matches[*]}{.path.type}={.path.value}{\" \"}{end}'" '(^| )PathPrefix=/api/?( |$)'
  check_output "backendRef shop-api-svc:8080" \
    "$RT='{range .spec.rules[*].backendRefs[*]}{.name}:{.port}{\" \"}{end}'" '(^| )shop-api-svc:8080( |$)'

  # ── 정리 — Ingress 는 지우고, Service · Secret 은 남긴다
  # pipefail 이 걸려 있어 'kubectl get | grep' 파이프는 kubectl 의 실패를 그대로 돌려준다 — 값으로 판정
  local ing; ing=$(kubectl get ingress shop-ingress -n "$ns" 2>&1)
  check_result "Ingress shop-ingress 삭제됨" "$([[ "$ing" == *NotFound* ]] && echo 0 || echo 1)" \
    "$([[ "$ing" == *NotFound* ]] || echo "아직 남아 있다 — kubectl delete ingress shop-ingress -n $ns")"
  check "Service shop-api-svc 와 Secret shop-tls-cert 는 남아 있다" \
    "kubectl get service shop-api-svc -n $ns && kubectl get secret shop-tls-cert -n $ns"

  [[ "$mode" != "full" ]] && { echo -e "  ${DIM}(컨트롤러 미설치 — 상태·트래픽 검증 생략)${RESET}"; return; }

  # ── 컨트롤러가 받아들였는가
  check_output "Gateway Accepted" \
    "$GW='{.status.conditions[?(@.type==\"Accepted\")].status}'" 'True'
  check_output "Gateway Programmed" \
    "$GW='{.status.conditions[?(@.type==\"Programmed\")].status}'" 'True'
  check_output "리스너 https 의 인증서 참조가 해석됨 (ResolvedRefs)" \
    "$GW='{.status.listeners[?(@.name==\"https\")].conditions[?(@.type==\"ResolvedRefs\")].status}'" '^True$'
  check_output "HTTPRoute 가 Gateway 에 Accepted" \
    "$RT='{.status.parents[*].conditions[?(@.type==\"Accepted\")].status}'" 'True'
  check_output "HTTPRoute 백엔드 참조가 해석됨 (ResolvedRefs)" \
    "$RT='{.status.parents[*].conditions[?(@.type==\"ResolvedRefs\")].status}'" 'True'

  # ── 실제 HTTPS 트래픽 (Gateway 가 만든 Service 의 443 NodePort 로)
  local port ip hit="" resp
  port=$(kubectl get svc -n "$ns" -l gateway.networking.k8s.io/gateway-name=shop-gateway \
           -o jsonpath='{.items[0].spec.ports[?(@.port==443)].nodePort}' 2>/dev/null)
  port="${port//[^0-9]/}"
  if [[ -n "$port" ]] && command -v curl &>/dev/null; then
    for ip in $(kubectl get nodes -o jsonpath='{range .items[*]}{.status.addresses[?(@.type=="InternalIP")].address}{"\n"}{end}' 2>/dev/null); do
      [[ -z "$ip" ]] && continue
      resp=$(curl -sk --max-time 5 --resolve "${Q5_HOST}:${port}:${ip}" "https://${Q5_HOST}:${port}/api/" 2>/dev/null || true)
      [[ "$resp" == *shop-api-ok* ]] && { hit="$ip"; break; }
    done
  fi
  check_result "https://$Q5_HOST/api/ 가 Gateway 를 거쳐 백엔드에 닿는다${hit:+ — $hit:$port}" \
    "$([[ -n "$hit" ]] && echo 0 || echo 1)" \
    "${port:+NodePort $port 응답 없음 — }리스너 hostname · certificateRefs · HTTPRoute hostnames/경로 확인 (kubectl get svc -n $ns)"
}
q5_hint() { cat <<'EOF'
kubectl get ingress shop-ingress -n ing-migrate -o yaml   # host · secretName · path · backend 를 옮겨 적는다

apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata: { name: shop-gateway, namespace: ing-migrate }
spec:
  gatewayClassName: nginx                    # ← ingressClassName
  listeners:
  - name: https
    port: 443
    protocol: HTTPS
    hostname: shop.example.local             # ← tls[].hosts
    tls:
      mode: Terminate
      certificateRefs:
      - { kind: Secret, name: shop-tls-cert } # ← tls[].secretName
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata: { name: shop-route, namespace: ing-migrate }
spec:
  parentRefs: [ { name: shop-gateway } ]
  hostnames: [ shop.example.local ]          # ← rules[].host
  rules:
  - matches: [ { path: { type: PathPrefix, value: /api } } ]   # ← Prefix
    backendRefs: [ { name: shop-api-svc, port: 8080 } ]       # ← backend.service

kubectl describe gateway shop-gateway -n ing-migrate   # Accepted · Programmed · ResolvedRefs
kubectl delete ingress shop-ingress -n ing-migrate
EOF
}

exam_main "$@"
