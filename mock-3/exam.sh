#!/usr/bin/env bash
# CKA Mock Exam 3 — 순차 진행형 (100점 배점)
# 사용법: bash exam.sh start → 풀고 → bash exam.sh check → ...
set -uo pipefail
EXAM_UNIT="점"
source "$(cd "$(dirname "$0")/.." && pwd)/_lib/exam-lib.sh"

EXAM_TITLE="CKA Mock Exam 3 — 자동화·권한·트러블슈팅 (100점 · 목표 50분)"
EXAM_NQ=7

exam_cleanup() {
  kdel deployment web-app broken-deploy
  kdel hpa web-app
  kdel svc broken-svc
  kdel pvc fast-pvc
  kdel pv fast-pv
  kdel storageclass fast-ssd
  kdel clusterrolebinding cluster-reader-crb
  kdel clusterrole cluster-reader
  kdel serviceaccount reader-sa
  kdel daemonset log-collector
  kubectl delete pod crash-pod --ignore-not-found --force --grace-period=0 &>/dev/null || true
  rm -f /tmp/upgrade-plan.txt
  echo "  web-app/HPA · fast-ssd/pv/pvc · RBAC · DaemonSet · broken-deploy/svc · crash-pod · upgrade-plan 삭제"
}

exam_setup() {
  # Q2: PVC 가 실제로 Bound 되도록 hostPath PV 준비 (StorageClass 는 학생이 만든다)
  kubectl apply -f - &>/dev/null <<'EOF'
apiVersion: v1
kind: PersistentVolume
metadata: { name: fast-pv }
spec:
  capacity: { storage: 1Gi }
  accessModes: [ReadWriteOnce]
  persistentVolumeReclaimPolicy: Retain
  storageClassName: fast-ssd
  hostPath: { path: /mnt/fast-data, type: DirectoryOrCreate }
EOF
  echo "  Q2 용 PV fast-pv (sc fast-ssd, 1Gi) 준비"

  # Q5: selector 가 틀린 Service
  kubectl create deployment broken-deploy --image=nginx:1.24 --replicas=2 &>/dev/null || true
  kubectl apply -f - &>/dev/null <<'EOF'
apiVersion: v1
kind: Service
metadata: { name: broken-svc, namespace: default }
spec:
  selector: { app: broken-wrong }
  ports: [ { port: 80, targetPort: 80 } ]
EOF
  echo "  Q5 용 broken-deploy + broken-svc (selector 불일치) 생성"

  # Q6: 잘못된 command
  kubectl apply -f - &>/dev/null <<'EOF'
apiVersion: v1
kind: Pod
metadata: { name: crash-pod, namespace: default }
spec:
  containers:
  - { name: crash-pod, image: busybox:1.36, command: ["wrongcmd"] }
EOF
  echo "  Q6 용 crash-pod (CrashLoopBackOff) 생성"
}

q1_title() { echo "Configure an HPA [10 pts]"; }
q1_text() { cat <<'EOF'
Create a Deployment and an HPA with the following spec.

Deployment
  name          web-app
  image         nginx:1.24
  replicas      2

HPA
  target        deployment/web-app
  min replicas  2
  max replicas  5
  CPU target    70%

Verify:
  kubectl get deployment web-app
  kubectl get hpa web-app
EOF
}
q1_title_ko() { echo "HPA 설정 [10점]"; }
q1_text_ko() { cat <<'EOF'
다음 조건으로 Deployment 와 HPA 를 생성하시오.

Deployment
  이름          web-app
  이미지        nginx:1.24
  복제본        2

HPA
  대상          deployment/web-app
  최소 복제본   2
  최대 복제본   5
  CPU 임계값    70%

[확인]
  kubectl get deployment web-app
  kubectl get hpa web-app
EOF
}
q1_hint() { cat <<'EOF'
kubectl create deployment web-app --image=nginx:1.24 --replicas=2
kubectl autoscale deployment web-app --min=2 --max=5 --cpu-percent=70
EOF
}
q1_grade() {
  check_output "Deployment web-app 이미지 nginx:1.24" \
    "kubectl get deployment web-app -n default -o jsonpath='{.spec.template.spec.containers[0].image}'" "^nginx:1\.24$" 2
  check "HPA web-app 존재" "kubectl get hpa web-app -n default" 2
  check_output "HPA minReplicas=2" "kubectl get hpa web-app -n default -o jsonpath='{.spec.minReplicas}'" "^2$" 2
  check_output "HPA maxReplicas=5" "kubectl get hpa web-app -n default -o jsonpath='{.spec.maxReplicas}'" "^5$" 2
  check_output "HPA CPU 70%" \
    "kubectl get hpa web-app -n default -o jsonpath='{.spec.metrics[0].resource.target.averageUtilization}'" "^70$" 2
}

q2_title() { echo "StorageClass and PVC [15 pts]"; }
q2_text() { cat <<'EOF'
Create a StorageClass and a PVC with the following spec.
(A PV for the fast-ssd class has already been prepared.)

StorageClass
  name          fast-ssd
  provisioner   kubernetes.io/no-provisioner
  reclaimPolicy Delete

PVC
  name              fast-pvc
  capacity          1Gi
  accessMode        ReadWriteOnce
  storageClassName  fast-ssd
  namespace         default

Verify:
  kubectl get storageclass fast-ssd
  kubectl get pvc fast-pvc          -> Bound
EOF
}
q2_title_ko() { echo "StorageClass + PVC [15점]"; }
q2_text_ko() { cat <<'EOF'
다음 조건으로 StorageClass 와 PVC 를 생성하시오.
(fast-ssd 클래스용 PV 는 미리 준비되어 있다)

StorageClass
  이름          fast-ssd
  provisioner   kubernetes.io/no-provisioner
  reclaimPolicy Delete

PVC
  이름              fast-pvc
  용량              1Gi
  accessMode        ReadWriteOnce
  storageClassName  fast-ssd
  네임스페이스      default

[확인]
  kubectl get storageclass fast-ssd
  kubectl get pvc fast-pvc          → Bound
EOF
}
q2_hint() { cat <<'EOF'
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata: { name: fast-ssd }
provisioner: kubernetes.io/no-provisioner
reclaimPolicy: Delete
EOF
}
q2_grade() {
  check "StorageClass fast-ssd 존재" "kubectl get storageclass fast-ssd" 3
  check_output "provisioner = kubernetes.io/no-provisioner" \
    "kubectl get storageclass fast-ssd -o jsonpath='{.provisioner}'" "^kubernetes\.io/no-provisioner$" 3
  check_output "reclaimPolicy = Delete" "kubectl get storageclass fast-ssd -o jsonpath='{.reclaimPolicy}'" "^Delete$" 2
  check "PVC fast-pvc 존재" "kubectl get pvc fast-pvc -n default" 2
  check_output "PVC storageClassName = fast-ssd" "kubectl get pvc fast-pvc -n default -o jsonpath='{.spec.storageClassName}'" "^fast-ssd$" 2
  check_output "PVC 가 Bound 상태" "kubectl get pvc fast-pvc -n default -o jsonpath='{.status.phase}'" "^Bound$" 3
}

q3_title() { echo "RBAC with a ClusterRole [20 pts]"; }
q3_text() { cat <<'EOF'
Create the following three RBAC resources.

ServiceAccount        reader-sa (default namespace)
ClusterRole           cluster-reader
                      resources pods, nodes, services / verbs get, list, watch
ClusterRoleBinding    cluster-reader-crb
                      ClusterRole cluster-reader -> ServiceAccount default:reader-sa

Verify:
  kubectl auth can-i list nodes --as=system:serviceaccount:default:reader-sa   -> yes
  kubectl auth can-i list pods  --as=system:serviceaccount:default:reader-sa   -> yes
EOF
}
q3_title_ko() { echo "RBAC ClusterRole [20점]"; }
q3_text_ko() { cat <<'EOF'
다음 세 가지 RBAC 리소스를 생성하시오.

ServiceAccount        reader-sa (default 네임스페이스)
ClusterRole           cluster-reader
                      리소스 pods, nodes, services / 동사 get, list, watch
ClusterRoleBinding    cluster-reader-crb
                      ClusterRole cluster-reader → ServiceAccount default:reader-sa

[확인]
  kubectl auth can-i list nodes --as=system:serviceaccount:default:reader-sa   → yes
  kubectl auth can-i list pods  --as=system:serviceaccount:default:reader-sa   → yes
EOF
}
q3_hint() { cat <<'EOF'
kubectl create serviceaccount reader-sa
kubectl create clusterrole cluster-reader --verb=get,list,watch --resource=pods,nodes,services
kubectl create clusterrolebinding cluster-reader-crb --clusterrole=cluster-reader --serviceaccount=default:reader-sa
EOF
}
q3_grade() {
  check "ServiceAccount reader-sa 존재" "kubectl get serviceaccount reader-sa -n default" 3
  check "ClusterRole cluster-reader 존재" "kubectl get clusterrole cluster-reader" 3
  local res verbs
  res=$(kubectl get clusterrole cluster-reader -o jsonpath='{.rules[*].resources}' 2>/dev/null || echo "")
  verbs=$(kubectl get clusterrole cluster-reader -o jsonpath='{.rules[*].verbs}' 2>/dev/null || echo "")
  check_result "리소스에 pods · nodes · services 모두 포함" \
    "$(echo "$res" | grep -q pods && echo "$res" | grep -q nodes && echo "$res" | grep -q services && echo 0 || echo 1)" "" 3
  check_result "verbs 에 get · list · watch 모두 포함" \
    "$(echo "$verbs" | grep -q get && echo "$verbs" | grep -q list && echo "$verbs" | grep -q watch && echo 0 || echo 1)" "" 3
  check "ClusterRoleBinding cluster-reader-crb 존재" "kubectl get clusterrolebinding cluster-reader-crb" 3
  check_output "권한: list nodes = yes" "kubectl auth can-i list nodes --as=system:serviceaccount:default:reader-sa" "^yes$" 3
  check_output "권한: list pods = yes" "kubectl auth can-i list pods --as=system:serviceaccount:default:reader-sa" "^yes$" 2
}

q4_title() { echo "Create a DaemonSet [15 pts]"; }
q4_text() { cat <<'EOF'
Create a DaemonSet with the following spec.

  name          log-collector
  namespace     default
  image         busybox:1.36
  command       ["sh", "-c", "while true; do echo $(date); sleep 60; done"]
  labels        app=log-collector  (in both selector and template)

Note: there is no kubectl create command for a DaemonSet — write the YAML.

Verify:
  kubectl get daemonset log-collector    -> DESIRED == READY (number of worker nodes)
EOF
}
q4_title_ko() { echo "DaemonSet 생성 [15점]"; }
q4_text_ko() { cat <<'EOF'
다음 조건으로 DaemonSet 을 생성하시오.

  이름          log-collector
  네임스페이스  default
  이미지        busybox:1.36
  command       ["sh", "-c", "while true; do echo $(date); sleep 60; done"]
  레이블        app=log-collector  (selector 와 template 모두)

참고: DaemonSet 은 kubectl create 명령이 없다 → YAML 작성

[확인]
  kubectl get daemonset log-collector    → DESIRED == READY (워커 노드 수)
EOF
}
q4_hint() { echo "kubectl create deployment 로 뼈대를 뽑아 kind 를 DaemonSet 으로 바꾸고 replicas/strategy 를 지운다"; }
q4_grade() {
  check "DaemonSet log-collector 존재" "kubectl get daemonset log-collector -n default" 4
  check_output "이미지: busybox" "kubectl get daemonset log-collector -n default -o jsonpath='{.spec.template.spec.containers[0].image}'" "busybox" 3
  check_output "selector app=log-collector" "kubectl get daemonset log-collector -n default -o jsonpath='{.spec.selector.matchLabels.app}'" "^log-collector$" 3
  local i; for i in $(seq 1 10); do
    local d r; d=$(kubectl get daemonset log-collector -n default -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null || echo 0)
    r=$(kubectl get daemonset log-collector -n default -o jsonpath='{.status.numberReady}' 2>/dev/null || echo 0)
    [[ "$d" != "0" && "$d" == "$r" ]] && break; sleep 3
  done
  local d r; d=$(kubectl get daemonset log-collector -n default -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null || echo 0)
  r=$(kubectl get daemonset log-collector -n default -o jsonpath='{.status.numberReady}' 2>/dev/null || echo 0)
  check_result "DESIRED(${d}) == READY(${r}) — 노드마다 1개씩 기동" "$([[ "$d" != "0" && "$d" == "$r" ]] && echo 0 || echo 1)" "" 5
}

q5_title() { echo "Fix an empty Service endpoint [20 pts]"; }
q5_text() { cat <<'EOF'
The Endpoints of broken-svc are empty, while broken-deploy is running
normally with two pods.

Diagnose the cause and fix broken-svc so that it sends traffic to the pods
of broken-deploy.

Useful commands:
  kubectl get endpoints broken-svc
  kubectl get svc broken-svc -o yaml
  kubectl get pod -l app=broken-deploy --show-labels

Verify:
  kubectl get endpoints broken-svc         -> two Pod IPs
EOF
}
q5_title_ko() { echo "Service Endpoint 수정 [20점]"; }
q5_text_ko() { cat <<'EOF'
현재 broken-svc 의 Endpoints 가 비어 있다. broken-deploy 는 정상 실행 중
(파드 2개)이다.

원인을 진단하고 broken-svc 가 broken-deploy 의 파드로 트래픽을 보내도록
수정하시오.

진단에 쓸 명령
  kubectl get endpoints broken-svc
  kubectl get svc broken-svc -o yaml
  kubectl get pod -l app=broken-deploy --show-labels

[확인]
  kubectl get endpoints broken-svc         → Pod IP 2개
EOF
}
q5_hint() { echo "kubectl patch svc broken-svc -p '{\"spec\":{\"selector\":{\"app\":\"broken-deploy\"}}}'"; }
q5_grade() {
  check_output "broken-svc selector 가 app=broken-deploy" \
    "kubectl get svc broken-svc -n default -o jsonpath='{.spec.selector.app}'" "^broken-deploy$" 8
  local ep; ep=$(kubectl get endpoints broken-svc -n default -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null | wc -w | tr -d ' ')
  check_result "broken-svc Endpoints 에 Pod IP 2개" "$([[ "$ep" == "2" ]] && echo 0 || echo 1)" "실제 ${ep}개" 6
  kubectl delete pod ep-probe -n default --ignore-not-found &>/dev/null || true
  local out; out=$(kubectl run ep-probe -n default --image=busybox:1.36 --restart=Never --rm -i --timeout=60s --command -- wget -qO- --timeout=5 http://broken-svc 2>/dev/null || echo "")
  kubectl delete pod ep-probe -n default --ignore-not-found &>/dev/null || true
  check_result "http://broken-svc 로 실제 응답 (통신 검증)" "$(echo "$out" | grep -qi nginx && echo 0 || echo 1)" "" 6
}

q6_title() { echo "Fix a CrashLoopBackOff [10 pts]"; }
q6_text() { cat <<'EOF'
The Pod crash-pod is in CrashLoopBackOff state.
Find the cause and make the Pod reach Running state. Keep the same image.

Useful commands:
  kubectl logs crash-pod --previous
  kubectl describe pod crash-pod

Verify:
  kubectl get pod crash-pod                -> Running, no further restarts

Note: the command of a running Pod cannot be edited — delete and recreate it.
EOF
}
q6_title_ko() { echo "CrashLoopBackOff 수정 [10점]"; }
q6_text_ko() { cat <<'EOF'
crash-pod 가 CrashLoopBackOff 상태다.
원인을 파악하고 Pod 가 Running 이 되도록 수정하시오. (이미지는 그대로)

진단에 쓸 명령
  kubectl logs crash-pod --previous
  kubectl describe pod crash-pod

[확인]
  kubectl get pod crash-pod                → Running, RESTARTS 증가 없음

※ Pod 의 command 는 실행 중 수정할 수 없다. 삭제 후 재생성한다.
EOF
}
q6_hint() { cat <<'EOF'
kubectl delete pod crash-pod --force --grace-period=0
kubectl run crash-pod --image=busybox:1.36 --command -- sleep 3600
EOF
}
q6_grade() {
  wait_ready "crash-pod" default || true
  check_output "crash-pod STATUS=Running" "kubectl get pod crash-pod -n default -o jsonpath='{.status.phase}'" "^Running$" 4
  check_output "crash-pod Ready" "kubectl get pod crash-pod -n default -o jsonpath='{.status.containerStatuses[0].ready}'" "^true$" 3
  local cmd; cmd=$(kubectl get pod crash-pod -n default -o jsonpath='{.spec.containers[0].command}' 2>/dev/null || echo "")
  check_result "command 가 wrongcmd 가 아님" "$(kubectl get pod crash-pod -n default &>/dev/null && ! echo "$cmd" | grep -q wrongcmd && echo 0 || echo 1)" "" 3
}

q7_title() { echo "Cluster upgrade plan [10 pts]"; }
q7_text() { cat <<'EOF'
Check the kubeadm cluster upgrade plan and save the output to the file
/tmp/upgrade-plan.txt.

  - it must be run on the control plane node
  - capture both standard output and standard error into the file

Verify:
  cat /tmp/upgrade-plan.txt     -> contains the Kubernetes version information
EOF
}
q7_title_ko() { echo "클러스터 업그레이드 계획 [10점]"; }
q7_text_ko() { cat <<'EOF'
kubeadm 으로 클러스터 업그레이드 계획을 확인하고 결과를
/tmp/upgrade-plan.txt 파일에 저장하시오.

  - 컨트롤플레인 노드에서 실행해야 한다
  - 표준 출력과 표준 에러를 모두 파일에 담는다

[확인]
  cat /tmp/upgrade-plan.txt     → 쿠버네티스 버전 정보 포함
EOF
}
q7_hint() { echo "kubeadm upgrade plan > /tmp/upgrade-plan.txt 2>&1"; }
q7_grade() {
  check_result "/tmp/upgrade-plan.txt 파일 존재" "$([[ -f /tmp/upgrade-plan.txt ]] && echo 0 || echo 1)" "컨트롤플레인에서 실행" 4
  local sz; sz=$(stat -c%s /tmp/upgrade-plan.txt 2>/dev/null || stat -f%z /tmp/upgrade-plan.txt 2>/dev/null || echo 0)
  check_result "파일 내용 있음" "$([[ "$sz" -gt 0 ]] && echo 0 || echo 1)" "" 3
  check_output "버전 정보(v1.x) 포함" "cat /tmp/upgrade-plan.txt" "v1\.[0-9]+" 3
}

exam_main "$@"
