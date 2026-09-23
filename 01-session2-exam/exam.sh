#!/usr/bin/env bash
# CKA 2세션 시험 — 순차 진행형
# 사용법: bash exam.sh start → 풀고 → bash exam.sh check → ...
set -uo pipefail
source "$(cd "$(dirname "$0")/.." && pwd)/_lib/exam-lib.sh"

EXAM_TITLE="CKA 2세션 시험 — 네임스페이스 · NodePort · ConfigMap · 롤아웃"
EXAM_NQ=3

exam_cleanup() {
  for ns in ops app; do
    if kubectl get namespace "$ns" &>/dev/null; then
      echo "  네임스페이스 $ns 삭제 중... (수십 초 걸릴 수 있음)"
      kubectl delete namespace "$ns" --wait=true &>/dev/null || true
    fi
  done
  kdel deployment cache-app -n default
  echo "  ops / app 네임스페이스 삭제"
}
exam_setup() { echo "  (네임스페이스는 학생이 직접 만든다)"; }

# ══════════════════════════════════════════════════════════════
q1_title() { echo "Namespace, Deployment and NodePort Service"; }
q1_text() { cat <<'EOF'
Create a namespace named ops.

In the ops namespace, create a Deployment named cache-app using image
nginx:1.24 with 2 replicas, exposing container port 80.

Then expose it with a NodePort Service named cache-svc on port 80 ->
targetPort 80, using nodePort 30090.

Conditions:
  namespace       ops  (you must create it)
  Deployment      cache-app / nginx:1.24 / replicas 2 / port 80
  Service         cache-svc / NodePort / 80 -> 80 / nodePort 30090
  Every resource must live in ops, not in default.

Verify:
  kubectl get deployment,svc -n ops
  kubectl get endpoints cache-svc -n ops
  curl http://<NodeIP>:30090
EOF
}
q1_title_ko() { echo "네임스페이스 지정 · Deployment · NodePort"; }
q1_text_ko() { cat <<'EOF'
Create a namespace named ops.

In the ops namespace, create a Deployment named cache-app using image
nginx:1.24 with 2 replicas, exposing container port 80.

Then expose it with a NodePort Service named cache-svc on port 80 →
targetPort 80, using nodePort 30090.

[조건]
  namespace       ops  (직접 생성)
  Deployment      cache-app / nginx:1.24 / replicas 2 / port 80
  Service         cache-svc / NodePort / 80 → 80 / nodePort 30090
  모든 리소스는 default 가 아니라 ops 네임스페이스에 있어야 한다

[확인]
  kubectl get deployment,svc -n ops
  kubectl get endpoints cache-svc -n ops
  curl http://<NodeIP>:30090
EOF
}
q1_hint() { cat <<'EOF'
kubectl create namespace ops
kubectl create deployment cache-app --image=nginx:1.24 --replicas=2 --port=80 -n ops
kubectl expose deployment cache-app --name=cache-svc --port=80 --target-port=80 --type=NodePort -n ops
# expose 는 nodePort 값을 지정할 수 없다 → patch
kubectl patch svc cache-svc -n ops -p '{"spec":{"ports":[{"port":80,"targetPort":80,"nodePort":30090}]}}'
EOF
}
q1_grade() {
  check "namespace ops 가 존재한다" "kubectl get namespace ops"
  check "cache-app Deployment 가 ops 네임스페이스에 존재한다" "kubectl get deployment cache-app -n ops"
  check_output "cache-app 이미지가 nginx:1.24 이다" \
    "kubectl get deployment cache-app -n ops -o jsonpath='{.spec.template.spec.containers[0].image}'" "^nginx:1\.24$"
  check_output "cache-app replicas 가 2 이다" \
    "kubectl get deployment cache-app -n ops -o jsonpath='{.spec.replicas}'" "^2$"
  wait_ready "-l app=cache-app" ops || true
  check_output "cache-app 파드 2개가 모두 Ready 이다" \
    "kubectl get deployment cache-app -n ops -o jsonpath='{.status.readyReplicas}'" "^2$"
  check_output "cache-app containerPort 80 이 노출되어 있다" \
    "kubectl get deployment cache-app -n ops -o jsonpath='{.spec.template.spec.containers[0].ports[0].containerPort}'" "^80$"
  local ok=1 note=""
  if kubectl get deployment cache-app -n ops &>/dev/null && ! kubectl get deployment cache-app -n default &>/dev/null; then ok=0
  elif kubectl get deployment cache-app -n default &>/dev/null; then note="default 에도 있음 — -n ops 누락"
  else note="ops 에 없음"; fi
  check_result "cache-app 이 ops 네임스페이스에만 존재한다" "$ok" "$note"
  check "cache-svc Service 가 ops 네임스페이스에 존재한다" "kubectl get service cache-svc -n ops"
  check_output "cache-svc 타입이 NodePort 이다" \
    "kubectl get service cache-svc -n ops -o jsonpath='{.spec.type}'" "^NodePort$"
  check_output "cache-svc port 가 80 이다" \
    "kubectl get service cache-svc -n ops -o jsonpath='{.spec.ports[0].port}'" "^80$"
  check_output "cache-svc targetPort 가 80 이다" \
    "kubectl get service cache-svc -n ops -o jsonpath='{.spec.ports[0].targetPort}'" "^80$"
  check_output "cache-svc nodePort 가 30090 이다" \
    "kubectl get service cache-svc -n ops -o jsonpath='{.spec.ports[0].nodePort}'" "^30090$"
  local ep; ep=$(kubectl get endpoints cache-svc -n ops -o jsonpath='{.subsets[*].addresses[*].ip}' 2>/dev/null | wc -w | tr -d ' ')
  check_result "cache-svc Endpoints 에 파드 IP 2개가 등록되어 있다" "$([[ "$ep" == "2" ]] && echo 0 || echo 1)" "실제: ${ep}개 — selector 확인"
}

# ══════════════════════════════════════════════════════════════
q2_title() { echo "ConfigMap as environment variables and as a volume"; }
q2_text() { cat <<'EOF'
Create a namespace named app.

In the app namespace, create a ConfigMap named app-config with keys
APP_ENV=production and LOG_LEVEL=info.

Then create a Pod named config-pod (image busybox:1.36, command sleep 3600)
that consumes the ConfigMap in both ways:
  (a) all keys injected as environment variables
  (b) the same ConfigMap mounted as a volume at /etc/app-config

Conditions:
  namespace       app  (you must create it)
  ConfigMap       app-config / APP_ENV=production / LOG_LEVEL=info
  Pod             config-pod / busybox:1.36 / sleep 3600
  injection       envFrom (all keys)  AND  volume mount at /etc/app-config

Verify:
  kubectl exec config-pod -n app -- env | grep -E 'APP_ENV|LOG_LEVEL'
  kubectl exec config-pod -n app -- cat /etc/app-config/LOG_LEVEL
EOF
}
q2_title_ko() { echo "ConfigMap — env + 볼륨 마운트"; }
q2_text_ko() { cat <<'EOF'
Create a namespace named app.

In the app namespace, create a ConfigMap named app-config with keys
APP_ENV=production and LOG_LEVEL=info.

Then create a Pod named config-pod (image busybox:1.36, command sleep 3600)
that consumes the ConfigMap in both ways:
  (a) all keys injected as environment variables
  (b) the same ConfigMap mounted as a volume at /etc/app-config

[조건]
  namespace       app  (직접 생성)
  ConfigMap       app-config / APP_ENV=production / LOG_LEVEL=info
  Pod             config-pod / busybox:1.36 / sleep 3600
  주입 방식       envFrom 전체 주입  +  볼륨 마운트 /etc/app-config

[확인]
  kubectl exec config-pod -n app -- env | grep -E 'APP_ENV|LOG_LEVEL'
  kubectl exec config-pod -n app -- cat /etc/app-config/LOG_LEVEL
EOF
}
q2_hint() { cat <<'EOF'
kubectl create namespace app
kubectl create configmap app-config -n app --from-literal=APP_ENV=production --from-literal=LOG_LEVEL=info

# 파드는 envFrom + volume 둘 다 필요 → YAML
apiVersion: v1
kind: Pod
metadata: { name: config-pod, namespace: app }
spec:
  containers:
  - name: config-pod
    image: busybox:1.36
    command: ["sleep", "3600"]
    envFrom:
    - configMapRef: { name: app-config }
    volumeMounts:
    - { name: config-vol, mountPath: /etc/app-config }
  volumes:
  - name: config-vol
    configMap: { name: app-config }
EOF
}
q2_grade() {
  check "namespace app 이 존재한다" "kubectl get namespace app"
  check "app-config ConfigMap 이 app 네임스페이스에 존재한다" "kubectl get configmap app-config -n app"
  check_output "app-config 에 APP_ENV=production 이 있다" \
    "kubectl get configmap app-config -n app -o jsonpath='{.data.APP_ENV}'" "^production$"
  check_output "app-config 에 LOG_LEVEL=info 가 있다" \
    "kubectl get configmap app-config -n app -o jsonpath='{.data.LOG_LEVEL}'" "^info$"
  check "config-pod Pod 가 app 네임스페이스에 존재한다" "kubectl get pod config-pod -n app"
  wait_ready "config-pod" app || true
  check_output "config-pod 가 Running 상태이다" \
    "kubectl get pod config-pod -n app -o jsonpath='{.status.phase}'" "^Running$"
  check_output "config-pod 안에서 APP_ENV=production 환경변수가 보인다 (실제 exec 검증)" \
    "kubectl exec config-pod -n app -- env 2>/dev/null" "^APP_ENV=production$"
  check_output "config-pod 안에서 LOG_LEVEL=info 환경변수가 보인다 (실제 exec 검증)" \
    "kubectl exec config-pod -n app -- env 2>/dev/null" "^LOG_LEVEL=info$"
  check_output "config-pod 의 /etc/app-config 에 ConfigMap 이 마운트되어 있다 (실제 exec 검증)" \
    "kubectl exec config-pod -n app -- ls /etc/app-config 2>/dev/null" "APP_ENV"
  check_output "/etc/app-config/LOG_LEVEL 파일 내용이 info 이다 (실제 exec 검증)" \
    "kubectl exec config-pod -n app -- cat /etc/app-config/LOG_LEVEL 2>/dev/null" "^info$"
}

# ══════════════════════════════════════════════════════════════
q3_title() { echo "Scale, rolling update and rollback"; }
q3_text() { cat <<'EOF'
In the app namespace, create a Deployment named frontend using image
nginx:1.24 with 2 replicas.

Then perform the following operations in order:
  (a) scale the Deployment to 4 replicas
  (b) perform a rolling update to image nginx:1.25 and wait until it completes
  (c) roll back to the previous revision

After the rollback the Deployment must run nginx:1.24 with 4 replicas.

Conditions:
  namespace       app  (reuse the one from the previous task)
  Deployment      frontend / initially nginx:1.24 / replicas 2
  order           (a) replicas 4  ->  (b) nginx:1.25  ->  (c) rollback
  final state     image nginx:1.24 / replicas 4 / all Ready
  You must actually go through all three steps. Creating it with 1.24 and
  only scaling does not count.

Verify:
  kubectl get deployment frontend -n app
  kubectl rollout history deployment/frontend -n app
  kubectl get rs -n app
EOF
}
q3_title_ko() { echo "Deployment 스케일 · 롤링 업데이트 · 롤백"; }
q3_text_ko() { cat <<'EOF'
In the app namespace, create a Deployment named frontend using image
nginx:1.24 with 2 replicas.

Then perform the following operations in order:
  (a) scale the Deployment to 4 replicas
  (b) perform a rolling update to image nginx:1.25 and wait until it completes
  (c) roll back to the previous revision

After the rollback, the Deployment must be running nginx:1.24 with 4 replicas.

[조건]
  namespace       app  (Q2 에서 만든 것 재사용)
  Deployment      frontend / 최초 nginx:1.24 / replicas 2
  순서            (a) replicas 4  →  (b) nginx:1.25  →  (c) 롤백
  최종 상태       이미지 nginx:1.24 / replicas 4 / 전부 Ready
  세 단계를 실제로 거쳐야 한다. 처음부터 1.24 로 두고 스케일만 하면 오답.

[확인]
  kubectl get deployment frontend -n app
  kubectl rollout history deployment/frontend -n app
  kubectl get rs -n app
EOF
}
q3_hint() { cat <<'EOF'
kubectl create deployment frontend --image=nginx:1.24 --replicas=2 -n app
kubectl scale deployment frontend --replicas=4 -n app
kubectl set image deployment/frontend nginx=nginx:1.25 -n app
kubectl rollout status deployment/frontend -n app
kubectl rollout undo deployment/frontend -n app
kubectl rollout status deployment/frontend -n app
EOF
}
q3_grade() {
  check "frontend Deployment 가 app 네임스페이스에 존재한다" "kubectl get deployment frontend -n app"
  check_output "frontend replicas 가 4 이다 (kubectl scale)" \
    "kubectl get deployment frontend -n app -o jsonpath='{.spec.replicas}'" "^4$"
  wait_ready "-l app=frontend" app || true
  check_output "frontend 파드 4개가 모두 Ready 이다" \
    "kubectl get deployment frontend -n app -o jsonpath='{.status.readyReplicas}'" "^4$"
  check_output "롤백 후 최종 이미지가 nginx:1.24 이다" \
    "kubectl get deployment frontend -n app -o jsonpath='{.spec.template.spec.containers[0].image}'" "^nginx:1\.24$"
  check_output "nginx:1.25 로 업데이트한 이력이 남아 있다 (이전 ReplicaSet 존재)" \
    "kubectl get rs -n app -o jsonpath='{range .items[*]}{.spec.template.spec.containers[0].image}{\"\\n\"}{end}'" "^nginx:1\.25$"
  local rev; rev=$(kubectl get deployment frontend -n app -o jsonpath='{.metadata.annotations.deployment\.kubernetes\.io/revision}' 2>/dev/null || echo "0")
  check_result "생성 → 업데이트 → 롤백을 모두 거쳤다 (revision ≥ 3)" \
    "$([[ "$rev" =~ ^[0-9]+$ && "$rev" -ge 3 ]] && echo 0 || echo 1)" "현재 revision: ${rev:-0}"
  local img; img=$(kubectl get pods -n app -l app=frontend -o jsonpath='{range .items[*]}{.spec.containers[0].image}{"\n"}{end}' 2>/dev/null | sort -u | tr '\n' ' ' | sed 's/ *$//')
  check_result "현재 실행 중인 파드가 모두 nginx:1.24 이다" "$([[ "$img" == "nginx:1.24" ]] && echo 0 || echo 1)" "실제: '${img:-없음}'"
}

exam_main "$@"
