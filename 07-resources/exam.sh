#!/usr/bin/env bash
# CKA 7강 실습 — 나눠 쓰고 아껴 쓰기: 네임스페이스와 자원 (순차 진행형)
# 사용법: bash exam.sh start  →  풀고  →  bash exam.sh check  →  ...
set -uo pipefail
source "$(cd "$(dirname "$0")/.." && pwd)/_lib/exam-lib.sh"

EXAM_TITLE="CKA 7강 실습 — 네임스페이스와 자원 (requests/limits · OOM · QoS · LimitRange · ResourceQuota · 자원 배분)"
EXAM_NQ=7

NS=res-lab                       # Q3 · Q4
OUT_DIR=/tmp/07-resources
FINDER_FILE="$WORK_DIR/.q1-finder"

# ── Q7 자원 배분용 ────────────────────────────────────────────
Q7_NS=capacity
Q7_DEP=report-api

# 파일 한 줄을 공백 없이 읽는다 (채점용)
fval() { [[ -f "$1" ]] && tr -d ' \t\r\n' < "$1" || true; }

# 쿠버네티스 수량 → 정수.  _cpu_m 2 → 2000 · 1500m → 1500 · 0.5 → 500
_cpu_m() {
  awk -v x="${1//[[:space:]]/}" 'BEGIN{ if (x=="") { print 0; exit }
    n=x+0; s=x; sub(/^[0-9.]+/,"",s)
    if (s=="m") printf "%d", n; else printf "%d", n*1000 }'
}
# 메모리 → Mi.  _mem_mi 2014036Ki → 1966 · 1Gi → 1024 · 500M → 476 · 바이트 → Mi
_mem_mi() {
  awk -v x="${1//[[:space:]]/}" 'BEGIN{ if (x=="") { print 0; exit }
    n=x+0; s=x; sub(/^[0-9.]+/,"",s); f=1/1048576
    if (s=="Ki") f=1/1024; else if (s=="Mi") f=1; else if (s=="Gi") f=1024; else if (s=="Ti") f=1048576
    else if (s=="k") f=1000/1048576; else if (s=="M") f=1000000/1048576; else if (s=="G") f=1000000000/1048576
    printf "%d", n*f }'
}
_q7get() { kubectl -n "$Q7_NS" get deployment "$Q7_DEP" -o jsonpath="$1" 2>/dev/null; }

exam_cleanup() {
  kdel namespace team-a team-b team-c --wait=false        # Q1
  kdel deployment hello -n default
  kdel pod resource-pod -n default                        # Q2
  kdel namespace "$NS" --wait=false                       # Q3 · Q4
  kdel namespace "$Q7_NS" --wait=false                    # Q7
  kdel namespace dev quota-lab --wait=false               # Q5 · Q6
  rm -rf "$OUT_DIR" "$FINDER_FILE"
  echo "  team-a/b/c · $NS · $Q7_NS · dev · quota-lab 네임스페이스 · resource-pod · $OUT_DIR 삭제"
}
exam_setup() {
  mkdir -p "$OUT_DIR"

  # Q1 — 같은 이름 web 이 두 칸에 산다. finder 는 둘 중 한 칸에만 (매번 바뀐다)
  local where; where=$( (( RANDOM % 2 )) && echo team-a || echo team-b )
  echo "$where" > "$FINDER_FILE"
  kubectl create namespace team-a &>/dev/null
  kubectl create namespace team-b &>/dev/null
  kubectl -n team-a run web --image=nginx:1.27 &>/dev/null
  kubectl -n team-b run web --image=nginx:1.27 &>/dev/null
  cat <<YAML | kubectl apply -f - &>/dev/null
apiVersion: v1
kind: Pod
metadata: { name: finder, namespace: $where }
spec:
  terminationGracePeriodSeconds: 1
  containers:
    - { name: finder, image: busybox:1.36, command: ["sh", "-c", "sleep 36000"] }
YAML
  echo "  team-a · team-b 에 web 파드, 둘 중 한 곳에 finder 파드 (Q1)"

  # Q3 — 메모리를 120MB 채우는 컨테이너에 limit 64Mi → OOMKilled 반복
  #   셸 변수에 담아 두므로 채운 뒤에도 메모리를 계속 잡고 있다
  kubectl create namespace "$NS" &>/dev/null
  cat <<YAML | kubectl apply -f - &>/dev/null
apiVersion: apps/v1
kind: Deployment
metadata: { name: cruncher, namespace: $NS, labels: { app: cruncher } }
spec:
  replicas: 1
  selector: { matchLabels: { app: cruncher } }
  template:
    metadata: { labels: { app: cruncher } }
    spec:
      terminationGracePeriodSeconds: 1
      containers:
        - name: cruncher
          image: busybox:1.36
          command: ["sh", "-c", "x=\$(head -c 120000000 /dev/zero | tr '\\\\0' a); echo cache filled; sleep 36000"]
          resources:
            requests: { memory: 32Mi }
            limits:   { memory: 64Mi }
---
apiVersion: v1
kind: Pod
metadata: { name: mystery, namespace: $NS }
spec:
  containers:
    - name: app
      image: nginx:1.27
      resources:
        requests: { cpu: 50m }
YAML
  echo "  $NS 에 cruncher(메모리 limit 64Mi — OOM 반복) · mystery 파드 (Q3 · Q4)"


  # Q5 — 빈 dev 칸
  kubectl create namespace dev &>/dev/null
  echo "  dev 네임스페이스 준비 (Q5)"

  # Q6 — 쿼터 600m 에 250m × 3 을 요청 → 2개만 생긴다
  kubectl create namespace quota-lab &>/dev/null
  cat <<'YAML' | kubectl apply -f - &>/dev/null
apiVersion: v1
kind: ResourceQuota
metadata: { name: team-quota, namespace: quota-lab }
spec:
  hard:
    pods: "10"
    requests.cpu: 600m
    requests.memory: 1Gi
YAML
  cat <<'YAML' | kubectl apply -f - &>/dev/null
apiVersion: apps/v1
kind: Deployment
metadata: { name: api, namespace: quota-lab, labels: { app: api } }
spec:
  replicas: 3
  selector: { matchLabels: { app: api } }
  template:
    metadata: { labels: { app: api } }
    spec:
      containers:
        - name: api
          image: nginx:1.27
          resources:
            requests: { cpu: 250m, memory: 64Mi }
YAML
  echo "  quota-lab 에 team-quota(requests.cpu 600m) · api(250m × 3) 배치 (Q6)"
}

# ══════════════════════════════════════════════════════════════
# Q1 — 네임스페이스: 찾기 · 만들기 · 그 안에 만들기
# ══════════════════════════════════════════════════════════════
q1_title() { echo "Namespaces: find, create, deploy into"; }
q1_text() { cat <<'EOF'
  (a) A Pod named finder runs in exactly one namespace of the cluster.
      Save the name of that namespace to /tmp/07-resources/finder-ns.txt
  (b) Create a namespace named team-c and, inside it, a Deployment named
      hello (image nginx:1.27, 2 replicas). Both Pods must be Ready.
      Nothing named hello may be created in the default namespace.

Verify:
  cat /tmp/07-resources/finder-ns.txt
  kubectl -n team-c get deploy hello
EOF
}
q1_title_ko() { echo "네임스페이스 — 찾기 · 만들기 · 그 안에 만들기"; }
q1_text_ko() { cat <<'EOF'
  (a) finder 파드가 클러스터의 네임스페이스 하나에 떠 있다.
      그 네임스페이스 이름을 /tmp/07-resources/finder-ns.txt 에 저장하시오.
  (b) team-c 네임스페이스를 만들고, 그 안에 hello Deployment
      (이미지 nginx:1.27, replicas 2) 를 만드시오. 파드 2개가 Ready 여야 한다.
      default 네임스페이스에 hello 가 만들어지면 안 된다.

[확인]
  cat /tmp/07-resources/finder-ns.txt
  kubectl -n team-c get deploy hello
EOF
}
q1_grade() {
  local want; want=$(cat "$FINDER_FILE" 2>/dev/null)
  check_result "(a) finder-ns.txt = finder 가 있는 네임스페이스" \
    "$([[ -n "$want" && "$(fval $OUT_DIR/finder-ns.txt)" == "$want" ]] && echo 0 || echo 1)" \
    "파일: '$(fval $OUT_DIR/finder-ns.txt)'"
  check "(b) team-c 네임스페이스 존재" "kubectl get namespace team-c"
  check_output "(b) team-c 의 hello 가 nginx:1.27 · replicas 2" \
    "kubectl -n team-c get deployment hello -o jsonpath='{.spec.template.spec.containers[0].image}/{.spec.replicas}'" '^nginx:1\.27/2$'
  wait_ready "-l app=hello" team-c
  check_output "(b) Ready 파드 2개" \
    "kubectl -n team-c get deployment hello -o jsonpath='{.status.readyReplicas}'" '^2$'
  check_result "(b) default 에 hello 가 없다 (-n 을 빠뜨리지 않았다)" \
    "$([[ -z "$(kubectl -n default get deployment hello -o name 2>/dev/null)" ]] && echo 0 || echo 1)" \
    "default 에 hello 가 있다 — 지우고 team-c 에 만든다"
}
q1_hint() { cat <<'EOF'
kubectl get pods -A | grep finder                      # 첫 칸이 NAMESPACE
kubectl get pods -A --field-selector metadata.name=finder \
  -o jsonpath='{.items[0].metadata.namespace}' > /tmp/07-resources/finder-ns.txt

kubectl create namespace team-c
kubectl -n team-c create deployment hello --image=nginx:1.27 --replicas=2
EOF
}


# ══════════════════════════════════════════════════════════════
q2_title() { echo "Pod with resource requests and limits"; }
q2_text() { cat <<'EOF'
In the default namespace, create a Pod named resource-pod using image
nginx:1.24 with the following resources on its container:

  requests    cpu 100m, memory 128Mi
  limits      cpu 200m, memory 256Mi

The Pod must be Running.

Verify:
  kubectl get pod resource-pod
  kubectl get pod resource-pod -o jsonpath='{.spec.containers[0].resources}'
EOF
}
q2_title_ko() { echo "Requests / Limits 가 설정된 파드"; }
q2_text_ko() { cat <<'EOF'
default 네임스페이스에 resource-pod 파드를 nginx:1.24 이미지로 만들되
컨테이너에 다음 자원 설정을 넣으시오.

  requests    cpu 100m, memory 128Mi
  limits      cpu 200m, memory 256Mi

파드는 Running 이어야 한다.

[확인]
  kubectl get pod resource-pod
  kubectl get pod resource-pod -o jsonpath='{.spec.containers[0].resources}'
EOF
}
q2_grade() {
  check "resource-pod 존재" "kubectl get pod resource-pod -n default"
  wait_ready "resource-pod" default
  check_output "Running" "kubectl get pod resource-pod -n default -o jsonpath='{.status.phase}'" '^Running$'
  check_output "requests.cpu=100m" \
    "kubectl get pod resource-pod -n default -o jsonpath='{.spec.containers[0].resources.requests.cpu}'" '^100m$'
  check_output "requests.memory=128Mi" \
    "kubectl get pod resource-pod -n default -o jsonpath='{.spec.containers[0].resources.requests.memory}'" '^128Mi$'
  check_output "limits.cpu=200m" \
    "kubectl get pod resource-pod -n default -o jsonpath='{.spec.containers[0].resources.limits.cpu}'" '^200m$'
  check_output "limits.memory=256Mi" \
    "kubectl get pod resource-pod -n default -o jsonpath='{.spec.containers[0].resources.limits.memory}'" '^256Mi$'
}
q2_hint() { cat <<'EOF'
kubectl run resource-pod --image=nginx:1.24 $do > pod.yaml
#   spec.containers[0] 아래에:
#   resources:
#     requests: { cpu: 100m, memory: 128Mi }
#     limits:   { cpu: 200m, memory: 256Mi }
kubectl apply -f pod.yaml

# 필드가 헷갈리면
kubectl explain pod.spec.containers.resources
EOF
}

# ══════════════════════════════════════════════════════════════
# Q3 — 메모리 limit 을 넘기면 죽는다 (OOMKilled)
# ══════════════════════════════════════════════════════════════
q3_title() { echo "A container killed for exceeding its memory limit"; }
q3_text() { cat <<'EOF'
The Deployment cruncher in the namespace res-lab keeps restarting.

  (a) Find the reason its container was last terminated and save that
      reason (one word, as Kubernetes shows it) to
      /tmp/07-resources/cruncher-reason.txt
  (b) Change ONLY the memory limit of the container to 512Mi
      (keep the memory request as it is) so that the Pod keeps running.

Verify:
  kubectl -n res-lab get pods -l app=cruncher
  kubectl -n res-lab describe pod -l app=cruncher | grep -A3 'Last State'
EOF
}
q3_title_ko() { echo "메모리 limit 을 넘기면 — OOMKilled"; }
q3_text_ko() { cat <<'EOF'
res-lab 네임스페이스의 cruncher Deployment 가 계속 재시작한다.

  (a) 컨테이너가 마지막으로 종료된 이유를 찾아, 쿠버네티스가 보여 주는
      한 단어 그대로 /tmp/07-resources/cruncher-reason.txt 에 저장하시오.
  (b) 컨테이너의 메모리 limit 만 512Mi 로 바꿔서 (메모리 request 는
      그대로) 파드가 계속 돌게 하시오.

[확인]
  kubectl -n res-lab get pods -l app=cruncher
  kubectl -n res-lab describe pod -l app=cruncher | grep -A3 'Last State'
EOF
}
q3_grade() {
  check_result "(a) cruncher-reason.txt = OOMKilled" \
    "$([[ "$(fval $OUT_DIR/cruncher-reason.txt)" == "OOMKilled" ]] && echo 0 || echo 1)" \
    "파일: '$(fval $OUT_DIR/cruncher-reason.txt)'"
  check_output "(b) limits.memory = 512Mi" \
    "kubectl -n $NS get deployment cruncher -o jsonpath='{.spec.template.spec.containers[0].resources.limits.memory}'" '^512Mi$'
  check_output "(b) requests.memory 는 그대로 32Mi" \
    "kubectl -n $NS get deployment cruncher -o jsonpath='{.spec.template.spec.containers[0].resources.requests.memory}'" '^32Mi$'
  wait_ready "-l app=cruncher" "$NS"
  check_output "(b) 새 설정의 파드 1개가 Ready" \
    "kubectl -n $NS get deployment cruncher -o jsonpath='{.status.updatedReplicas}/{.status.readyReplicas}'" '^1/1$'
  check_output "(b) 지금 파드는 재시작 0 (메모리를 다 채우고도 살아 있다)" \
    "kubectl -n $NS get pods -l app=cruncher --field-selector=status.phase=Running -o jsonpath='{.items[*].status.containerStatuses[0].restartCount}'" '^0$'
}
q3_hint() { cat <<'EOF'
kubectl -n res-lab get pods -l app=cruncher            # OOMKilled / CrashLoopBackOff
kubectl -n res-lab describe pod -l app=cruncher | grep -A3 'Last State'
kubectl -n res-lab get pod -l app=cruncher \
  -o jsonpath='{.items[0].status.containerStatuses[0].lastState.terminated.reason}' \
  > /tmp/07-resources/cruncher-reason.txt

kubectl -n res-lab edit deployment cruncher
#   resources.limits.memory: 64Mi → 512Mi   (requests 는 손대지 않는다)
# 또는
kubectl -n res-lab set resources deployment cruncher --limits=memory=512Mi
EOF
}

# ══════════════════════════════════════════════════════════════
# Q4 — QoS 등급
# ══════════════════════════════════════════════════════════════
q4_title() { echo "QoS classes"; }
q4_text() { cat <<'EOF'
Work in the namespace res-lab.

  (a) Save the QoS class of the existing Pod mystery to
      /tmp/07-resources/mystery-qos.txt
  (b) Create a Pod named gold (image nginx:1.27) whose QoS class is
      Guaranteed, using cpu 100m and memory 64Mi.
      The Pod must be Running.

Verify:
  kubectl -n res-lab get pod mystery gold -o custom-columns=NAME:.metadata.name,QOS:.status.qosClass
EOF
}
q4_title_ko() { echo "QoS 등급 — 읽기와 만들기"; }
q4_text_ko() { cat <<'EOF'
res-lab 네임스페이스에서 작업한다.

  (a) 이미 있는 mystery 파드의 QoS 등급을
      /tmp/07-resources/mystery-qos.txt 에 저장하시오.
  (b) QoS 등급이 Guaranteed 인 gold 파드(이미지 nginx:1.27)를 만드시오.
      cpu 100m, memory 64Mi 를 쓴다. 파드는 Running 이어야 한다.

[확인]
  kubectl -n res-lab get pod mystery gold -o custom-columns=NAME:.metadata.name,QOS:.status.qosClass
EOF
}
q4_grade() {
  local want; want=$(kubectl -n $NS get pod mystery -o jsonpath='{.status.qosClass}' 2>/dev/null)
  check_result "(a) mystery-qos.txt = mystery 의 QoS 등급" \
    "$([[ -n "$want" && "$(fval $OUT_DIR/mystery-qos.txt)" == "$want" ]] && echo 0 || echo 1)" \
    "파일: '$(fval $OUT_DIR/mystery-qos.txt)'"
  check "(b) gold 파드 존재" "kubectl -n $NS get pod gold"
  check_output "(b) QoS 등급 Guaranteed" \
    "kubectl -n $NS get pod gold -o jsonpath='{.status.qosClass}'" '^Guaranteed$'
  check_output "(b) cpu 100m · memory 64Mi (requests = limits)" \
    "kubectl -n $NS get pod gold -o jsonpath='{.spec.containers[0].resources.requests.cpu}/{.spec.containers[0].resources.requests.memory}/{.spec.containers[0].resources.limits.cpu}/{.spec.containers[0].resources.limits.memory}'" '^100m/64Mi/100m/64Mi$'
  wait_ready gold "$NS"
  check_output "(b) Running" \
    "kubectl -n $NS get pod gold -o jsonpath='{.status.phase}'" '^Running$'
}
q4_hint() { cat <<'EOF'
kubectl -n res-lab get pod mystery -o jsonpath='{.status.qosClass}' > /tmp/07-resources/mystery-qos.txt
kubectl -n res-lab get pod mystery -o jsonpath='{.spec.containers[0].resources}'   # 무엇을 적었나

# Guaranteed = 모든 컨테이너의 cpu · memory 에 requests 와 limits 를 같게
kubectl -n res-lab run gold --image=nginx:1.27 $do > gold.yaml
#   resources:
#     requests: { cpu: 100m, memory: 64Mi }
#     limits:   { cpu: 100m, memory: 64Mi }
kubectl apply -f gold.yaml
EOF
}

# ══════════════════════════════════════════════════════════════
# Q5 — LimitRange: 하나당 기본값과 최대값
# ══════════════════════════════════════════════════════════════
q5_title() { echo "LimitRange — per-container defaults and maximum"; }
q5_text() { cat <<'EOF'
In the namespace dev, create a LimitRange named dev-defaults that applies
to containers:

  default request   cpu 100m, memory 64Mi
  default limit     cpu 200m, memory 128Mi
  max               cpu 500m, memory 256Mi

Then create a Pod named plain in dev (image nginx:1.27) WITHOUT any
resources section, and check that the defaults were filled in.

Verify:
  kubectl -n dev describe limitrange dev-defaults
  kubectl -n dev get pod plain -o jsonpath='{.spec.containers[0].resources}'
EOF
}
q5_title_ko() { echo "LimitRange — 하나당 기본값과 최대값"; }
q5_text_ko() { cat <<'EOF'
dev 네임스페이스에 컨테이너에 적용되는 LimitRange dev-defaults 를 만드시오.

  기본 request   cpu 100m, memory 64Mi
  기본 limit     cpu 200m, memory 128Mi
  최대           cpu 500m, memory 256Mi

그다음 resources 를 적지 않은 plain 파드(이미지 nginx:1.27)를 dev 에 만들어
기본값이 채워졌는지 확인하시오.

[확인]
  kubectl -n dev describe limitrange dev-defaults
  kubectl -n dev get pod plain -o jsonpath='{.spec.containers[0].resources}'
EOF
}
q5_grade() {
  check "dev-defaults LimitRange 존재" "kubectl -n dev get limitrange dev-defaults"
  check_output "기본 request cpu 100m · memory 64Mi" "kubectl -n dev get limitrange dev-defaults -o jsonpath='{.spec.limits[?(@.type==\"Container\")].defaultRequest.cpu}/{.spec.limits[?(@.type==\"Container\")].defaultRequest.memory}'" '^100m/64Mi$'
  check_output "기본 limit cpu 200m · memory 128Mi" "kubectl -n dev get limitrange dev-defaults -o jsonpath='{.spec.limits[?(@.type==\"Container\")].default.cpu}/{.spec.limits[?(@.type==\"Container\")].default.memory}'" '^200m/128Mi$'
  check_output "최대 cpu 500m · memory 256Mi" "kubectl -n dev get limitrange dev-defaults -o jsonpath='{.spec.limits[?(@.type==\"Container\")].max.cpu}/{.spec.limits[?(@.type==\"Container\")].max.memory}'" '^500m/256Mi$'
  check "plain 파드 존재" "kubectl -n dev get pod plain"
  check_output "plain 에 기본값이 채워졌다 (req 100m/64Mi · lim 200m/128Mi)" \
    "kubectl -n dev get pod plain -o jsonpath='{.spec.containers[0].resources.requests.cpu}/{.spec.containers[0].resources.requests.memory}/{.spec.containers[0].resources.limits.cpu}/{.spec.containers[0].resources.limits.memory}'" '^100m/64Mi/200m/128Mi$'
  # 최대값을 넘는 파드는 API 서버가 거부해야 한다 — 서버 dry-run 으로 실제 검사만 해 본다
  check "최대값을 넘는 파드(cpu limit 1)는 거부된다" \
    "! printf '%s\n' 'apiVersion: v1' 'kind: Pod' 'metadata: {name: too-big, namespace: dev}' 'spec:' '  containers:' '  - name: c' '    image: nginx:1.27' '    resources: {limits: {cpu: \"1\"}}' | kubectl apply --dry-run=server -f -"
}
q5_hint() { cat <<'EOF'
cat > lr.yaml <<'YAML'
apiVersion: v1
kind: LimitRange
metadata:
  name: dev-defaults
  namespace: dev
spec:
  limits:
  - type: Container
    defaultRequest: { cpu: 100m, memory: 64Mi }
    default:        { cpu: 200m, memory: 128Mi }   # limit 의 기본값
    max:            { cpu: 500m, memory: 256Mi }
YAML
kubectl apply -f lr.yaml

# LimitRange 는 만들어질 때 검사한다 — 먼저 만들고 파드는 그 뒤에
kubectl -n dev run plain --image=nginx:1.27
kubectl -n dev get pod plain -o jsonpath='{.spec.containers[0].resources}'
EOF
}

# ══════════════════════════════════════════════════════════════
# Q6 — ResourceQuota: 쿼터에 막혀 일부만 뜬다
# ══════════════════════════════════════════════════════════════
q6_title() { echo "ResourceQuota blocks part of a Deployment"; }
q6_text() { cat <<'EOF'
The Deployment api in the namespace quota-lab wants 3 replicas, but only
some of its Pods were created.

  (a) Find which object prevents the remaining Pods from being created and
      save its name to /tmp/07-resources/blocker.txt
  (b) Without changing that object and without deleting the Deployment,
      set the cpu request of the api container to 150m so that all
      3 replicas run. (Hint: the rollout itself also needs room.)

Verify:
  kubectl -n quota-lab describe resourcequota
  kubectl -n quota-lab get deploy api
EOF
}
q6_title_ko() { echo "ResourceQuota — 쿼터에 막혀 일부만 뜬다"; }
q6_text_ko() { cat <<'EOF'
quota-lab 네임스페이스의 api Deployment 는 레플리카 3개를 원하는데
파드가 일부만 만들어졌다.

  (a) 나머지 파드가 만들어지지 못하게 막는 오브젝트를 찾아
      그 이름을 /tmp/07-resources/blocker.txt 에 저장하시오.
  (b) 그 오브젝트는 바꾸지 말고, Deployment 도 지우지 말고,
      api 컨테이너의 cpu request 를 150m 로 바꿔 3개가 모두 뜨게 하시오.
      (힌트: 롤아웃 자체에도 자리가 필요하다)

[확인]
  kubectl -n quota-lab describe resourcequota
  kubectl -n quota-lab get deploy api
EOF
}
q6_grade() {
  check_result "(a) blocker.txt = team-quota" \
    "$([[ "$(fval $OUT_DIR/blocker.txt)" == "team-quota" ]] && echo 0 || echo 1)" \
    "파일: '$(fval $OUT_DIR/blocker.txt)'"
  check_output "(b) 쿼터는 그대로 (requests.cpu 600m)" \
    "kubectl -n quota-lab get resourcequota team-quota -o jsonpath='{.spec.hard.requests\.cpu}'" '^600m$'
  check_output "(b) api 의 cpu request 150m" \
    "kubectl -n quota-lab get deployment api -o jsonpath='{.spec.template.spec.containers[0].resources.requests.cpu}'" '^150m$'
  wait_ready "-l app=api" quota-lab
  check_output "(b) replicas 3 · 전부 새 설정으로 Ready (spec:updated/ready)" \
    "kubectl -n quota-lab get deployment api -o jsonpath='{.spec.replicas}:{.status.updatedReplicas}/{.status.readyReplicas}'" '^3:3/3$'
  local rev; rev=$(kubectl -n quota-lab get deployment api -o jsonpath='{.metadata.annotations.deployment\.kubernetes\.io/revision}' 2>/dev/null)
  rev="${rev//[^0-9]/}"; rev="${rev:-0}"
  check_result "(b) 기존 Deployment 를 고쳤다 (revision ${rev} ≥ 2)" \
    "$([[ "$rev" -ge 2 ]] && echo 0 || echo 1)" "지우고 새로 만들면 revision 이 1 이다"
}
q6_hint() { cat <<'EOF'
kubectl -n quota-lab get deploy,rs,pods
kubectl -n quota-lab describe rs -l app=api | tail -5      # exceeded quota: team-quota ...
kubectl -n quota-lab describe resourcequota                 # Used / Hard
echo team-quota > /tmp/07-resources/blocker.txt

# 600m 중 250m × 2 = 500m 를 이미 쓰고 있다 → 새 파드(150m)를 하나 더 만들 자리도 없다
#   그래서 롤아웃이 멈춘다 → 비우고, 고치고, 늘린다
kubectl -n quota-lab scale deployment api --replicas=0
kubectl -n quota-lab set resources deployment api -c api --requests=cpu=150m
kubectl -n quota-lab scale deployment api --replicas=3
kubectl -n quota-lab get deploy api                         # 3/3 (150m × 3 = 450m)
EOF
}

# ══════════════════════════════════════════════════════════════
# Q7 — 자원 부족: 레플리카 3개가 다 뜨도록 노드 자원을 나눠 requests 조정
#   이 문제에 들어갈 때(q7_enter) 워커 allocatable 의 55~60% 를 요청하는 Deployment 를 만든다 → 노드당 1개만 들어가서
#   3개 중 1개 이상이 Pending. 노드 크기를 하드코딩하지 않으려고 그때 계산한다.
# ══════════════════════════════════════════════════════════════
q7_enter() {
  local nodes c m max_c=0 max_m=0
  local jp='{range .items[*]}{.status.allocatable.cpu} {.status.allocatable.memory}{"\n"}{end}'
  nodes=$(kubectl get nodes -l '!node-role.kubernetes.io/control-plane' -o jsonpath="$jp" 2>/dev/null)
  [[ -z "${nodes//[[:space:]]/}" ]] && nodes=$(kubectl get nodes -o jsonpath="$jp" 2>/dev/null)
  while read -r c m; do
    [[ -z "$c" ]] && continue
    c=$(_cpu_m "$c"); m=$(_mem_mi "$m")
    (( c > max_c )) && max_c=$c
    (( m > max_m )) && max_m=$m
  done <<< "$nodes"
  (( max_c > 0 )) || max_c=2000
  (( max_m > 0 )) || max_m=1900
  # 가장 큰 워커에서도 한 노드에 하나만 들어가는 크기 (50% 초과)
  local main_c=$(( max_c * 55 / 100 )) main_m=$(( max_m * 55 / 100 ))
  local init_c=$(( max_c * 60 / 100 )) init_m=$(( max_m * 60 / 100 ))

  cat <<YAML | kubectl apply -f - &>/dev/null
apiVersion: v1
kind: Namespace
metadata: { name: $Q7_NS }
---
apiVersion: apps/v1
kind: Deployment
metadata: { name: $Q7_DEP, namespace: $Q7_NS, labels: { app: $Q7_DEP } }
spec:
  replicas: 3
  selector: { matchLabels: { app: $Q7_DEP } }
  template:
    metadata: { labels: { app: $Q7_DEP } }
    spec:
      tolerations:
      - { key: dedicated, operator: Exists, effect: NoSchedule }
      initContainers:
      - name: warmup
        image: busybox:1.36
        command: ["sh", "-c", "echo warming cache; sleep 3"]
        resources:
          requests: { cpu: ${init_c}m, memory: ${init_m}Mi }
      containers:
      - name: api
        image: nginx:1.24
        resources:
          requests: { cpu: ${main_c}m, memory: ${main_m}Mi }
YAML
  echo "  $Q7_NS 네임스페이스에 $Q7_DEP (replicas 3) — 파드당 cpu ${main_c}m/${init_c}m(init) 요청이라 일부가 Pending"
}

q7_title() { echo "Share node resources so every replica runs"; }
q7_text() { cat <<'EOF'
The Deployment report-api in the capacity namespace should run 3 replicas,
but some of its Pods stay Pending: their resource requests are too large
for the worker nodes.

Adjust the resource requests so that all 3 replicas are Running and Ready:

  - divide the CPU and memory still available on the worker nodes fairly
    among the 3 Pods, and leave some headroom so the nodes stay stable
  - the init container (warmup) and the main container (api) must use
    exactly the same requests
  - do not delete the Deployment. You may scale it down to 0 first,
    update it, and then scale it back to 3

Verify:
  kubectl -n capacity get deployment report-api
  kubectl -n capacity get pods -o wide
EOF
}
q7_title_ko() { echo "자원 부족 — 노드 자원을 나눠 레플리카 모두 띄우기"; }
q7_text_ko() { cat <<'EOF'
capacity 네임스페이스의 report-api Deployment 는 레플리카 3개가 돌아야 하는데,
요청한 자원(requests)이 워커 노드에 비해 너무 커서 일부 파드가 Pending 이다.

requests 를 고쳐서 3개가 모두 Running · Ready 가 되게 하시오.

  - 워커 노드에 남아 있는 CPU 와 메모리를 3개 파드에 공평하게 나누되,
    노드가 안정적으로 돌도록 약간의 여유를 남긴다
  - init 컨테이너(warmup)와 메인 컨테이너(api)의 requests 는 정확히 같아야 한다
  - Deployment 를 지우지 않는다. 먼저 0 으로 줄이고, 고친 뒤, 다시 3 으로
    늘려도 된다

[확인]
  kubectl -n capacity get deployment report-api
  kubectl -n capacity get pods -o wide
EOF
}
q7_grade() {
  check "Deployment report-api 존재" "kubectl -n $Q7_NS get deployment $Q7_DEP"
  check_output "init 컨테이너 warmup 이 그대로 있다" \
    "kubectl -n $Q7_NS get deployment $Q7_DEP -o jsonpath='{.spec.template.spec.initContainers[*].name}'" '(^| )warmup( |$)'
  wait_ready "-l app=$Q7_DEP" "$Q7_NS"
  check_output "replicas 3 · 전부 새 설정으로 Ready (spec:updated/ready/total)" \
    "kubectl -n $Q7_NS get deployment $Q7_DEP -o jsonpath='{.spec.replicas}:{.status.updatedReplicas}/{.status.readyReplicas}/{.status.replicas}'" '^3:3/3/3$'

  local ic im mc mm
  ic=$(_cpu_m "$(_q7get '{.spec.template.spec.initContainers[0].resources.requests.cpu}')")
  im=$(_mem_mi "$(_q7get '{.spec.template.spec.initContainers[0].resources.requests.memory}')")
  mc=$(_cpu_m "$(_q7get '{.spec.template.spec.containers[0].resources.requests.cpu}')")
  mm=$(_mem_mi "$(_q7get '{.spec.template.spec.containers[0].resources.requests.memory}')")
  ic="${ic//[^0-9]/}"; im="${im//[^0-9]/}"; mc="${mc//[^0-9]/}"; mm="${mm//[^0-9]/}"
  ic="${ic:-0}"; im="${im:-0}"; mc="${mc:-0}"; mm="${mm:-0}"
  check_result "init 과 main 의 cpu requests 가 같다" \
    "$([[ "$mc" -gt 0 && "$ic" == "$mc" ]] && echo 0 || echo 1)" \
    "init=${ic}m / main=${mc}m"
  check_result "init 과 main 의 memory requests 가 같다" \
    "$([[ "$mm" -gt 0 && "$im" == "$mm" ]] && echo 0 || echo 1)" \
    "init=${im}Mi / main=${mm}Mi"
  check_result "requests 가 지나치게 작지 않다 (cpu ≥ 100m · memory ≥ 64Mi)" \
    "$([[ "$mc" -ge 100 && "$mm" -ge 64 ]] && echo 0 || echo 1)" \
    "main cpu=${mc}m / memory=${mm}Mi — 공평하게 나눈 몫이어야 한다"

  # 지우고 다시 만들지 않았는지 — 템플릿을 고치면 revision 이 2 이상이 된다
  local rev; rev=$(_q7get '{.metadata.annotations.deployment\.kubernetes\.io/revision}')
  rev="${rev//[^0-9]/}"; rev="${rev:-0}"
  check_result "기존 Deployment 를 고쳤다 (지우고 다시 만들지 않음)" \
    "$([[ "$rev" -ge 2 ]] && echo 0 || echo 1)" \
    "revision=${rev} — 새로 만들면 1 이다"
}
q7_hint() { cat <<'EOF'
# 1) 무엇이 모자란지
kubectl -n capacity get pods -o wide                       # Pending 파드 찾기
kubectl -n capacity describe pod <Pending 파드> | tail -3   # Insufficient cpu / memory

# 2) 먼저 0 으로 줄여서 report-api 가 잡고 있던 몫을 돌려받는다
kubectl -n capacity scale deployment report-api --replicas=0

# 3) 워커마다 남은 양 = Allocatable - Allocated(Requests)
kubectl describe node <워커> | grep -A6 '^Allocatable'
kubectl describe node <워커> | grep -A8 'Allocated resources'
#   파드 3개를 워커 2대에 → 한 노드에 2개가 간다
#   파드당 = (남은 양이 적은 워커의 여유 / 2) 에서 10~20% 를 뺀 값
#   예) 남은 cpu 1600m, memory 1500Mi → 파드당 약 650m / 600Mi

# 4) init 컨테이너와 메인 컨테이너에 같은 값을 넣는다
kubectl -n capacity edit deployment report-api
#   spec.template.spec.initContainers[0].resources.requests
#   spec.template.spec.containers[0].resources.requests

# 5) 다시 3 으로
kubectl -n capacity scale deployment report-api --replicas=3
kubectl -n capacity get deployment report-api               # READY 3/3

# 파드의 실제 요청량 = max( init 컨테이너 중 최댓값 , 메인 컨테이너 합 )
#   init 만 큰 값으로 남겨 두면 메인을 줄여도 여전히 Pending 이다
EOF
}

exam_main "$@"
