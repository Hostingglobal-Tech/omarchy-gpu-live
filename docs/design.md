# AI-OS 설계 (2026-08-23, Fable 자문 반영)

전제: Ventoy + persistence / 자립형 ISO(중앙 전송 없이 동작) / 신규 상주 코드 Rust /
호스트 내장 디스크 불가침 / 자격증명 외부 전송 금지.
**단순 우선** — 복잡한 보안층은 얹지 않는다(2026-08-23 사장님 지시).

## 1. 계층 구조 — 포크하지 않는다

Omarchy 를 **서명된 pacman 패키지 상류로 소비**한다. 상류 파일을 직접 고치지 않는다.

```
AI-OS/
  profile/            mkarchiso 프로파일 (archiso releng 시드 + 우리 diff)
  overlay/airootfs/   우리 파일만
  tools/              Rust: bootcheck, vaultd, mediactl, bootstrapd
  manifests/          버전 핀 + sha256 (omarchy pkg, kernel, nvidia, 에이전트, 모델)
  builder/            빌드 컨테이너 (omarchy-iso builder 차용, MIT)
  ventoy/             claude-code-os 제작기 확장
```

근거: Omarchy 는 `omarchy`/`omarchy-settings`/`omarchy-nvim` pacman 패키지로 배포되고
런타임 정본은 `/usr/share/omarchy`. ISO 마감 시
`arch-chroot → omarchy-apply-system --first-install` +
`arch-chroot -u user → omarchy-provision-user` 가 **상류의 정식 경로**다.
"빌드 시점에 완제품 사용자 환경을 구워 넣는" 우리 요구와 같은 메커니즘이 이미 있다.

## 2. persistence — 라벨 고정이 핵심

archiso persistence 는 initramfs 훅(`mkinitcpio-archiso/hooks/archiso`)이 전담.

| 파라미터 | 기본값 | 동작 |
|---|---|---|
| `cow_label` | 없음 | `/dev/disk/by-label/${cow_label}` 로 장치 해석 |
| `cow_device` | 없음 | 장치 직접 지정(label 보다 우선) |
| `cow_persistent` | label/device 지정 시 `P` | P=영속, N=휘발 |
| `cow_directory` | `persistent_${archisolabel}/${arch}` | cow 장치 안 upperdir 경로 |
| `cow_spacesize` | `256M` | **tmpfs(비영속)일 때만** 의미 |

### 함정 — ISO 재빌드하면 상태가 사라진 것처럼 보인다

기본 upperdir 이 `persistent_${archisolabel}/…` 인데 omarchy-iso 라벨은
`OMARCHY_YYYYMM`(빌드 월 포함). 재빌드 = 라벨 변경 = 새 upperdir = 로그인 소실.

**대응**: (a) `iso_label` 고정 문자열 (b) 부트 엔트리에 `cow_directory=persistent/x86_64` 명시.

### Plan A / Plan B

- **Plan A**: Ventoy `.dat` + `vtoycow` 라벨 + `ventoy.json`.
  `CreatePersistentImg.sh -s <MB> -t ext4 -l vtoycow`, backend 는 반드시 1번 파티션.
- **Plan B (2곳+ 실패 시 전환)**: Ventoy 설치 시 `-r <MB>` 로 디스크 끝 공간 예약 →
  실파티션 ext4 `OMARCHY_PERSIST` → 부트 엔트리에 `cow_label=OMARCHY_PERSIST` 소성.
  Ventoy persistence 플러그인이 경로에서 빠져 신뢰성이 올라간다.

실패 비대칭: "장치 지정했는데 없음" = **응급 셸**(시끄러운 실패) /
"장치 미지정" = **조용한 휘발**. 그래서 검출이 필요하다.

### bootcheck (Rust, systemd oneshot, Before=display-manager)

1. `/run/archiso/cowspace` SOURCE/FSTYPE — **tmpfs = VOLATILE 확정**
2. upperdir 카나리아 파일 — 있으면 PERSIST-CONTINUED, 없으면 PERSIST-FRESH
3. cow 사용률 — 80%/95% 경고

결과를 `/run/omarchy-live/status.json` 에 기록 → SDDM 배너 + 상단바 배지
(PERSIST / VOLATILE). **VOLATILE 이면 로그인 진입 전에 경고**한다 — 로그인해봤자
휘발된다는 사실을 미리 알려주는 것뿐, 그 이상은 하지 않는다.

## 3. 자격증명 — 단순하게 (2026-08-23 사장님 지시)

> "분실할 걱정하지 말고 복잡하게 하지 말고 tailscale 키도 복잡하게 넣을려고 하지 말고
>  쉽게 쉽게 구현하라"

**persistence 에 평문으로 그냥 저장한다.** LUKS 금고·Ed25519 per-media 키쌍·임차 TTL
토큰·leak-audit·무효화 드릴 — Fable 이 제안한 이 층 전부 **채택하지 않는다.**

| 자산 | 저장 |
|---|---|
| `~/.claude` · `~/.codex` (OAuth) | persistence 평문 |
| Tailscale 노드키 | persistence 평문 (`/var/lib/tailscale`) |

Tailscale 은 **authkey 파일 하나**를 매체에 두고 첫 부팅에 `tailscale up --authkey` 로 붙인다.
그 뒤로는 노드키가 persistence 에 남아 재등록이 없다.

분실 대비는 필요해지면 그때 얹는다. 지금은 **돌아가게 만드는 것**이 먼저다.

## 4. 자립형 — 업데이트 경로 동결

**Omarchy 에 자동 업데이트 타이머는 없다**(`OnCalendar` 0건 실측). 봉인 지점:

| 경로 | 실측 동작 | 동결 |
|---|---|---|
| mise 스텁 | `~/.local/bin/<cmd>` 가 매 실행마다 `MISE_MINIMUM_RELEASE_AGE=0` + `mise use -g` 로 **최신 해석 시도** | 빌드 체르트에서 실설치 후 스텁을 실물 `exec` 로 재작성 |
| `omarchy-update` | pacman -Syu + AUR + mise + migrate | Rust 가드로 대체("갱신은 새 ISO 빌드로") |
| pacman | 롤링 | 런타임 불필요. Arch Archive 날짜 고정 스냅샷 |
| `omarchy-update-dev` | git pull | `/usr/share/omarchy` 소비 시 즉시 exit 0(무해) |

**완료 조건**: 네트워크 물리 차단 후 부팅 → Hyprland → `claude/codex/ffmpeg/tailscale --version`
전부 성공, 다운로드 시도 로그 0건.


## 5. 3계층 갱신 — 한 덩어리로 굽지 않는다

| 계층 | 내용 | 주기 | 방법 |
|---|---|---|---|
| **S** assets 파티션 | 모델 2.94GB, CUDA/cuDNN wheel, ffmpeg, 골든샘플, **에이전트 CLI 실물** | 모델=무기한 / 에이전트=주 | **ISO 재빌드 없이 파일 복사 + 매니페스트** |
| **M** ISO | Arch base+커널+NVIDIA, Omarchy 핀, 우리 Rust 도구, venv 골격 | 월 1 | CI 재빌드 → blue/green |
| **F** .dat + vault | 로그인·설정·이력 | 매 부팅 | 사용 자체 |

에이전트 CLI 가 가장 빨리 바뀌는데 그것 때문에 매주 수 GB ISO 를 굽는 건 낭비.
**에이전트를 assets 로 내리고 스텁이 매니페스트 핀 버전을 exec** 한다.


| # | Windows 현행 | 이동식 매체 |
|---|---|---|
| 1 | Tailscale 설치 | **소멸** → 빌드 시 소성 |
| 2 | 무인 모드 등록 | **대부분 소멸** — 노드키 vault 영속 |
| 3 | 중앙 연결 확인 | **남음** — 매 부팅 |
| 4 | Python + faster-whisper 설치 | **소멸** → 빌드 시 venv 소성 |
| 5 | GPU 실인식 | **남음** — 3단 프로브 |
| 6 | 워커 기동 | **남음** |

### GPU 3단 프로브 (Omarchy 경계 로직 이식)

PCI vendor `0x10de`, class `0x03*`, **device id ≥ `0x1e00` = Turing 이상(GSP)**.
`0x1340~0x1e00` = Maxwell/Pascal/Volta → 미지원 표시.

```
1단  sysfs PCI 스캔 (lspci 아님 — 절전 GPU 를 깨우지 않는다)
2단  nvidia 모듈 바인드 + NVML (이름·VRAM·드라이버 기록)
3단  CT2 CUDA 골든샘플 1건 전사 → RTF 실측 → 통과 시에만 수임 개시
```

**드라이버**: ISO 커널이 빌드 시 고정되므로 **런타임 DKMS 불필요**.
`nvidia-open` 단일 스택만 싣는다 — RTX 50(Blackwell)은 오픈 모듈 전용이고,
PC방 현역(RTX 20~50)은 전부 Turing+. Pascal 이하는 GPU_UNSUPPORTED 로 사유 표시.
NVIDIA 없는 자리 부팅을 위해 초기램 강제 로드 대신 udev 지연 로드.

### 상태기계 (bootstrapd, 화면에 항상 표시)

```
NO_GPU            NVIDIA 없음 — 데스크톱 전용 (정상 상태로 표시)
GPU_UNSUPPORTED   지원 밖 (사유 표기)
GPU_OK_OFFLINE    중앙 미도달 — 지수 백오프 15s→5m, 30분 지속 시 강조 경고
ACTIVE            일감 수행 중
DRAINING          임차 종료 임박 — 신규 수임 중단
```

**CPU 전사 폴백은 만들지 않는다** (배속 1.03 실측 — 무의미).

## 7. 크기

| 구성 | 크기 |
|---|---|
| ISO (미러 제외) | 3.5~5GB 추정 |
| assets 파티션 | 8~10GB |
| `.dat` overlay | 8GB 권장(최소 4) |
| blue/green 여분 | +5GB |
| **합계** | **~25–30GB → 64GB 매체 권장** |

overlay ENOSPC 대비 4중: 갱신 봉인 / `XDG_CACHE_HOME` tmpfs 상한 2G +
journald `SystemMaxUse=64M` / bootcheck 사용률 감시 / `ExtendPersistentImg.sh`.
오디오·전사 작업분은 overlay 가 아니라 tmpfs 스크래치에 둔다.

## 8. 단계 — 위험 큰 것 먼저

| 단계 | 완료 조건 |
|---|---|
| **0. 현장 정찰** | 부팅메뉴 진입 / Secure Boot 상태 / `lspci` GPU 채집 / USB 실효속도 / 유선 DHCP.  **MOK 등록은 호스트 NVRAM 에 키를 영구 기록** — 호스트 불가침 원칙과 충돌하므로 SB off 가능 자리 우선 |
| **1. 빌드 스파이크** | QEMU(`-net none`)에서 SDDM→Hyprland 진입, 4개 `--version` 성공, `omarchy update` 거부, bootcheck 가 VOLATILE 정확 표기 |
| **2. Ventoy + persistence** | 재부팅 후 마커 유지, `findmnt /run/archiso/cowspace`=ext4. dat 제거 부팅 시 VOLATILE 경고 표시 |
| **3. GPU + 워커** | `nvidia-smi` 인식, 골든샘플 RTF 기록, E2E MSSQL 적재 + 재실행 멱등 |
| **4. 운영화** | 월간 재빌드 완주, 에이전트 갱신이 ISO 재빌드 없이 완료 |

## 9. 라이선스

Omarchy MIT(DHH) / omarchy-iso MIT(Anton Hvornum) / claude-code-os MIT.
결합·수정·재배포 자유, 의무는 고지 유지뿐.

**주의 3건**:
- MIT 는 **상표를 부여하지 않는다**. 공개 배포 시 "Omarchy" 이름 사용은 별개 문제
- **ISO 에 굽는 NVIDIA 사용자공간·cuDNN/cuBLAS wheel·에이전트 CLI 실물은 각자 EULA** →
  **산출 ISO 는 private 보관(본인 매체 전용), 저장소에는 빌드 스크립트만**
- large-v3 CT2 변환본은 MIT 계보 — 소성 문제없음

## 10. 미확인 (정직 표기)

1. Ventoy issue #3407 의 정확한 수정 버전 — "Fixed" 라벨만 확인
2. `.dat` ext4 기능 플래그(`orphan_file` 등)와 실패의 인과 — 가설
3. 라이브 부팅에서 SDDM+Hyprland 자동 세션 기립 (체르트 적용은 상류 보증)
4. ISO·wheel 크기 "추정" 표기분

## 11. 부트 파라미터를 박을 자리 (2026-08-23 실측)

이 archiso 는 `archisolabel` 이 아니라 **`archisosearchuuid=%ARCHISO_UUID%`** 를 쓴다
(최신 버전). 수정 지점:

| 파일 | 줄 |
|---|---|
| `archiso/configs/releng/grub/grub.cfg` | 49 |
| `archiso/configs/releng/syslinux/archiso_sys-linux.cfg` | 9, 20 |

붙일 것:

```
cow_label=vtoycow cow_directory=persistent/x86_64
```

**단, 첫 부팅 테스트 후에 고친다.** Ventoy persistence 플러그인이 `cow_label` 을
자동 주입하는지 실제로 봐야 알기 때문이다. 먼저 굽고, 안 붙으면 그때 박는다.

확인 방법:

```bash
findmnt /run/archiso/cowspace     # ext4 = 성공 / tmpfs = 실패
```

## 12. Ventoy USB 는 FAT32 다 — 단일 파일 4GB 상한 (2026-08-23 실측)

persistence 를 8GB 로 만들어 복사했더니 **정확히 4,294,934,528 바이트(4GiB−32KB)에서
멈추고 `No space left on device`** 가 났다. 디스크 여유는 40GB 였다.

```
Get-Volume -DriveLetter E → FileSystem: FAT32
```

FAT32 는 파일 하나가 4GiB 를 넘지 못한다. 기존 `cco-persistence.dat` 이 3.67GB 인 것도
같은 제약이었다(그때 이미 겪고 3.5GB 로 만든 것이다).

**그래서 persistence 는 3.5GB(3584MB) 로 만든다.** 자격증명·설정·작업파일용으로 충분하다 —
모델과 CUDA 는 ISO 안에 들어가므로 여기 담지 않는다.

ISO 자체도 4GB 를 넘으면 안 된다. 현재 2.2GB 라 여유가 있지만, 자산을 소성해 넣다 보면
넘길 수 있다. **넘기면 그 USB 에 못 올린다** — 그때는 매체를 exFAT 로 다시 만들어야 하고
기존 ISO 들이 전부 날아간다.

| 파일 | 상한 |
|---|---|
| `aios.iso` | 4GiB (현재 2.2GB) |
| `aios-persistence.dat` | 4GiB (3.5GB 로 고정) |

## 13. 자산은 ISO 가 아니라 USB 에 둔다 (2026-08-23 사장님 제안)

> "ISO 안에 넣지 말고 USB 안에 넣고 ISO에서 USB 안에 파일을 다운로드받을 수 있게 하면 안될까?"

**채택한다.** 12장의 4GiB 벽이 통째로 사라지고, 부수 이득이 더 크다.

### 왜 더 나은가

| | ISO 소성 | **USB 별치** |
|---|---|---|
| ISO 크기 | 6.5GB — FAT32 불가 | **2.2GB 유지** |
| 모델 교체 | ISO 재빌드(수십 분) | **파일 복사** |
| 매체 재포맷 | exFAT 필수 | **불필요** |
| 네트워크 | 0 | **0** (같은 USB 라 마운트만 하면 된다) |
| 기존 USB | 재구성 필요 | **안 건드림** |

"다운로드"가 아니다 — **같은 매체이므로 마운트해서 바로 읽는다.** 그래서 오프라인
자립 원칙(4장)도 그대로 지켜진다.

### 어떻게 찾나

Ventoy 는 ISO 를 가상 디스크로 노출하지만 **USB 의 데이터 파티션은 그대로 보인다.**
라벨로 찾는다 — 장치 이름(`/dev/sdb1`)은 기기마다 달라지므로 쓰지 않는다.

```
/dev/disk/by-label/VENTOY     ← 실측: FileSystemLabel=VENTOY, FAT32, 59GB
```

### 배치

```
E:\  (VENTOY, FAT32)
  aios.iso                     2.2GB
  aios-persistence.dat         3.5GB
  aios-assets\
    models\faster-whisper-large-v3\    2.88GB  (파일별 4GiB 미만이라 FAT32 OK)
    wheels\                            약 1.1GB  nvidia_cublas_cu12 · nvidia_cudnn_cu12
    bin\                               ffmpeg 등 ISO 에 없는 것
    MANIFEST.sha256                    전 파일 해시 — 부팅 때 대조한다
```

### 부팅 후 배선

첫 부팅 서비스가 하는 일:

```
1. mount -o ro,exec,umask=022 /dev/disk/by-label/VENTOY /mnt/vtoy
2. MANIFEST.sha256 대조 — 어긋나면 그 자산은 안 쓴다(조용히 쓰면 그게 사고다)
3. 모델: 복사하지 않는다. faster-whisper 에 경로만 준다
   → /mnt/vtoy/aios-assets/models/faster-whisper-large-v3
4. wheel: persistence 의 venv 에 설치 (pip install --no-index --find-links)
5. bin: persistence 로 복사 후 chmod +x (FAT32 는 실행 비트를 못 갖는다)
```

**FAT32 주의 두 가지.** 실행 권한 비트가 없으므로 마운트 옵션 `exec,umask=022` 로
전체에 부여하거나 persistence 로 복사한다. 그리고 심볼릭 링크가 안 되므로 자산
트리에 링크를 쓰지 않는다.

### ISO 에 남는 것

OS·드라이버·런타임처럼 **부팅에 필요한 것**만 ISO 에 넣는다.
모델·wheel처럼 **크고 자주 바뀌는 것**은 USB 에 둔다. 경계는 이 한 줄이다.

### 배치판 — 자산과 ISO 가 따로 놀 때 알아채기

USB 별치의 대가는 **둘이 어긋날 수 있다는 것**이다. ISO 를 새로 굽고 자산이 옛것이면
경로·이름 규약이 달라 못 읽을 수 있는데, 아무 표시가 없으면 그냥 "자산이 없다" 로 보인다.

배치 규약에 번호를 매기고 양쪽에 적는다.

| 어디 | 파일 | 키 |
|---|---|---|
| ISO | `/etc/aios-release` | `AIOS_ASSET_API=1` — 이 ISO 가 읽을 수 있는 배치판 |
| USB | `aios-assets/VERSION` | `ASSET_LAYOUT=1` — 이 자산이 따르는 배치판 |

**번호가 같으면 자산을 마음대로 갈아끼워도 된다** — 그것이 이 설계의 요점이므로
여기서 차단하지 않는다. 어긋나면 경고만 남기고(`AIOS_ASSET_WARN`) 읽을 수 있는 만큼 읽는다.

번호를 올리는 때는 **경로·파일이름 규약이 바뀔 때뿐이다.** 모델을 바꾸거나 wheel 을
더하는 것은 번호와 무관하다.

### exFAT 가 아니라 FAT32 여야 하는 진짜 이유

Ventoy 는 파티션이 둘(데이터 + VTOYEFI/FAT16)이라 데이터가 exFAT 여도 **부팅 자체는** 된다 —
펌웨어는 FAT16 쪽에서 부트로더를 읽고, Ventoy 가 자체 드라이버로 데이터 파티션을 읽는다.

차이는 **부팅한 뒤 우리가 마운트할 때** 난다. `vfat` 은 어느 커널에나 있지만 `exfat` 은
모듈이 빠져 있을 수 있다. 자산을 못 읽으면 그 순간 전부 무용지물이다.
덤으로 FAT32 는 Windows·Mac·안드로이드 어디에 꽂아도 모델 파일을 갈아끼울 수 있다.
