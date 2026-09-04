# 패치

ISO 를 다시 굽지 않고 부팅한 뒤 한 번 실행해 고치는 것들입니다.
소스가 전부 여기 있습니다 — 라이브 USB 는 남의 컴퓨터에서 도는 물건이라
감춰진 동작이 있으면 안 됩니다.

## aios-live-fix.sh

라이브 세션에서 데스크톱이 제대로 뜨게 합니다.

고치는 것:

| # | 증상 | 원인 |
|---|---|---|
| 1 | 터미널 맨 위에 빨간 오류 (`foot.ini: failed to open`) | 테마 디렉토리가 없다 |
| 2 | 배경화면이 안 걸려 화면이 검다 | 같은 원인 |
| 3 | 상단 바가 안 뜬다 | 같은 원인 + 가상머신에서 Qt 하드웨어 렌더 실패 |
| 4 | 150초 두면 화면보호기가 덮는다 | Omarchy 기본값 |

1~3 은 원인이 하나입니다. Omarchy 는 테마를
`~/.local/state/omarchy/current/` 에 두는데, 그 디렉토리는 **설치 과정에서**
`omarchy-theme-set` 이 만듭니다. 라이브 세션 사용자는 설치를 거치지 않으므로
그것이 없습니다. 이 스크립트가 대신 만들어 줍니다. Omarchy 자체는 손대지
않습니다 — 설치본에서 이미 하는 일을 라이브 세션에서도 하게 할 뿐입니다.

4 는 잠깐 쓰는 라이브 USB 에 어울리지 않아 끕니다.

### 쓰는 법

```bash
curl -O https://raw.githubusercontent.com/Hostingglobal-Tech/omarchy-gpu-live/main/patches/aios-live-fix.sh
chmod +x aios-live-fix.sh
./aios-live-fix.sh
```

옵션:

```
./aios-live-fix.sh gruvbox    # 테마를 골라서
./aios-live-fix.sh --list     # 고를 수 있는 것 보기
./aios-live-fix.sh --no-bar   # 배경만, 상단 바는 그대로
```

터미널을 새로 열면 오류 없이 뜹니다.

라이선스 MIT.
