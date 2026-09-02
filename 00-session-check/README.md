# 1세션 확인 실습 — 명령어로 만들 수 있는가

> 목적: 첫 세션 종료 시점에 **imperative 명령어(kubectl run / label / create deployment / scale / expose)** 만으로
> Pod → Deployment → Service를 조건에 맞게 만들 수 있는지 판정한다.
> CKA 시험은 2시간에 15~20문제이므로 YAML을 처음부터 손으로 쓰면 시간이 부족하다. 명령어 숙련도가 곧 점수다.

## 사용법

```bash
# 1) 환경 초기화 + 문제 출력
bash exam-start.sh

# 힌트까지 함께 보려면
bash exam-start.sh --hints

# 2) 문제 풀이 후 채점
bash verify.sh
```

전제 조건: kubeadm으로 구축한 VM 클러스터에서 `kubectl get nodes`가 Ready로 응답할 것.
사용 이미지는 `nginx:1.24`, `busybox:1.36` — 노드에서 이미지 pull이 가능해야 한다.

---

## P1. 명령어로 Pod 생성 + 명령어로 레이블 부착

**조건**

| 항목 | 값 |
|------|-----|
| 이름 | `web-pod` |
| 네임스페이스 | `default` |
| 이미지 | `nginx:1.24` |
| 컨테이너 포트 | `80` |
| 환경변수 | `APP_ENV=prod` |
| 생성 후 추가 레이블 | `tier=frontend`, `env=production` |

1. `kubectl run` 한 줄로 Pod를 생성한다 (YAML 파일 작성 금지).
2. 생성이 끝난 뒤 `kubectl label` 로 레이블 2개를 추가한다.
3. `kubectl get pods -l env=production` 으로 조회되는지 확인한다.

**채점 포인트 (10항목)**
- Pod 존재 / 이미지 / Running / Ready
- `containerPort: 80` → `--port=80` 플래그를 알고 있는가
- `APP_ENV=prod` → `--env` 플래그를 알고 있는가
- **`run=web-pod` 레이블 존재** → `kubectl run`으로 만들었다는 증거 (YAML로 만들면 이 레이블이 없어 FAIL)
- `tier=frontend`, `env=production` 부착 여부
- 레이블 셀렉터 조회 동작

> 함정: `kubectl run --labels=...` 로 레이블을 한 번에 주면 `run=web-pod` 기본 레이블이 덮여 사라진다.
> 이 문제는 **"만든 뒤에 레이블을 붙일 수 있는가"** 를 보는 것이므로 `kubectl label` 을 따로 써야 한다.

---

## P2. 명령어로 Deployment 생성 + 스케일

**조건**

| 항목 | 값 |
|------|-----|
| 이름 | `web-app` |
| 네임스페이스 | `default` |
| 이미지 | `nginx:1.24` |
| 최초 레플리카 | `3` |
| 컨테이너 포트 | `80` |
| 최종 레플리카 | `4` (`kubectl scale` 로 변경) |

1. `kubectl create deployment` 로 조건에 맞게 생성한다.
2. `kubectl scale` 로 레플리카를 4로 늘린다.
3. `kubectl rollout status` 로 전부 Ready가 될 때까지 확인한다.

**채점 포인트 (7항목)**
- Deployment 존재 / 이미지 / `spec.replicas == 4` / `status.readyReplicas == 4`
- `containerPort: 80` → `--port=80`
- `app=web-app` 셀렉터 (create deployment 기본 레이블) — P3의 selector와 연결되는 지점
- `-l app=web-app` 파드 4개 조회

---

## P3. Deployment에 Service 붙이기

**조건**

| 항목 | 값 |
|------|-----|
| 이름 | `web-svc` |
| 대상 | P2의 `web-app` Deployment |
| 타입 | `ClusterIP` |
| port → targetPort | `80` → `80` |
| selector | `app=web-app` |

1. `kubectl expose deployment` 로 Service를 생성한다.
2. `kubectl get endpoints web-svc` 로 파드 IP 4개가 등록됐는지 확인한다.
3. 임시 파드에서 서비스 **이름**으로 HTTP 요청이 되는지 확인한다.

**채점 포인트 (6항목 + 통신 검증 1항목)**
- Service 존재 / 타입 / port / targetPort / selector
- **Endpoints에 파드 IP 4개** — 여기가 0이면 selector ↔ 파드 레이블 불일치
- **실제 통신 검증**: 채점 스크립트가 `busybox` 임시 파드를 띄워
  `wget -qO- http://web-svc` 응답에 `nginx` 문자열이 있는지 확인한다.
  이 항목이 통과하면 Service selector·Endpoints·CoreDNS·kube-proxy가 모두 정상이라는 뜻이다.

---

---

# 2세션 시험 (E1~E3)

> 출제 범위: 네임스페이스 지정 · Service NodePort · ConfigMap · Secret
> 1세션 개념(Pod / Deployment / Service)을 네임스페이스 위에서 다시 다루므로 복습을 겸한다.
> 문제 형식은 실제 CKA 기출 스타일(`In namespace <ns>, create ...`)을 따랐다.

```bash
bash exam-start.sh --exam            # 시험 문제만 출제 (권장 25분)
bash exam-start.sh --exam --hints    # 정답 힌트 포함 — 시험 중 사용 금지
bash verify.sh --exam                # 시험 채점 (31항목)

bash exam-start.sh --all             # S1~S3 + E1~E3 전체
```

## E1. 네임스페이스를 지정해 Deployment + NodePort Service

| 항목 | 값 |
|------|-----|
| namespace | `ops` (직접 생성) |
| Deployment | `cache-app` / `nginx:1.24` / replicas 2 / containerPort 80 |
| Service | `cache-svc` / NodePort / 80 → 80 / **nodePort 30090** |

**채점 포인트 (13항목)**
- 네임스페이스 생성, 리소스가 `ops` 안에 있는지
- **`default`에 잘못 만들지 않았는지** — `-n` 누락을 잡아내는 항목
- `--port=80` 반영, replicas 2 Ready, NodePort 타입, nodePort 30090 고정
- Endpoints에 파드 IP 2개

> `kubectl expose`는 nodePort 값을 지정할 수 없다. 만든 뒤 `kubectl patch` 하거나 처음부터 YAML로 만들어야 한다. 이 점을 아는지가 이 문제의 핵심이다.

## E2. ConfigMap을 파드에 두 가지 방식으로 주입

| 항목 | 값 |
|------|-----|
| namespace | `app` (직접 생성) |
| ConfigMap | `app-config` / `APP_ENV=production` / `LOG_LEVEL=info` |
| Pod | `config-pod` / `busybox:1.36` / `sleep 3600` |
| 주입 방식 | (a) `envFrom` 전체 주입 + (b) 볼륨 마운트 `/etc/app-config` |

**채점 포인트 (10항목)**
- ConfigMap 키/값 정확도
- 파드 안에서 `env`로 `APP_ENV`, `LOG_LEVEL`이 실제로 보이는지 (`kubectl exec` 실검증)
- `/etc/app-config/LOG_LEVEL` 파일 내용이 `info`인지 (`kubectl exec` 실검증)

> 볼륨으로 마운트하면 **키 이름이 파일명, 값이 파일 내용**이 된다. env 방식과 volume 방식을 둘 다 시켜서 차이를 이해했는지 본다.

## E3. Secret을 만들고 필요한 키만 골라 주입

| 항목 | 값 |
|------|-----|
| namespace | `app` (E2에서 만든 것 재사용) |
| Secret | `db-secret` / generic / `DB_USER=admin` / `DB_PASSWORD=supersecret` |
| Pod | `secret-pod` / `busybox:1.36` / `sleep 3600` |
| 주입 | **`DB_PASSWORD`만** 환경변수로 |

**채점 포인트 (8항목)**
- Secret 타입 Opaque, 값이 base64 디코딩해서 일치하는지
- 파드 안에서 `DB_PASSWORD=supersecret`이 보이는지 (`kubectl exec` 실검증)
- **`DB_USER`가 주입되지 않았는지** — `envFrom`으로 통째로 넣으면 오답

> 실무에서도 시험에서도 "필요한 키만 주입"이 기본이다. `envFrom`(전체)과 `env` + `secretKeyRef`(선택)의 차이를 아는지 가르는 문제다.

## 시험 정답 명령어 (강사용)

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
# config-pod 는 envFrom + volume 둘 다 필요 → YAML (exam-start.sh --exam --hints 에 전문 있음)

# E3
kubectl create secret generic db-secret -n app \
  --from-literal=DB_USER=admin --from-literal=DB_PASSWORD=supersecret
# secret-pod 는 env + secretKeyRef 로 DB_PASSWORD 만 주입
```

## 시험 채점 총점

| 문제 | 항목 수 |
|------|--------|
| E1 네임스페이스 + NodePort | 13 |
| E2 ConfigMap (env + volume) | 10 |
| E3 Secret (선택 주입) | 8 |
| **합계** | **31** |

---

## 정답 명령어 (강사용)

```bash
# P1
kubectl run web-pod --image=nginx:1.24 --port=80 --env="APP_ENV=prod"
kubectl label pod web-pod tier=frontend env=production
kubectl get pods -l env=production

# P2
kubectl create deployment web-app --image=nginx:1.24 --replicas=3 --port=80
kubectl scale deployment web-app --replicas=4
kubectl rollout status deployment/web-app

# P3
kubectl expose deployment web-app --name=web-svc --port=80 --target-port=80 --type=ClusterIP
kubectl get endpoints web-svc
kubectl run tmp --rm -it --image=busybox:1.36 --restart=Never -- wget -qO- http://web-svc
```

## 채점 총점

| 문제 | 항목 수 |
|------|--------|
| P1 Pod + 레이블 | 10 |
| P2 Deployment + 스케일 | 7 |
| P3 Service | 6 |
| 실제 통신 검증 | 1 |
| **합계** | **24** |

`verify.sh` 는 실패 개수를 exit code로 반환하므로 자동화에 그대로 쓸 수 있다.

## 실습 후 정리

```bash
kubectl delete pod web-pod
kubectl delete deployment web-app
kubectl delete service web-svc
```

(`exam-start.sh` 를 다시 실행하면 자동으로 정리된다.)
