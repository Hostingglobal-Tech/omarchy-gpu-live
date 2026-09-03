#!/bin/bash
# AI-OS USB 만들기 (Linux)
#
# Ventoy 를 USB 에 설치하고 ISO 를 복사한다. 그 다음부터는 ISO 파일을
# 그냥 복사해 넣기만 하면 여러 개를 골라 부팅할 수 있다.
#
# 쓰는 법:
#   ./make-usb.sh /dev/sdX aios.iso
#   ./make-usb.sh --list                 # 꽂힌 USB 목록만 본다
#
# ★이 스크립트는 지정한 장치를 통째로 지운다. 두 번 확인한다.

set -u

RED=$'\e[31m'; GRN=$'\e[32m'; YEL=$'\e[33m'; OFF=$'\e[0m'
say()  { printf '%s\n' "$*"; }
die()  { printf '%s%s%s\n' "$RED" "$*" "$OFF" >&2; exit 1; }
ok()   { printf '%s%s%s\n' "$GRN" "$*" "$OFF"; }
warn() { printf '%s%s%s\n' "$YEL" "$*" "$OFF"; }

list_usb() {
  say "꽂혀 있는 이동식 장치:"
  say ""
  lsblk -d -o NAME,SIZE,TRAN,MODEL 2>/dev/null | awk 'NR==1 || $3=="usb"' | sed 's/^/  /'
  say ""
  say "위 목록에서 고른 뒤:  $0 /dev/<이름> <iso 파일>"
}

[ "${1:-}" = "--list" ] && { list_usb; exit 0; }
[ $# -lt 2 ] && { say "쓰는 법: $0 /dev/sdX aios.iso"; say ""; list_usb; exit 2; }

DEV="$1"; ISO="$2"

# ── 확인 ────────────────────────────────────────────────────────────
[ -b "$DEV" ] || die "장치가 아니다: $DEV"
[ -f "$ISO" ] || die "ISO 파일이 없다: $ISO"

# 내장 디스크를 지우는 사고를 막는다 — 이동식인지 반드시 본다.
BASE=$(basename "$DEV")
REMOVABLE=$(cat "/sys/block/$BASE/removable" 2>/dev/null || echo 0)
TRAN=$(lsblk -dn -o TRAN "$DEV" 2>/dev/null)
if [ "$REMOVABLE" != "1" ] && [ "$TRAN" != "usb" ]; then
  die "$DEV 는 이동식이 아니다. 내장 디스크를 지울 뻔했다 — 멈춘다."
fi

SIZE=$(lsblk -dn -o SIZE "$DEV" 2>/dev/null)
MODEL=$(lsblk -dn -o MODEL "$DEV" 2>/dev/null)
ISOSZ=$(du -h "$ISO" | cut -f1)

say ""
warn "이 장치를 통째로 지운다:"
say "    $DEV  ($SIZE, $MODEL)"
say ""
say "  얹을 것:  $ISO  ($ISOSZ)"
say ""
printf '  정말 지울까? 장치 이름을 그대로 입력하라 (%s): ' "$DEV"
read -r ANS
[ "$ANS" = "$DEV" ] || die "취소했다."

# ── Ventoy 준비 ─────────────────────────────────────────────────────
VENTOY=$(command -v ventoy 2>/dev/null || echo "")
if [ -z "$VENTOY" ]; then
  for d in ./ventoy* /opt/ventoy* "$HOME"/ventoy*; do
    [ -x "$d/Ventoy2Disk.sh" ] && { VENTOY="$d/Ventoy2Disk.sh"; break; }
  done
fi
[ -n "$VENTOY" ] || die "Ventoy 를 못 찾았다.
  https://www.ventoy.net 에서 받아 이 폴더에 풀거나 PATH 에 두어라."

# ── 굽기 ────────────────────────────────────────────────────────────
say ""
say "1/3  Ventoy 설치"
# -I = 강제 재설치, -r = 뒤에 보존 공간(MB). 영구 저장용 자리를 남긴다.
RESERVE=20480
sudo "$VENTOY" -I -r "$RESERVE" "$DEV" || die "Ventoy 설치 실패"

say ""
say "2/3  마운트"
sleep 2
sudo partprobe "$DEV" 2>/dev/null
MNT=$(mktemp -d)
VPART="${DEV}1"
[ -b "$VPART" ] || VPART="${DEV}p1"
sudo mount "$VPART" "$MNT" || die "마운트 실패: $VPART"

say ""
say "3/3  ISO 복사 (몇 분 걸린다)"
sudo cp -v "$ISO" "$MNT/" || { sudo umount "$MNT"; die "복사 실패"; }
sync
sudo umount "$MNT"; rmdir "$MNT"

say ""
ok "끝났다."
say ""
say "  이 USB 로 부팅하면 Ventoy 메뉴에서 ISO 를 고를 수 있다."
say ""
say "  ★영구 저장을 쓰려면 (저장한 것이 재부팅에 남는다):"
say "     뒤쪽에 ${RESERVE}MB 를 비워 두었다. 그 자리에 ext4 저장 영역을 만들고"
say "     라벨을 AIOSDATA 로 주면, 부팅 메뉴의 '영구 저장' 항목이 그것을 쓴다."
say "     자세한 것은 docs/persist.md"
say ""
