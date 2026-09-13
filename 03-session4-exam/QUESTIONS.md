# CKA 4세션 시험 — 문제지

**권장 제한 시간 30분 · 총 33항목**

문제를 풀기 전에 아래를 실행해 환경을 준비한다.

```bash
bash exam-start.sh
```

다 풀었으면 채점한다.

```bash
bash verify.sh
```

---

## 이미 준비되어 있는 것

| 항목 | 내용 |
|------|------|
| 네임스페이스 | `api` |
| StorageClass | `api-storage` |
| PersistentVolume | 2Gi 짜리 3개 (`api-pv-1~3`) |
| Deployment | `api-worker` (replicas 2, 컨테이너 이름 `worker`, 리소스 제한 없음) — Q2 에서 수정할 대상 |

---

## Q1. PVC 를 만들고 Deployment YAML 에서 바로 연결

A StorageClass named **`api-storage`** already exists in the cluster.

In the `api` namespace, create a PersistentVolumeClaim named **`api-data`** that requests **1Gi** with access mode **ReadWriteOnce** using that StorageClass.

Then create a Deployment named **`api-server`** (image **`nginx:1.24`**, **1** replica) whose manifest **already includes** the PVC as a volume, mounted at **`/var/www/data`**.

The Deployment must be created **with the volume from the start** — do not add it afterwards.

**조건**

- PVC: `api-data` / storageClassName `api-storage` / 1Gi / ReadWriteOnce
- Deployment: `api-server` / `nginx:1.24` / replicas 1
- Deployment YAML 안에 `volumes` + `volumeMounts` 를 **처음부터** 포함해 생성
- mountPath: `/var/www/data`
- 주의: Deployment 를 먼저 만들고 나중에 볼륨을 추가하면 오답 처리된다 (채점 스크립트가 revision 이 1 인지 확인한다)

**확인용 명령**

```bash
kubectl get pvc api-data -n api
kubectl rollout history deployment/api-server -n api
kubectl exec -n api deploy/api-server -- df -h /var/www/data
```

---

## Q2. 기존 Deployment 에 Requests / Limits 추가

A Deployment named **`api-worker`** already exists in the `api` namespace with **2** replicas and **no** resource requests or limits.

Update it so that its container (**`worker`**) has:

- requests: cpu **100m**, memory **128Mi**
- limits: cpu **200m**, memory **256Mi**

All pods must be rolled out and Ready with the new resource settings.

**조건**

- 대상: `api` 네임스페이스의 `api-worker` Deployment (이미 존재)
- requests: cpu 100m / memory 128Mi
- limits: cpu 200m / memory 256Mi
- 변경 후 파드 2개가 모두 새 설정으로 Ready 여야 한다

**확인용 명령**

```bash
kubectl get deployment api-worker -n api -o jsonpath='{.spec.template.spec.containers[0].resources}'
kubectl get pods -n api -l app=api-worker -o jsonpath='{.items[*].status.qosClass}'
kubectl describe pod -n api -l app=api-worker | grep -A4 Limits
```

---

## Q3. 조건에 맞는 Liveness / Readiness Probe 작성

In the `api` namespace, create a Pod named **`health-pod`** using image **`nginx:1.24`** with the following probes configured on its container:

- **livenessProbe**: HTTP GET on path `/` port `80`, initialDelaySeconds **5**, periodSeconds **10**, failureThreshold **3**
- **readinessProbe**: HTTP GET on path `/` port `80`, initialDelaySeconds **3**, periodSeconds **5**

The Pod must become **Ready** and must **not restart**.

**조건**

- Pod: `health-pod` / `nginx:1.24` / namespace `api`
- livenessProbe: httpGet `/` :80 · initialDelaySeconds 5 · periodSeconds 10 · failureThreshold 3
- readinessProbe: httpGet `/` :80 · initialDelaySeconds 3 · periodSeconds 5
- 파드가 Ready 상태이고 재시작 횟수가 0 이어야 한다

**확인용 명령**

```bash
kubectl get pod health-pod -n api
kubectl describe pod health-pod -n api | grep -E 'Liveness|Readiness'
```

---

## 채점 배분

| 문제 | 항목 수 |
|------|--------|
| Q1 PVC + Deployment YAML 연결 | 12 |
| Q2 Requests / Limits | 8 |
| Q3 Probe | 13 |
| **합계** | **33** |

세 문제는 서로 독립적이다. 순서에 상관없이 풀어도 된다.

막히면 `bash exam-start.sh --hints` 로 힌트를 볼 수 있다. **시험 중에는 사용하지 않는다.**
