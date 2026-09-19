#!/usr/bin/env bash
# CKA Mock Exam 1-1 — 순차 진행형 (100점 배점) · mock-1 변형판
# 사용법: bash exam.sh start → 풀고 → bash exam.sh check → ...
set -uo pipefail
EXAM_UNIT="점"
source "$(cd "$(dirname "$0")/.." && pwd)/_lib/exam-lib.sh"

EXAM_TITLE="CKA Mock Exam 1-1 — 기초 워크로드 변형판 (100점 · 목표 40분)"
EXAM_NQ=7
NS=retail

exam_setup() {
  if kubectl get namespace retail &>/dev/null; then
    echo "  네임스페이스 retail 삭제 중..."
    kubectl delete namespace retail --wait=true &>/dev/null || true
  fi
  kubectl delete pv report-pv --ignore-not-found &>/dev/null || true
  kubectl uncordon worker-2 &>/dev/null || true
  kubectl create namespace retail &>/dev/null || true
  echo "  retail 네임스페이스 생성"
  kubectl run web-broken --image=nginz:1.24 --restart=Never -n retail &>/dev/null || true
  echo "  Q7 용 web-broken 파드 생성 (이미지 저장소 오타)"
}

q1_title() { echo "Deployment 생성 [15점]"; }
q1_text() { cat <<'EOF'
retail 네임스페이스에 다음 조건으로 Deployment 를 생성하시오.

  이름            store-front
  이미지          nginx:1.25
  복제본          4
  컨테이너 포트   80

[확인]
  kubectl get deployment store-front -n retail   → READY 4/4
EOF
}
q1_hint() { echo "kubectl create deployment store-front --image=nginx:1.25 --replicas=4 --port=80 -n retail"; }
q1_grade() {
  check "Deployment store-front 가 retail 네임스페이스에 존재" "kubectl get deployment store-front -n $NS" 4
  check_output "이미지: nginx:1.25" \
    "kubectl get deployment store-front -n $NS -o jsonpath='{.spec.template.spec.containers[0].image}'" "^nginx:1\.25$" 4
  check_output "containerPort 80" \
    "kubectl get deployment store-front -n $NS -o jsonpath='{.spec.template.spec.containers[0].ports[0].containerPort}'" "^80$" 2
  wait_ready "-l app=store-front" $NS || true
  check_output "Ready 복제본 4개" \
    "kubectl get deployment store-front -n $NS -o jsonpath='{.status.readyReplicas}'" "^4$" 5
}

q2_title() { echo "Service 생성 — 8080 → 80 [10점]"; }
q2_text() { cat <<'EOF'
Q1 의 Deployment 를 노출하는 Service 를 생성하시오.

  이름            store-svc
  타입            ClusterIP
  port            8080  →  targetPort 80   (포트가 다르다)
  셀렉터          app=store-front
  네임스페이스    retail

[확인]
  kubectl get svc store-svc -n retail          → 8080/TCP
  kubectl get endpoints store-svc -n retail    → Pod IP 4개
EOF
}
q2_hint() { echo "kubectl expose deployment store-front --name=store-svc --port=8080 --target-port=80 -n retail"; }
q2_grade() {
  check_output "Service store-svc 존재 + ClusterIP 타입" \
    "kubectl get svc store-svc -n $NS -o jsonpath='{.spec.type}'" "^ClusterIP$" 3
  check_output "port 8080" "kubectl get svc store-svc -n $NS -o jsonpath='{.spec.ports[0].port}'" "^8080$" 2
  check_output "targetPort 80" "kubectl get svc store-svc -n $NS -o jsonpath='{.spec.ports[0].targetPort}'" "^80$" 2
  local ep; ep=$(kubectl get endpoints store-svc -n $NS -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null | wc -w | tr -d ' ')
  check_result "Endpoints 에 Pod IP 4개 등록" "$([[ "$ep" == "4" ]] && echo 0 || echo 1)" "실제 ${ep}개" 3
}

q3_title() { echo "ConfigMap + Pod [10점]"; }
q3_text() { cat <<'EOF'
retail 네임스페이스에서 다음 두 가지 작업을 수행하시오.

(1) ConfigMap 생성
  이름            store-config
  데이터          APP_MODE=staging
                  APP_PORT=9090

(2) Pod 생성
  이름            store-cfg
  이미지          busybox:1.36
  명령            sleep 7200
  주입            store-config 전체를 envFrom 으로

[확인]
  kubectl exec store-cfg -n retail -- printenv APP_MODE   → staging
  kubectl exec store-cfg -n retail -- printenv APP_PORT   → 9090
EOF
}
q3_hint() { cat <<'EOF'
kubectl create configmap store-config -n retail --from-literal=APP_MODE=staging --from-literal=APP_PORT=9090
# 파드 YAML containers[0] 에:  envFrom: [ { configMapRef: { name: store-config } } ]
EOF
}
q3_grade() {
  check_output "ConfigMap store-config / APP_MODE=staging" \
    "kubectl get configmap store-config -n $NS -o jsonpath='{.data.APP_MODE}'" "^staging$" 2
  check_output "ConfigMap store-config / APP_PORT=9090" \
    "kubectl get configmap store-config -n $NS -o jsonpath='{.data.APP_PORT}'" "^9090$" 2
  wait_ready "store-cfg" $NS || true
  check_output "store-cfg Running" "kubectl get pod store-cfg -n $NS -o jsonpath='{.status.phase}'" "^Running$" 2
  check_output "store-cfg 내부 APP_MODE=staging (실제 exec)" "kubectl exec store-cfg -n $NS -- printenv APP_MODE" "^staging$" 2
  check_output "store-cfg 내부 APP_PORT=9090 (실제 exec)" "kubectl exec store-cfg -n $NS -- printenv APP_PORT" "^9090$" 2
}

q4_title() { echo "PV + PVC — ReadWriteMany [15점]"; }
q4_text() { cat <<'EOF'
다음 조건으로 PV 와 PVC 를 생성하고 Bound 시키시오.

PersistentVolume
  이름              report-pv
  용량              1Gi
  접근 모드         ReadWriteMany
  타입              hostPath, path=/tmp/report-data
  storageClassName  local-manual

PersistentVolumeClaim
  이름              report-pvc
  네임스페이스      retail
  용량 요청         1Gi
  접근 모드         ReadWriteMany
  storageClassName  local-manual

[확인]
  kubectl get pv report-pv                     → Bound
  kubectl get pvc report-pvc -n retail         → Bound
EOF
}
q4_hint() { echo "accessModes 가 ReadWriteMany 여야 한다. RWO 로 만들면 Bound 되지 않는다."; }
q4_grade() {
  check_output "PV report-pv 용량 1Gi" "kubectl get pv report-pv -o jsonpath='{.spec.capacity.storage}'" "^1Gi$" 3
  check_output "PV accessMode ReadWriteMany" "kubectl get pv report-pv -o jsonpath='{.spec.accessModes[0]}'" "^ReadWriteMany$" 3
  check_output "PV hostPath /tmp/report-data" "kubectl get pv report-pv -o jsonpath='{.spec.hostPath.path}'" "^/tmp/report-data$" 2
  check_output "PV storageClassName local-manual" "kubectl get pv report-pv -o jsonpath='{.spec.storageClassName}'" "^local-manual$" 2
  check_output "PVC report-pvc STATUS=Bound (retail)" "kubectl get pvc report-pvc -n $NS -o jsonpath='{.status.phase}'" "^Bound$" 5
}

q5_title() { echo "RBAC — deployments 만 [15점]"; }
q5_text() { cat <<'EOF'
retail 네임스페이스에 다음 세 가지 RBAC 리소스를 생성하시오.

ServiceAccount   이름 deploy-sa
Role             이름 deploy-reader / 리소스 deployments (apps 그룹)
                 동사 get, list, watch
RoleBinding      이름 deploy-reader-rb / Role deploy-reader
                 → Subject ServiceAccount deploy-sa

[확인]
  kubectl auth can-i list deployments \
    --as=system:serviceaccount:retail:deploy-sa -n retail   → yes
  kubectl auth can-i list pods \
    --as=system:serviceaccount:retail:deploy-sa -n retail   → no
EOF
}
q5_hint() { cat <<'EOF'
kubectl create serviceaccount deploy-sa -n retail
kubectl create role deploy-reader --verb=get,list,watch --resource=deployments -n retail
kubectl create rolebinding deploy-reader-rb --role=deploy-reader --serviceaccount=retail:deploy-sa -n retail
# pods 를 같이 넣으면 과잉 권한으로 감점
EOF
}
q5_grade() {
  local sa rb; sa=$(kubectl get serviceaccount deploy-sa -n $NS -o name 2>/dev/null || echo ""); rb=$(kubectl get rolebinding deploy-reader-rb -n $NS -o name 2>/dev/null || echo "")
  check_result "ServiceAccount deploy-sa 존재" "$([[ -n "$sa" ]] && echo 0 || echo 1)" "" 2
  local j; j=$(kubectl get role deploy-reader -n $NS -o json 2>/dev/null || echo '{}')
  local verbs res grp
  verbs=$(echo "$j" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(" ".join(v for r in d.get("rules",[]) for v in r.get("verbs",[])))' 2>/dev/null || echo "")
  res=$(echo "$j" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(" ".join(v for r in d.get("rules",[]) for v in r.get("resources",[])))' 2>/dev/null || echo "")
  grp=$(echo "$j" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(" ".join(v for r in d.get("rules",[]) for v in r.get("apiGroups",[])))' 2>/dev/null || echo "")
  check_result "Role deploy-reader 리소스: deployments" "$(echo "$res" | grep -q deployments && echo 0 || echo 1)" "" 2
  check_result "Role deploy-reader apiGroup: apps" "$(echo "$grp" | grep -q apps && echo 0 || echo 1)" "" 2
  check_result "Role verbs 에 get·list·watch 포함" "$(echo "$verbs" | grep -q get && echo "$verbs" | grep -q list && echo "$verbs" | grep -q watch && echo 0 || echo 1)" "" 2
  check_result "RoleBinding deploy-reader-rb 존재" "$([[ -n "$rb" ]] && echo 0 || echo 1)" "" 2
  check_output "권한 검증: list deployments = yes" \
    "kubectl auth can-i list deployments --as=system:serviceaccount:$NS:deploy-sa -n $NS" "^yes$" 3
  local ap; ap=$(kubectl auth can-i list pods --as=system:serviceaccount:$NS:deploy-sa -n $NS 2>/dev/null || echo yes)
  check_result "권한 검증: list pods = no (필요한 권한만)" "$([[ -n "$sa" && -n "$rb" && "$ap" == "no" ]] && echo 0 || echo 1)" "" 2
}

q6_title() { echo "노드 drain — worker-2 [10점]"; }
q6_text() { cat <<'EOF'
(1) worker-2 노드를 drain 한다.
    - DaemonSet Pod 는 무시
    - emptyDir 데이터는 삭제 허용
(2) 유지보수 완료 후 worker-2 를 다시 스케줄 가능 상태로 전환한다.

[확인]
  kubectl get nodes   → worker-2 가 Ready, SchedulingDisabled 아님
EOF
}
q6_hint() { cat <<'EOF'
kubectl drain worker-2 --ignore-daemonsets --delete-emptydir-data
kubectl uncordon worker-2
EOF
}
q6_grade() {
  if ! kubectl get node worker-2 &>/dev/null; then
    check_result "worker-2 노드 (이 클러스터에 없음 — 통과 처리)" 0 "" 10; return
  fi
  check_output "worker-2 스케줄 가능 (uncordon 완료)" "kubectl get node worker-2 -o jsonpath='{.spec.unschedulable}'" "^$|^false$" 5
  check_output "worker-2 Ready 상태" "kubectl get node worker-2 -o jsonpath='{.status.conditions[?(@.type==\"Ready\")].status}'" "^True$" 5
}

q7_title() { echo "Pod 트러블슈팅 [25점]"; }
q7_text() { cat <<'EOF'
retail 네임스페이스의 web-broken Pod 가 ErrImagePull / ImagePullBackOff
상태다.

원인을 파악하고, 이미지를 nginx:1.24 로 수정하여 Pod 가 Running 상태가
되도록 하시오.

[확인]
  kubectl get pod web-broken -n retail         → Running
EOF
}
q7_hint() { cat <<'EOF'
kubectl describe pod web-broken -n retail      # 이미지 이름 오타(nginz) 확인
kubectl set image pod/web-broken web-broken=nginx:1.24 -n retail
EOF
}
q7_grade() {
  wait_ready "web-broken" $NS || true
  check_output "web-broken STATUS=Running" "kubectl get pod web-broken -n $NS -o jsonpath='{.status.phase}'" "^Running$" 13
  check_output "web-broken 이미지가 nginx:1.24 로 수정됨" \
    "kubectl get pod web-broken -n $NS -o jsonpath='{.spec.containers[0].image}'" "^nginx:1\.24$" 12
}

exam_main "$@"
