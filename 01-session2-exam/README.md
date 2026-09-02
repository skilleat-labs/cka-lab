# 2세션 시험 — 네임스페이스 · ConfigMap · Secret

> 출제 범위: 네임스페이스 지정 · Service NodePort · ConfigMap · Secret
> 1세션 개념(Pod / Deployment / Service)을 네임스페이스 위에서 다시 다루므로 복습을 겸한다.
> 문제 형식은 실제 CKA 기출 스타일(`In namespace <ns>, create ...`)을 따랐다.

## 사용법

```bash
bash exam-start.sh      # 시험 시작 (환경 초기화 + 문제 출제) — 권장 25분
bash verify.sh          # 채점 (31항목)

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

## E3. Secret 을 만들고 필요한 키만 골라 주입

| 항목 | 값 |
|------|-----|
| namespace | `app` (E2 에서 만든 것 재사용) |
| Secret | `db-secret` / generic / `DB_USER=admin` / `DB_PASSWORD=supersecret` |
| Pod | `secret-pod` / `busybox:1.36` / `sleep 3600` |
| 주입 | **`DB_PASSWORD` 만** 환경변수로 |

**채점 포인트 (8항목)**
- Secret 타입 Opaque, 값이 base64 디코딩해서 일치하는지
- 파드 안에서 `DB_PASSWORD=supersecret` 이 보이는지 (`kubectl exec` 실검증)
- **`DB_USER` 가 주입되지 않았는지** — `envFrom` 으로 통째로 넣으면 오답

> "필요한 키만 주입"이 기본이다. `envFrom`(전체)과 `env` + `secretKeyRef`(선택)의 차이를 아는지 가르는 문제다.

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
kubectl create secret generic db-secret -n app \
  --from-literal=DB_USER=admin --from-literal=DB_PASSWORD=supersecret
# secret-pod 는 env + secretKeyRef 로 DB_PASSWORD 만 주입
```

## 채점 총점

| 문제 | 항목 수 |
|------|--------|
| E1 네임스페이스 + NodePort | 13 |
| E2 ConfigMap (env + volume) | 10 |
| E3 Secret (선택 주입) | 8 |
| **합계** | **31** |

`verify.sh` 는 실패 개수를 종료 코드로 반환한다.

## 실습 후 정리

```bash
kubectl delete namespace ops app
```
