#!/usr/bin/env bash
# CKA 10강 실습 — Helm 과 Kustomize (순차 진행형)
set -uo pipefail
source "$(cd "$(dirname "$0")/.." && pwd)/_lib/exam-lib.sh"

EXAM_TITLE="CKA 10강 실습 — Helm (install · upgrade · rollback) · Kustomize"
EXAM_NQ=5

exam_cleanup() {
  if command -v helm &>/dev/null; then
    helm uninstall my-nginx &>/dev/null || true
  fi
  kdel deployment,service -l app.kubernetes.io/instance=my-nginx -n default
  kdel deployment dev-web-app -n default
  rm -rf /tmp/kustomize-lab /tmp/argocd.yaml 2>/dev/null || true
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

# ══════════════════════════════════════════════════════════════
q5_title() { echo "Render a chart without installing it"; }
q5_text() { cat <<'EOF'
Sometimes you need the manifests a chart would produce, without touching
the cluster — for review, for GitOps, or to install the CRDs separately.

  1) add the Helm repository
       name  argo
       url   https://argoproj.github.io/argo-helm

  2) render the chart argo/argo-cd WITHOUT installing it
       release name   argocd
       namespace      argocd
       CRDs           must NOT be in the output
       save it to     /tmp/argocd.yaml

Do not install the chart into the cluster.

Verify:
  head -5 /tmp/argocd.yaml
  grep -c CustomResourceDefinition /tmp/argocd.yaml     -> 0
  helm list -A                                          -> no argocd release
EOF
}
q5_title_ko() { echo "설치하지 않고 매니페스트만 뽑기"; }
q5_text_ko() { cat <<'EOF'
차트가 만들어 낼 매니페스트만 필요할 때가 있다. 클러스터는 건드리지 않고
검토하거나, GitOps 로 넘기거나, CRD 만 따로 설치하려는 경우다.

  1) Helm 저장소를 추가한다
       이름  argo
       주소  https://argoproj.github.io/argo-helm

  2) argo/argo-cd 차트를 설치하지 말고 렌더링만 한다
       릴리스 이름   argocd
       네임스페이스  argocd
       CRD           결과에 들어가면 안 된다
       저장 경로     /tmp/argocd.yaml

클러스터에 설치하지 않는다.

[확인]
  head -5 /tmp/argocd.yaml
  grep -c CustomResourceDefinition /tmp/argocd.yaml     → 0
  helm list -A                                          → argocd 릴리스 없음
EOF
}
q5_grade() {
  check "helm 이 설치돼 있다" "command -v helm"
  check_output "argo 저장소가 추가됐다" "helm repo list 2>/dev/null" 'argoproj\.github\.io/argo-helm'
  check "/tmp/argocd.yaml 이 있다" "test -s /tmp/argocd.yaml"
  check_output "렌더링 결과다 (쿠버네티스 매니페스트)" "cat /tmp/argocd.yaml 2>/dev/null" '^kind:|^apiVersion:'
  check_output "argo-cd 차트의 리소스가 들어 있다" "cat /tmp/argocd.yaml 2>/dev/null" 'argocd'
  # CRD 가 빠졌는지 — --skip-crds 를 줬는지 보는 핵심 항목
  local crd; crd=$(grep -c 'kind: CustomResourceDefinition' /tmp/argocd.yaml 2>/dev/null)
  crd="${crd//[^0-9]/}"; crd="${crd:-0}"
  check_result "CRD 가 빠져 있다 (--skip-crds)" \
    "$([[ "$crd" == "0" ]] && echo 0 || echo 1)" "CustomResourceDefinition ${crd}개가 들어 있다" 2
  # 설치는 하지 말라고 했다
  local inst; inst=$(helm list -A -q 2>/dev/null | grep -cx argocd)
  inst="${inst//[^0-9]/}"; inst="${inst:-0}"
  check_result "클러스터에 설치하지는 않았다" \
    "$([[ "$inst" == "0" ]] && echo 0 || echo 1)" "argocd 릴리스가 설치돼 있다 — template 만 하면 된다"
}
q5_hint() { cat <<'EOF'
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

helm template argocd argo/argo-cd \
  --namespace argocd \
  --skip-crds > /tmp/argocd.yaml

# template 은 클러스터에 아무것도 만들지 않는다. 결과를 화면(또는 파일)로 뱉을 뿐이다.
# --skip-crds 를 빼면 CustomResourceDefinition 이 함께 나온다.
# 특정 버전이 필요하면  --version 8.8.3  처럼 붙인다.
EOF
}

exam_main "$@"
