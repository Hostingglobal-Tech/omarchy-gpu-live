# 상류(omarchy-iso)에 얹는 패치

`no-offline-mirror.patch` — 오프라인 설치용 pacman 미러(패키지 2,493개 **4.5GB**)를
ISO 에서 뺀다. `AIOS_NO_OFFLINE_MIRROR=1` 을 준 빌드에서만 발동하고 상류 기본 동작은
그대로다.

**왜 필요한가** — 이 미러는 인터넷 없이 *호스트 디스크에 설치*하기 위한 것이다.
AI-OS 는 호스트 내장 디스크를 읽지도 쓰지도 않으므로 한 번도 쓰이지 않는다.
그런데 이것 때문에 ISO 가 **6.29GB** 가 되어 Ventoy USB(FAT32)의 단일 파일 상한
**4GiB** 를 넘는다. 빼면 약 1.8GB.

**지우지 않고 가린다** — `$offline_mirror_dir` 는 호스트 웜 캐시
(`~/.cache/omarchy/iso_stable/airootfs/var/cache/omarchy`)의 bind mount 다.
`-delete` 하면 다음 빌드가 4.5GB 를 다시 받는다. 빈 디렉토리를 `mount --bind` 로
덮어 mkarchiso 에게만 안 보이게 하고, 끝나면 `umount` 로 되돌린다.

## 적용

```bash
cd <omarchy-iso 클론>
git apply <AI-OS>/patches/no-offline-mirror.patch
```

## 빌드

```bash
AIOS_NO_OFFLINE_MIRROR=1 setsid nohup ./bin/omarchy-iso-make --no-boot-offer \
  > ~/aios-iso-build.log 2>&1 < /dev/null &
```

**`setsid` 를 빼지 마라.** 뺐다가 ssh 가 끊기며 SIGHUP 으로 빌드가 33% 에서 죽었고,
잘린 ISO 를 완성본으로 알고 USB·GitHub Release 까지 퍼뜨렸다(2026-08-23).

## 빌드 후 필수 검사 — ISO 가 잘렸는지

```bash
SZ=$(stat -c %s "$ISO")
BLK=$(dd if="$ISO" bs=1 skip=32848 count=4 2>/dev/null | od -An -tu4 | tr -d ' ')
[ $((BLK*2048)) -le "$SZ" ] || echo "잘렸다"
```

ISO 는 자기 크기를 PVD(오프셋 32768+80)에 2048바이트 블록 수로 적어 둔다.
**sha256 도 `dd` 전체 읽기도 이 사고를 못 잡는다** — 해시는 "내가 만든 것과 같다" 만
증명하고, `dd` 는 있는 데까지만 읽는다.
