#!/bin/bash
# 부팅 메뉴 배경(splash.png)을 AI-OS 로 만든다.
#
# 왜: 사장님 지시 — "Arch Linux 그거도 AI-OS 그런걸로 바꿔주지.
#     첨보는 사람들이 보고 아리송해 하잖아."
#
# 규격 640x480 PNG. 화면을 세 구역으로 나눠 쓴다:
#   위(y 0~150)    우리가 쓴다 — 이름·정체
#   중앙(y 170~340) syslinux 메뉴 상자가 덮는다 — 비워 둔다
#   아래(y 400~480) ★syslinux 가 도움말·카운트다운을 직접 쓴다 — 비워 둔다
#
# ★2026-09-04 실측: 아래에 글자를 넣었더니 도움말과 겹쳐 둘 다 못 읽었다.
#   안심 문구("Nothing is installed")는 TEXT HELP 가 이미 같은 말을 한다.
#
# 색은 원본 팔레트를 따른다 — 바탕 #1E1E1E, 강조 #2096D1, 글자 #DEE4E7
set -euo pipefail

OUT="${1:-/tmp/splash-aios.png}"

F=""
for c in DejaVu-Sans-Bold DejaVu-Sans DejaVuSans-Bold Liberation-Sans-Bold; do
  convert -list font 2>/dev/null | grep -q "Font: $c\$" && { F="-font $c"; break; }
done
[ -z "$F" ] && {
  p=$(fc-match -f "%{file}" "DejaVu Sans:bold" 2>/dev/null)
  [ -n "$p" ] && F="-font $p"
}
echo "  폰트: ${F:-기본}"

convert -size 640x480 gradient:'#232428'-'#141518' \
  -fill '#2096D1' -draw 'rectangle 0,0 640,3' \
  $F -fill '#DEE4E7' -pointsize 68 -gravity north -annotate +0+42 'AI-OS' \
  $F -fill '#8FA3AD' -pointsize 17 -gravity north -annotate +0+122 'Live USB  ·  Omarchy Linux (Arch + Hyprland)' \
  $F -fill '#6E7B85' -pointsize 13 -gravity north -annotate +0+148 'NVIDIA driver preloaded  ·  RTX 50 black-screen fixed' \
  -depth 8 PNG24:"$OUT"

identify "$OUT" | sed 's/^/  /'
