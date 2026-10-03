#!/usr/bin/env bash
# CKA 7강 실습 — 스케줄링 (순차 진행형)
set -uo pipefail
source "$(cd "$(dirname "$0")/.." && pwd)/_lib/exam-lib.sh"

EXAM_TITLE="CKA 7강 실습 — 스케줄링 (Requests/Limits · Affinity · Taint · HPA · 자원 배분)"
EXAM_NQ=6

# ── Q6 자원 배분용 ────────────────────────────────────────────
Q6_NS=capacity
Q6_DEP=report-api

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
_q6get() { kubectl -n "$Q6_NS" get deployment "$Q6_DEP" -o jsonpath="$1" 2>/dev/null; }

exam_cleanup() {
  kdel deployment web-logger -n priority
  kdel namespace priority
  kdel priorityclass high-priority-apps
  kdel priorityclass medium-priority
  kdel pod resource-pod ssd-pod gpu-pod -n default
  kdel deployment nginx-hpa -n default
  kdel hpa nginx-hpa -n default
  kubectl label node worker-1 disktype- &>/dev/null || true
  kubectl taint node worker-2 dedicated=gpu:NoSchedule- &>/dev/null || true
  kdel namespace "$Q6_NS" --wait=false
  echo "  resource-pod / ssd-pod / gpu-pod / nginx-hpa / $Q6_NS 네임스페이스 삭제, 노드 레이블·taint 원복"
}
exam_setup() {
  kubectl create namespace priority &>/dev/null
  kubectl create priorityclass medium-priority --value=500 --description="기준값" &>/dev/null
  kubectl -n priority create deployment web-logger --image=nginx:1.24 --replicas=2 &>/dev/null
  echo "  priority 네임스페이스에 web-logger · 기준 PriorityClass medium-priority(500) 준비"
  kubectl label node worker-1 disktype=ssd --overwrite &>/dev/null || true
  kubectl taint node worker-2 dedicated=gpu:NoSchedule --overwrite &>/dev/null || true
  echo "  worker-1 에 disktype=ssd 레이블, worker-2 에 dedicated=gpu:NoSchedule taint 를 걸었다"
  q6_setup
}

# ══════════════════════════════════════════════════════════════
q1_title() { echo "Pod with resource requests and limits"; }
q1_text() { cat <<'EOF'
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
q1_title_ko() { echo "Requests / Limits 가 설정된 파드"; }
q1_text_ko() { cat <<'EOF'
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
q1_grade() {
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
q1_hint() { cat <<'EOF'
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
q2_title() { echo "Place a Pod with node affinity"; }
q2_text() { cat <<'EOF'
The node worker-1 carries the label disktype=ssd.

In the default namespace, create a Pod named ssd-pod (image nginx:1.24)
that is scheduled onto that node using node affinity:

  requiredDuringSchedulingIgnoredDuringExecution
  matchExpressions   key disktype, operator In, values [ssd]

Use nodeAffinity, not nodeSelector and not nodeName.

Verify:
  kubectl get pod ssd-pod -o wide
EOF
}
q2_title_ko() { echo "Node Affinity 로 파드 배치"; }
q2_text_ko() { cat <<'EOF'
worker-1 노드에는 disktype=ssd 레이블이 붙어 있다.

default 네임스페이스에 ssd-pod 파드(nginx:1.24)를 만들되,
Node Affinity 로 그 노드에 배치되게 하시오.

  requiredDuringSchedulingIgnoredDuringExecution
  matchExpressions   key disktype, operator In, values [ssd]

nodeSelector 나 nodeName 이 아니라 nodeAffinity 를 써야 한다.

[확인]
  kubectl get pod ssd-pod -o wide
EOF
}
q2_grade() {
  check "ssd-pod 존재" "kubectl get pod ssd-pod -n default"
  wait_ready "ssd-pod" default
  check_output "Running" "kubectl get pod ssd-pod -n default -o jsonpath='{.status.phase}'" '^Running$'
  check_output "worker-1 에 스케줄됐다" \
    "kubectl get pod ssd-pod -n default -o jsonpath='{.spec.nodeName}'" 'worker-1'
  check_output "nodeAffinity(required) 사용" \
    "kubectl get pod ssd-pod -n default -o jsonpath='{.spec.affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution}'" 'disktype'
  check_output "operator In / values ssd" \
    "kubectl get pod ssd-pod -n default -o jsonpath='{.spec.affinity.nodeAffinity.requiredDuringSchedulingIgnoredDuringExecution.nodeSelectorTerms[0].matchExpressions[0]}'" 'In'
  check_result "nodeName 을 직접 박지 않았다" \
    "$(kubectl get pod ssd-pod -n default -o jsonpath='{.spec.affinity}' 2>/dev/null | grep -q nodeAffinity && echo 0 || echo 1)" \
    "affinity 없이 nodeName/nodeSelector 로 붙이면 오답"
}
q2_hint() { cat <<'EOF'
kubectl explain pod.spec.affinity.nodeAffinity --recursive | head -30

# YAML 뼈대
#   spec:
#     affinity:
#       nodeAffinity:
#         requiredDuringSchedulingIgnoredDuringExecution:
#           nodeSelectorTerms:
#           - matchExpressions:
#             - key: disktype
#               operator: In
#               values: ["ssd"]
EOF
}

# ══════════════════════════════════════════════════════════════
q3_title() { echo "Tolerate a node taint"; }
q3_text() { cat <<'EOF'
The node worker-2 has the taint dedicated=gpu:NoSchedule.

In the default namespace, create a Pod named gpu-pod (image nginx:1.24)
that tolerates that taint and therefore can run on worker-2.

  toleration   key dedicated / operator Equal / value gpu / effect NoSchedule

Verify:
  kubectl get pod gpu-pod -o wide
EOF
}
q3_title_ko() { echo "Taint 를 허용하는 Toleration"; }
q3_text_ko() { cat <<'EOF'
worker-2 노드에는 dedicated=gpu:NoSchedule taint 가 걸려 있다.

default 네임스페이스에 gpu-pod 파드(nginx:1.24)를 만들되,
그 taint 를 허용해서 worker-2 에서 돌 수 있게 하시오.

  toleration   key dedicated / operator Equal / value gpu / effect NoSchedule

[확인]
  kubectl get pod gpu-pod -o wide
EOF
}
q3_grade() {
  check "gpu-pod 존재" "kubectl get pod gpu-pod -n default"
  wait_ready "gpu-pod" default
  check_output "Running" "kubectl get pod gpu-pod -n default -o jsonpath='{.status.phase}'" '^Running$'
  check_output "toleration key=dedicated" \
    "kubectl get pod gpu-pod -n default -o jsonpath='{.spec.tolerations}'" 'dedicated'
  check_output "value=gpu" \
    "kubectl get pod gpu-pod -n default -o jsonpath='{.spec.tolerations}'" 'gpu'
  check_output "effect=NoSchedule" \
    "kubectl get pod gpu-pod -n default -o jsonpath='{.spec.tolerations}'" 'NoSchedule'
}
q3_hint() { cat <<'EOF'
kubectl explain pod.spec.tolerations

#   spec:
#     tolerations:
#     - key: dedicated
#       operator: Equal
#       value: gpu
#       effect: NoSchedule

# 반드시 worker-2 에 떠야 하는 건 아니다 — toleration 은 "허용"일 뿐이다.
# worker-2 에만 두고 싶으면 nodeSelector/affinity 를 함께 쓴다.
EOF
}

# ══════════════════════════════════════════════════════════════
q4_title() { echo "HorizontalPodAutoscaler with a scale-down window"; }
q4_text() { cat <<'EOF'
In the default namespace, create a Deployment named nginx-hpa
(image nginx:1.24, 2 replicas) and an HPA for it.

  HPA name        nginx-hpa
  target          Deployment nginx-hpa
  minReplicas     1
  maxReplicas     4
  metric          average CPU utilization 50%
  scale-down      stabilization window 30 seconds
                  (spec.behavior.scaleDown.stabilizationWindowSeconds)

Verify:
  kubectl get deployment nginx-hpa
  kubectl get hpa nginx-hpa
  kubectl get hpa nginx-hpa -o yaml | grep -A4 behavior
EOF
}
q4_title_ko() { echo "HPA (자동 스케일) + 스케일 다운 안정화"; }
q4_text_ko() { cat <<'EOF'
default 네임스페이스에 nginx-hpa Deployment(nginx:1.24, replicas 2)를
만들고 거기에 HPA 를 붙이시오.

  HPA 이름        nginx-hpa
  대상            Deployment nginx-hpa
  minReplicas     1
  maxReplicas     4
  기준            CPU 평균 사용률 50%
  스케일 다운     안정화 시간 30초
                  (spec.behavior.scaleDown.stabilizationWindowSeconds)

[확인]
  kubectl get deployment nginx-hpa
  kubectl get hpa nginx-hpa
  kubectl get hpa nginx-hpa -o yaml | grep -A4 behavior
EOF
}
q4_grade() {
  local hpa="kubectl get hpa nginx-hpa -n default -o jsonpath"
  check "nginx-hpa Deployment 존재" "kubectl get deployment nginx-hpa -n default"
  check_output "Deployment 파드가 Ready" \
    "kubectl get deployment nginx-hpa -n default -o jsonpath='{.status.readyReplicas}'" '^[1-9]'
  check "HPA nginx-hpa 존재" "kubectl get hpa nginx-hpa -n default"
  check_output "대상이 Deployment nginx-hpa" \
    "$hpa='{.spec.scaleTargetRef.kind}/{.spec.scaleTargetRef.name}'" '^Deployment/nginx-hpa$'
  check_output "minReplicas=1" "$hpa='{.spec.minReplicas}'" '^1$'
  check_output "maxReplicas=4" "$hpa='{.spec.maxReplicas}'" '^4$'
  check_output "CPU 목표 50%" \
    "$hpa='{.spec.metrics[?(@.resource.name==\"cpu\")].resource.target.averageUtilization}'" '^50$'
  check_output "scaleDown stabilizationWindowSeconds=30" \
    "$hpa='{.spec.behavior.scaleDown.stabilizationWindowSeconds}'" '^30$'
}
q4_hint() { cat <<'EOF'
kubectl create deployment nginx-hpa --image=nginx:1.24 --replicas=2
kubectl autoscale deployment nginx-hpa --min=1 --max=4 --cpu-percent=50

# behavior 는 autoscale 명령에 옵션이 없다 → edit 로 spec 아래에 추가
kubectl edit hpa nginx-hpa
#   spec:
#     behavior:                         ← metrics · minReplicas 와 같은 깊이
#       scaleDown:
#         stabilizationWindowSeconds: 30

# 필드 위치가 헷갈리면
kubectl explain hpa.spec.behavior.scaleDown --api-version=autoscaling/v2

# 확인 (metrics-server 가 없으면 TARGETS 가 <unknown> 으로 나오지만 채점에는 문제없다)
kubectl get hpa nginx-hpa -o jsonpath='{.spec.behavior.scaleDown.stabilizationWindowSeconds}{"\n"}'
EOF
}

# ══════════════════════════════════════════════════════════════
q5_title() { echo "PriorityClass and preemption"; }
q5_text() { cat <<'EOF'
A PriorityClass named medium-priority already exists in the cluster.
A Deployment named web-logger runs in the priority namespace.

  1) create a PriorityClass named high-priority-apps
     its value must be LOWER than medium-priority

  2) make the existing Deployment web-logger use it
     (do not delete and recreate the Deployment)

Verify:
  kubectl get priorityclass
  kubectl -n priority get deployment web-logger     -o jsonpath='{.spec.template.spec.priorityClassName}'
EOF
}
q5_title_ko() { echo "PriorityClass 와 우선순위"; }
q5_text_ko() { cat <<'EOF'
클러스터에 medium-priority 라는 PriorityClass 가 이미 있다.
priority 네임스페이스에는 web-logger Deployment 가 돌고 있다.

  1) high-priority-apps 라는 PriorityClass 를 만든다
     값은 medium-priority 보다 **낮아야** 한다

  2) 기존 web-logger Deployment 가 그것을 쓰도록 한다
     (지우고 다시 만들지 않는다)

[확인]
  kubectl get priorityclass
  kubectl -n priority get deployment web-logger     -o jsonpath='{.spec.template.spec.priorityClassName}'
EOF
}
q5_grade() {
  check "PriorityClass high-priority-apps 존재" "kubectl get priorityclass high-priority-apps"
  local hv mv
  hv=$(kubectl get priorityclass high-priority-apps -o jsonpath='{.value}' 2>/dev/null); hv="${hv//[^0-9-]/}"
  mv=$(kubectl get priorityclass medium-priority   -o jsonpath='{.value}' 2>/dev/null); mv="${mv//[^0-9-]/}"
  check_result "medium-priority 보다 값이 낮다" \
    "$([[ -n "$hv" && -n "$mv" && "$hv" -lt "$mv" ]] && echo 0 || echo 1)" \
    "high-priority-apps=${hv:-없음} / medium-priority=${mv:-없음}"
  check_output "web-logger 가 그 클래스를 쓴다" \
    "kubectl -n priority get deployment web-logger -o jsonpath='{.spec.template.spec.priorityClassName}'" '^high-priority-apps$'
  # 지우고 다시 만들지 않았는지 — 재생성했다면 revision 이 1 이다
  local rev; rev=$(kubectl -n priority get deployment web-logger -o jsonpath='{.metadata.annotations.deployment\.kubernetes\.io/revision}' 2>/dev/null)
  rev="${rev//[^0-9]/}"; rev="${rev:-0}"
  check_result "기존 Deployment 를 고쳤다 (지우고 다시 만들지 않음)" \
    "$([[ "$rev" -ge 2 ]] && echo 0 || echo 1)" \
    "revision=${rev} — 새로 만들면 1 이 된다"
  wait_ready "-l app=web-logger" priority
  check_output "파드가 Ready" \
    "kubectl -n priority get deployment web-logger -o jsonpath='{.status.readyReplicas}'" '^2$'
}
q5_hint() { cat <<'EOF'
# 기존 값을 먼저 본다 — "보다 낮게" 가 조건이다
kubectl get priorityclass
#   medium-priority   500

kubectl create priorityclass high-priority-apps --value=100 \
  --description="medium 보다 낮은 우선순위"

# 붙이는 자리가 spec 바로 아래가 아니라 spec.template.spec 이다 (파드 속성이므로)
kubectl -n priority patch deployment web-logger -p \
  '{"spec":{"template":{"spec":{"priorityClassName":"high-priority-apps"}}}}'

# edit 로 해도 된다 — template.spec 아래에 priorityClassName 한 줄
kubectl -n priority edit deployment web-logger
EOF
}

# ══════════════════════════════════════════════════════════════
# Q6 — 자원 부족: 레플리카 3개가 다 뜨도록 노드 자원을 나눠 requests 조정
#   setup 이 워커 allocatable 의 55~60% 를 요청하는 Deployment 를 만든다 → 노드당 1개만 들어가서
#   3개 중 1개 이상이 Pending. 노드 크기를 하드코딩하지 않으려고 setup 시점에 계산한다.
# ══════════════════════════════════════════════════════════════
q6_setup() {
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
metadata: { name: $Q6_NS }
---
apiVersion: apps/v1
kind: Deployment
metadata: { name: $Q6_DEP, namespace: $Q6_NS, labels: { app: $Q6_DEP } }
spec:
  replicas: 3
  selector: { matchLabels: { app: $Q6_DEP } }
  template:
    metadata: { labels: { app: $Q6_DEP } }
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
  echo "  $Q6_NS 네임스페이스에 $Q6_DEP (replicas 3) — 파드당 cpu ${main_c}m/${init_c}m(init) 요청이라 일부가 Pending"
}

q6_title() { echo "Share node resources so every replica runs"; }
q6_text() { cat <<'EOF'
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

The Pods already tolerate the dedicated=gpu taint, so both workers can be used.

Verify:
  kubectl -n capacity get deployment report-api
  kubectl -n capacity get pods -o wide
EOF
}
q6_title_ko() { echo "자원 부족 — 노드 자원을 나눠 레플리카 모두 띄우기"; }
q6_text_ko() { cat <<'EOF'
capacity 네임스페이스의 report-api Deployment 는 레플리카 3개가 돌아야 하는데,
요청한 자원(requests)이 워커 노드에 비해 너무 커서 일부 파드가 Pending 이다.

requests 를 고쳐서 3개가 모두 Running · Ready 가 되게 하시오.

  - 워커 노드에 남아 있는 CPU 와 메모리를 3개 파드에 공평하게 나누되,
    노드가 안정적으로 돌도록 약간의 여유를 남긴다
  - init 컨테이너(warmup)와 메인 컨테이너(api)의 requests 는 정확히 같아야 한다
  - Deployment 를 지우지 않는다. 먼저 0 으로 줄이고, 고친 뒤, 다시 3 으로
    늘려도 된다

파드에는 dedicated=gpu taint 를 견디는 toleration 이 이미 있어서 워커 두 대를 모두 쓸 수 있다.

[확인]
  kubectl -n capacity get deployment report-api
  kubectl -n capacity get pods -o wide
EOF
}
q6_grade() {
  check "Deployment report-api 존재" "kubectl -n $Q6_NS get deployment $Q6_DEP"
  check_output "init 컨테이너 warmup 이 그대로 있다" \
    "kubectl -n $Q6_NS get deployment $Q6_DEP -o jsonpath='{.spec.template.spec.initContainers[*].name}'" '(^| )warmup( |$)'
  wait_ready "-l app=$Q6_DEP" "$Q6_NS"
  check_output "replicas 3 · 전부 새 설정으로 Ready (spec:updated/ready/total)" \
    "kubectl -n $Q6_NS get deployment $Q6_DEP -o jsonpath='{.spec.replicas}:{.status.updatedReplicas}/{.status.readyReplicas}/{.status.replicas}'" '^3:3/3/3$'

  local ic im mc mm
  ic=$(_cpu_m "$(_q6get '{.spec.template.spec.initContainers[0].resources.requests.cpu}')")
  im=$(_mem_mi "$(_q6get '{.spec.template.spec.initContainers[0].resources.requests.memory}')")
  mc=$(_cpu_m "$(_q6get '{.spec.template.spec.containers[0].resources.requests.cpu}')")
  mm=$(_mem_mi "$(_q6get '{.spec.template.spec.containers[0].resources.requests.memory}')")
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
  local rev; rev=$(_q6get '{.metadata.annotations.deployment\.kubernetes\.io/revision}')
  rev="${rev//[^0-9]/}"; rev="${rev:-0}"
  check_result "기존 Deployment 를 고쳤다 (지우고 다시 만들지 않음)" \
    "$([[ "$rev" -ge 2 ]] && echo 0 || echo 1)" \
    "revision=${rev} — 새로 만들면 1 이다"
}
q6_hint() { cat <<'EOF'
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
