#!/usr/bin/env bash
# CKA 9강 실습 — 워크로드 배포와 관리 (순차 진행형)
# 사용법: bash exam.sh start  →  풀고  →  bash exam.sh check  →  ...
set -uo pipefail
source "$(cd "$(dirname "$0")/.." && pwd)/_lib/exam-lib.sh"

EXAM_TITLE="CKA 9강 실습 — 워크로드 배포와 관리"
EXAM_NQ=4

# ══════════════════════════════════════════════════════════════
exam_cleanup() {
  kdel deployment log-app -n logging
  kdel namespace logging
  kdel deployment web-app -n default
  kdel cronjob date-printer -n default
  kubectl get jobs -n default -o name 2>/dev/null | grep "date-printer" | xargs -r kubectl delete -n default &>/dev/null || true
  kdel namespace monitoring
  echo "  web-app / date-printer / monitoring ns / logging ns 삭제"
}
exam_setup() {
  # Q4(사이드카) 용 — 로그를 계속 쓰는 앱을 미리 띄워 둔다. 사이드카만 붙이면 되게.
  kubectl create namespace logging &>/dev/null
  cat <<'YAML' | kubectl apply -f - &>/dev/null
apiVersion: apps/v1
kind: Deployment
metadata:
  name: log-app
  namespace: logging
  labels: { app: log-app }
spec:
  replicas: 1
  selector: { matchLabels: { app: log-app } }
  template:
    metadata:
      labels: { app: log-app }
    spec:
      containers:
        - name: app
          image: busybox:1.36
          command: ["sh", "-c", "while true; do echo \"$(date) hello from log-app\" >> /var/log/app/app.log; sleep 2; done"]
          volumeMounts:
            - name: applogs
              mountPath: /var/log/app
      volumes:
        - name: applogs
          emptyDir: {}
YAML
  echo "  logging 네임스페이스에 log-app 배치 (Q4 에서 사이드카를 붙인다)"
}

# ══════════════════════════════════════════════════════════════
# Q1 — Deployment 생성 · 스케일 · 롤링 업데이트 · 롤백
# ══════════════════════════════════════════════════════════════
q1_title() { echo "Deployment: create, scale, update, rollback"; }
q1_text() { cat <<'EOF'
In the default namespace, create a Deployment named web-app using image
nginx:1.24 with 3 replicas, then perform the following in order:

  (a) scale to 5 replicas
  (b) rolling update to image nginx:1.25, wait until the rollout completes
  (c) roll back to the previous revision

Final state: image nginx:1.24 with 5 replicas, all Ready.
You must really go through all three steps — creating it with 1.24 and only
scaling does not count.

Verify:
  kubectl get deployment web-app
  kubectl rollout history deployment/web-app
  kubectl get rs
EOF
}
q1_title_ko() { echo "Deployment 생성 · 스케일 · 롤링 업데이트 · 롤백"; }
q1_text_ko() { cat <<'EOF'
default 네임스페이스에 web-app Deployment 를 nginx:1.24 / replicas 3 으로
만든 뒤 순서대로 수행하시오.

  (a) 레플리카를 5 로 스케일
  (b) 이미지를 nginx:1.25 로 롤링 업데이트하고 완료될 때까지 대기
  (c) 이전 리비전으로 롤백

최종 상태: nginx:1.24 / replicas 5 / 전부 Ready
세 단계를 실제로 거쳐야 한다 (처음부터 1.24 로 두고 스케일만 하면 오답).

[확인]
  kubectl get deployment web-app
  kubectl rollout history deployment/web-app
  kubectl get rs
EOF
}
q1_grade() {
  check "web-app Deployment 존재" \
    "kubectl get deployment web-app -n default"
  check_output "replicas 5" \
    "kubectl get deployment web-app -n default -o jsonpath='{.spec.replicas}'" '^5$'
  wait_ready "-l app=web-app" default
  check_output "파드 5개가 Ready" \
    "kubectl get deployment web-app -n default -o jsonpath='{.status.readyReplicas}'" '^5$'
  check_output "롤백 후 이미지가 nginx:1.24" \
    "kubectl get deployment web-app -n default -o jsonpath='{.spec.template.spec.containers[0].image}'" '^nginx:1\.24$'
  local rev; rev=$(kubectl get deployment web-app -n default -o jsonpath='{.metadata.annotations.deployment\.kubernetes\.io/revision}' 2>/dev/null || echo 0)
  rev="${rev//[^0-9]/}"; rev="${rev:-0}"      # 숫자만 남긴다 (설명 문구에 그대로 들어가므로)
  check_result "업데이트 후 롤백한 이력 (revision ${rev:-0} ≥ 3)" \
    "$([[ "${rev:-0}" -ge 3 ]] && echo 0 || echo 1)" "revision=${rev:-0} — 1.25 로 올렸다가 되돌렸는지 확인"
  check_output "이전 ReplicaSet(nginx:1.25)이 남아 있다" \
    "kubectl get rs -n default -l app=web-app -o jsonpath='{.items[*].spec.template.spec.containers[0].image}'" 'nginx:1\.25'
}
q1_hint() { cat <<'EOF'
kubectl create deployment web-app --image=nginx:1.24 --replicas=3
kubectl scale deployment web-app --replicas=5
kubectl set image deployment/web-app nginx=nginx:1.25    # 컨테이너명은 describe 로 확인
kubectl rollout status deployment/web-app
kubectl rollout undo deployment/web-app
EOF
}


# ══════════════════════════════════════════════════════════════
# Q2 — CronJob
# ══════════════════════════════════════════════════════════════
q2_title() { echo "CronJob that prints the date every minute"; }
q2_text() { cat <<'EOF'
Create a CronJob named date-printer in the default namespace that runs
every minute and prints the date.

  schedule   */1 * * * *
  image      busybox
  command    ["date"]

Wait one or two minutes so that at least one Job is created by the CronJob.

Verify:
  kubectl get cronjob date-printer
  kubectl get jobs | grep date-printer
EOF
}
q2_title_ko() { echo "매 분마다 date 를 출력하는 CronJob"; }
q2_text_ko() { cat <<'EOF'
default 네임스페이스에 매 분마다 date 를 출력하는 CronJob 을 만드시오.

  이름       date-printer
  schedule   */1 * * * *
  이미지     busybox
  명령       ["date"]

CronJob 이 Job 을 최소 1개 만들 때까지 1~2분 기다린다.

[확인]
  kubectl get cronjob date-printer
  kubectl get jobs | grep date-printer
EOF
}
q2_grade() {
  check "CronJob date-printer 존재" "kubectl get cronjob date-printer -n default"
  check_output "schedule 이 */1 * * * *" \
    "kubectl get cronjob date-printer -n default -o jsonpath='{.spec.schedule}'" '^\*/1 \* \* \* \*$'
  check_output "이미지 busybox" \
    "kubectl get cronjob date-printer -n default -o jsonpath='{.spec.jobTemplate.spec.template.spec.containers[0].image}'" 'busybox'
  check_output "command 가 date" \
    "kubectl get cronjob date-printer -n default -o jsonpath='{.spec.jobTemplate.spec.template.spec.containers[0].command[*]}'" 'date'
  local n; n=$(kubectl get jobs -n default --no-headers 2>/dev/null | grep -c "date-printer"); n=${n//[^0-9]/}; n=${n:-0}
  check_result "CronJob 이 만든 Job 이 1개 이상 (현재 ${n}개)" \
    "$([[ "$n" -ge 1 ]] && echo 0 || echo 1)" "1~2분 기다렸다가 다시 채점하세요"
}
q2_hint() { cat <<'EOF'
kubectl create cronjob date-printer --image=busybox --schedule='*/1 * * * *' -- date

# 1~2분 뒤
kubectl get job | grep date-printer
kubectl logs job/<생성된-job-이름>
EOF
}

# ══════════════════════════════════════════════════════════════
# Q3 — DaemonSet
# ══════════════════════════════════════════════════════════════
q3_title() { echo "DaemonSet in the monitoring namespace"; }
q3_text() { cat <<'EOF'
Create a namespace named monitoring and, inside it, a DaemonSet named
node-exporter.

  image          prom/node-exporter:latest
  hostNetwork    true
  hostPID        true
  labels         app=node-exporter  (in both selector and template)

At least one Pod must be Running.
Note: there is no kubectl create command for a DaemonSet — write the YAML
(tip: generate a Deployment with --dry-run and change kind, remove replicas
and strategy).

Verify:
  kubectl get daemonset -n monitoring
  kubectl get pods -n monitoring -o wide
EOF
}
q3_title_ko() { echo "monitoring 네임스페이스에 DaemonSet 생성"; }
q3_text_ko() { cat <<'EOF'
monitoring 네임스페이스를 만들고 그 안에 node-exporter DaemonSet 을
생성하시오.

  이미지         prom/node-exporter:latest
  hostNetwork    true
  hostPID        true
  레이블         app=node-exporter  (selector 와 template 양쪽)

파드가 최소 1개 Running 이어야 한다.
DaemonSet 은 kubectl create 명령이 없다 — YAML 을 직접 쓴다
(Deployment 를 --dry-run 으로 뽑아 kind 를 바꾸고 replicas·strategy 를 지우면 빠르다).

[확인]
  kubectl get daemonset -n monitoring
  kubectl get pods -n monitoring -o wide
EOF
}
q3_grade() {
  check "monitoring 네임스페이스 존재" "kubectl get namespace monitoring"
  check "DaemonSet node-exporter 존재" "kubectl get daemonset node-exporter -n monitoring"
  check_output "이미지 prom/node-exporter" \
    "kubectl get daemonset node-exporter -n monitoring -o jsonpath='{.spec.template.spec.containers[0].image}'" 'node-exporter'
  check_output "hostNetwork: true" \
    "kubectl get daemonset node-exporter -n monitoring -o jsonpath='{.spec.template.spec.hostNetwork}'" '^true$'
  check_output "hostPID: true" \
    "kubectl get daemonset node-exporter -n monitoring -o jsonpath='{.spec.template.spec.hostPID}'" '^true$'
  check_output "selector 가 app=node-exporter" \
    "kubectl get daemonset node-exporter -n monitoring -o jsonpath='{.spec.selector.matchLabels.app}'" '^node-exporter$'
  local ready; ready=$(kubectl get daemonset node-exporter -n monitoring -o jsonpath='{.status.numberReady}' 2>/dev/null || echo 0)
  check_result "파드가 1개 이상 Ready (현재 ${ready:-0}개)" \
    "$([[ "${ready:-0}" -ge 1 ]] && echo 0 || echo 1)" "이미지 pull 에 시간이 걸릴 수 있습니다"
}
q3_hint() { cat <<'EOF'
kubectl create namespace monitoring

# Deployment 뼈대를 뽑아 DaemonSet 으로 고친다
kubectl create deployment node-exporter -n monitoring \
  --image=prom/node-exporter:latest $do > ds.yaml
#   kind: Deployment  →  DaemonSet
#   spec.replicas / spec.strategy 줄 삭제
#   spec.template.spec 에 hostNetwork: true, hostPID: true 추가
kubectl apply -f ds.yaml
EOF
}

# ══════════════════════════════════════════════════════════════
q4_title() { echo "Native sidecar — a logging container"; }
q4_text() { cat <<'EOF'
A Deployment named log-app already exists in the logging namespace.
Its main container writes to /var/log/app/app.log on a shared emptyDir volume.

Add a native sidecar named log-sidecar to that Deployment.

  image        busybox:1.36
  command      sh -c 'tail -F /var/log/app/app.log'
  mountPath    /var/log/app   (the same emptyDir volume)

It must be a NATIVE sidecar:
  - declared under initContainers
  - with restartPolicy: Always

After the change each Pod must show READY 2/2.

Verify:
  kubectl -n logging get pods
  kubectl -n logging logs deploy/log-app -c log-sidecar
EOF
}
q4_title_ko() { echo "네이티브 사이드카 — 로그 수집 컨테이너"; }
q4_text_ko() { cat <<'EOF'
logging 네임스페이스에 log-app Deployment 가 이미 있다.
본 컨테이너가 공유 emptyDir 볼륨의 /var/log/app/app.log 에 로그를 쓴다.

여기에 log-sidecar 라는 네이티브 사이드카를 추가한다.

  이미지       busybox:1.36
  명령         sh -c 'tail -F /var/log/app/app.log'
  마운트 경로  /var/log/app   (같은 emptyDir 볼륨)

반드시 네이티브 사이드카여야 한다.
  - initContainers 아래에 선언
  - restartPolicy: Always

바꾸고 나면 각 파드가 READY 2/2 로 보여야 한다.

[확인]
  kubectl -n logging get pods
  kubectl -n logging logs deploy/log-app -c log-sidecar
EOF
}
q4_grade() {
  check "Deployment log-app 존재" "kubectl -n logging get deployment log-app"
  check_output "initContainers 에 log-sidecar 가 있다" \
    "kubectl -n logging get deployment log-app -o jsonpath='{.spec.template.spec.initContainers[*].name}'" 'log-sidecar'
  check_output "사이드카 이미지가 busybox:1.36" \
    "kubectl -n logging get deployment log-app -o jsonpath='{range .spec.template.spec.initContainers[?(@.name==\"log-sidecar\")]}{.image}{end}'" '^busybox:1\.36$'
  check_output "restartPolicy: Always (네이티브 사이드카의 조건)" \
    "kubectl -n logging get deployment log-app -o jsonpath='{range .spec.template.spec.initContainers[?(@.name==\"log-sidecar\")]}{.restartPolicy}{end}'" '^Always$'
  check_output "같은 볼륨을 /var/log/app 에 마운트" \
    "kubectl -n logging get deployment log-app -o jsonpath='{range .spec.template.spec.initContainers[?(@.name==\"log-sidecar\")]}{range .volumeMounts[*]}{.mountPath}{\" \"}{end}{end}'" '/var/log/app'
  wait_ready "-l app=log-app" logging
  check_output "파드가 READY 2/2 (사이드카가 살아 있다)" \
    "kubectl -n logging get deployment log-app -o jsonpath='{.status.readyReplicas}'" '^1$'
  check_output "사이드카가 본 컨테이너의 로그를 읽고 있다" \
    "kubectl -n logging logs deploy/log-app -c log-sidecar --tail=5 2>/dev/null" '.'
}
q4_hint() { cat <<'EOF'
kubectl -n logging edit deployment log-app

# spec.template.spec 아래, containers 와 나란히 initContainers 를 둔다
  initContainers:
    - name: log-sidecar
      image: busybox:1.36
      restartPolicy: Always          # ← 이 한 줄이 '네이티브 사이드카' 를 만든다
      command: ["sh", "-c", "tail -F /var/log/app/app.log"]
      volumeMounts:
        - name: applogs             # 본 컨테이너가 쓰는 볼륨과 같은 이름
          mountPath: /var/log/app

# 일반 initContainer 는 끝나야 본 컨테이너가 시작한다.
# restartPolicy: Always 를 주면 먼저 시작해서 끝까지 함께 산다 → READY 2/2
EOF
}


exam_main "$@"
