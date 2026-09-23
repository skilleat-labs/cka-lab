# CKA 실습 문제 모음

CKA(Certified Kubernetes Administrator) 온라인 교육 실습 저장소입니다.
각 강의에서 배운 내용을 **직접 만든 쿠버네티스 클러스터**에서 풀고, 자동 채점 스크립트로 확인합니다.

## 시작하기

```bash
git clone <저장소 주소>
cd practice
```

전제 조건:
- kubeadm으로 구축한 클러스터에서 `kubectl get nodes` 가 **Ready** 로 응답할 것
- 노드에서 이미지 pull 이 가능할 것 (`nginx:1.24`, `busybox:1.36` 등 사용)

## 브라우저로 풀기 (웹 패널)

```bash
cd ~/cka-lab && python3 web/server.py
```

출력된 주소(`http://192.168.56.10:8080`)를 맥/윈도우 브라우저에서 연다.
**왼쪽에 문제, 오른쪽에 터미널**이 함께 있어서 브라우저 하나로 시험을 볼 수 있다 (터미널은 VM 의 실제 셸).
터미널 방식과 점수·기록이 같다 — 자세한 건 [web/README.md](web/README.md).

## 실습 진행 방법

### 지문 언어 · 시험 환경 셸

지문은 실제 CKA 처럼 **영어가 기본**이다. 막히면 한글로 바꾼다.

```bash
bash exam.sh lang ko      # 한글 지문 (웹 패널은 오른쪽 위 EN/KO 버튼)
```

터미널을 시험장과 같은 상태(kubectl 자동완성 · `alias k` · `$do` · vim YAML 2칸)로 맞추려면:

```bash
bash setup-shell.sh       # ~/.bashrc 에 한 줄 추가 — 웹 패널 터미널은 자동 적용
```

### 한 문제씩 풀기 (`exam.sh` — 19개 세트 전부)

```bash
cd 00-session-check
bash exam.sh start      # 환경 준비 + 1번 문제
bash exam.sh check      # 채점 → 만점이면 자동으로 다음 문제
bash exam.sh status     # 진행 현황 (점수·소요 시간)
```

막히면 `bash exam.sh hint`, 넘어가려면 `bash exam.sh skip`.
문제 사이는 자유롭게 오간다 — `bash exam.sh go 3` (또는 `next` / `prev`).
되돌아가 다시 채점하면 점수가 갱신되고, 시간은 그 문제에 머문 만큼만 누적된다. 마지막 문제를 통과하면 최종 리포트가 나온다.
끝나고 클러스터를 원래대로 돌리려면 `bash exam.sh clean` — 시험에서 만든 리소스(네임스페이스·PV·노드 레이블 등)를 전부 지운다.
세션 시험 4개 · 모의고사 5개 · 강의 실습 10개 — **전체 19세트 84문항**에 적용돼 있다.
모의고사는 100점 배점, 세션 시험은 항목 수로 채점된다. 강의 실습(02-cluster-setup ~ 11)은 아직 한꺼번에 방식만 있다.

### 한꺼번에 풀기 (모든 세트)

모든 폴더가 동일한 방식입니다.

```bash
cd 00-session-check

bash exam-start.sh            # ① 환경 초기화 + 문제 출력
bash exam-start.sh --hints    # 힌트까지 함께 보고 싶을 때

# ② 문제 풀이 (kubectl 로 직접 작업)

bash verify.sh                # ③ 자동 채점 — 항목별 PASS/FAIL
```

- `exam-start.sh` 는 실행할 때마다 이전 실습 리소스를 **정리**합니다. 처음부터 다시 풀고 싶으면 그냥 다시 실행하세요.
- `verify.sh` 는 실패 개수를 종료 코드로 반환하므로 반복 실행하며 0이 될 때까지 고치면 됩니다.
- `work/` 는 개인 작업 공간입니다. `.gitignore` 처리되어 커밋되지 않습니다.
- 문제만 따로 보려면 각 폴더의 `QUESTIONS.txt` 를 엽니다 — `cat QUESTIONS.txt` 또는 `less QUESTIONS.txt`

## 실습 목록

> 각 폴더에 어떤 문제가 들어 있는지 자세한 내용은 [PROBLEMS.md](PROBLEMS.md) 참고.

| 폴더 | 주제 | 핵심 |
|------|------|------|
| `00-session-check` | 1세션 점검 | kubectl run / label / create deployment / scale / expose |
| `01-session2-exam` | 2세션 시험 | 네임스페이스 지정 / NodePort / ConfigMap / 롤아웃·롤백 |
| `02-session3-exam` | 3세션 시험 | Deployment+Service / StorageClass·PVC / Gateway API |
| `03-session4-exam` | 4세션 시험 | PVC를 Deployment YAML에서 바로 연결 / Requests·Limits / Probe |
| `02-cluster-setup` | 클러스터 구축 | kubeadm join, crictl |
| `03-workloads` | 워크로드 | Deployment, ConfigMap, CronJob, DaemonSet |
| `04-scheduling` | 스케줄링 | Requests/Limits, Affinity, Taint/Toleration |
| `05-storage` | 스토리지 | PV, PVC, StorageClass |
| `06-networking` | 서비스·네트워킹 | ClusterIP, NodePort, NetworkPolicy, DNS |
| `07-ingress` | 외부 트래픽 | Ingress |
| `08-rbac` | 권한과 인증 | Role, RoleBinding, ServiceAccount |
| `09-maintenance` | 유지보수 | drain/cordon, 업그레이드, etcd 백업 |
| `10-helm` | 패키징 | Helm |
| `11-troubleshooting` | 트러블슈팅 | 파드/노드/컨트롤플레인 장애 진단 |
| `mock-1` ~ `mock-3` | 모의고사 | 전 범위 통합 |
| `mock-1-1` | 모의고사 변형 | mock-1 과 같은 유형, 다른 값 — 암기 답안 판별용 |
| `mock-2-2` | 30분 속도 점검 | 기초~중급 6문항 100점 — 문제별 소요 시간 확인용 |

> 폴더 번호는 실습 세트 번호이며 강의 회차와 일대일로 맞지 않습니다. 담당 강사의 안내를 따르세요.

## 개념 문서

| 문서 | 내용 |
|------|------|
| [docs/NETWORKPOLICY.md](docs/NETWORKPOLICY.md) | NetworkPolicy — 아키텍처(CNI 가 집행), 동작 원칙 5가지, 셀렉터 AND/OR, 3계층 격리 시나리오, 예제 YAML 9개, CKA 함정 |

예제 YAML 은 `docs/networkpolicy-examples/` 에 파일로 있어 바로 `kubectl apply -f` 할 수 있다.

## 참고

- `02-cluster-setup` 실습은 worker 노드 IP 가 `192.168.56.12` 로 지정되어 있습니다. 다른 IP 로 VM 을 구성했다면 스크립트를 수정하세요.
- 실습 중 만든 리소스는 클러스터에 그대로 남습니다. 정리는 각 폴더의 `exam-start.sh` 를 다시 실행하면 됩니다.
- 문제가 풀리지 않을 때는 `bash exam-start.sh --hints` 로 힌트를 먼저 확인하세요. 정답 명령어까지 들어 있습니다.
