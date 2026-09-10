# 2세션 시험 — 네임스페이스 · ConfigMap · Secret

> **문제만 보려면 [QUESTIONS.md](QUESTIONS.md) 를 열면 된다.** 이 파일(README)에는 정답이 들어 있다.
>
> 출제 범위: 네임스페이스 지정 · Service NodePort · ConfigMap · Deployment 롤아웃/롤백
> 1세션 개념(Pod / Deployment / Service)을 네임스페이스 위에서 다시 다루므로 복습을 겸한다.
> 문제 형식은 실제 CKA 기출 스타일(`In namespace <ns>, create ...`)을 따랐다.

## 사용법

```bash
bash exam-start.sh      # 시험 시작 (환경 초기화 + 문제 출제) — 권장 25분
bash verify.sh          # 채점 (30항목)

bash exam-start.sh --hints    # 정답 힌트 포함 — 시험 중에는 사용 금지
```

`exam-start.sh` 는 시작할 때 `ops`, `app` 네임스페이스를 통째로 삭제한다. 다시 풀고 싶으면 같은 명령을 재실행하면 된다.

전제 조건: kubeadm 클러스터에서 `kubectl get nodes` 가 Ready. 사용 이미지 `nginx:1.24`, `busybox:1.36`.

---

## E1. 네임스페이스를 지정해 Deployment + NodePort Service

| 항목 | 값 |
|------|-----|
| namespace | `ops` (직접 생성) |
| Deployment | `cache-app` / `nginx:1.24` / replicas 2 / containerPort 80 |
| Service | `cache-svc` / NodePort / 80 → 80 / **nodePort 30090** |

**채점 포인트 (13항목)**
- 네임스페이스 생성, 리소스가 `ops` 안에 있는지
- **`default` 에 잘못 만들지 않았는지** — `-n` 누락을 잡아내는 항목
- `--port=80` 반영, replicas 2 Ready, NodePort 타입, nodePort 30090 고정
- Endpoints 에 파드 IP 2개

> `kubectl expose` 는 nodePort 값을 지정할 수 없다. 만든 뒤 `kubectl patch` 하거나 처음부터 YAML 로 만들어야 한다. 이 점을 아는지가 이 문제의 핵심이다.

## E2. ConfigMap 을 파드에 두 가지 방식으로 주입

| 항목 | 값 |
|------|-----|
| namespace | `app` (직접 생성) |
| ConfigMap | `app-config` / `APP_ENV=production` / `LOG_LEVEL=info` |
| Pod | `config-pod` / `busybox:1.36` / `sleep 3600` |
| 주입 방식 | (a) `envFrom` 전체 주입 + (b) 볼륨 마운트 `/etc/app-config` |

**채점 포인트 (10항목)**
- ConfigMap 키/값 정확도
- 파드 안에서 `env` 로 `APP_ENV`, `LOG_LEVEL` 이 실제로 보이는지 (`kubectl exec` 실검증)
- `/etc/app-config/LOG_LEVEL` 파일 내용이 `info` 인지 (`kubectl exec` 실검증)

> 볼륨으로 마운트하면 **키 이름이 파일명, 값이 파일 내용**이 된다. env 방식과 volume 방식을 둘 다 시켜서 차이를 이해했는지 본다.

## E3. Deployment 스케일 · 롤링 업데이트 · 롤백

| 항목 | 값 |
|------|-----|
| namespace | `app` (E2 에서 만든 것 재사용) |
| Deployment | `frontend` / 최초 `nginx:1.24` / replicas 2 |
| 수행 순서 | (a) replicas 4 로 스케일 → (b) `nginx:1.25` 로 롤링 업데이트 → (c) 이전 리비전으로 롤백 |
| 최종 상태 | 이미지 `nginx:1.24` / replicas 4 / 전부 Ready |

**채점 포인트 (7항목)**
- replicas 4, 4개 모두 Ready
- 롤백 후 최종 이미지가 `nginx:1.24`
- **`nginx:1.25` 를 쓰는 ReplicaSet 이 남아 있는지** — 롤링 업데이트를 실제로 거쳤다는 증거
- **revision 이 3 이상인지** — 생성 → 업데이트 → 롤백 세 단계를 모두 밟았는지
- 현재 실행 중인 파드가 전부 `nginx:1.24` 인지 (스펙이 아니라 구동 상태 확인)

> 처음부터 `nginx:1.24` 로 만들고 스케일만 하면 최종 상태는 같아 보이지만 revision 과 ReplicaSet 이력이 남지 않아 오답 처리된다.
> 롤백은 이전 ReplicaSet 을 다시 살리는 동작이다. 업데이트 후에도 예전 RS 가 replicas 0 으로 남아 있고, 그게 롤백의 재료다.

---

## 정답 명령어 (강사용)

```bash
# E1
kubectl create namespace ops
kubectl create deployment cache-app --image=nginx:1.24 --replicas=2 --port=80 -n ops
kubectl expose deployment cache-app --name=cache-svc --port=80 --target-port=80 --type=NodePort -n ops
kubectl patch svc cache-svc -n ops -p '{"spec":{"ports":[{"port":80,"targetPort":80,"nodePort":30090}]}}'

# E2
kubectl create namespace app
kubectl create configmap app-config -n app \
  --from-literal=APP_ENV=production --from-literal=LOG_LEVEL=info
# config-pod 는 envFrom + volume 둘 다 필요 → YAML (exam-start.sh --hints 에 전문 있음)

# E3
kubectl create deployment frontend --image=nginx:1.24 --replicas=2 -n app
kubectl scale deployment frontend --replicas=4 -n app
kubectl set image deployment/frontend nginx=nginx:1.25 -n app
kubectl rollout status deployment/frontend -n app
kubectl rollout undo deployment/frontend -n app
kubectl rollout status deployment/frontend -n app
```

## 채점 총점

| 문제 | 항목 수 |
|------|--------|
| E1 네임스페이스 + NodePort | 13 |
| E2 ConfigMap (env + volume) | 10 |
| E3 Deployment 롤아웃·롤백 | 7 |
| **합계** | **30** |

`verify.sh` 는 실패 개수를 종료 코드로 반환한다.

## 실습 후 정리

```bash
kubectl delete namespace ops app
```
