# 첫 부팅 점검표

USB 를 꽂고 BIOS 에서 USB 부팅을 고른 뒤, 아래를 순서대로 본다.
**하나라도 어긋나면 그 자리에서 멈추고 원인을 적어라** — 다음 것으로 넘어가지 마라.

## 1. 부팅 자체

| 확인 | 정상 | 어긋나면 |
|---|---|---|
| Ventoy 메뉴에 `aios.iso` 가 보이나 | 보인다 | USB 에 파일이 안 올라갔거나 이름이 다르다 |
| 골랐을 때 부팅되나 | Arch 커널이 뜬다 | Secure Boot 를 끄고 다시. 그래도 안 되면 ISO 손상 — 해시 대조 |
| 데스크톱이 뜨나 | Hyprland | 여기가 **가장 불확실한 지점**. omarchy-iso 는 원래 설치용이라 라이브 세션 기립은 우리가 처음 조립한 조합이다 |

**데스크톱이 안 뜨면**: tty 로 떨어졌는지 본다(Ctrl+Alt+F2). 떨어졌다면 `journalctl -b -p err` 로
SDDM·Hyprland 오류를 본다. 그것이 1단계 스파이크에서 잡아야 할 것이다.

## 2. persistence — 이게 핵심이다

```bash
findmnt /run/archiso/cowspace
```

| 결과 | 뜻 |
|---|---|
| `ext4` | **성공.** 상태가 남는다 |
| `tmpfs` | **실패.** 매 부팅 초기화된다 |

`tmpfs` 면 순서대로:

1. `lsblk -f | grep vtoycow` — 장치가 보이나
2. `cat /proc/cmdline` — `cow_label` / `cow_device` 가 들어왔나
3. 안 들어왔으면 **Ventoy 가 주입을 안 한 것** → ISO 부트 엔트리에 직접 박는다
   (`docs/design.md` 11장에 위치가 있다)
4. 그래도 안 되면 Plan B — Ventoy `-r` 예약 파티션 + `cow_label=OMARCHY_PERSIST`

확인용 표식:

```bash
date > ~/부팅표식.txt      # 첫 부팅에서
cat ~/부팅표식.txt          # 재부팅 후 — 있으면 성공
```

## 3. 자립 확인 (네트워크 뽑고)

랜선을 뽑거나 Wi-Fi 를 끄고:

```bash
claude --version
codex --version
ffmpeg -version
tailscale version
```

**하나라도 "다운로드 중" 이 뜨면 자립형이 깨진 것이다.**
Omarchy 의 mise 스텁이 매 실행마다 최신을 해석하기 때문이며,
`docs/design.md` 4장의 "스텁을 실물 exec 로 재작성" 을 해야 한다.

## 4. GPU (있는 자리에서)

```bash
lspci -nn | grep -i nvidia     # device id 확인 — 0x1e00 이상이어야 지원
nvidia-smi                     # 인식되나
```

`nvidia-smi` 가 안 되면 드라이버가 커널과 안 맞는 것. ISO 를 다시 구워야 한다
(런타임 DKMS 를 쓰지 않기로 했으므로).

## 5. 한글

터미널에서 한글이 깨지는지, 입력이 되는지 본다.
Omarchy 기본에 한글 IME 가 있는지는 **미확인**이다. 없으면 fcitx5 계열을 ISO 에 넣어야 한다
(Wayland 라 ibus 가 아니다).

## 기록

각 항목의 결과를 이 파일에 그대로 추가하라. 추측을 적지 말고 본 것을 적어라.
안 된 것은 "안 됨" 으로 남겨야 다음 빌드에서 고칠 수 있다.
