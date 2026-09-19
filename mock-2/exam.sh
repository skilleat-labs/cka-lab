#!/usr/bin/env bash
# CKA Mock Exam 2 — 순차 진행형 (100점 배점)
# 사용법: bash exam.sh start → 풀고 → bash exam.sh check → ...
set -uo pipefail
EXAM_UNIT="점"
source "$(cd "$(dirname "$0")/.." && pwd)/_lib/exam-lib.sh"

EXAM_TITLE="CKA Mock Exam 2 — 스케줄링·네트워킹·운영 (100점 · 목표 45분)"
EXAM_NQ=7

exam_cleanup() {
  kubectl delete pod affinity-pod toleration-pod shop-backend api-backend --ignore-not-found --force --grace-period=0 &>/dev/null || true
  kubectl delete svc shop-svc api-svc mysql-headless --ignore-not-found &>/dev/null || true
  kubectl delete networkpolicy deny-all allow-web --ignore-not-found &>/dev/null || true
  kubectl delete ingress shop-ingress --ignore-not-found &>/dev/null || true
  kubectl delete statefulset mysql-sts --ignore-not-found &>/dev/null || true
  kubectl delete pvc -l app=mysql-sts --ignore-not-found &>/dev/null || true
  kubectl delete pvc data-mysql-sts-0 data-mysql-sts-1 --ignore-not-found &>/dev/null || true
  rm -f /tmp/mock2-etcd.db
  kubectl label node worker-1 disktype- &>/dev/null || true
  # worker-2 kubelet 복구 (시험 중단 시 NotReady 로 남지 않도록)
  if kubectl get node worker-2 &>/dev/null; then
    ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no worker-2 'systemctl start kubelet; systemctl enable kubelet' &>/dev/null \
      && echo "  worker-2 kubelet 복구" || echo "  worker-2 kubelet 은 직접 확인 필요 (ssh 불가)"
  fi
  echo "  affinity/toleration 파드 · NetworkPolicy · Ingress · StatefulSet · 백엔드 · etcd 스냅샷 삭제, worker-1 레이블 제거"
}

exam_setup() {
  # Q1: worker-1 에 disktype=ssd 레이블 (파드가 실제로 배치되도록)
  kubectl label node worker-1 disktype=ssd --overwrite &>/dev/null && echo "  worker-1 에 disktype=ssd 레이블" || true
  # Q4: Ingress 백엔드
  kubectl run shop-backend --image=nginx:1.24 --labels="app=shop" --restart=Never &>/dev/null || true
  kubectl expose pod shop-backend --name=shop-svc --port=80 &>/dev/null || true
  kubectl run api-backend --image=nginx:1.24 --labels="app=api" --restart=Never &>/dev/null || true
  kubectl expose pod api-backend --name=api-svc --port=8080 --target-port=80 &>/dev/null || true
  echo "  Q4 용 shop-svc(80) / api-svc(8080) 백엔드 생성"
  # Q7: worker-2 kubelet 정지 시도 (ssh 가능할 때만)
  if kubectl get node worker-2 &>/dev/null; then
    if ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no worker-2 'systemctl stop kubelet' &>/dev/null; then
      echo "  Q7 용 worker-2 kubelet 정지 → 약 40초 후 NotReady 가 됩니다"
    else
      echo "  Q7: worker-2 에 ssh 로 kubelet 을 멈추지 못했습니다."
      echo "      강사가 worker-2 에서 직접  systemctl stop kubelet  을 실행해 주세요."
    fi
  fi
}

q1_title() { echo "Node Affinity Pod [15점]"; }
q1_text() { cat <<'EOF'
다음 조건의 Pod 를 생성하시오.

  이름          affinity-pod
  이미지        nginx:1.24
  네임스페이스  default
  스케줄링      disktype=ssd 레이블을 가진 노드에
                requiredDuringSchedulingIgnoredDuringExecution 방식으로 배치

참고: kubectl explain pod.spec.affinity.nodeAffinity

[확인]
  kubectl get pod affinity-pod -o wide    → disktype=ssd 노드에 Running
EOF
}
q1_hint() { cat <<'EOF'
spec:
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
        - matchExpressions:
          - { key: disktype, operator: In, values: [ssd] }
EOF
}
q1_grade() {
  check "affinity-pod 존재" "kubectl get pod affinity-pod -n default" 3
  local aff; aff=$(kubectl get pod affinity-pod -n default -o jsonpath='{.spec.affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution}' 2>/dev/null || echo "")
  check_result "requiredDuringScheduling nodeAffinity 설정" "$([[ -n "$aff" ]] && echo 0 || echo 1)" "" 4
  check_result "matchExpressions 에 disktype / ssd" "$(echo "$aff" | grep -q disktype && echo "$aff" | grep -q ssd && echo 0 || echo 1)" "" 4
  wait_ready "affinity-pod" default || true
  local node; node=$(kubectl get pod affinity-pod -n default -o jsonpath='{.spec.nodeName}' 2>/dev/null || echo "")
  local lbl=""; [[ -n "$node" ]] && lbl=$(kubectl get node "$node" -o jsonpath='{.metadata.labels.disktype}' 2>/dev/null || echo "")
  check_result "disktype=ssd 노드에 실제로 배치됨 (${node:-미배치})" "$([[ "$lbl" == "ssd" ]] && echo 0 || echo 1)" "" 4
}

q2_title() { echo "Taint + Toleration [15점]"; }
q2_text() { cat <<'EOF'
다음 조건의 Pod 를 생성하시오.

  이름          toleration-pod
  이미지        busybox:1.36
  명령          sleep 3600
  네임스페이스  default
  Toleration    key: dedicated / value: gpu / effect: NoSchedule / operator: Equal

참고: kubectl explain pod.spec.tolerations

[확인]
  kubectl get pod toleration-pod -o yaml | grep -A10 tolerations
EOF
}
q2_hint() { cat <<'EOF'
spec:
  tolerations:
  - { key: dedicated, operator: Equal, value: gpu, effect: NoSchedule }
EOF
}
q2_grade() {
  check "toleration-pod 존재" "kubectl get pod toleration-pod -n default" 3
  local t; t=$(kubectl get pod toleration-pod -n default -o jsonpath='{.spec.tolerations}' 2>/dev/null || echo "")
  check_result "toleration key=dedicated" "$(echo "$t" | grep -q '"key":"dedicated"' && echo 0 || echo 1)" "" 3
  check_result "toleration value=gpu" "$(echo "$t" | grep -q '"value":"gpu"' && echo 0 || echo 1)" "" 3
  check_result "toleration effect=NoSchedule" "$(echo "$t" | grep -q '"effect":"NoSchedule"' && echo 0 || echo 1)" "" 3
  wait_ready "toleration-pod" default || true
  check_output "toleration-pod Running" "kubectl get pod toleration-pod -n default -o jsonpath='{.status.phase}'" "^Running$" 3
}

q3_title() { echo "NetworkPolicy — deny-all + allow-web [20점]"; }
q3_text() { cat <<'EOF'
default 네임스페이스에 다음 두 가지 NetworkPolicy 를 생성하시오.

(1) deny-all
    - 모든 Pod 에 대해 Ingress 트래픽 전체 차단
    - podSelector: {}   (빈 selector = 전체 적용)
    - policyTypes: [Ingress]

(2) allow-web
    - app=db 레이블 Pod 가 수신 측
    - app=web 레이블 Pod 에서 포트 3306/TCP 만 허용
    - policyTypes: [Ingress]

[확인]
  kubectl describe networkpolicy deny-all
  kubectl describe networkpolicy allow-web
EOF
}
q3_hint() { cat <<'EOF'
# allow-web
spec:
  podSelector: { matchLabels: { app: db } }
  policyTypes: [Ingress]
  ingress:
  - from: [ { podSelector: { matchLabels: { app: web } } } ]
    ports: [ { protocol: TCP, port: 3306 } ]
EOF
}
q3_grade() {
  check "NetworkPolicy deny-all 존재" "kubectl get networkpolicy deny-all -n default" 3
  check_output "deny-all podSelector 가 비어 있다 (전체 적용)" \
    "kubectl get networkpolicy deny-all -n default -o jsonpath='{.spec.podSelector}'" "^\{\}$" 3
  check_output "deny-all policyTypes: Ingress" \
    "kubectl get networkpolicy deny-all -n default -o jsonpath='{.spec.policyTypes}'" "Ingress" 2
  check_result "deny-all 에 ingress 허용 규칙이 없다 (전부 차단)" \
    "$(kubectl get networkpolicy deny-all -n default &>/dev/null && [[ -z "$(kubectl get networkpolicy deny-all -n default -o jsonpath='{.spec.ingress}' 2>/dev/null)" ]] && echo 0 || echo 1)" "" 2
  check "NetworkPolicy allow-web 존재" "kubectl get networkpolicy allow-web -n default" 2
  check_output "allow-web 대상이 app=db" \
    "kubectl get networkpolicy allow-web -n default -o jsonpath='{.spec.podSelector.matchLabels.app}'" "^db$" 2
  check_output "allow-web from 이 app=web" \
    "kubectl get networkpolicy allow-web -n default -o jsonpath='{.spec.ingress[0].from[*].podSelector.matchLabels.app}'" "web" 3
  check_output "allow-web 포트 3306/TCP" \
    "kubectl get networkpolicy allow-web -n default -o jsonpath='{.spec.ingress[0].ports[0].port}'" "^3306$" 3
}

q4_title() { echo "Ingress 생성 [15점]"; }
q4_text() { cat <<'EOF'
다음 조건으로 Ingress 를 생성하시오. (백엔드 shop-svc, api-svc 는 이미 있다)

  이름          shop-ingress
  네임스페이스  default
  pathType      Prefix
  라우팅        /shop  →  shop-svc : 80
                /api   →  api-svc  : 8080

[확인]
  kubectl describe ingress shop-ingress
EOF
}
q4_hint() { echo 'kubectl create ingress shop-ingress --rule="/shop=shop-svc:80" --rule="/api=api-svc:8080"'; }
q4_grade() {
  check "Ingress shop-ingress 존재" "kubectl get ingress shop-ingress -n default" 3
  local rules; rules=$(kubectl get ingress shop-ingress -n default -o json 2>/dev/null || echo "{}")
  local py='import sys,json; d=json.load(sys.stdin); ps=[(p.get("path"),p.get("pathType"),p["backend"]["service"]["name"],p["backend"]["service"]["port"].get("number")) for r in d.get("spec",{}).get("rules",[]) for p in r.get("http",{}).get("paths",[])]; print(ps)'
  local paths; paths=$(echo "$rules" | python3 -c "$py" 2>/dev/null || echo "")
  check_result "/shop → shop-svc:80" "$(echo "$paths" | grep -q "('/shop', 'Prefix', 'shop-svc', 80)" && echo 0 || echo 1)" "" 6
  check_result "/api → api-svc:8080" "$(echo "$paths" | grep -q "('/api', 'Prefix', 'api-svc', 8080)" && echo 0 || echo 1)" "" 6
}

q5_title() { echo "StatefulSet + headless Service [15점]"; }
q5_text() { cat <<'EOF'
다음 조건으로 StatefulSet 과 headless Service 를 생성하시오.

StatefulSet
  이름          mysql-sts
  이미지        mysql:8.0
  복제본        2
  환경변수      MYSQL_ROOT_PASSWORD=rootpass
  serviceName   mysql-headless
  volumeClaimTemplates   이름 data / 1Gi / ReadWriteOnce / mountPath /var/lib/mysql

headless Service (clusterIP: None)
  이름          mysql-headless
  포트          3306

[확인]
  kubectl get statefulset mysql-sts
  kubectl get pvc          → data-mysql-sts-0, data-mysql-sts-1
EOF
}
q5_hint() { echo "StatefulSet 은 create 명령이 없다 → 공식 문서 예제(nginx StatefulSet)를 복사해서 수정"; }
q5_grade() {
  check "StatefulSet mysql-sts 존재" "kubectl get statefulset mysql-sts -n default" 3
  check_output "이미지: mysql:8.0" \
    "kubectl get statefulset mysql-sts -n default -o jsonpath='{.spec.template.spec.containers[0].image}'" "^mysql:8\.0$" 2
  check_output "복제본 2" "kubectl get statefulset mysql-sts -n default -o jsonpath='{.spec.replicas}'" "^2$" 2
  check_output "serviceName 이 mysql-headless" "kubectl get statefulset mysql-sts -n default -o jsonpath='{.spec.serviceName}'" "^mysql-headless$" 2
  check_output "volumeClaimTemplates data / 1Gi" \
    "kubectl get statefulset mysql-sts -n default -o jsonpath='{.spec.volumeClaimTemplates[0].metadata.name}{\" \"}{.spec.volumeClaimTemplates[0].spec.resources.requests.storage}'" "^data 1Gi$" 3
  check_output "headless Service mysql-headless (clusterIP: None)" \
    "kubectl get svc mysql-headless -n default -o jsonpath='{.spec.clusterIP}'" "^None$" 3
}

q6_title() { echo "etcd 백업 [10점]"; }
q6_text() { cat <<'EOF'
etcd 스냅샷을 /tmp/mock2-etcd.db 에 저장하시오.

  endpoint      https://127.0.0.1:2379
  CA cert       /etc/kubernetes/pki/etcd/ca.crt
  Cert          /etc/kubernetes/pki/etcd/server.crt
  Key           /etc/kubernetes/pki/etcd/server.key

[확인]
  ls -lh /tmp/mock2-etcd.db
  ETCDCTL_API=3 etcdctl snapshot status /tmp/mock2-etcd.db
EOF
}
q6_hint() { cat <<'EOF'
ETCDCTL_API=3 etcdctl snapshot save /tmp/mock2-etcd.db \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key
EOF
}
q6_grade() {
  check_result "/tmp/mock2-etcd.db 파일 존재" "$([[ -f /tmp/mock2-etcd.db ]] && echo 0 || echo 1)" "컨트롤플레인 노드에서 실행해야 함" 4
  local sz; sz=$(stat -c%s /tmp/mock2-etcd.db 2>/dev/null || stat -f%z /tmp/mock2-etcd.db 2>/dev/null || echo 0)
  check_result "스냅샷 크기 > 1MB (실제 etcd 데이터)" "$([[ "$sz" -gt 1000000 ]] && echo 0 || echo 1)" "${sz} bytes" 3
  local st=1
  if command -v etcdctl &>/dev/null; then ETCDCTL_API=3 etcdctl snapshot status /tmp/mock2-etcd.db &>/dev/null && st=0
  elif command -v etcdutl &>/dev/null; then etcdutl snapshot status /tmp/mock2-etcd.db &>/dev/null && st=0
  else st=$([[ "$sz" -gt 1000000 ]] && echo 0 || echo 1); fi
  check_result "스냅샷이 유효하다 (snapshot status)" "$st" "" 3
}

q7_title() { echo "Node NotReady 복구 [10점]"; }
q7_text() { cat <<'EOF'
worker-2 노드가 NotReady 상태다. 원인을 파악하고 복구하시오.
복구 후 재부팅에도 kubelet 이 자동으로 뜨도록 설정하시오.

진단 순서
  kubectl describe node worker-2     → Conditions
  ssh worker-2
  systemctl status kubelet
  journalctl -u kubelet -n 50

[확인]
  kubectl get nodes                  → worker-2 가 Ready
EOF
}
q7_hint() { cat <<'EOF'
ssh worker-2
systemctl start kubelet && systemctl enable kubelet
EOF
}
q7_grade() {
  if ! kubectl get node worker-2 &>/dev/null; then
    check_result "worker-2 노드 (이 클러스터에 없음 — 통과 처리)" 0 "" 10; return
  fi
  local i; for i in $(seq 1 10); do
    [[ "$(kubectl get node worker-2 -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)" == "True" ]] && break; sleep 3
  done
  check_output "worker-2 Ready 상태" "kubectl get node worker-2 -o jsonpath='{.status.conditions[?(@.type==\"Ready\")].status}'" "^True$" 7
  local en; en=$(ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no worker-2 'systemctl is-enabled kubelet' 2>/dev/null || echo "unknown")
  if [[ "$en" == "unknown" ]]; then
    check_result "kubelet enabled (ssh 불가 — 확인 생략, 통과 처리)" 0 "" 3
  else
    check_result "kubelet 이 enabled 상태 (재부팅 후 자동 시작)" "$([[ "$en" == "enabled" ]] && echo 0 || echo 1)" "$en" 3
  fi
}

exam_main "$@"
