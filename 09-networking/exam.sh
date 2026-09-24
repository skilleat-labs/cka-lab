#!/usr/bin/env bash
# CKA 5강 실습 — 서비스와 네트워킹 (순차 진행형)
set -uo pipefail
source "$(cd "$(dirname "$0")/.." && pwd)/_lib/exam-lib.sh"

EXAM_TITLE="CKA 5강 실습 — 서비스 · NodePort · NetworkPolicy · DNS"
EXAM_NQ=4

exam_cleanup() {
  kdel deployment web api backend -n default
  kdel service web-svc api-svc -n default
  kdel networkpolicy backend-policy -n default
  kdel pod dns-test -n default
  echo "  web / api / backend / web-svc / api-svc / backend-policy / dns-test 삭제"
}
exam_setup() { echo "  (미리 만들어둘 것 없음)"; }

# ══════════════════════════════════════════════════════════════
q1_title() { echo "Deployment behind a ClusterIP Service"; }
q1_text() { cat <<'EOF'
In the default namespace:

  1) create a Deployment named web
     image nginx:1.24 / replicas 3 / label app=web

  2) create a ClusterIP Service named web-svc
     selector app=web / port 80 -> targetPort 80

All three Pod IPs must appear in the Service Endpoints.

Verify:
  kubectl get deployment web
  kubectl get svc web-svc
  kubectl get endpoints web-svc
EOF
}
q1_title_ko() { echo "Deployment + ClusterIP Service"; }
q1_text_ko() { cat <<'EOF'
default 네임스페이스에서:

  1) web Deployment 생성
     이미지 nginx:1.24 / 레플리카 3 / 레이블 app=web

  2) web-svc ClusterIP Service 생성
     selector app=web / port 80 → targetPort 80

Endpoints 에 파드 IP 3개가 모두 보여야 한다.

[확인]
  kubectl get deployment web
  kubectl get svc web-svc
  kubectl get endpoints web-svc
EOF
}
q1_grade() {
  check "Deployment web 존재" "kubectl get deployment web -n default"
  check_output "replicas 3" "kubectl get deployment web -n default -o jsonpath='{.spec.replicas}'" '^3$'
  check_output "이미지 nginx:1.24" \
    "kubectl get deployment web -n default -o jsonpath='{.spec.template.spec.containers[0].image}'" '^nginx:1\.24$'
  wait_ready "-l app=web" default
  check "Service web-svc 존재" "kubectl get service web-svc -n default"
  check_output "타입 ClusterIP" "kubectl get service web-svc -n default -o jsonpath='{.spec.type}'" '^ClusterIP$'
  check_output "port 80" "kubectl get service web-svc -n default -o jsonpath='{.spec.ports[0].port}'" '^80$'
  check_output "selector app=web" "kubectl get service web-svc -n default -o jsonpath='{.spec.selector.app}'" '^web$'
  check_output "Endpoints 에 파드 IP 3개" \
    "kubectl get endpoints web-svc -n default -o jsonpath='{.subsets[0].addresses[*].ip}' | wc -w" '^\s*3$'
  check_output "임시 파드에서 web-svc 로 실제 HTTP 응답" \
    "kubectl run netchk-q1 -n default --rm -i --restart=Never --image=busybox:1.36 -- wget -qO- --timeout=5 http://web-svc 2>/dev/null" 'nginx'
}
q1_hint() { cat <<'EOF'
kubectl create deployment web --image=nginx:1.24 --replicas=3
kubectl expose deployment web --name=web-svc --port=80 --target-port=80 --type=ClusterIP
kubectl get endpoints web-svc     # 비어 있으면 selector 와 파드 레이블 불일치
EOF
}

# ══════════════════════════════════════════════════════════════
q2_title() { echo "NodePort Service on a fixed port"; }
q2_text() { cat <<'EOF'
In the default namespace:

  1) create a Deployment named api
     image nginx:1.24 / replicas 2 / label app=api

  2) create a NodePort Service named api-svc
     selector app=api / port 80 -> targetPort 80 / nodePort 30080

The nodePort must be exactly 30080, so kubectl expose alone is not enough.

Verify:
  kubectl get svc api-svc          -> 80:30080/TCP
  curl http://<NodeIP>:30080
EOF
}
q2_title_ko() { echo "NodePort Service (포트 고정)"; }
q2_text_ko() { cat <<'EOF'
default 네임스페이스에서:

  1) api Deployment 생성
     이미지 nginx:1.24 / 레플리카 2 / 레이블 app=api

  2) api-svc NodePort Service 생성
     selector app=api / port 80 → targetPort 80 / nodePort 30080

nodePort 를 반드시 30080 으로 고정해야 한다 — kubectl expose 만으로는
지정할 수 없다.

[확인]
  kubectl get svc api-svc          → 80:30080/TCP
  curl http://<NodeIP>:30080
EOF
}
q2_grade() {
  check "Deployment api 존재" "kubectl get deployment api -n default"
  check_output "replicas 2" "kubectl get deployment api -n default -o jsonpath='{.spec.replicas}'" '^2$'
  check_output "이미지 nginx:1.24" \
    "kubectl get deployment api -n default -o jsonpath='{.spec.template.spec.containers[0].image}'" '^nginx:1\.24$'
  wait_ready "-l app=api" default
  check "Service api-svc 존재" "kubectl get service api-svc -n default"
  check_output "타입 NodePort" "kubectl get service api-svc -n default -o jsonpath='{.spec.type}'" '^NodePort$'
  check_output "nodePort 30080" "kubectl get service api-svc -n default -o jsonpath='{.spec.ports[0].nodePort}'" '^30080$'
  check_output "port 80" "kubectl get service api-svc -n default -o jsonpath='{.spec.ports[0].port}'" '^80$'
  check_output "selector app=api" "kubectl get service api-svc -n default -o jsonpath='{.spec.selector.app}'" '^api$'
  local ip; ip=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null | awk '{print $1}')
  check_output "노드 IP:30080 으로 실제 응답 (${ip:-노드IP})" \
    "curl -s --max-time 5 http://${ip:-127.0.0.1}:30080" 'nginx'
}
q2_hint() { cat <<'EOF'
kubectl create deployment api --image=nginx:1.24 --replicas=2

# expose 는 nodePort 를 못 정한다 → YAML 로 뽑아서 고친다
kubectl expose deployment api --name=api-svc --port=80 --target-port=80 --type=NodePort $do > svc.yaml
#   spec.ports[0].nodePort: 30080  추가
kubectl apply -f svc.yaml
EOF
}

# ══════════════════════════════════════════════════════════════
q3_title() { echo "NetworkPolicy — only frontend may reach backend"; }
q3_text() { cat <<'EOF'
In the default namespace:

  1) create a Deployment named backend
     image nginx:1.24 / replicas 1 / label app=backend

  2) create a NetworkPolicy named backend-policy
     applies to    Pods labelled app=backend
     policyTypes   Ingress
     allow         traffic only from Pods labelled app=frontend
     everything else must be denied

Verify:
  kubectl describe networkpolicy backend-policy
EOF
}
q3_title_ko() { echo "NetworkPolicy — frontend 에서만 backend 로"; }
q3_text_ko() { cat <<'EOF'
default 네임스페이스에서:

  1) backend Deployment 생성
     이미지 nginx:1.24 / 레플리카 1 / 레이블 app=backend

  2) backend-policy NetworkPolicy 생성
     적용 대상    app=backend 레이블 파드
     policyTypes  Ingress
     허용         app=frontend 레이블 파드에서 오는 트래픽만
     그 외 모든 인바운드는 차단

[확인]
  kubectl describe networkpolicy backend-policy
EOF
}
q3_grade() {
  check "Deployment backend 존재" "kubectl get deployment backend -n default"
  check_output "이미지 nginx:1.24" \
    "kubectl get deployment backend -n default -o jsonpath='{.spec.template.spec.containers[0].image}'" '^nginx:1\.24$'
  check "NetworkPolicy backend-policy 존재" "kubectl get networkpolicy backend-policy -n default"
  check_output "대상이 app=backend" \
    "kubectl get networkpolicy backend-policy -n default -o jsonpath='{.spec.podSelector.matchLabels.app}'" '^backend$'
  check_output "policyTypes 에 Ingress" \
    "kubectl get networkpolicy backend-policy -n default -o jsonpath='{.spec.policyTypes}'" 'Ingress'
  check_output "허용 출처가 app=frontend" \
    "kubectl get networkpolicy backend-policy -n default -o jsonpath='{.spec.ingress[0].from[0].podSelector.matchLabels.app}'" '^frontend$'
  check_output "ingress 규칙이 1개 (전부 허용이 아니다)" \
    "kubectl get networkpolicy backend-policy -n default -o jsonpath='{.spec.ingress}' | grep -c 'podSelector'" '^[1-9]'
}
q3_hint() { cat <<'EOF'
kubectl create deployment backend --image=nginx:1.24 --replicas=1

#   kind: NetworkPolicy
#   spec:
#     podSelector: { matchLabels: { app: backend } }
#     policyTypes: [Ingress]
#     ingress:
#     - from:
#       - podSelector: { matchLabels: { app: frontend } }
# NetworkPolicy 는 create 명령이 없다 — 문서 예제를 복사해서 고치는 게 빠르다.
EOF
}

# ══════════════════════════════════════════════════════════════
q4_title() { echo "Check cluster DNS from a Pod"; }
q4_text() { cat <<'EOF'
In the default namespace, create a Pod named dns-test.

  image     busybox:1.36
  command   sleep 3600

From inside that Pod, resolve the Service name web-svc and confirm that it
returns the ClusterIP of web-svc.

Verify:
  kubectl get pod dns-test
  kubectl exec dns-test -- nslookup web-svc
  kubectl exec dns-test -- nslookup web-svc.default.svc.cluster.local
EOF
}
q4_title_ko() { echo "파드 안에서 클러스터 DNS 확인"; }
q4_text_ko() { cat <<'EOF'
default 네임스페이스에 dns-test 파드를 만드시오.

  이미지    busybox:1.36
  명령      sleep 3600

그 파드 안에서 web-svc 서비스 이름을 조회해 web-svc 의 ClusterIP 가
돌아오는지 확인하시오.

[확인]
  kubectl get pod dns-test
  kubectl exec dns-test -- nslookup web-svc
  kubectl exec dns-test -- nslookup web-svc.default.svc.cluster.local
EOF
}
q4_grade() {
  check "파드 dns-test 존재" "kubectl get pod dns-test -n default"
  wait_ready "dns-test" default
  check_output "Running" "kubectl get pod dns-test -n default -o jsonpath='{.status.phase}'" '^Running$'
  check_output "이미지 busybox:1.36" \
    "kubectl get pod dns-test -n default -o jsonpath='{.spec.containers[0].image}'" 'busybox'
  if kubectl get pod dns-test -n default &>/dev/null; then
    local cip; cip=$(kubectl get svc web-svc -n default -o jsonpath='{.spec.clusterIP}' 2>/dev/null)
    check_output "파드 안에서 web-svc 이름이 해석된다" \
      "kubectl exec dns-test -n default -- nslookup web-svc 2>/dev/null" "${cip:-Address}"
    check_output "FQDN 도 해석된다 (web-svc.default.svc.cluster.local)" \
      "kubectl exec dns-test -n default -- nslookup web-svc.default.svc.cluster.local 2>/dev/null" 'Address'
  else
    check_result "web-svc 이름 해석" 1 "파드가 없음"
    check_result "FQDN 해석" 1 "파드가 없음"
  fi
}
q4_hint() { cat <<'EOF'
kubectl run dns-test --image=busybox:1.36 --command -- sleep 3600
kubectl exec dns-test -- nslookup web-svc

# 해석이 안 되면
kubectl get pods -n kube-system -l k8s-app=kube-dns    # CoreDNS 가 Running 인가
kubectl exec dns-test -- cat /etc/resolv.conf          # nameserver 가 CoreDNS ClusterIP 인가
EOF
}

exam_main "$@"
