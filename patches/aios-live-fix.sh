#!/usr/bin/env bash
# aios-live-fix — 라이브 세션에서 데스크톱이 제대로 뜨게 한다
#
# 무엇을 고치나
# ─────────────
# 라이브 USB 로 부팅하면 세 가지가 어긋난다. 전부 원인이 하나다:
# Omarchy 는 테마를 `~/.local/state/omarchy/current/` 에 두는데, 그 디렉토리는
# 설치 과정에서 `omarchy-theme-set` 이 만든다. 라이브 세션 사용자는 설치를
# 거치지 않으므로 그것이 없다.
#
#   1) 터미널 맨 위에 빨간 오류가 뜬다
#        error: foot: ~/.config/foot/foot.ini:2: [main].include:
#          ~/.local/state/omarchy/current/theme/foot.ini: failed to open
#   2) 배경화면이 안 걸려 화면이 검다
#   3) 상단 바가 안 뜬다
#
# 여기에 하나를 더 고친다:
#
#   4) 화면보호기 — 150초만 두면 매트릭스 애니메이션이 화면을 덮는다.
#      라이브 USB 는 남의 PC 앞에서 잠깐 쓰는 물건이다. 화면이 덮이면
#      쓰던 것이 사라진 줄 알고 당황한다. 장식일 뿐 하는 일이 없어 끈다.
#
# Omarchy 자체는 손대지 않는다 — 설치본에서 이미 하는 일을 라이브 세션에서도
# 하게 할 뿐이다.
#
# 왜 별도 패치인가
# ────────────────
# ISO 를 다시 굽는 대신 부팅한 뒤 한 번 실행하면 되게 만들었다. 무엇을 하는지
# 이 파일 하나로 다 읽힌다 — 라이브 USB 는 남의 컴퓨터에서 도는 물건이라
# 감춰진 동작이 있으면 안 된다.
#
# 쓰는 법
#   ./aios-live-fix.sh              # 기본 테마로
#   ./aios-live-fix.sh gruvbox      # 테마를 골라서
#   ./aios-live-fix.sh --list       # 고를 수 있는 것 보기
#   ./aios-live-fix.sh --no-bar     # 배경만, 상단 바는 그대로 둔다
#
# 라이선스 MIT

set -uo pipefail

THEMES_DIR="/usr/share/omarchy/themes"
STATE_DIR="$HOME/.local/state/omarchy"
CURRENT="$STATE_DIR/current"
OMARCHY_CFG="$HOME/.config/omarchy"
DEFAULT_THEME="catppuccin"
WANT_BAR=1

say()  { printf '%s\n' "$*"; }
warn() { printf '  경고: %s\n' "$*" >&2; }
die()  { printf '  오류: %s\n' "$*" >&2; exit 1; }

list_themes() {
  [ -d "$THEMES_DIR" ] || die "$THEMES_DIR 가 없다. Omarchy 시스템이 맞나?"
  find "$THEMES_DIR" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null | sort
}

ARGS=()
for a in "$@"; do
  case "$a" in
    --list|-l) say "고를 수 있는 테마:"; list_themes | sed 's/^/  /'; exit 0 ;;
    --no-bar)  WANT_BAR=0 ;;
    -*)        die "모르는 옵션: $a" ;;
    *)         ARGS+=("$a") ;;
  esac
done
THEME="${ARGS[0]:-$DEFAULT_THEME}"

[ -d "$THEMES_DIR" ] || die "$THEMES_DIR 가 없다. Omarchy 시스템이 맞나?"
SRC="$THEMES_DIR/$THEME"
if [ ! -d "$SRC" ]; then
  warn "'$THEME' 라는 테마가 없다."
  say  "고를 수 있는 것:"; list_themes | sed 's/^/  /'
  exit 1
fi

say "AI-OS 라이브 세션 보정"
say "  테마   $THEME"
say ""

# ── 1. 테마 디렉토리 ──────────────────────────────────────
#   심볼릭이 아니라 실제 디렉토리다. omarchy-theme-set 도 그렇게 만든다
#   (next-theme 를 만들어 current/theme 로 mv 한다 — 소스 292~293행).
mkdir -p "$CURRENT" || die "$CURRENT 를 만들 수 없다"
rm -rf "$CURRENT/theme"
cp -r "$SRC" "$CURRENT/theme" || die "테마 복사 실패"
say "  [1/4] 테마 복사        $CURRENT/theme"

# ── 2. foot.ini ───────────────────────────────────────────
#   foot 의 include 는 파일이 없으면 오류를 낸다. 그 오류가 이 패치를
#   만든 이유다.
#
#   ★기본 서식(/usr/share/omarchy/default/themed/foot.ini.tpl)을 그대로
#     복사하면 안 된다. 그것은 `{{ bright_blue_strip }}` 같은 치환 자리를
#     담은 틀이고, foot 은 그것을 색으로 못 읽어 새 오류를 낸다.
#     색이 없는 것보다 오류가 안 나는 것이 낫다.
if [ ! -f "$CURRENT/theme/foot.ini" ]; then
  printf '# AI-OS: 이 테마에는 foot 색 설정이 없다. include 오류만 막는다.\n' \
    > "$CURRENT/theme/foot.ini"
  say "  [2/4] foot.ini 생성    (include 오류 방지)"
else
  say "  [2/4] foot.ini        테마에 이미 있음"
fi

# ── 3. 배경화면 ───────────────────────────────────────────
BG=$(find "$CURRENT/theme/backgrounds" -maxdepth 1 -type f \
       \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' \) 2>/dev/null | sort | head -1)
if [ -n "$BG" ]; then
  ln -nsf "$BG" "$CURRENT/background"
  if command -v swaybg >/dev/null 2>&1; then
    pkill -x swaybg 2>/dev/null
    setsid swaybg -m fill -i "$BG" >/dev/null 2>&1 &
    say "  [3/4] 배경화면        $(basename "$BG")"
  else
    say "  [3/4] 배경화면 링크만  (swaybg 없음 — 화면에는 안 걸린다)"
  fi
else
  warn "이 테마에는 배경 그림이 없다."
fi

# ── 4. 화면보호기 끄기 ────────────────────────────────────
#   기본 150초. 라이브 USB 를 잠깐 만지다 손을 떼면 매트릭스가 화면을
#   덮는다. 하는 일이 없는 장식이라 끈다.
mkdir -p "$OMARCHY_CFG"
if [ -f "$OMARCHY_CFG/shell.json" ] && command -v python3 >/dev/null 2>&1; then
  python3 - "$OMARCHY_CFG/shell.json" <<'PY' 2>/dev/null || true
import json, sys
p = sys.argv[1]
try:    d = json.load(open(p))
except Exception: d = {}
d.setdefault("idle", {}).update({"screensaver": 0, "lock": 0})
json.dump(d, open(p, "w"), indent=2, ensure_ascii=False)
PY
else
  printf '{ "idle": { "screensaver": 0, "lock": 0 } }\n' > "$OMARCHY_CFG/shell.json"
fi
say "  [4/4] 화면보호기       꺼짐"

# ── 상단 바 ───────────────────────────────────────────────
#   Omarchy 의 바는 quickshell 이다. 가상머신이나 GPU 가속이 없는 곳에서는
#   Qt 가 하드웨어 렌더에 실패해 바가 안 뜬다(wl_surface.attach 오류).
#   소프트웨어 렌더로 떨어뜨리면 뜬다. 실기기에서는 무해하다.
if [ "$WANT_BAR" = "1" ] && command -v quickshell >/dev/null 2>&1; then
  if ! pgrep -x quickshell >/dev/null 2>&1; then
    QS_DISABLE_FILE_WATCHER=1 QT_QPA_PLATFORM=wayland QT_QUICK_BACKEND=software \
      OMARCHY_PATH="${OMARCHY_PATH:-/usr/share/omarchy}" \
      setsid quickshell -n -p "${OMARCHY_PATH:-/usr/share/omarchy}/shell" \
      >/dev/null 2>&1 &
    sleep 2
    pgrep -x quickshell >/dev/null 2>&1 \
      && say "        상단 바         떴다" \
      || warn "상단 바를 못 띄웠다. --no-bar 로 건너뛸 수 있다."
  else
    say "        상단 바         이미 떠 있음"
  fi
fi

say ""
say "확인:"
[ -f "$CURRENT/theme/foot.ini" ] && say "  foot.ini      있음  (새 터미널부터 오류 없이 뜬다)" \
                                 || warn "foot.ini 가 여전히 없다"
[ -L "$CURRENT/background" ]     && say "  배경화면      $(basename "$(readlink "$CURRENT/background")")"
pgrep -x swaybg    >/dev/null 2>&1 && say "  swaybg        돌고 있음"
pgrep -x quickshell >/dev/null 2>&1 && say "  상단 바       돌고 있음"
say ""
say "터미널을 새로 열면 오류 없이 뜬다."
