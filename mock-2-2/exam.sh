#!/usr/bin/env bash
# CKA Mock Exam 2-2 — 30분 속도 점검 (100점 · 6문항)
# 사용법: bash exam.sh start → 풀고 → bash exam.sh check → ...
#
# 목적: 기초~중급 유형 6개를 30분 안에 푸는지 확인한다.
# 모든 리소스는 store 네임스페이스에 격리된다.
set -uo pipefail
EXAM_UNIT="점"
source "$(cd "$(dirname "$0")/.." && pwd)/_lib/exam-lib.sh"

EXAM_TITLE="CKA Mock Exam 2-2 — 30분 속도 점검 (100점 · 6문항)"
EXAM_NQ=6
NS=store

exam_cleanup() {
  if kubectl get namespace $NS &>/dev/null; then
    echo "  네임스페이스 $NS 삭제 중... (수십 초 걸릴 수 있음)"
    kubectl delete namespace $NS --wait=true &>/dev/null || true
  fi
  kdel pv logs-pv
  echo "  store 네임스페이스 · logs-pv 삭제"
}

exam_setup() {
  kubectl create namespace $NS &>/dev/null || true
  echo "  store 네임스페이스 생성 (모든 문제는 여기서)"
}

# ══════════════════════════════════════════════════════════════
q1_title() { echo "Create a Pod to spec [15 pts]"; }
q1_text() { cat <<'EOF'
In the store namespace, create a Pod with the following spec.

  name            edge-cache
  image           nginx:1.25
  container port  80
  environment     CACHE_MODE=lru
  labels          app=edge, tier=cache

Verify:
  kubectl get pod edge-cache -n store --show-labels
  kubectl exec edge-cache -n store -- printenv CACHE_MODE
EOF
}
q1_title_ko() { echo "조건대로 Pod 생성 [15점]"; }
q1_text_ko() { cat <<'EOF'
store 네임스페이스에 다음 조건의 Pod 를 생성하시오.

  이름            edge-cache
  이미지          nginx:1.25
  컨테이너 포트   80
  환경변수        CACHE_MODE=lru
  레이블          app=edge, tier=cache

[확인]
  kubectl get pod edge-cache -n store --show-labels
  kubectl exec edge-cache -n store -- printenv CACHE_MODE
EOF
}
q1_hint() { echo 'kubectl run edge-cache -n store --image=nginx:1.25 --port=80 --env=CACHE_MODE=lru --labels=app=edge,tier=cache'; }
q1_grade() {
  check "edge-cache Pod 가 store 네임스페이스에 존재" "kubectl get pod edge-cache -n $NS" 3
  check_output "이미지 nginx:1.25" "kubectl get pod edge-cache -n $NS -o jsonpath='{.spec.containers[0].image}'" "^nginx:1\.25$" 2
  check_output "containerPort 80" "kubectl get pod edge-cache -n $NS -o jsonpath='{.spec.containers[0].ports[0].containerPort}'" "^80$" 2
  check_output "레이블 app=edge" "kubectl get pod edge-cache -n $NS -o jsonpath='{.metadata.labels.app}'" "^edge$" 2
  check_output "레이블 tier=cache" "kubectl get pod edge-cache -n $NS -o jsonpath='{.metadata.labels.tier}'" "^cache$" 2
  wait_ready "edge-cache" $NS || true
  check_output "Running" "kubectl get pod edge-cache -n $NS -o jsonpath='{.status.phase}'" "^Running$" 2
  check_output "파드 안에서 CACHE_MODE=lru (실제 exec)" "kubectl exec edge-cache -n $NS -- printenv CACHE_MODE" "^lru$" 2
}

# ══════════════════════════════════════════════════════════════
q2_title() { echo "Deployment with a NodePort Service [15 pts]"; }
q2_text() { cat <<'EOF'
In the store namespace, create a Deployment and expose it with a NodePort
Service.

Deployment
  name            catalog
  image           nginx:1.24
  replicas        3
  container port  80

Service
  name            catalog-svc
  type            NodePort
  port            80 -> targetPort 80
  nodePort        30095

Verify:
  kubectl get deploy,svc,endpoints -n store
  curl http://<NodeIP>:30095
EOF
}
q2_title_ko() { echo "Deployment + NodePort Service [15점]"; }
q2_text_ko() { cat <<'EOF'
store 네임스페이스에 Deployment 를 만들고 NodePort 로 노출하시오.

Deployment
  이름            catalog
  이미지          nginx:1.24
  복제본          3
  컨테이너 포트   80

Service
  이름            catalog-svc
  타입            NodePort
  port            80 → targetPort 80
  nodePort        30095

[확인]
  kubectl get deploy,svc,endpoints -n store
  curl http://<NodeIP>:30095
EOF
}
q2_hint() { cat <<'EOF'
kubectl create deployment catalog --image=nginx:1.24 --replicas=3 --port=80 -n store
kubectl expose deployment catalog --name=catalog-svc --port=80 --target-port=80 --type=NodePort -n store
kubectl patch svc catalog-svc -n store -p '{"spec":{"ports":[{"port":80,"targetPort":80,"nodePort":30095}]}}'
EOF
}
q2_grade() {
  check "catalog Deployment 존재" "kubectl get deployment catalog -n $NS" 2
  check_output "이미지 nginx:1.24" "kubectl get deployment catalog -n $NS -o jsonpath='{.spec.template.spec.containers[0].image}'" "^nginx:1\.24$" 2
  wait_ready "-l app=catalog" $NS || true
  check_output "Ready 복제본 3" "kubectl get deployment catalog -n $NS -o jsonpath='{.status.readyReplicas}'" "^3$" 3
  check_output "catalog-svc NodePort 타입" "kubectl get svc catalog-svc -n $NS -o jsonpath='{.spec.type}'" "^NodePort$" 2
  check_output "nodePort 30095" "kubectl get svc catalog-svc -n $NS -o jsonpath='{.spec.ports[0].nodePort}'" "^30095$" 3
  local ep; ep=$(kubectl get endpoints catalog-svc -n $NS -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null | wc -w | tr -d ' ')
  check_result "Endpoints 에 파드 IP 3개" "$([[ "$ep" == "3" ]] && echo 0 || echo 1)" "실제 ${ep}개" 3
}

# ══════════════════════════════════════════════════════════════
q3_title() { echo "Secret as env, ConfigMap as volume [15 pts]"; }
q3_text() { cat <<'EOF'
Perform the following in the store namespace.

(1) Create a generic Secret
  name            db-cred
  data            user=admin, pass=s3cret

(2) Create a ConfigMap
  name            app-cfg
  data            key config.properties with the value "mode=prod"

(3) Create a Pod
  name            worker
  image           busybox:1.36
  command         sleep 3600
  environment     DB_USER from key user of Secret db-cred
  volume mount    ConfigMap app-cfg mounted at /etc/app

Verify:
  kubectl exec worker -n store -- printenv DB_USER          -> admin
  kubectl exec worker -n store -- cat /etc/app/config.properties   -> mode=prod
EOF
}
q3_title_ko() { echo "Secret 은 환경변수로, ConfigMap 은 볼륨으로 [15점]"; }
q3_text_ko() { cat <<'EOF'
store 네임스페이스에서 다음을 수행하시오.

(1) Secret 생성 (generic)
  이름            db-cred
  데이터          user=admin, pass=s3cret

(2) ConfigMap 생성
  이름            app-cfg
  데이터          config.properties 키에 값 "mode=prod"

(3) Pod 생성
  이름            worker
  이미지          busybox:1.36
  명령            sleep 3600
  환경변수        DB_USER ← Secret db-cred 의 user 키
  볼륨 마운트     ConfigMap app-cfg 를 /etc/app 에

[확인]
  kubectl exec worker -n store -- printenv DB_USER          → admin
  kubectl exec worker -n store -- cat /etc/app/config.properties   → mode=prod
EOF
}
q3_hint() { cat <<'EOF'
kubectl create secret generic db-cred -n store --from-literal=user=admin --from-literal=pass=s3cret
kubectl create configmap app-cfg -n store --from-literal=config.properties=mode=prod
# Pod YAML: env[0].valueFrom.secretKeyRef {name: db-cred, key: user} / volumes[0].configMap {name: app-cfg} → /etc/app
EOF
}
q3_grade() {
  check_output "Secret db-cred 의 user 가 admin" "kubectl get secret db-cred -n $NS -o jsonpath='{.data.user}' | base64 -d" "^admin$" 2
  check_output "ConfigMap app-cfg 의 config.properties" "kubectl get configmap app-cfg -n $NS -o jsonpath='{.data.config\.properties}'" "mode=prod" 2
  check "worker Pod 존재" "kubectl get pod worker -n $NS" 2
  wait_ready "worker" $NS || true
  check_output "worker Running" "kubectl get pod worker -n $NS -o jsonpath='{.status.phase}'" "^Running$" 2
  check_output "DB_USER 가 secretKeyRef 로 주입됨" "kubectl get pod worker -n $NS -o jsonpath='{.spec.containers[0].env[?(@.name==\"DB_USER\")].valueFrom.secretKeyRef.key}'" "^user$" 2
  check_output "파드 안에서 DB_USER=admin (실제 exec)" "kubectl exec worker -n $NS -- printenv DB_USER" "^admin$" 2
  check_output "/etc/app/config.properties 내용 (실제 exec)" "kubectl exec worker -n $NS -- cat /etc/app/config.properties" "mode=prod" 3
}

# ══════════════════════════════════════════════════════════════
q4_title() { echo "Scale, rolling update and rollback [15 pts]"; }
q4_text() { cat <<'EOF'
In the store namespace, create a Deployment named orders (nginx:1.24,
replicas 2), then perform the following in order.

  (a) scale to 3 replicas
  (b) rolling update to nginx:1.25 and wait until it completes
  (c) roll back to the previous revision

Final state: nginx:1.24 / replicas 3 / all Ready.
You must actually go through all three steps (creating it with 1.24 and
only scaling does not count).

Verify:
  kubectl rollout history deployment/orders -n store   -> at least three revisions
  kubectl get rs -n store
EOF
}
q4_title_ko() { echo "스케일 · 롤링 업데이트 · 롤백 [15점]"; }
q4_text_ko() { cat <<'EOF'
store 네임스페이스에 Deployment orders (nginx:1.24, replicas 2) 를 만든 뒤
순서대로 수행하시오.

  (a) replicas 를 3 으로 스케일
  (b) 이미지를 nginx:1.25 로 롤링 업데이트하고 완료될 때까지 대기
  (c) 이전 리비전으로 롤백

최종 상태: nginx:1.24 / replicas 3 / 전부 Ready
세 단계를 실제로 거쳐야 한다 (처음부터 1.24 로 두고 스케일만 하면 오답).

[확인]
  kubectl rollout history deployment/orders -n store   → 리비전 3개 이상
  kubectl get rs -n store
EOF
}
q4_hint() { cat <<'EOF'
kubectl create deployment orders --image=nginx:1.24 --replicas=2 -n store
kubectl scale deployment orders --replicas=3 -n store
kubectl set image deployment/orders nginx=nginx:1.25 -n store && kubectl rollout status deployment/orders -n store
kubectl rollout undo deployment/orders -n store && kubectl rollout status deployment/orders -n store
EOF
}
q4_grade() {
  check "orders Deployment 존재" "kubectl get deployment orders -n $NS" 2
  check_output "replicas 3" "kubectl get deployment orders -n $NS -o jsonpath='{.spec.replicas}'" "^3$" 2
  wait_ready "-l app=orders" $NS || true
  check_output "Ready 3" "kubectl get deployment orders -n $NS -o jsonpath='{.status.readyReplicas}'" "^3$" 2
  check_output "최종 이미지 nginx:1.24 (롤백 완료)" "kubectl get deployment orders -n $NS -o jsonpath='{.spec.template.spec.containers[0].image}'" "^nginx:1\.24$" 3
  check_output "nginx:1.25 ReplicaSet 이력 존재 (업데이트를 실제로 함)" \
    "kubectl get rs -n $NS -l app=orders -o jsonpath='{range .items[*]}{.spec.template.spec.containers[0].image}{\"\\n\"}{end}'" "^nginx:1\.25$" 3
  local rev; rev=$(kubectl get deployment orders -n $NS -o jsonpath='{.metadata.annotations.deployment\.kubernetes\.io/revision}' 2>/dev/null || echo 0)
  check_result "revision ≥ 3 (생성→업데이트→롤백)" "$([[ "$rev" =~ ^[0-9]+$ && "$rev" -ge 3 ]] && echo 0 || echo 1)" "현재 ${rev:-0}" 3
}

# ══════════════════════════════════════════════════════════════
q5_title() { echo "Create a PV, bind a PVC, mount it [20 pts]"; }
q5_text() { cat <<'EOF'
Create a PV with the following spec, bind it with a PVC, then mount it in
a Pod.

PersistentVolume
  name              logs-pv
  capacity          1Gi
  access mode       ReadWriteOnce
  type              hostPath, path=/mnt/logs
  storageClassName  local-logs

PersistentVolumeClaim
  name              logs-pvc  (store namespace)
  request           500Mi
  access mode       ReadWriteOnce
  storageClassName  local-logs

Pod
  name              log-writer / busybox:1.36 / sleep 3600
  mount             logs-pvc at /var/log/app

Verify:
  kubectl get pv logs-pv ; kubectl get pvc logs-pvc -n store   -> both Bound
  kubectl exec log-writer -n store -- touch /var/log/app/ok
EOF
}
q5_title_ko() { echo "PV 직접 생성 → PVC Bound → 파드 마운트 [20점]"; }
q5_text_ko() { cat <<'EOF'
다음 조건으로 PV 를 만들고, PVC 로 Bound 시킨 뒤, 파드에 마운트하시오.

PersistentVolume
  이름              logs-pv
  용량              1Gi
  접근 모드         ReadWriteOnce
  타입              hostPath, path=/mnt/logs
  storageClassName  local-logs

PersistentVolumeClaim
  이름              logs-pvc  (store 네임스페이스)
  용량 요청         500Mi
  접근 모드         ReadWriteOnce
  storageClassName  local-logs

Pod
  이름              log-writer / busybox:1.36 / sleep 3600
  마운트            logs-pvc 를 /var/log/app 에

[확인]
  kubectl get pv logs-pv ; kubectl get pvc logs-pvc -n store   → 둘 다 Bound
  kubectl exec log-writer -n store -- touch /var/log/app/ok
EOF
}
q5_hint() { echo "PV 와 PVC 의 storageClassName·accessModes 가 같아야 하고 PVC 요청 ≤ PV 용량이어야 Bound 된다"; }
q5_grade() {
  check_output "PV logs-pv 용량 1Gi" "kubectl get pv logs-pv -o jsonpath='{.spec.capacity.storage}'" "^1Gi$" 2
  check_output "PV accessMode RWO" "kubectl get pv logs-pv -o jsonpath='{.spec.accessModes[0]}'" "^ReadWriteOnce$" 2
  check_output "PV hostPath /mnt/logs" "kubectl get pv logs-pv -o jsonpath='{.spec.hostPath.path}'" "^/mnt/logs$" 2
  check_output "PV storageClassName local-logs" "kubectl get pv logs-pv -o jsonpath='{.spec.storageClassName}'" "^local-logs$" 2
  check_output "PVC logs-pvc 요청 500Mi" "kubectl get pvc logs-pvc -n $NS -o jsonpath='{.spec.resources.requests.storage}'" "^500Mi$" 2
  check_output "PVC Bound" "kubectl get pvc logs-pvc -n $NS -o jsonpath='{.status.phase}'" "^Bound$" 3
  check_output "PVC 가 logs-pv 에 바인딩" "kubectl get pvc logs-pvc -n $NS -o jsonpath='{.spec.volumeName}'" "^logs-pv$" 2
  wait_ready "log-writer" $NS || true
  check_output "log-writer 가 logs-pvc 를 /var/log/app 에 마운트" \
    "kubectl get pod log-writer -n $NS -o jsonpath='{.spec.volumes[?(@.persistentVolumeClaim.claimName==\"logs-pvc\")].name}'" "." 2
  local out; out=$(kubectl exec log-writer -n $NS -- sh -c 'echo ok > /var/log/app/.probe && cat /var/log/app/.probe' 2>/dev/null || echo "")
  check_result "파드 안 /var/log/app 에 실제 쓰기·읽기" "$([[ "$out" == "ok" ]] && echo 0 || echo 1)" "" 3
}

# ══════════════════════════════════════════════════════════════
q6_title() { echo "NetworkPolicy — only tier=cache may reach catalog [20 pts]"; }
q6_text() { cat <<'EOF'
Create two NetworkPolicies in the store namespace.

(1) deny-all
    - block all ingress for every Pod  (podSelector: {} / policyTypes: [Ingress])

(2) allow-cache-to-catalog
    - target: Pods labelled app=catalog
    - allow: TCP 80 only from Pods labelled tier=cache

Result: from a tier=cache Pod (edge-cache from task 1) catalog-svc must
answer, and from a Pod without that label it must time out.

Verify:
  kubectl describe networkpolicy -n store
  kubectl exec edge-cache -n store -- curl -s --max-time 3 http://catalog-svc      -> answers
  kubectl run t -n store --rm -it --image=busybox:1.36 --restart=Never -- wget -qO- --timeout=3 http://catalog-svc   -> timeout
EOF
}
q6_title_ko() { echo "NetworkPolicy — tier=cache 에서만 catalog 로 [20점]"; }
q6_text_ko() { cat <<'EOF'
store 네임스페이스에 NetworkPolicy 두 개를 만드시오.

(1) deny-all
    - 모든 파드의 Ingress 전체 차단  (podSelector: {} / policyTypes: [Ingress])

(2) allow-cache-to-catalog
    - 대상: app=catalog 파드
    - 허용: tier=cache 레이블 파드에서 오는 TCP 80 만

결과: tier=cache 파드(Q1 의 edge-cache)에서는 catalog-svc 가 응답하고,
      레이블 없는 파드에서는 timeout 이어야 한다.

[확인]
  kubectl describe networkpolicy -n store
  kubectl exec edge-cache -n store -- curl -s --max-time 3 http://catalog-svc      → 응답
  kubectl run t -n store --rm -it --image=busybox:1.36 --restart=Never -- wget -qO- --timeout=3 http://catalog-svc   → timeout
EOF
}
q6_hint() { cat <<'EOF'
# allow-cache-to-catalog
spec:
  podSelector: { matchLabels: { app: catalog } }
  policyTypes: [Ingress]
  ingress:
  - from: [ { podSelector: { matchLabels: { tier: cache } } } ]
    ports: [ { protocol: TCP, port: 80 } ]
EOF
}
q6_grade() {
  check "deny-all 존재" "kubectl get networkpolicy deny-all -n $NS" 2
  check_output "deny-all podSelector 비어 있음" "kubectl get networkpolicy deny-all -n $NS -o jsonpath='{.spec.podSelector}'" "^\{\}$" 2
  check_output "deny-all policyTypes Ingress" "kubectl get networkpolicy deny-all -n $NS -o jsonpath='{.spec.policyTypes}'" "Ingress" 1
  check "allow-cache-to-catalog 존재" "kubectl get networkpolicy allow-cache-to-catalog -n $NS" 2
  check_output "대상 app=catalog" "kubectl get networkpolicy allow-cache-to-catalog -n $NS -o jsonpath='{.spec.podSelector.matchLabels.app}'" "^catalog$" 2
  check_output "from tier=cache" "kubectl get networkpolicy allow-cache-to-catalog -n $NS -o jsonpath='{.spec.ingress[0].from[*].podSelector.matchLabels.tier}'" "cache" 2
  check_output "포트 80" "kubectl get networkpolicy allow-cache-to-catalog -n $NS -o jsonpath='{.spec.ingress[0].ports[0].port}'" "^80$" 1
  # 실제 통신 — 허용 경로 (edge-cache 는 tier=cache)
  local ok; ok=$(kubectl exec edge-cache -n $NS -- sh -c 'wget -qO- --timeout=3 http://catalog-svc 2>/dev/null || curl -s --max-time 3 http://catalog-svc' 2>/dev/null || echo "")
  check_result "tier=cache 파드에서 catalog-svc 응답 (허용 경로)" "$(echo "$ok" | grep -qi nginx && echo 0 || echo 1)" "edge-cache 가 없거나 통신 실패" 4
  # 실제 통신 — 차단 경로 (레이블 없는 임시 파드)
  kubectl delete pod np-probe -n $NS --ignore-not-found &>/dev/null || true
  local blocked; blocked=$(kubectl run np-probe -n $NS --image=busybox:1.36 --restart=Never --rm -i --timeout=60s --command -- wget -qO- --timeout=3 http://catalog-svc 2>/dev/null || echo "")
  kubectl delete pod np-probe -n $NS --ignore-not-found &>/dev/null || true
  local gate=1; kubectl get networkpolicy deny-all -n $NS &>/dev/null && kubectl get svc catalog-svc -n $NS &>/dev/null && gate=0
  check_result "레이블 없는 파드에서는 차단됨 (timeout)" "$([[ $gate == 0 ]] && ! echo "$blocked" | grep -qi nginx && echo 0 || echo 1)" "차단되지 않음 — CNI 또는 정책 확인" 4
}

exam_main "$@"
