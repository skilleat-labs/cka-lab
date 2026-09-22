#!/usr/bin/env bash
# CKA 3강 실습 — 워크로드 배포와 관리 (순차 진행형)
# 사용법: bash exam.sh start  →  풀고  →  bash exam.sh check  →  ...
set -uo pipefail
source "$(cd "$(dirname "$0")/.." && pwd)/_lib/exam-lib.sh"

EXAM_TITLE="CKA 3강 실습 — 워크로드 배포와 관리"
EXAM_NQ=4

# ══════════════════════════════════════════════════════════════
exam_cleanup() {
  kubectl delete deployment web-app -n default --ignore-not-found &>/dev/null || true
  kubectl delete pod db-client -n default --ignore-not-found &>/dev/null || true
  kubectl delete configmap db-config -n default --ignore-not-found &>/dev/null || true
  kubectl delete cronjob date-printer -n default --ignore-not-found &>/dev/null || true
  kubectl get jobs -n default -o name 2>/dev/null | grep "date-printer" | xargs -r kubectl delete -n default &>/dev/null || true
  kubectl delete namespace monitoring --ignore-not-found &>/dev/null || true
  echo "  web-app / db-client / db-config / date-printer / monitoring ns 삭제"
}
exam_setup() { echo "  (미리 만들어둘 것 없음)"; }

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
# Q2 — ConfigMap + envFrom
# ══════════════════════════════════════════════════════════════
q2_title() { echo "ConfigMap injected as environment variables"; }
q2_text() { cat <<'EOF'
Create a ConfigMap named db-config in the default namespace with the keys
DB_HOST=mysql and DB_PORT=3306.

Then create a Pod named db-client (image busybox) that injects every key of
that ConfigMap as environment variables using envFrom.

  command   ["sh","-c","env | grep DB && sleep 3600"]

The Pod must be Running and both variables must be visible inside it.

Verify:
  kubectl exec db-client -- env | grep DB
EOF
}
q2_title_ko() { echo "ConfigMap 생성 + 파드에 환경변수로 주입"; }
q2_text_ko() { cat <<'EOF'
default 네임스페이스에 db-config ConfigMap 을 만드시오.
데이터: DB_HOST=mysql, DB_PORT=3306

그다음 db-client 파드(이미지 busybox)를 만들어 이 ConfigMap 전체를
envFrom 으로 환경변수에 주입하시오.

  command   ["sh","-c","env | grep DB && sleep 3600"]

파드는 Running 이어야 하고 두 환경변수가 파드 안에서 보여야 한다.

[확인]
  kubectl exec db-client -- env | grep DB
EOF
}
q2_grade() {
  check "ConfigMap db-config 존재" "kubectl get configmap db-config -n default"
  check_output "DB_HOST=mysql" \
    "kubectl get configmap db-config -n default -o jsonpath='{.data.DB_HOST}'" '^mysql$'
  check_output "DB_PORT=3306" \
    "kubectl get configmap db-config -n default -o jsonpath='{.data.DB_PORT}'" '^3306$'
  check "파드 db-client 존재" "kubectl get pod db-client -n default"
  wait_ready "db-client" default
  check_output "db-client Running" \
    "kubectl get pod db-client -n default -o jsonpath='{.status.phase}'" '^Running$'
  if kubectl get pod db-client -n default &>/dev/null; then
    check_output "파드 안에서 DB_HOST=mysql (실제 exec)" \
      "kubectl exec db-client -n default -- env 2>/dev/null" 'DB_HOST=mysql'
    check_output "파드 안에서 DB_PORT=3306 (실제 exec)" \
      "kubectl exec db-client -n default -- env 2>/dev/null" 'DB_PORT=3306'
    check_output "env 하나씩이 아니라 envFrom 으로 주입했는가" \
      "kubectl get pod db-client -n default -o jsonpath='{.spec.containers[0].envFrom[*].configMapRef.name}'" 'db-config'
  else
    check_result "파드 안에서 DB_HOST=mysql (실제 exec)" 1 "파드가 없음"
    check_result "파드 안에서 DB_PORT=3306 (실제 exec)" 1 "파드가 없음"
    check_result "envFrom 으로 주입" 1 "파드가 없음"
  fi
}
q2_hint() { cat <<'EOF'
kubectl create configmap db-config --from-literal=DB_HOST=mysql --from-literal=DB_PORT=3306

# 파드 YAML 뼈대를 뽑고 envFrom 을 넣는다
kubectl run db-client --image=busybox --restart=Never $do \
  -- sh -c 'env | grep DB && sleep 3600' > pod.yaml
#   spec.containers[0] 아래에:
#   envFrom:
#   - configMapRef:
#       name: db-config
EOF
}

# ══════════════════════════════════════════════════════════════
# Q3 — CronJob
# ══════════════════════════════════════════════════════════════
q3_title() { echo "CronJob that prints the date every minute"; }
q3_text() { cat <<'EOF'
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
q3_title_ko() { echo "매 분마다 date 를 출력하는 CronJob"; }
q3_text_ko() { cat <<'EOF'
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
q3_grade() {
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
q3_hint() { cat <<'EOF'
kubectl create cronjob date-printer --image=busybox --schedule='*/1 * * * *' -- date

# 1~2분 뒤
kubectl get job | grep date-printer
kubectl logs job/<생성된-job-이름>
EOF
}

# ══════════════════════════════════════════════════════════════
# Q4 — DaemonSet
# ══════════════════════════════════════════════════════════════
q4_title() { echo "DaemonSet in the monitoring namespace"; }
q4_text() { cat <<'EOF'
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
q4_title_ko() { echo "monitoring 네임스페이스에 DaemonSet 생성"; }
q4_text_ko() { cat <<'EOF'
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
q4_grade() {
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
q4_hint() { cat <<'EOF'
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

exam_main "$@"
