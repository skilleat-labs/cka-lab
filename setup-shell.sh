#!/usr/bin/env bash
# ssh 로 들어오는 터미널에도 시험 환경 셸 설정을 적용한다 (웹 패널 터미널은 자동).
# 사용: bash setup-shell.sh
set -euo pipefail
RC="$(cd "$(dirname "$0")" && pwd)/_lib/exam-shellrc.sh"
LINE="[ -f \"$RC\" ] && . \"$RC\"   # cka-lab 시험 환경 (자동완성·alias k·\$do)"
if grep -qF "$RC" "$HOME/.bashrc" 2>/dev/null; then
  echo "이미 적용돼 있습니다: ~/.bashrc"
else
  printf '\n%s\n' "$LINE" >> "$HOME/.bashrc"
  echo "~/.bashrc 에 추가했습니다."
fi
echo "지금 터미널에 바로 적용하려면:  source $RC"
