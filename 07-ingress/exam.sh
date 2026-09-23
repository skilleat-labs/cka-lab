#!/usr/bin/env bash
# CKA 7강 실습 — Ingress 와 네임스페이스 격리 (순차 진행형)
set -uo pipefail
source "$(cd "$(dirname "$0")/.." && pwd)/_lib/exam-lib.sh"

EXAM_TITLE="CKA 7강 실습 — Ingress (경로·호스트·TLS) · 네임스페이스 격리"
EXAM_NQ=4

exam_cleanup() {
  kdel ingress web-ingress host-ingress tls-ingress -n default
  kdel deployment web1 -n default
  kdel service web1-svc -n default
  kdel secret tls-secret -n default
  kdel namespace production
  echo "  web1 / web1-svc / ingress 3종 / tls-secret / production ns 삭제"
}
exam_setup() { echo "  (미리 만들어둘 것 없음 — Ingress 컨트롤러가 설치돼 있어야 실제 접속 테스트가 된다)"; }

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

exam_main "$@"
