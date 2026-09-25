#!/usr/bin/env bash
# CKA 9강 실습 — 클러스터 유지보수 (순차 진행형)
set -uo pipefail
source "$(cd "$(dirname "$0")/.." && pwd)/_lib/exam-lib.sh"

EXAM_TITLE="CKA 9강 실습 — 유지보수 (drain · etcd 백업 · 업그레이드 계획 · 인증서)"
EXAM_NQ=4

exam_cleanup() {
  kdel deployment drain-demo -n default
  kubectl uncordon worker-2 &>/dev/null || true
  rm -f /tmp/etcd-backup.db /tmp/upgrade-plan.txt /tmp/cert-expiration.txt 2>/dev/null || true
  echo "  worker-2 uncordon, /tmp 결과 파일 삭제"
}
exam_setup() {
  if kubectl get node worker-2 &>/dev/null; then
    kubectl create deployment drain-demo --image=nginx:1.24 --replicas=4 &>/dev/null
    wait_ready "-l app=drain-demo" default >/dev/null 2>&1 || true
    drain_mark "app=drain-demo" worker-2          # drain 이 실제로 파드를 옮겼는지 보려고 적어 둔다
    echo "  drain-demo (4 레플리카) 배치 — worker-2 의 파드 $(cat work/.drain-before 2>/dev/null || echo 0)개"
  else
    echo "  (worker-2 가 없어 drain 검증용 배치를 건너뜁니다)"
  fi
  echo "  Q2~Q4 는 control-plane 노드에서 실행합니다"
}

# ══════════════════════════════════════════════════════════════
q1_title() { echo "Drain and uncordon a node"; }
q1_text() { cat <<'EOF'
Take the node worker-2 out of service for maintenance and put it back.

  1) drain worker-2
     - ignore DaemonSet pods
     - allow deletion of emptyDir data
  2) confirm it shows Ready,SchedulingDisabled
  3) after the maintenance, make it schedulable again

Verify:
  kubectl get nodes     -> worker-2 Ready, not SchedulingDisabled
EOF
}
q1_title_ko() { echo "노드 drain 후 uncordon"; }
q1_text_ko() { cat <<'EOF'
worker-2 노드를 유지보수용으로 비웠다가 다시 투입하시오.

  1) worker-2 를 drain 한다
     - DaemonSet 파드는 무시
     - emptyDir 데이터 삭제 허용
  2) Ready,SchedulingDisabled 로 표시되는지 확인한다
  3) 유지보수가 끝났다고 보고 다시 스케줄 가능 상태로 되돌린다

[확인]
  kubectl get nodes     → worker-2 가 Ready 이고 SchedulingDisabled 아님
EOF
}
q1_grade() {
  check "worker-2 노드 존재" "kubectl get node worker-2"
  check_output "worker-2 가 Ready" "kubectl get node worker-2 --no-headers" '\sReady'
  check_result "uncordon 되어 스케줄 가능 (SchedulingDisabled 아님)" \
    "$(kubectl get node worker-2 -o jsonpath='{.spec.unschedulable}' 2>/dev/null | grep -q true && echo 1 || echo 0)" \
    "drain 만 하고 uncordon 을 안 했으면 여기서 FAIL"
  check_result "drain 으로 파드가 실제로 비워졌다" \
    "$(drain_moved "app=drain-demo" worker-2 && echo 0 || echo 1)" \
    "worker-2 에 drain-demo 파드가 아직 남아 있다 — cordon 만 하면 파드는 그대로다"
}
q1_hint() { cat <<'EOF'
kubectl drain worker-2 --ignore-daemonsets --delete-emptydir-data
kubectl get nodes                  # Ready,SchedulingDisabled
kubectl uncordon worker-2
kubectl get nodes                  # Ready
EOF
}

# ══════════════════════════════════════════════════════════════
q2_title() { echo "Take an etcd snapshot"; }
q2_text() { cat <<'EOF'
On the control plane node, save an etcd snapshot to /tmp/etcd-backup.db.

  endpoint   https://127.0.0.1:2379
  cacert     /etc/kubernetes/pki/etcd/ca.crt
  cert       /etc/kubernetes/pki/etcd/server.crt
  key        /etc/kubernetes/pki/etcd/server.key

Then confirm the file with snapshot status.

Verify:
  ls -lh /tmp/etcd-backup.db
  ETCDCTL_API=3 etcdctl snapshot status /tmp/etcd-backup.db --write-out=table
EOF
}
q2_title_ko() { echo "etcd 스냅샷 백업"; }
q2_text_ko() { cat <<'EOF'
control-plane 노드에서 etcd 스냅샷을 /tmp/etcd-backup.db 에 저장하시오.

  endpoint   https://127.0.0.1:2379
  cacert     /etc/kubernetes/pki/etcd/ca.crt
  cert       /etc/kubernetes/pki/etcd/server.crt
  key        /etc/kubernetes/pki/etcd/server.key

저장한 뒤 snapshot status 로 파일을 확인한다.

[확인]
  ls -lh /tmp/etcd-backup.db
  ETCDCTL_API=3 etcdctl snapshot status /tmp/etcd-backup.db --write-out=table
EOF
}
q2_grade() {
  check "/tmp/etcd-backup.db 파일 존재" "test -f /tmp/etcd-backup.db"
  check "파일이 비어 있지 않다" "test -s /tmp/etcd-backup.db"
  check_result "1MB 이상 (진짜 스냅샷인가)" \
    "$([[ $(stat -f%z /tmp/etcd-backup.db 2>/dev/null || stat -c%s /tmp/etcd-backup.db 2>/dev/null || echo 0) -ge 1000000 ]] && echo 0 || echo 1)" \
    "빈 파일을 touch 만 하면 FAIL"
  check_output "snapshot status 가 읽힌다" \
    "ETCDCTL_API=3 etcdctl snapshot status /tmp/etcd-backup.db 2>/dev/null || etcdutl snapshot status /tmp/etcd-backup.db 2>/dev/null" '[0-9]'
}
q2_hint() { cat <<'EOF'
sudo ETCDCTL_API=3 etcdctl snapshot save /tmp/etcd-backup.db \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key

# 플래그 값이 헷갈리면 etcd 매니페스트에서 읽는다
sudo grep -E 'cert-file|key-file|trusted-ca-file' /etc/kubernetes/manifests/etcd.yaml

# 채점이 읽을 수 있게 권한을 열어둔다
sudo chmod a+r /tmp/etcd-backup.db
EOF
}

# ══════════════════════════════════════════════════════════════
q3_title() { echo "Check the cluster upgrade plan"; }
q3_text() { cat <<'EOF'
On the control plane node, check which versions the cluster can be upgraded
to and save the output to /tmp/upgrade-plan.txt.

  - run kubeadm upgrade plan
  - capture both standard output and standard error into the file

Verify:
  cat /tmp/upgrade-plan.txt    -> contains the current and target versions
EOF
}
q3_title_ko() { echo "클러스터 업그레이드 계획 확인"; }
q3_text_ko() { cat <<'EOF'
control-plane 노드에서 이 클러스터가 어느 버전으로 업그레이드 가능한지
확인하고, 그 출력을 /tmp/upgrade-plan.txt 에 저장하시오.

  - kubeadm upgrade plan 을 실행한다
  - 표준 출력과 표준 에러를 모두 파일에 담는다

[확인]
  cat /tmp/upgrade-plan.txt    → 현재 버전과 업그레이드 대상 버전이 보인다
EOF
}
q3_grade() {
  check "kubeadm 이 설치돼 있다" "command -v kubeadm"
  check "/tmp/upgrade-plan.txt 존재" "test -f /tmp/upgrade-plan.txt"
  check "파일이 비어 있지 않다" "test -s /tmp/upgrade-plan.txt"
  check_output "쿠버네티스 버전 문자열이 들어 있다" \
    "cat /tmp/upgrade-plan.txt 2>/dev/null" 'v1\.[0-9]+'
  check_output "upgrade plan 출력으로 보인다" \
    "cat /tmp/upgrade-plan.txt 2>/dev/null" 'upgrade|Upgrade|COMPONENT|CURRENT'
}
q3_hint() { cat <<'EOF'
sudo kubeadm upgrade plan > /tmp/upgrade-plan.txt 2>&1
cat /tmp/upgrade-plan.txt

# 인터넷이 없으면 버전 조회에서 실패할 수 있다 — 그 경우 출력이 에러여도
# 파일에는 현재 버전 정보가 남는다
EOF
}

# ══════════════════════════════════════════════════════════════
q4_title() { echo "Check certificate expiration"; }
q4_text() { cat <<'EOF'
On the control plane node, list the expiration dates of the cluster
certificates and save the result to /tmp/cert-expiration.txt.

  - use kubeadm certs check-expiration
  - the file must show each certificate and its residual time

Verify:
  cat /tmp/cert-expiration.txt   -> apiserver, etcd-server ... with dates
EOF
}
q4_title_ko() { echo "인증서 만료일 확인"; }
q4_text_ko() { cat <<'EOF'
control-plane 노드에서 클러스터 인증서들의 만료일을 확인하고 결과를
/tmp/cert-expiration.txt 에 저장하시오.

  - kubeadm certs check-expiration 을 사용한다
  - 각 인증서와 남은 기간(RESIDUAL TIME)이 파일에 보여야 한다

[확인]
  cat /tmp/cert-expiration.txt   → apiserver, etcd-server … 와 날짜
EOF
}
q4_grade() {
  check "/tmp/cert-expiration.txt 존재" "test -f /tmp/cert-expiration.txt"
  check "파일이 비어 있지 않다" "test -s /tmp/cert-expiration.txt"
  check_output "apiserver 인증서 항목이 있다" \
    "cat /tmp/cert-expiration.txt 2>/dev/null" 'apiserver'
  check_output "만료 관련 열(EXPIRES / RESIDUAL)이 있다" \
    "cat /tmp/cert-expiration.txt 2>/dev/null" 'EXPIRES|RESIDUAL|expires'
  check_output "etcd 관련 인증서도 포함" \
    "cat /tmp/cert-expiration.txt 2>/dev/null" 'etcd'
}
q4_hint() { cat <<'EOF'
sudo kubeadm certs check-expiration > /tmp/cert-expiration.txt 2>&1
cat /tmp/cert-expiration.txt

# 갱신이 필요하면 (이 문제에서는 확인만 한다)
sudo kubeadm certs renew all
EOF
}

exam_main "$@"
