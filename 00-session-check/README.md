# 1세션 확인 실습 — 명령어로 만들 수 있는가

> **문제만 보려면 `QUESTIONS.txt` 를 열면 된다.** 이 파일(README)에는 정답이 들어 있다.
>
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
