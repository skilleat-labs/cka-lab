#!/usr/bin/env bash
# CKA 11강 실습 — 스케줄링 (순차 진행형)
set -uo pipefail
source "$(cd "$(dirname "$0")/.." && pwd)/_lib/exam-lib.sh"

EXAM_TITLE="CKA 11강 실습 — 스케줄링 (Affinity · Taint · HPA · PriorityClass)"
EXAM_NQ=4

exam_cleanup() {
  kdel deployment web-logger -n priority
  kdel namespace priority
  kdel priorityclass high-priority-apps
  kdel priorityclass medium-priority
  kdel pod ssd-pod gpu-pod -n default
  kdel deployment nginx-hpa -n default
  kdel hpa nginx-hpa -n default
  kubectl label node worker-1 disktype- &>/dev/null || true
  kubectl taint node worker-2 dedicated=gpu:NoSchedule- &>/dev/null || true
  echo "  ssd-pod / gpu-pod / nginx-hpa 삭제, 노드 레이블·taint 원복"
}
exam_setup() {
  kubectl create namespace priority &>/dev/null
  kubectl create priorityclass medium-priority --value=500 --description="기준값" &>/dev/null
  kubectl -n priority create deployment web-logger --image=nginx:1.24 --replicas=2 &>/dev/null
  echo "  priority 네임스페이스에 web-logger · 기준 PriorityClass medium-priority(500) 준비"
  kubectl label node worker-1 disktype=ssd --overwrite &>/dev/null || true
  kubectl taint node worker-2 dedicated=gpu:NoSchedule --overwrite &>/dev/null || true
  echo "  worker-1 에 disktype=ssd 레이블, worker-2 에 dedicated=gpu:NoSchedule taint 를 걸었다"
}


# ══════════════════════════════════════════════════════════════
q1_title() { echo "Place a Pod with node affinity"; }
q1_text() { cat <<'EOF'
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
q1_title_ko() { echo "Node Affinity 로 파드 배치"; }
q1_text_ko() { cat <<'EOF'
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
q1_grade() {
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
q1_hint() { cat <<'EOF'
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
q2_title() { echo "Tolerate a node taint"; }
q2_text() { cat <<'EOF'
The node worker-2 has the taint dedicated=gpu:NoSchedule.

In the default namespace, create a Pod named gpu-pod (image nginx:1.24)
that tolerates that taint and therefore can run on worker-2.

  toleration   key dedicated / operator Equal / value gpu / effect NoSchedule

Verify:
  kubectl get pod gpu-pod -o wide
EOF
}
q2_title_ko() { echo "Taint 를 허용하는 Toleration"; }
q2_text_ko() { cat <<'EOF'
worker-2 노드에는 dedicated=gpu:NoSchedule taint 가 걸려 있다.

default 네임스페이스에 gpu-pod 파드(nginx:1.24)를 만들되,
그 taint 를 허용해서 worker-2 에서 돌 수 있게 하시오.

  toleration   key dedicated / operator Equal / value gpu / effect NoSchedule

[확인]
  kubectl get pod gpu-pod -o wide
EOF
}
q2_grade() {
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
q2_hint() { cat <<'EOF'
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
q3_title() { echo "HorizontalPodAutoscaler with a scale-down window"; }
q3_text() { cat <<'EOF'
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
q3_title_ko() { echo "HPA (자동 스케일) + 스케일 다운 안정화"; }
q3_text_ko() { cat <<'EOF'
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
q3_grade() {
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
q3_hint() { cat <<'EOF'
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
q4_title() { echo "PriorityClass and preemption"; }
q4_text() { cat <<'EOF'
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
q4_title_ko() { echo "PriorityClass 와 우선순위"; }
q4_text_ko() { cat <<'EOF'
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
q4_grade() {
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
q4_hint() { cat <<'EOF'
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


exam_main "$@"
