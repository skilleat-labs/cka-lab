# 4세션 시험 — PVC/Deployment YAML · Requests/Limits · Probe

> **문제만 보려면 [QUESTIONS.md](QUESTIONS.md) 를 열면 된다.** 이 파일(README)에는 정답이 들어 있다.
>
> 출제 범위: StorageClass 로 PVC 생성 후 Deployment YAML 에서 바로 연결 · Requests/Limits · Liveness/Readiness Probe
> 모든 환경은 `exam-start.sh` 가 자동으로 준비한다. 외부 설치가 없어 **인터넷 없이도 동작**한다.

## 사용법

```bash
bash exam-start.sh      # 환경 준비 + 문제 출제 (권장 30분)
bash verify.sh          # 채점 (33항목)

bash exam-start.sh --hints    # 정답 힌트 포함 — 시험 중 사용 금지
```

## exam-start.sh 가 준비하는 것

| 항목 | 내용 |
|------|------|
| 네임스페이스 | `api` |
| StorageClass | `api-storage` (hostPath 기반, `no-provisioner`, Immediate 바인딩) |
| PersistentVolume | `api-pv-1~3` — 각 2Gi, hostPath `/mnt/api-data-N` |
| Deployment | `api-worker` — nginx:1.24, replicas 2, 컨테이너 이름 `worker`, **리소스 제한 없음** (Q2 대상) |

---

## Q1. PVC 를 만들고 Deployment YAML 에서 바로 연결 (12항목)

| 항목 | 값 |
|------|-----|
| PVC | `api-data` / `api-storage` / 1Gi / ReadWriteOnce |
| Deployment | `api-server` / `nginx:1.24` / replicas 1 |
| 마운트 | `/var/www/data` — **YAML 에 처음부터 포함** |

**채점 포인트**
- PVC 스펙과 Bound 상태
- Deployment 가 PVC 를 볼륨으로 참조하고 지정 경로에 마운트하는지
- **Deployment revision 이 1 인지** — 생성 후 `edit`/`patch` 로 볼륨을 추가하면 revision 2 가 되어 FAIL
- 파드 내부 `/var/www/data` 에 실제로 쓰고 읽을 수 있는지 (`kubectl exec`)

> 3세션 Q2 는 "만든 뒤에 붙이기"였고, 이번 Q1 은 "처음부터 YAML 에 넣기"다. `--dry-run=client -o yaml` 로 뼈대를 뽑아 수정하고 `apply` 하는 흐름을 손에 익히는 것이 목적이다. replicas 를 1 로 둔 이유는 hostPath PV 가 노드 단위라 여러 파드가 다른 노드에 흩어지면 같은 데이터를 보지 못하기 때문이다.

## Q2. 기존 Deployment 에 Requests / Limits 추가 (8항목)

| 항목 | 값 |
|------|-----|
| 대상 | `api-worker` (컨테이너 `worker`) |
| requests | cpu 100m / memory 128Mi |
| limits | cpu 200m / memory 256Mi |

**채점 포인트**
- Deployment 스펙의 4개 값
- 롤아웃 완료 (readyReplicas 2)
- **실행 중인 파드**에 limits 가 실제 반영되어 있는지 (스펙만 바꾸고 롤아웃이 안 끝난 경우를 걸러냄)
- QoS 클래스가 **Burstable** 인지 (requests < limits)

> `kubectl set resources` 한 줄로 끝나는 문제다. 이 명령을 아는지가 시간 차이를 만든다. QoS 는 requests 와 limits 가 같으면 Guaranteed, 다르면 Burstable, 둘 다 없으면 BestEffort — 노드 메모리 부족 시 BestEffort 부터 죽는다.

## Q3. Liveness / Readiness Probe (13항목)

| 항목 | 값 |
|------|-----|
| Pod | `health-pod` / `nginx:1.24` |
| livenessProbe | httpGet `/` :80 · initialDelaySeconds 5 · periodSeconds 10 · failureThreshold 3 |
| readinessProbe | httpGet `/` :80 · initialDelaySeconds 3 · periodSeconds 5 |

**채점 포인트**
- 두 probe 의 필드 값 9개
- 파드가 **Ready** 인지 (readiness 통과)
- **재시작 횟수 0** 인지 (liveness 통과) — 경로나 포트를 틀리면 재시작이 쌓인다

> liveness 실패 → 컨테이너 재시작. readiness 실패 → Service 트래픽에서 제외되지만 재시작은 안 함. 이 차이가 시험에 나온다. probe 는 YAML 로만 작성할 수 있으므로 `kubectl run --dry-run=client -o yaml` 로 뼈대를 뽑고 넣는다.

---

## 정답 명령어 (강사용)

```bash
# Q1 — PVC
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: api-data
  namespace: api
spec:
  storageClassName: api-storage
  accessModes: ["ReadWriteOnce"]
  resources:
    requests:
      storage: 1Gi
EOF

# Q1 — Deployment (볼륨 포함해서 한 번에 생성)
cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-server
  namespace: api
  labels:
    app: api-server
spec:
  replicas: 1
  selector:
    matchLabels:
      app: api-server
  template:
    metadata:
      labels:
        app: api-server
    spec:
      containers:
      - name: nginx
        image: nginx:1.24
        volumeMounts:
        - name: data
          mountPath: /var/www/data
      volumes:
      - name: data
        persistentVolumeClaim:
          claimName: api-data
EOF

# Q2 — 한 줄
kubectl set resources deployment api-worker -n api \
  --requests=cpu=100m,memory=128Mi --limits=cpu=200m,memory=256Mi
kubectl rollout status deployment/api-worker -n api

# Q3 — Probe
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: health-pod
  namespace: api
spec:
  containers:
  - name: nginx
    image: nginx:1.24
    livenessProbe:
      httpGet:
        path: /
        port: 80
      initialDelaySeconds: 5
      periodSeconds: 10
      failureThreshold: 3
    readinessProbe:
      httpGet:
        path: /
        port: 80
      initialDelaySeconds: 3
      periodSeconds: 5
EOF
```

## 채점 총점

| 문제 | 항목 수 |
|------|--------|
| Q1 PVC + Deployment YAML 연결 | 12 |
| Q2 Requests / Limits | 8 |
| Q3 Probe | 13 |
| **합계** | **33** |

## 실습 후 정리

```bash
kubectl delete namespace api
```

```bash
kubectl delete pv api-pv-1 api-pv-2 api-pv-3 && kubectl delete sc api-storage
```

## 다른 실습 세트와의 관계

모든 리소스를 `api` 네임스페이스와 `api-` 접두사에 격리한다. 3세션 세트(`shop` / `exam-storage`)와도 겹치지 않으므로 두 세트를 같은 클러스터에 동시에 두어도 서로 지우지 않는다.
