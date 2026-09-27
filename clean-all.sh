#!/usr/bin/env bash
# 모든 실습 세트가 클러스터에 만들어 둔 리소스와 진행 기록을 지운다.
#
#   bash clean-all.sh            무엇을 지울지 보여주고 물어본다
#   bash clean-all.sh --yes      묻지 않고 바로 지운다
#   bash clean-all.sh --dry-run  지우지 않고 대상만 보여준다
#
# 각 세트의 exam.sh clean 을 부르므로, 그 세트가 만든 것만 정확히 지운다.
# 실습과 무관한 리소스는 건드리지 않는다.
set -uo pipefail
cd "$(dirname "$0")"

RED='\033[0;31m'; GREEN='\033[0;32m'; BLUE='\033[0;34m'
CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; RESET='\033[0m'

YES=0; DRY=0
for a in "$@"; do
  case "$a" in
    --yes|-y) YES=1 ;;
    --dry-run|-n) DRY=1 ;;
    *) echo "모르는 옵션: $a"; exit 1 ;;
  esac
done

sets=()
for d in */; do
  [[ -f "$d/exam.sh" ]] && sets+=("${d%/}")
done
(( ${#sets[@]} == 0 )) && { echo "실습 세트를 찾지 못했습니다."; exit 1; }

echo ""
echo -e "${BOLD}지금 연결된 클러스터${RESET}"
kubectl config current-context 2>/dev/null | sed 's/^/  컨텍스트: /' || echo "  (컨텍스트를 읽지 못했습니다)"
kubectl get nodes --no-headers 2>/dev/null | awk '{print "  노드: "$1"  "$2}' || {
  echo -e "  ${RED}kubectl 로 클러스터에 닿지 않습니다.${RESET}"; exit 1; }

# 엉뚱한 클러스터에서 도는 사고를 막는다.
# 이 실습 클러스터는 192.168.56.x 의 VirtualBox 노드다.
SERVER=$(kubectl config view --minify -o jsonpath='{.clusters[0].cluster.server}' 2>/dev/null)
echo "  서버: ${SERVER:-알 수 없음}"
case "$SERVER" in
  *192.168.56.*|*127.0.0.1*|*localhost*) ;;
  *)
    echo ""
    echo -e "  ${RED}${BOLD}실습 클러스터가 아닌 것 같습니다.${RESET}"
    echo -e "  ${DIM}실습 클러스터는 192.168.56.x 입니다. 지금은 위 서버에 연결돼 있습니다.${RESET}"
    if (( ! DRY )); then
      read -r -p "  그래도 이 클러스터에서 지울까요? (DELETE 를 입력) " sure
      [[ "$sure" == "DELETE" ]] || { echo "  중단했습니다."; exit 0; }
    fi
    ;;
esac

echo ""
echo -e "${BOLD}정리할 세트 ${#sets[@]}개${RESET}  ${DIM}(각 세트의 리소스 + 진행 기록)${RESET}"
printf '  %s\n' "${sets[@]}" | paste -d' ' - - - 2>/dev/null || printf '  %s\n' "${sets[@]}"

if (( DRY )); then
  echo ""
  echo -e "${CYAN}--dry-run 이므로 아무것도 지우지 않았습니다.${RESET}"
  exit 0
fi

if (( ! YES )); then
  echo ""
  echo -e "${RED}${BOLD}되돌릴 수 없습니다.${RESET} 풀던 기록과 만들어 둔 리소스가 모두 사라집니다."
  read -r -p "  계속할까요? (yes 를 입력) " ans
  [[ "$ans" == "yes" ]] || { echo "  취소했습니다."; exit 0; }
fi

echo ""
ok=0; fail=0
for s in "${sets[@]}"; do
  printf "  %-22s " "$s"
  if (cd "$s" && bash exam.sh clean </dev/null &>/dev/null); then
    rm -rf "$s/work"; mkdir -p "$s/work"; touch "$s/work/.gitkeep"
    echo -e "${GREEN}정리됨${RESET}"; ok=$((ok+1))
  else
    echo -e "${RED}실패${RESET} ${DIM}(bash $s/exam.sh clean 으로 직접 확인)${RESET}"; fail=$((fail+1))
  fi
done

echo ""
echo -e "  ${BOLD}${ok}개 정리 완료${RESET}${fail:+, ${RED}${fail}개 실패${RESET}}"
echo ""
echo -e "${DIM}실습이 만든 것 말고도 남은 게 있는지 보려면:${RESET}"
echo -e "  ${CYAN}kubectl get all -A | grep -vE 'kube-system|kube-public|kube-node-lease|^NAMESPACE'${RESET}"
echo -e "  ${CYAN}kubectl get ns${RESET}"
