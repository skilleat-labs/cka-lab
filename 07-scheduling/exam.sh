#!/usr/bin/env bash
# CKA 3강 실습 — 스케줄링 (순차 진행형)
set -uo pipefail
source "$(cd "$(dirname "$0")/.." && pwd)/_lib/exam-lib.sh"

EXAM_TITLE="CKA 3강 실습 — 스케줄링 (Requests/Limits · Affinity · Taint · HPA)"
EXAM_NQ=4

exam_cleanup() {
  kdel pod resource-pod ssd-pod gpu-pod -n default
  kdel deployment nginx-hpa -n default
  kdel hpa nginx-hpa -n default
  kubectl label node worker-1 disktype- &>/dev/null || true
  kubectl taint node worker-2 dedicated=gpu:NoSchedule- &>/dev/null || true
  echo "  resource-pod / ssd-pod / gpu-pod / nginx-hpa 삭제, 노드 레이블·taint 원복"
}
exam_setup() {
  kubectl label node worker-1 disktype=ssd --overwrite &>/dev/null || true
  kubectl taint node worker-2 dedicated=gpu:NoSchedule --overwrite &>/dev/null || true
  echo "  worker-1 에 disktype=ssd 레이블, worker-2 에 dedicated=gpu:NoSchedule taint 를 걸었다"
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
q4_title() { echo "HorizontalPodAutoscaler"; }
q4_text() { cat <<'EOF'
In the default namespace, create a Deployment named nginx-hpa
(image nginx:1.24, 2 replicas) and an HPA for it.

  HPA name        nginx-hpa
  minReplicas     2
  maxReplicas     10
  target          average CPU utilization 50%

Verify:
  kubectl get deployment nginx-hpa
  kubectl get hpa nginx-hpa
EOF
}
q4_title_ko() { echo "HPA (자동 스케일)"; }
q4_text_ko() { cat <<'EOF'
default 네임스페이스에 nginx-hpa Deployment(nginx:1.24, replicas 2)를
만들고 거기에 HPA 를 붙이시오.

  HPA 이름        nginx-hpa
  minReplicas     2
  maxReplicas     10
  기준            CPU 평균 사용률 50%

[확인]
  kubectl get deployment nginx-hpa
  kubectl get hpa nginx-hpa
EOF
}
q4_grade() {
  check "nginx-hpa Deployment 존재" "kubectl get deployment nginx-hpa -n default"
  check_output "Deployment 파드가 Ready" \
    "kubectl get deployment nginx-hpa -n default -o jsonpath='{.status.readyReplicas}'" '^[1-9]'
  check "HPA nginx-hpa 존재" "kubectl get hpa nginx-hpa -n default"
  check_output "minReplicas=2" \
    "kubectl get hpa nginx-hpa -n default -o jsonpath='{.spec.minReplicas}'" '^2$'
  check_output "maxReplicas=10" \
    "kubectl get hpa nginx-hpa -n default -o jsonpath='{.spec.maxReplicas}'" '^10$'
  check_output "CPU 목표 50%" \
    "kubectl get hpa nginx-hpa -n default -o jsonpath='{.spec.metrics[0].resource.target.averageUtilization}{.spec.targetCPUUtilizationPercentage}'" '50'
  check_output "대상이 nginx-hpa Deployment" \
    "kubectl get hpa nginx-hpa -n default -o jsonpath='{.spec.scaleTargetRef.name}'" '^nginx-hpa$'
}
q4_hint() { cat <<'EOF'
kubectl create deployment nginx-hpa --image=nginx:1.24 --replicas=2
kubectl autoscale deployment nginx-hpa --min=2 --max=10 --cpu-percent=50

# 확인 (metrics-server 가 없으면 TARGETS 가 <unknown> 으로 나오지만 채점에는 문제없다)
kubectl get hpa nginx-hpa
EOF
}

exam_main "$@"
