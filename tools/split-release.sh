#!/bin/bash
# ISO 를 GitHub 릴리스에 올릴 수 있게 나눈다.
#
# GitHub 릴리스는 파일 하나가 2GiB 를 넘을 수 없다. 그래서 조각내고,
# 받는 쪽이 합쳐서 원본과 같은지 확인할 수 있게 체크섬을 같이 만든다.
#
#   ./split-release.sh aios.iso [출력폴더]
#
# 만드는 것:
#   <이름>.part00, part01, ...   조각 (각 1.9GiB)
#   <이름>.sha256                합친 뒤 검사용
#   <이름>.parts.sha256          조각별 검사용 (덜 받은 조각을 집어낸다)
#   HOWTO-합치기.txt             받는 사람용 안내

set -eu

ISO="${1:?쓰는 법: $0 <iso 파일> [출력폴더]}"
OUT="${2:-./release-parts}"
CHUNK="1900M"   # 2GiB 상한에 여유를 둔다

[ -f "$ISO" ] || { echo "파일이 없다: $ISO" >&2; exit 1; }

BASE=$(basename "$ISO")
mkdir -p "$OUT"

SZ=$(stat -c %s "$ISO")
echo "원본  : $BASE  ($(numfmt --to=iec "$SZ" 2>/dev/null || echo "$SZ bytes"))"
echo "조각  : $CHUNK 씩"
echo ""

echo "1/3  나누는 중..."
split -b "$CHUNK" -d -a 2 "$ISO" "$OUT/$BASE.part"
N=$(ls "$OUT/$BASE.part"* | wc -l)
echo "      조각 $N 개"

echo ""
echo "2/3  체크섬..."
( cd "$(dirname "$ISO")" && sha256sum "$BASE" ) > "$OUT/$BASE.sha256"
( cd "$OUT" && sha256sum "$BASE.part"* ) > "$OUT/$BASE.parts.sha256"

echo ""
echo "3/3  안내문..."
cat > "$OUT/HOWTO-합치기.txt" <<EOF
AI-OS ISO 합치기
================

파일이 커서 조각으로 나눠 올렸습니다. 전부 받은 뒤 합치면 됩니다.

■ 받을 것
    $BASE.part00 ~ $BASE.part$(printf '%02d' $((N-1)))   (조각 $N 개)
    $BASE.sha256          (합친 뒤 검사용)
    $BASE.parts.sha256    (조각별 검사용)

■ 조각이 온전한지 먼저 보기 (권장)

    Linux/macOS:  sha256sum -c $BASE.parts.sha256
    Windows:      certutil -hashfile $BASE.part00 SHA256
                  (parts.sha256 파일의 값과 눈으로 대조)

  하나라도 어긋나면 그 조각만 다시 받으세요.

■ 합치기

  Linux / macOS
      cat $BASE.part* > $BASE
      sha256sum -c $BASE.sha256

  Windows (명령 프롬프트)
      copy /b $BASE.part00+$BASE.part01$([ $N -gt 2 ] && for i in $(seq 2 $((N-1))); do printf '+%s.part%02d' "$BASE" "$i"; done) $BASE
      certutil -hashfile $BASE SHA256

  Windows (PowerShell)
      \$out = [IO.File]::Create("\$PWD\\$BASE")
      Get-ChildItem "$BASE.part*" | Sort-Object Name | ForEach-Object {
          \$in = [IO.File]::OpenRead(\$_.FullName); \$in.CopyTo(\$out); \$in.Close()
      }
      \$out.Close()
      Get-FileHash $BASE -Algorithm SHA256

■ 확인

  합친 파일의 SHA256 이 $BASE.sha256 의 값과 같아야 합니다.
  다르면 조각을 덜 받았거나 순서가 틀린 것입니다 — 그대로 구우면 부팅이 안 됩니다.

■ 그 다음

  USB 에 굽는 법은 README 를 보세요. Ventoy 를 쓰면 이 ISO 를 그냥
  복사해 넣기만 하면 됩니다.
EOF

echo ""
echo "끝났다 -> $OUT"
ls -la "$OUT" | tail -n +2 | awk '{printf "  %-40s %s\n", $9, $5}'
echo ""
echo "GitHub 릴리스에 이 폴더의 파일을 전부 올리면 된다."
