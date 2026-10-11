#!/usr/bin/env bash
# ssh 로 들어오는 터미널에도 시험 환경 셸 설정을 적용한다 (웹 패널 터미널은 자동).
# 사용: bash setup-shell.sh
#
# 넣는 줄은 이중으로 막혀 있다 — 이미 읽었으면(__CKA_RC_LOADED) 건너뛰고, 읽을 때는
# "~/.bashrc 안에서 부른다"(__CKA_FROM_BASHRC) 고 알려 exam-shellrc.sh 가 ~/.bashrc 를 다시 읽지 않게 한다.
# 예전 버전이 넣은 줄(막힘 없는 한 줄)이 있으면 새 줄로 바꾼다.
set -euo pipefail
RC="$(cd "$(dirname "$0")" && pwd)/_lib/exam-shellrc.sh"
BRC="$HOME/.bashrc"
TAG="# cka-lab 시험 환경"
LINE="[ -z \"\${__CKA_RC_LOADED:-}\" ] && [ -f \"$RC\" ] && { __CKA_FROM_BASHRC=1; . \"$RC\"; unset __CKA_FROM_BASHRC; }   $TAG (자동완성·alias k·\$do)"

if [ -f "$BRC" ] && grep -qF "$LINE" "$BRC"; then
  echo "이미 적용돼 있습니다: ~/.bashrc"
else
  if [ -f "$BRC" ] && grep -qF -e "$RC" -e "$TAG" "$BRC"; then
    cp "$BRC" "$BRC.cka-bak"
    # cat > 로 다시 써서 ~/.bashrc 가 링크여도 그대로 둔다
    { grep -vF -e "$RC" -e "$TAG" "$BRC.cka-bak" || true; } > "$BRC"
    echo "예전 cka-lab 줄을 지웠습니다 (백업: ~/.bashrc.cka-bak)"
  fi
  printf '\n%s\n' "$LINE" >> "$BRC"
  echo "~/.bashrc 에 추가했습니다."
fi
echo "지금 터미널에 바로 적용하려면:  source $RC"
