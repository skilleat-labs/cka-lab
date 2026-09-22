#!/usr/bin/env bash
# CKA 10강 실습 — Helm 과 Kustomize (순차 진행형)
set -uo pipefail
source "$(cd "$(dirname "$0")/.." && pwd)/_lib/exam-lib.sh"

EXAM_TITLE="CKA 10강 실습 — Helm (install · upgrade · rollback) · Kustomize"
EXAM_NQ=4

exam_cleanup() {
  if command -v helm &>/dev/null; then
    helm uninstall my-nginx &>/dev/null || true
  fi
  kubectl delete deployment,service -l app.kubernetes.io/instance=my-nginx -n default --ignore-not-found &>/dev/null || true
  kubectl delete deployment dev-web-app -n default --ignore-not-found &>/dev/null || true
  rm -rf /tmp/kustomize-lab 2>/dev/null || true
  echo "  helm release my-nginx, dev-web-app, /tmp/kustomize-lab 삭제"
}
exam_setup() {
  command -v helm &>/dev/null || echo "  [주의] helm 이 설치돼 있지 않습니다 — Q1~Q3 를 풀 수 없습니다"
  echo "  (인터넷이 필요합니다 — 차트를 내려받습니다)"
}

# ══════════════════════════════════════════════════════════════
q1_title() { echo "Add a repo and install a chart"; }
q1_text() { cat <<'EOF'
  1) add the chart repository
     name bitnami / url https://charts.bitnami.com/bitnami
  2) install the nginx chart as a release named my-nginx
     set service.type=NodePort

The release must show status "deployed".

Verify:
  helm list
  kubectl get svc -l app.kubernetes.io/instance=my-nginx
EOF
}
q1_title_ko() { echo "repo 추가 후 차트 설치"; }
q1_text_ko() { cat <<'EOF'
  1) 차트 저장소를 추가한다
     이름 bitnami / 주소 https://charts.bitnami.com/bitnami
  2) nginx 차트를 my-nginx 릴리스로 설치한다
     service.type=NodePort 로 설정

릴리스 상태가 deployed 여야 한다.

[확인]
  helm list
  kubectl get svc -l app.kubernetes.io/instance=my-nginx
EOF
}
q1_grade() {
  check "helm 이 설치돼 있다" "command -v helm"
  check_output "bitnami repo 가 등록됨" "helm repo list 2>/dev/null" 'bitnami'
  check_output "릴리스 my-nginx 가 있다" "helm list -A 2>/dev/null" 'my-nginx'
  check_output "상태가 deployed" "helm list -A 2>/dev/null | grep my-nginx" 'deployed'
  check_output "차트가 만든 Service 가 NodePort" \
    "kubectl get svc -l app.kubernetes.io/instance=my-nginx -n default -o jsonpath='{.items[0].spec.type}'" '^NodePort$'
}
q1_hint() { cat <<'EOF'
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update
helm install my-nginx bitnami/nginx --set service.type=NodePort
helm list
EOF
}

# ══════════════════════════════════════════════════════════════
q2_title() { echo "Upgrade the release"; }
q2_text() { cat <<'EOF'
Upgrade the my-nginx release so that it runs 3 replicas.

  helm upgrade with replicaCount=3

After the upgrade the release revision must be 2 or higher and three Pods
must be running.

Verify:
  helm history my-nginx
  kubectl get pods -l app.kubernetes.io/instance=my-nginx
EOF
}
q2_title_ko() { echo "릴리스 업그레이드"; }
q2_text_ko() { cat <<'EOF'
my-nginx 릴리스를 레플리카 3개로 업그레이드하시오.

  helm upgrade 로 replicaCount=3

업그레이드 후 릴리스 리비전이 2 이상이고 파드 3개가 떠야 한다.

[확인]
  helm history my-nginx
  kubectl get pods -l app.kubernetes.io/instance=my-nginx
EOF
}
q2_grade() {
  check_output "릴리스 리비전이 2 이상" \
    "helm list -A -o json 2>/dev/null | grep -o '\"revision\":\"[0-9]*\"' | head -1" '"[2-9]"'
  check_output "Deployment 의 replicas 가 3" \
    "kubectl get deployment -l app.kubernetes.io/instance=my-nginx -n default -o jsonpath='{.items[0].spec.replicas}'" '^3$'
  wait_ready "-l app.kubernetes.io/instance=my-nginx" default
  check_output "파드 3개가 Ready" \
    "kubectl get deployment -l app.kubernetes.io/instance=my-nginx -n default -o jsonpath='{.items[0].status.readyReplicas}'" '^3$'
}
q2_hint() { cat <<'EOF'
helm upgrade my-nginx bitnami/nginx --set replicaCount=3 --set service.type=NodePort
helm history my-nginx
kubectl get pods -l app.kubernetes.io/instance=my-nginx
EOF
}

# ══════════════════════════════════════════════════════════════
q3_title() { echo "Roll back the release"; }
q3_text() { cat <<'EOF'
Roll the my-nginx release back to revision 1.

  - check the revisions with helm history
  - roll back to revision 1

After the rollback there must be a new revision (3 or higher) and the
Deployment must be back to 1 replica.

Verify:
  helm history my-nginx
  kubectl get deployment -l app.kubernetes.io/instance=my-nginx
EOF
}
q3_title_ko() { echo "릴리스 롤백"; }
q3_text_ko() { cat <<'EOF'
my-nginx 릴리스를 리비전 1 로 롤백하시오.

  - helm history 로 리비전을 확인한다
  - 리비전 1 로 롤백한다

롤백하면 새 리비전(3 이상)이 생기고 Deployment 의 레플리카가 1 로
돌아와야 한다.

[확인]
  helm history my-nginx
  kubectl get deployment -l app.kubernetes.io/instance=my-nginx
EOF
}
q3_grade() {
  check_output "리비전이 3 이상 (롤백도 새 리비전이다)" \
    "helm list -A -o json 2>/dev/null | grep -o '\"revision\":\"[0-9]*\"' | head -1" '"[3-9]"'
  check_output "history 에 rollback 기록" "helm history my-nginx 2>/dev/null" 'Rollback|rollback'
  check_output "replicas 가 1 로 돌아왔다" \
    "kubectl get deployment -l app.kubernetes.io/instance=my-nginx -n default -o jsonpath='{.items[0].spec.replicas}'" '^1$'
}
q3_hint() { cat <<'EOF'
helm history my-nginx
helm rollback my-nginx 1
helm history my-nginx      # Rollback to 1 이라는 줄이 추가된다
EOF
}

# ══════════════════════════════════════════════════════════════
q4_title() { echo "Kustomize base and overlay"; }
q4_text() { cat <<'EOF'
Build a Kustomize directory under /tmp/kustomize-lab and apply it.

  base/deployment.yaml       a Deployment named web-app (nginx:1.24)
  base/kustomization.yaml    includes deployment.yaml as a resource
  overlays/dev/kustomization.yaml
                             refers to ../../base and sets namePrefix: dev-

Then apply the overlay:
  kubectl apply -k /tmp/kustomize-lab/overlays/dev/

The result must be a Deployment named dev-web-app.

Verify:
  kubectl get deployment dev-web-app
EOF
}
q4_title_ko() { echo "Kustomize base 와 overlay"; }
q4_text_ko() { cat <<'EOF'
/tmp/kustomize-lab 아래에 Kustomize 디렉터리를 만들고 적용하시오.

  base/deployment.yaml       web-app Deployment (nginx:1.24)
  base/kustomization.yaml    deployment.yaml 을 resources 로 포함
  overlays/dev/kustomization.yaml
                             ../../base 를 참조하고 namePrefix: dev- 설정

그다음 overlay 를 적용한다:
  kubectl apply -k /tmp/kustomize-lab/overlays/dev/

결과로 dev-web-app Deployment 가 만들어져야 한다.

[확인]
  kubectl get deployment dev-web-app
EOF
}
q4_grade() {
  check "base/kustomization.yaml 존재" "test -f /tmp/kustomize-lab/base/kustomization.yaml"
  check "base/deployment.yaml 존재" "test -f /tmp/kustomize-lab/base/deployment.yaml"
  check "overlays/dev/kustomization.yaml 존재" "test -f /tmp/kustomize-lab/overlays/dev/kustomization.yaml"
  check_output "overlay 에 namePrefix: dev-" \
    "cat /tmp/kustomize-lab/overlays/dev/kustomization.yaml 2>/dev/null" 'namePrefix:\s*dev-'
  check_output "overlay 가 base 를 참조" \
    "cat /tmp/kustomize-lab/overlays/dev/kustomization.yaml 2>/dev/null" '\.\./\.\./base|resources'
  check "Deployment dev-web-app 이 생성됨" "kubectl get deployment dev-web-app -n default"
  check_output "이미지 nginx:1.24" \
    "kubectl get deployment dev-web-app -n default -o jsonpath='{.spec.template.spec.containers[0].image}'" 'nginx:1\.24'
}
q4_hint() { cat <<'EOF'
mkdir -p /tmp/kustomize-lab/base /tmp/kustomize-lab/overlays/dev
kubectl create deployment web-app --image=nginx:1.24 $do > /tmp/kustomize-lab/base/deployment.yaml

cat > /tmp/kustomize-lab/base/kustomization.yaml <<'YAML'
resources:
  - deployment.yaml
YAML

cat > /tmp/kustomize-lab/overlays/dev/kustomization.yaml <<'YAML'
resources:
  - ../../base
namePrefix: dev-
YAML

kubectl apply -k /tmp/kustomize-lab/overlays/dev/
EOF
}

exam_main "$@"
