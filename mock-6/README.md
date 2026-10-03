# Mock Exam 6 — 2026 출제 주제 20분 점검 (강사용)

> **문제만 보려면 `QUESTIONS.txt`.** 이 파일에는 정답이 들어 있다.
>
> **한 문제씩 풀기:** `bash exam.sh start` → 풀고 → `bash exam.sh check`. 끝나면 `bash exam.sh clean`.

## 목적

2026 합격 후기에서 확인된 **출제 주제 13선**(`고객발송/CKA_출제주제13선_풀이`) 중 5개를 **20분 안에** 푸는지 본다.
문제당 4분이다. 실제 시험(문제당 6~8분)보다 빠듯하게 잡았다 — 여기서 20분 안에 끝나면 시험장에서 여유가 생긴다.

| 문항 | 13선 번호 | 주제 | 출제영역 | 함정 |
|------|-----------|------|----------|------|
| Q1 | 01 | PriorityClass 생성 · Deployment 연결 | Workloads & Scheduling | "가장 높은 값 - 1" 을 직접 찾아야 한다. `spec` 이 아니라 `spec.template.spec` |
| Q2 | 02 | Helm template (설치 없이 렌더링) | Cluster Architecture | argo-cd 차트는 CRD 를 `templates/` 에 둬서 **`--skip-crds` 만으로는 안 빠진다** |
| Q3 | 08 | 네이티브 사이드카 + 볼륨 | Workloads & Scheduling | `initContainers` + `restartPolicy: Always` |
| Q4 | 09 | NetworkPolicy 기본 거부 + 선택 허용 | Services & Networking | 다른 네임스페이스의 같은 레이블 파드는 막혀야 한다 |
| Q5 | 10 | 기본 StorageClass | Storage | 기존 기본 클래스를 **해제**해야 "유일한 기본" 이 된다. PVC 는 그다음에 |

뺀 주제와 이유: 패키지 설치(03, `.deb` 없음) · CNI 설치(07, 클러스터를 망가뜨려야 함) · etcd 복원(05, 되돌릴 수 없음·20분 초과) · Gateway 전환(13, 컨트롤러 없음) · HPA·NodePort·PV/PVC·Pod 목록(04·06·11·12, 다른 모의고사에 이미 많다).

## 환경

`exam.sh start` 가 준비하는 것:

| 문항 | 네임스페이스 | 미리 만드는 것 |
|------|--------------|----------------|
| Q1 | `analytics` | PriorityClass `team-high`(10000) · `team-mid`(5000), Deployment `report-gen` (2 replicas) |
| Q2 | — | 없음. helm 이 없으면 설치 명령을 안내한다. **VM 에서 인터넷이 돼야 한다** |
| Q3 | `edge` | Deployment `audit-api` — `/var/log/audit/api.log` 에 기록, emptyDir `audit-logs` |
| Q4 | `payments` · `partner` | `ledger` Deployment+Service, 테스트 파드 `payments/checkout` · `payments/scanner` · `partner/checkout` |
| Q5 | `warehouse` | StorageClass `legacy-std` (기본으로 지정된 상태) |

- 제한시간 20분. `EXAM_LIMIT_MIN=0 bash exam.sh start` 로 풀면 무제한 연습.
- Q1 의 기대값은 **채점 시점에 계산**한다(system-* 과 report-urgent 를 뺀 최댓값 - 1). 다른 실습이 남긴 PriorityClass 가 있어도 그 값 기준으로 맞게 채점된다.
- Q5 는 클러스터 전체 설정(기본 StorageClass)을 바꾼다. **`clean` 을 꼭 돌릴 것** — `legacy-std`·`fast-local` 을 모두 지워 원래 상태(기본 클래스 없음)로 돌린다.
- Q4 는 CNI 가 NetworkPolicy 를 지원해야 한다 (Cilium 이면 된다).

## 정답

```bash
# Q1 — system-* 을 빼면 가장 높은 값은 team-high 10000 → 9999
kubectl get priorityclass --sort-by=.value
kubectl create priorityclass report-urgent --value=9999 --description="report jobs"
kubectl -n analytics patch deployment report-gen \
  -p '{"spec":{"template":{"spec":{"priorityClassName":"report-urgent"}}}}'
kubectl -n analytics rollout status deployment report-gen
kubectl -n analytics get pods -l app=report-gen -o custom-columns=NAME:.metadata.name,PRIORITY:.spec.priority

# Q2
helm repo add argo https://argoproj.github.io/argo-helm && helm repo update
helm template cd argo/argo-cd --version 7.7.0 -n gitops \
  --skip-crds --set crds.install=false > /tmp/mock6-argocd.yaml
grep -c 'kind: CustomResourceDefinition' /tmp/mock6-argocd.yaml      # 0

# Q3
kubectl -n edge edit deployment audit-api
#   spec.template.spec 아래에
#   initContainers:
#     - name: audit-shipper
#       image: busybox:1.36
#       restartPolicy: Always
#       command: ["sh", "-c", "tail -F /var/log/audit/api.log"]
#       volumeMounts:
#         - name: audit-logs
#           mountPath: /var/log/audit
kubectl -n edge logs deploy/audit-api -c audit-shipper --tail=3

# Q4
cat <<'YAML' | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: deny-all-ingress, namespace: payments }
spec:
  podSelector: {}
  policyTypes: [Ingress]
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata: { name: allow-checkout, namespace: payments }
spec:
  podSelector: { matchLabels: { app: ledger } }
  policyTypes: [Ingress]
  ingress:
    - from: [ { podSelector: { matchLabels: { app: checkout } } } ]
      ports: [ { protocol: TCP, port: 80 } ]
YAML

# Q5 — 순서가 중요하다: 기본 클래스를 바꾼 '뒤에' PVC
cat <<'YAML' | kubectl apply -f -
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: fast-local
  annotations: { storageclass.kubernetes.io/is-default-class: "true" }
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: WaitForFirstConsumer
reclaimPolicy: Retain
YAML
kubectl patch storageclass legacy-std \
  -p '{"metadata":{"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'
cat <<'YAML' | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata: { name: scratch, namespace: warehouse }
spec:
  accessModes: [ReadWriteOnce]
  resources: { requests: { storage: 1Gi } }
YAML
kubectl -n warehouse get pvc scratch      # Pending (WaitForFirstConsumer) 이 정상
```

## 자주 틀리는 곳

| 문항 | 실수 | 채점에서 보이는 것 |
|------|------|-------------------|
| Q1 | `spec.priorityClassName` 에 넣음 (Deployment 에는 그런 필드가 없다) | 템플릿 항목 FAIL |
| Q1 | Deployment 를 지우고 새로 만듦 | 통과는 되지만 지문 위반 — 리포트의 시간 기록으로 확인 |
| Q2 | `--skip-crds` 만 줌 | "CRD 0개" 5점 FAIL (현재 3개) |
| Q2 | `helm install` 로 설치함 | "설치하지 않았다" FAIL |
| Q3 | `containers` 에 추가 (일반 사이드카) | initContainers · restartPolicy FAIL |
| Q4 | `from` 에 `namespaceSelector: {}` 를 함께 씀 | partner/checkout 차단 4점 FAIL |
| Q5 | legacy-std 를 해제하지 않음 | "기본이 하나뿐" FAIL, PVC 에 legacy-std 가 붙을 수 있음 |
| Q5 | PVC 를 먼저 만듦 | PVC storageClassName 이 legacy-std → FAIL. PVC 는 고칠 수 없으니 지우고 다시 |

## 검증 상태

- 문법(`bash -n`)과 배점 합계(문항당 20점)는 확인했다.
- Q2 채점 패턴은 argo-cd 7.7.0 실제 렌더링 결과로 확인했다 (`--skip-crds` 만: CRD 3개 / `--set crds.install=false` 추가: 0개).
- **VM 클러스터에서 start → 풀이 → check → clean 전체 흐름은 아직 돌려 보지 않았다.**
