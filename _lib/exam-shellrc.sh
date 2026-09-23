# ============================================================
# exam-shellrc.sh — 시험 환경 셸 설정
#
# 실제 CKA 시험 터미널과 같은 상태로 맞춘다:
#   kubectl 자동완성 · alias k · $do / $now · vim YAML 들여쓰기
#
# 웹 패널 터미널은 이 파일을 자동으로 읽는다.
# ssh 로 들어와서 쓰려면:  bash setup-shell.sh   (~/.bashrc 에 한 줄 추가)
# ============================================================

# 기존 설정 먼저 (PATH, kubeconfig 등)
[ -f /etc/bash.bashrc ] && . /etc/bash.bashrc
[ -f "$HOME/.bashrc" ] && . "$HOME/.bashrc"

# ── 자동완성 ────────────────────────────────────────────────
# bash-completion 이 있어야 complete -F 가 동작한다 (없으면 조용히 건너뜀)
if ! type _get_comp_words_by_ref &>/dev/null; then
  for f in /usr/share/bash-completion/bash_completion /etc/bash_completion; do
    [ -r "$f" ] && . "$f" && break
  done
fi

if command -v kubectl &>/dev/null; then
  source <(kubectl completion bash) 2>/dev/null
  alias k=kubectl
  complete -o default -F __start_kubectl k 2>/dev/null
fi
command -v kubeadm  &>/dev/null && source <(kubeadm completion bash)  2>/dev/null
command -v helm     &>/dev/null && source <(helm completion bash)     2>/dev/null
command -v crictl   &>/dev/null && source <(crictl completion bash)   2>/dev/null

# ── 시험에서 손이 가장 많이 가는 축약 ───────────────────────
export do='--dry-run=client -o yaml'      # k run nginx --image=nginx $do > pod.yaml
export now='--force --grace-period=0'     # k delete pod x $now
export KUBE_EDITOR="${KUBE_EDITOR:-vim}"

# ── vim: YAML 은 스페이스 2칸 ───────────────────────────────
# ~/.vimrc 를 건드리지 않고 이 셸에서만 적용된다
export VIMINIT='set expandtab tabstop=2 shiftwidth=2 softtabstop=2 autoindent number | syntax on'

# ── 웹 패널에서 세트를 바꾸면 이 셸도 그 폴더로 따라간다 ────
#   패널이 $CKA_SET_FILE 에 세트 이름만 써 두고, 셸은 프롬프트가 그려질 때
#   그 값을 읽어 cd 한다. 입력 중인 명령줄을 건드리지 않는 방식이다.
__cka_follow() {
  [ -n "${CKA_SET_FILE:-}" ] && [ -r "$CKA_SET_FILE" ] || return 0
  local want; want=$(cat "$CKA_SET_FILE" 2>/dev/null)
  [ -n "$want" ] && [ "$want" != "${__CKA_SET:-}" ] || return 0
  __CKA_SET="$want"
  [ -d "${CKA_ROOT:-}/$want" ] && cd "$CKA_ROOT/$want"
  return 0
}
if [ -n "${CKA_SET_FILE:-}" ]; then
  __CKA_SET=$(cat "$CKA_SET_FILE" 2>/dev/null)
  PROMPT_COMMAND="__cka_follow${PROMPT_COMMAND:+;$PROMPT_COMMAND}"
fi

# ── 시험 명령 단축 ──────────────────────────────────────────
# 지금 있는 세트 폴더에서 그대로 쓴다:  ex check / ex show / ex hint
ex() { bash exam.sh "$@"; }
export -f ex 2>/dev/null

if [ -z "${CKA_RC_QUIET:-}" ]; then
  printf '\033[0;34m%s\033[0m\n' "kubectl 자동완성 · alias k · \$do · \$now 준비됨   (ex check = bash exam.sh check)"
fi
