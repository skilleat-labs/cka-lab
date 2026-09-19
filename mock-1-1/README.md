# Mock Exam 1-1 — mock-1 변형판 (강사용)

> **한 문제씩 풀기:** `bash exam.sh start` → 풀고 → `bash exam.sh check` (만점이면 자동으로 다음 문제). 진행 현황 `bash exam.sh status`.
>

> **문제만 보려면 `QUESTIONS.txt`.** 이 파일에는 정답이 들어 있다.

mock-1 과 **같은 7가지 유형**이지만 이름·이미지·포트·접근모드·네임스페이스가 전부 다르다.
mock-1 정답을 메모해뒀다가 붙여넣으면 틀리도록 만들었다. "유형을 익혔는가"와 "답을 외웠는가"를 구분하는 용도.

## mock-1 과 달라진 점 (함정)

| 문제 | mock-1 | mock-1-1 | 붙여넣기하면 |
|------|--------|----------|-------------|
| 공통 | `default` | **`retail`** 네임스페이스 | `-n retail` 없으면 전부 FAIL |
| Q1 | nginx:1.24 / replicas 3 | **nginx:1.25 / replicas 4** / port 80 | 이미지·개수 불일치 |
| Q2 | port 80 | **port 8080 → targetPort 80** | `expose --port=80` 하면 FAIL |
| Q3 | APP_ENV/APP_PORT, busybox | **APP_MODE/APP_PORT**, busybox:1.36, sleep 7200 | 값 불일치 |
| Q4 | 500Mi RWO, sc `manual` | **1Gi RWX**, sc **`local-manual`** | RWO 로 만들면 Bound 안 됨 |
| Q5 | pods get,list | **deployments**(apps) get,list,**watch** + pods 는 **no** 여야 함 | 리소스·동사 불일치, 과잉 권한이면 감점 |
| Q6 | worker-1 | **worker-2** | 다른 노드 |
| Q7 | `nginx:broken` → latest | `nginz:1.24`(저장소 오타) → **nginx:1.24** | latest 로 고치면 12점 감점 |

## 정답

```bash
# Q1
kubectl create deployment store-front --image=nginx:1.25 --replicas=4 --port=80 -n retail

# Q2 — port 와 targetPort 가 다르다
kubectl expose deployment store-front --name=store-svc --port=8080 --target-port=80 -n retail

# Q3
kubectl create configmap store-config -n retail --from-literal=APP_MODE=staging --from-literal=APP_PORT=9090
kubectl run store-cfg -n retail --image=busybox:1.36 --dry-run=client -o yaml --command -- sleep 7200 > store-cfg.yaml
# spec.containers[0] 에 추가:
#   envFrom:
#   - configMapRef:
#       name: store-config
kubectl apply -f store-cfg.yaml

# Q4
cat <<'YAML' | kubectl apply -f -
apiVersion: v1
kind: PersistentVolume
metadata:
  name: report-pv
spec:
  capacity:
    storage: 1Gi
  accessModes: ["ReadWriteMany"]
  storageClassName: local-manual
  hostPath:
    path: /tmp/report-data
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: report-pvc
  namespace: retail
spec:
  accessModes: ["ReadWriteMany"]
  storageClassName: local-manual
  resources:
    requests:
      storage: 1Gi
YAML

# Q5 — --resource=deployments 로 주면 apiGroup apps 가 자동으로 붙는다
kubectl create serviceaccount deploy-sa -n retail
kubectl create role deploy-reader --verb=get,list,watch --resource=deployments -n retail
kubectl create rolebinding deploy-reader-rb --role=deploy-reader --serviceaccount=retail:deploy-sa -n retail

# Q6
kubectl drain worker-2 --ignore-daemonsets --delete-emptydir-data
kubectl uncordon worker-2

# Q7 — image 필드는 실행 중 수정 가능
kubectl set image pod/web-broken web-broken=nginx:1.24 -n retail
# 또는 kubectl edit pod web-broken -n retail
```

## 채점 배점

mock-1 과 동일: 15 / 10 / 10 / 15 / 15 / 10 / 25 = 100. 합격선 66.

Q5 에 "pods 는 조회 불가" 항목(2점)이 추가됐다. `--resource=pods,deployments` 처럼 과잉 권한을 주면 감점된다 — 최소 권한 원칙.

## 정리

```bash
kubectl delete namespace retail
kubectl delete pv report-pv
```
