#!/usr/bin/env bash
# CKA Mock Exam 1 — 순차 진행형 (100점 배점)
# 사용법: bash exam.sh start → 풀고 → bash exam.sh check → ...
set -uo pipefail
EXAM_UNIT="점"
source "$(cd "$(dirname "$0")/.." && pwd)/_lib/exam-lib.sh"

EXAM_TITLE="CKA Mock Exam 1 — 기초 워크로드 (100점 · 목표 40분)"
EXAM_NQ=7

exam_setup() {
  kubectl delete deployment nginx-deploy --ignore-not-found &>/dev/null || true
  kubectl delete svc nginx-svc --ignore-not-found &>/dev/null || true
  kubectl delete configmap app-config --ignore-not-found &>/dev/null || true
  kubectl delete pod config-pod broken-app --ignore-not-found --force --grace-period=0 &>/dev/null || true
  kubectl delete pvc task-pvc --ignore-not-found &>/dev/null || true
  kubectl delete pv task-pv --ignore-not-found &>/dev/null || true
  kubectl delete rolebinding app-rb --ignore-not-found &>/dev/null || true
  kubectl delete role app-role --ignore-not-found &>/dev/null || true
  kubectl delete serviceaccount app-sa --ignore-not-found &>/dev/null || true
  kubectl uncordon worker-1 &>/dev/null || true
  echo "  이전 리소스 정리"
  kubectl run broken-app --image=nginx:broken --restart=Never &>/dev/null || true
  echo "  Q7 용 broken-app 파드 생성 (ImagePullBackOff)"
}

q1_title() { echo "Deployment 생성 [15점]"; }
q1_text() { cat <<'EOF'
다음 조건으로 Deployment 를 생성하시오.

  이름          nginx-deploy
  이미지        nginx:1.24
  복제본        3
  네임스페이스  default

[확인]
  kubectl get deployment nginx-deploy -n default   → READY 3/3
EOF
}
q1_hint() { echo "kubectl create deployment nginx-deploy --image=nginx:1.24 --replicas=3"; }
q1_grade() {
  check "Deployment nginx-deploy 존재" "kubectl get deployment nginx-deploy -n default" 5
  check_output "이미지: nginx:1.24" \
    "kubectl get deployment nginx-deploy -n default -o jsonpath='{.spec.template.spec.containers[0].image}'" "^nginx:1\.24$" 5
  wait_ready "-l app=nginx-deploy" default || true
  check_output "Ready 복제본 3개" \
    "kubectl get deployment nginx-deploy -n default -o jsonpath='{.status.readyReplicas}'" "^3$" 5
}

q2_title() { echo "Service 생성 [10점]"; }
q2_text() { cat <<'EOF'
Q1 의 Deployment 를 노출하는 Service 를 생성하시오.

  이름          nginx-svc
  타입          ClusterIP
  포트          80
  셀렉터        app=nginx-deploy
  네임스페이스  default

[확인]
  kubectl get svc nginx-svc
  kubectl get endpoints nginx-svc      → Pod IP 3개
EOF
}
q2_hint() { echo "kubectl expose deployment nginx-deploy --name=nginx-svc --port=80"; }
q2_grade() {
  check_output "Service nginx-svc 존재 + ClusterIP 타입" \
    "kubectl get svc nginx-svc -n default -o jsonpath='{.spec.type}'" "^ClusterIP$" 5
  local ep; ep=$(kubectl get endpoints nginx-svc -n default -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null | wc -w | tr -d ' ')
  check_result "Endpoints 에 Pod IP 등록됨" "$([[ "${ep:-0}" -ge 1 ]] && echo 0 || echo 1)" "실제 ${ep}개" 5
}

q3_title() { echo "ConfigMap + Pod [10점]"; }
q3_text() { cat <<'EOF'
(1) ConfigMap 생성
  이름          app-config
  데이터        APP_ENV=prod
                APP_PORT=8080

(2) Pod 생성
  이름          config-pod
  이미지        busybox
  명령          sleep 3600
  주입          app-config 전체를 envFrom 으로

[확인]
  kubectl exec config-pod -- printenv APP_ENV      → prod
  kubectl exec config-pod -- printenv APP_PORT     → 8080
EOF
}
q3_hint() { cat <<'EOF'
kubectl create configmap app-config --from-literal=APP_ENV=prod --from-literal=APP_PORT=8080
# 파드 YAML 의 containers[0] 에:  envFrom: [ { configMapRef: { name: app-config } } ]
EOF
}
q3_grade() {
  check_output "ConfigMap app-config / APP_ENV=prod" \
    "kubectl get configmap app-config -n default -o jsonpath='{.data.APP_ENV}'" "^prod$" 3
  check_output "ConfigMap app-config / APP_PORT=8080" \
    "kubectl get configmap app-config -n default -o jsonpath='{.data.APP_PORT}'" "^8080$" 2
  wait_ready "config-pod" default || true
  check_output "config-pod Running" \
    "kubectl get pod config-pod -n default -o jsonpath='{.status.phase}'" "^Running$" 3
  check_output "config-pod 내부 APP_ENV=prod (실제 exec)" \
    "kubectl exec config-pod -n default -- printenv APP_ENV" "^prod$" 2
}

q4_title() { echo "PersistentVolume + PVC [15점]"; }
q4_text() { cat <<'EOF'
다음 조건으로 PV 와 PVC 를 생성하고 Bound 시키시오.

PersistentVolume
  이름              task-pv
  용량              500Mi
  접근 모드         ReadWriteOnce
  타입              hostPath, path=/tmp/task-data
  storageClassName  manual

PersistentVolumeClaim
  이름              task-pvc
  용량 요청         500Mi
  접근 모드         ReadWriteOnce
  storageClassName  manual

[확인]
  kubectl get pv task-pv       → Bound
  kubectl get pvc task-pvc     → Bound
EOF
}
q4_hint() { echo "PV 와 PVC 의 storageClassName·accessModes·용량이 맞아야 Bound 된다"; }
q4_grade() {
  check_output "PV task-pv 용량 500Mi" "kubectl get pv task-pv -o jsonpath='{.spec.capacity.storage}'" "^500Mi$" 4
  check_output "PV accessMode ReadWriteOnce" "kubectl get pv task-pv -o jsonpath='{.spec.accessModes[0]}'" "^ReadWriteOnce$" 3
  check_output "PV hostPath /tmp/task-data" "kubectl get pv task-pv -o jsonpath='{.spec.hostPath.path}'" "^/tmp/task-data$" 2
  check_output "PVC task-pvc STATUS=Bound" "kubectl get pvc task-pvc -n default -o jsonpath='{.status.phase}'" "^Bound$" 6
}

q5_title() { echo "RBAC [15점]"; }
q5_text() { cat <<'EOF'
default 네임스페이스에 다음 세 가지 RBAC 리소스를 생성하시오.

ServiceAccount   이름 app-sa
Role             이름 app-role / 리소스 pods / 동사 get, list
RoleBinding      이름 app-rb / Role app-role → Subject ServiceAccount app-sa

[확인]
  kubectl auth can-i list pods \
    --as=system:serviceaccount:default:app-sa -n default   → yes
EOF
}
q5_hint() { cat <<'EOF'
kubectl create serviceaccount app-sa
kubectl create role app-role --verb=get,list --resource=pods
kubectl create rolebinding app-rb --role=app-role --serviceaccount=default:app-sa
EOF
}
q5_grade() {
  check "ServiceAccount app-sa 존재" "kubectl get serviceaccount app-sa -n default" 3
  local verbs res
  verbs=$(kubectl get role app-role -n default -o jsonpath='{.rules[*].verbs}' 2>/dev/null || echo "")
  res=$(kubectl get role app-role -n default -o jsonpath='{.rules[*].resources}' 2>/dev/null || echo "")
  check_result "Role app-role verbs 에 get 포함" "$(echo "$verbs" | grep -q get && echo 0 || echo 1)" "" 3
  check_result "Role app-role verbs 에 list 포함" "$(echo "$verbs" | grep -q list && echo 0 || echo 1)" "" 2
  check_result "Role app-role 리소스: pods" "$(echo "$res" | grep -q pods && echo 0 || echo 1)" "" 2
  check "RoleBinding app-rb 존재" "kubectl get rolebinding app-rb -n default" 2
  check_output "권한 검증: list pods = yes" \
    "kubectl auth can-i list pods --as=system:serviceaccount:default:app-sa -n default" "^yes$" 3
}

q6_title() { echo "노드 drain [10점]"; }
q6_text() { cat <<'EOF'
(1) worker-1 노드를 drain 한다.
    - DaemonSet Pod 는 무시
    - emptyDir 데이터는 삭제 허용
(2) 유지보수 완료 후 worker-1 을 다시 스케줄 가능 상태로 전환한다.

[확인]
  kubectl get nodes   → worker-1 이 Ready, SchedulingDisabled 아님
EOF
}
q6_hint() { cat <<'EOF'
kubectl drain worker-1 --ignore-daemonsets --delete-emptydir-data
kubectl uncordon worker-1
EOF
}
q6_grade() {
  if ! kubectl get node worker-1 &>/dev/null; then
    check_result "worker-1 노드 (이 클러스터에 없음 — 통과 처리)" 0 "" 10; return
  fi
  check_output "worker-1 스케줄 가능 (uncordon 완료)" \
    "kubectl get node worker-1 -o jsonpath='{.spec.unschedulable}'" "^$|^false$" 5
  check_output "worker-1 Ready 상태" \
    "kubectl get node worker-1 -o jsonpath='{.status.conditions[?(@.type==\"Ready\")].status}'" "^True$" 5
}

q7_title() { echo "Pod 트러블슈팅 [25점]"; }
q7_text() { cat <<'EOF'
현재 broken-app Pod 가 ErrImagePull / ImagePullBackOff 상태다.

원인을 파악하고, 이미지를 nginx:latest 로 수정하여 Pod 가 Running 상태가
되도록 하시오.

[확인]
  kubectl get pod broken-app     → Running
EOF
}
q7_hint() { cat <<'EOF'
kubectl describe pod broken-app        # Events 에서 원인 확인
kubectl set image pod/broken-app broken-app=nginx:latest
EOF
}
q7_grade() {
  wait_ready "broken-app" default || true
  check_output "broken-app STATUS=Running" \
    "kubectl get pod broken-app -n default -o jsonpath='{.status.phase}'" "^Running$" 15
  check_output "broken-app 이미지가 nginx:broken 이 아님" \
    "kubectl get pod broken-app -n default -o jsonpath='{.spec.containers[0].image}'" "^nginx:(latest|[0-9.]+)$" 10
}

exam_main "$@"
