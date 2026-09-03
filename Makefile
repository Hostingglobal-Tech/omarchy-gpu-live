# AI-OS 빌드 배선
#
# omarchy-iso 는 upstream 그대로 둔다. 우리 변경은 이 repo 에 있고,
# `make overlay` 가 빌드 직전에 얹는다. 그래야 upstream 을 따라갈 수 있다.

ISO_SRC ?= $(HOME)/DEVEL/omarchy-iso
TARGET  := x86_64-unknown-linux-musl
# 오버레이는 반드시 "이기는 층"에 둔다. build-iso.sh 는 상류 releng 을 먼저 깔고
# 그 위에 omarchy configs/* 를 덮으므로, releng 쪽에 둔 것은 상류가 같은 경로에
# 파일을 추가하는 순간 경고 없이 사라진다 (profiledef.sh 로 실제로 당했다).
AIR     := $(ISO_SRC)/configs/airootfs
# 이 ISO 의 실제 부트로더는 GRUB(UEFI) + syslinux(BIOS) 다. systemd-boot 항목은 만들어지지도
# 않는다 (ISO 에 loader/entries 가 없음을 실측 2026-08-23). 커널 명령줄은 이 셋을 고쳐야 한다.
ENTRIES := $(ISO_SRC)/configs/grub/grub.cfg $(ISO_SRC)/configs/grub/loopback.cfg $(ISO_SRC)/configs/syslinux/archiso_sys-linux.cfg
PROFDEF := $(ISO_SRC)/configs/profiledef.sh
PATCHES := no-offline-mirror live-desktop wizard-tty2

.PHONY: all build overlay patch check verify-iso clean

all: overlay

build:
	cargo build --release --target $(TARGET) --manifest-path aios-assets/Cargo.toml

# 상류에 얹는 소스 패치. 이미 적용돼 있으면 조용히 넘어간다.
patch:
	@cd $(ISO_SRC); for p in $(PATCHES); do if git apply --check -R $(CURDIR)/patches/$$p.patch 2>/dev/null; then echo "  이미 적용됨: $$p"; elif git apply --check $(CURDIR)/patches/$$p.patch 2>/dev/null; then git apply $(CURDIR)/patches/$$p.patch && echo "  패치 적용함: $$p"; else echo "  >>> 충돌: $$p — 정방향도 역방향도 안 붙는다. 정지"; exit 1; fi; done

overlay: build patch
	install -Dm755 aios-assets/target/$(TARGET)/release/aios-assets $(AIR)/usr/local/bin/aios-assets
	install -Dm644 aios-assets/systemd/aios-assets.service $(AIR)/etc/systemd/system/aios-assets.service
	mkdir -p $(AIR)/etc/systemd/system/multi-user.target.wants
	ln -sf ../aios-assets.service $(AIR)/etc/systemd/system/multi-user.target.wants/aios-assets.service
	install -Dm755 aios-assets/target/$(TARGET)/release/aios-live-session $(AIR)/usr/local/bin/aios-live-session
	install -Dm644 aios-assets/systemd/aios-live-session.service $(AIR)/etc/systemd/system/aios-live-session.service
	mkdir -p $(AIR)/etc/systemd/system/graphical.target.wants
	ln -sf ../aios-live-session.service $(AIR)/etc/systemd/system/graphical.target.wants/aios-live-session.service
# 라이브 root 를 그래픽 부팅으로. 상류 releng 기본값은 multi-user 다.
	ln -sf /usr/lib/systemd/system/graphical.target $(AIR)/etc/systemd/system/default.target
# systemctl enable sddm 과 같은 것. 라이브 root 는 chroot 를 못 쓰니 직접 건다.
	ln -sf /usr/lib/systemd/system/sddm.service $(AIR)/etc/systemd/system/display-manager.service
# AI-OS 자동 동작 3종 - 망 합류, GPU 수신, 자격 수신. 전부 oneshot 이라 실패해도
# 부팅을 막지 않고, 조건 파일(/etc/aios/*)이 없으면 스스로 건너뛴다.
	@for u in aios-netjoin aios-provision aios-agentauth; do 	  install -Dm755 aios-assets/target/$(TARGET)/release/$$u $(AIR)/usr/local/bin/$$u; 	  install -Dm644 aios-assets/systemd/$$u.service $(AIR)/etc/systemd/system/$$u.service; 	  ln -sf ../$$u.service $(AIR)/etc/systemd/system/multi-user.target.wants/$$u.service; 	done
# 표시판은 사용자 세션 유닛이다. uwsm 이 graphical-session.target 을 세우므로
# 거기 걸면 데스크톱이 뜨는 순간 함께 뜬다. hyprland.conf 를 건드리면 패키지가
# 갱신될 때 조용히 화석이 되므로 그 길은 쓰지 않는다.
	install -Dm755 aios-assets/target/$(TARGET)/release/aios-demo $(AIR)/usr/local/bin/aios-demo
	install -Dm755 aios-assets/target/$(TARGET)/release/aios-run-task $(AIR)/usr/local/bin/aios-run-task
	install -Dm644 aios-assets/systemd/aios-demo.service $(AIR)/etc/systemd/user/aios-demo.service
	install -Dm755 aios-assets/target/$(TARGET)/release/aios-record $(AIR)/usr/local/bin/aios-record
	install -Dm644 aios-assets/systemd/aios-record.service $(AIR)/etc/systemd/user/aios-record.service
	mkdir -p $(AIR)/etc/systemd/user/graphical-session.target.wants
	ln -sf ../aios-demo.service $(AIR)/etc/systemd/user/graphical-session.target.wants/aios-demo.service
	ln -sf ../aios-record.service $(AIR)/etc/systemd/user/graphical-session.target.wants/aios-record.service
# AI 부팅 브리핑 — 사람이 묻기 전에 기계가 먼저 말을 건다.
# 사용자 세션 유닛이라 데스크톱이 뜨는 순간 함께 돈다.
	install -Dm755 aios-assets/target/$(TARGET)/release/aios-brief $(AIR)/usr/local/bin/aios-brief
	install -Dm644 aios-assets/systemd/aios-brief.service $(AIR)/etc/systemd/user/aios-brief.service
	ln -sf ../aios-brief.service $(AIR)/etc/systemd/user/graphical-session.target.wants/aios-brief.service
# 한글 입력기 — 폰트만 있고 입력기가 없어 글자를 칠 수 없었다(실측 2026-08-25).
	install -Dm644 aios-assets/ime/60-fcitx5.conf $(AIR)/etc/environment.d/60-fcitx5.conf
	install -Dm644 aios-assets/ime/profile $(AIR)/etc/skel/.config/fcitx5/profile
	install -Dm644 aios-assets/ime/config $(AIR)/etc/skel/.config/fcitx5/config
	@echo "  AI 브리핑 + 한글 입력기(fcitx5-hangul) 배선"
	install -Dm644 aios-assets/task/PROMPT.txt $(AIR)/opt/aios/task/PROMPT.txt
	install -Dm644 aios-assets/fonts/D2Coding.ttc $(AIR)/usr/share/fonts/d2coding/D2Coding.ttc
# 부팅한 라이브를 SSH 로 들어가 고칠 수 있어야 한다. 없으면 화면 사진으로만
# 진단해야 하고, 그 값이 실제로 컸다(2026-08-24 시연 준비에서 확인).
	install -Dm700 -d $(AIR)/root/.ssh
	install -Dm600 aios-assets/ssh/root_authorized_keys $(AIR)/root/.ssh/authorized_keys
# archiso 기본 sudoers 는 aios 에게 asdcontrol 둘만 준다 - 부팅 후 아무것도 못 고친다.
	install -Dm440 aios-assets/sudoers/99-aios $(AIR)/etc/sudoers.d/99-aios
# tailscale 인증키. repo 에는 없다(.secrets/ 는 gitignore) - 있으면 굽고 없으면
# 건너뛴다. 키 없는 ISO 는 "망에 안 붙는 배포본" 으로 정상 동작한다.
# 키를 구운 ISO 는 곧 그 키다. 외부 반출 금지, 시연 후 키 폐기.
	@if [ -f .secrets/tailscale.key ]; then install -Dm700 -d $(AIR)/etc/aios; install -Dm600 .secrets/tailscale.key $(AIR)/etc/aios/tailscale.key; echo "  tailscale 인증키 구움 - 이 ISO 는 외부 반출 금지"; else echo "  tailscale 인증키 없음 - 망 합류 없는 배포본"; fi
# 분할 GPU(vGPU)를 open 커널모듈이 거부하지 않게 한다. 물리 카드에는 무해하다.
	install -Dm644 aios-assets/modprobe/nvidia-aios.conf $(AIR)/etc/modprobe.d/nvidia-aios.conf
# omarchy first-run 토스트 2종을 무력화한다.
# welcome.sh 는 'Learn Keybindings', wifi.sh 는 'Update System'/'Setup Wi-Fi' 를
# 매 부팅 critical 토스트로 띄운다. 둘 다 알림 발송 외 기능이 없음을 Fable 이
# 소스 전수로 확인했다. 특히 'Update System' 을 누르면 omarchy-update 가 돌아
# '10 GiB free' 오류가 난다 - 사장님이 겪은 그 화면이다(라이브는 tmpfs 4G).
# omarchy first-run 토스트 2종 무력화. welcome.sh=Learn Keybindings,
# wifi.sh=Update System/Setup Wi-Fi. 둘 다 알림 발송 외 기능이 없다(Fable 전수확인).
# 'Update System' 을 누르면 omarchy-update 가 돌아 '10 GiB free' 오류가 난다.
	install -Dm644 aios-assets/pacman/zz-aios-omarchy-quiet.hook $(AIR)/usr/share/libalpm/hooks/zz-aios-omarchy-quiet.hook
	@echo "  omarchy 토스트 차단 - alpm 훅으로 설치 후 무력화"
# 망 — DNS 폴백 + NetworkManager.
# 실측(2026-08-24 사장님 노트북): tailscale 은 붙었는데 이름 해석이 안 돼
# codex 가 'failed to lookup address information' 으로 죽었고, Wi-Fi 는
# NetworkManager 가 없어 아예 잡을 수단이 없었다(iwctl 명령줄뿐).
	install -Dm644 aios-assets/net/resolved-fallback.conf $(AIR)/etc/systemd/resolved.conf.d/aios-dns.conf
	install -Dm644 aios-assets/net/nm-iwd.conf $(AIR)/etc/NetworkManager/conf.d/aios-iwd.conf
	ln -sf /usr/lib/systemd/system/NetworkManager.service $(AIR)/etc/systemd/system/multi-user.target.wants/NetworkManager.service
	mkdir -p $(AIR)/etc/systemd/system/network-online.target.wants
	ln -sf /usr/lib/systemd/system/NetworkManager-wait-online.service $(AIR)/etc/systemd/system/network-online.target.wants/NetworkManager-wait-online.service
# NetworkManager 와 systemd-networkd 가 같은 장치를 두고 싸우면 둘 다 진다.
# ★.service 심볼릭만 지우면 안 된다. 부활 경로가 셋 더 있다(Fable 검토 2026-08-24):
#   1) systemd-networkd-wait-online 은 BindsTo=systemd-networkd 라 타깃이 당겨지면
#      networkd 를 도로 띄운다. 그 타깃을 우리 aios-netjoin/provision 이 매 부팅 당긴다
#   2) systemd-networkd.socket — 소켓 활성화로 부활
#   3) dbus-org.freedesktop.network1.service — D-Bus 활성화로 부활
# iwd.service 도 끈다. NM 이 iwd 를 직접 띄우므로(Arch Wiki) 따로 켜면 장치를 두고 다툰다.
	@R=$(ISO_SRC)/archiso/configs/releng/airootfs/etc/systemd/system; 	 rm -f $$R/multi-user.target.wants/systemd-networkd.service 	       $$R/multi-user.target.wants/iwd.service 	       $$R/network-online.target.wants/systemd-networkd-wait-online.service 	       $$R/sockets.target.wants/systemd-networkd.socket 	       $$R/dbus-org.freedesktop.network1.service
	@echo "  망 — DNS 폴백(8.8.8.8/1.1.1.1) + NetworkManager(iwd 백엔드)"
# cloud-init 무력화 - 세 겹으로 막는다.
# Scaleway 에서 부팅이 통째로 멈춘 원인이다(실측 2026-08-24, 콘솔 원문:
# 'A start job is running for Cloud-in...(pre-network) (1min 57s / no limit)').
# 그쪽엔 메타데이터 서비스(169.254.42.42)가 있어 cloud-init 이 데이터소스를
# 찾았다고 판단하고 타임아웃 없이 매달린다. QEMU 에는 그게 없어 즉시 포기하므로
# 로컬 시험에서는 잡히지 않았다.
# 라이브 매체에 cloud-init 이 할 일은 0이다 - SSH 키·자격·망 합류는 전부
# ISO 에 구워져 있고 aios-netjoin / aios-agentauth 가 처리한다.
	install -Dm644 /dev/null $(AIR)/etc/cloud/cloud-init.disabled
	rm -f $(ISO_SRC)/archiso/configs/releng/airootfs/etc/systemd/system/cloud-init.target.wants/*.service
	@for u in cloud-init-local cloud-init-main cloud-init-network cloud-config cloud-final cloud-init; do ln -sf /dev/null $(AIR)/etc/systemd/system/$$u.service; done
	@for e in $(ENTRIES); do grep -q 'cloud-init=disabled' $$e || sed -i 's|archisobasedir=|cloud-init=disabled archisobasedir=|g' $$e; done
	@echo "  cloud-init 무력화 - 커널인자 + disabled 파일 + 유닛 mask 3겹"
# 라이브 root 의 pacman 은 [offline] 하나만 안다. 그 미러를 우리가 빼므로
# 부팅 후 무엇도 받을 수 없다 - 온라인 저장소 설정을 따로 실어 준다.
	install -Dm644 $(ISO_SRC)/configs/pacman-online-stable.conf $(AIR)/etc/pacman-online.conf
	install -Dm644 aios-assets/pacman/zz-aios-initramfs.hook $(AIR)/usr/share/libalpm/hooks/zz-aios-initramfs.hook
	install -Dm644 aios-assets/systemd/getty-tty2-autologin.conf $(AIR)/etc/systemd/system/getty@tty2.service.d/autologin.conf
	mkdir -p $(AIR)/etc/systemd/system/getty.target.wants
	ln -sf /usr/lib/systemd/system/getty@.service $(AIR)/etc/systemd/system/getty.target.wants/getty@tty2.service
# 시험 빌드 전용. ttyS0 이 마지막이라야 /dev/console 이 시리얼로 간다(tty0 은 화면 유지용).
# quiet splash 는 커널·systemd 상태를 통째로 삼키므로 시험 때는 걷어낸다.
# 시험 빌드 전용. ttyS0 이 마지막이라야 /dev/console 이 시리얼로 간다(tty0 은 화면 유지).
# quiet splash 는 커널·systemd 상태를 통째로 삼키므로 시험 때는 걷어낸다.
	@for e in $(ENTRIES); do sed -i "s|cow_spacesize=4G|cow_spacesize=8G|g" $$e; grep -q "cow_spacesize=" $$e || sed -i "s|archisobasedir=|cow_spacesize=8G archisobasedir=|g" $$e; done
	@echo "  cow_spacesize=8G — 라이브 쓰기공간(RAM). 기본 256M 로는 nvidia-utils(886MB) 도 못 받는다"
# 영구 저장 모드 — USB 에 AIOSDATA 라벨의 파티션이 있으면 그것을 쓰기 계층으로 쓴다.
# ★RAM 오버레이는 재부팅하면 사라진다. 업데이트도 설정도 파일도 남기려면 이 모드다.
	@python3 aios-assets/add-persist-menu.py $(ENTRIES) 2>/dev/null || true
	@echo "  영구저장 메뉴 — USB 의 AIOSDATA 파티션에 남긴다"
	@for e in $(ENTRIES); do if [ "$(SERIAL)" = "1" ]; then grep -q "console=ttyS0" $$e || sed -i "s|archisobasedir=|console=tty0 console=ttyS0 archisobasedir=|g" $$e; sed -i "s| quiet splash | systemd.show_status=1 |g" $$e; else sed -i "s|console=tty0 console=ttyS0 ||g; s| systemd.show_status=1 | quiet splash |g" $$e; fi; done
	@if [ "$(SERIAL)" = "1" ]; then echo "  시리얼 콘솔 켬 + quiet 해제 (시험 빌드 전용)"; fi
	@mkdir -p $(AIR)/etc
	@{ echo AIOS_ASSET_API=1; echo AIOS_LIVE_DESKTOP=1; echo "AIOS_BUILD=$$(date +%Y-%m-%d)"; echo "AIOS_COMMIT=$$(git rev-parse --short HEAD)"; } > $(AIR)/etc/aios-release
	@for e in "/root/.ssh|0:0:700" "/root/.ssh/authorized_keys|0:0:600" "/etc/sudoers.d/99-aios|0:0:440" "/etc/aios|0:0:700" "/etc/aios/tailscale.key|0:0:600"; do p=$${e%%|*}; m=$${e##*|}; [ -e "$(AIR)$$p" ] || continue; grep -q "\[\"$$p\"\]" $(PROFDEF) || { awk -v e="  [\"$$p\"]=\"$$m\"" '/^file_permissions=\(/{inb=1} inb && /^\)/ && !ins{print e; ins=1} {print}' $(PROFDEF) > $(PROFDEF).tmp && mv $(PROFDEF).tmp $(PROFDEF); }; done
	@for b in aios-assets aios-live-session aios-netjoin aios-provision aios-agentauth aios-demo aios-run-task aios-record aios-brief; do grep -q "/usr/local/bin/$$b" $(PROFDEF) || { awk -v e="  [\"/usr/local/bin/$$b\"]=\"0:0:755\"" '/^file_permissions=\(/{inb=1} inb && /^\)/ && !ins{print e; ins=1} {print}' $(PROFDEF) > $(PROFDEF).tmp && mv $(PROFDEF).tmp $(PROFDEF); }; done
# GPU 작업 도구는 이 배포판에 포함하지 않는다.
# 필요하면 부팅 후 직접 설치해서 쓰면 된다.
# 시각은 KST 단일 (하드룰 timezone-kst-only). 상류 archiso 기본값은 UTC 라
# 그대로 두면 화면 시계가 9시간 어긋난다.
	mkdir -p $(AIR)/etc
	ln -sf /usr/share/zoneinfo/Asia/Seoul $(AIR)/etc/localtime
	echo Asia/Seoul > $(AIR)/etc/timezone
# 부팅 메뉴와 커널 파라미터 — 이 ISO 의 실제 부트로더는 GRUB 이다.
#   ★loopback.cfg 가 Ventoy 가 읽는 것이고, grub.cfg 가 직접 부팅용이다. 둘 다 고친다.
#   timeout=0/hidden 이면 메뉴가 아예 안 떠서 사람이 파라미터를 넣을 기회가 없다
#   (2026-08-26 사장님이 PC방에서 두 번 헛걸음하셨다).
#   modprobe.blacklist=nvidia_drm 은 RTX 5060/5070 에서 화면이 검게 나오는 것을 막는다.
#   CUDA(nvidia/nvidia_uvm)는 그대로 살아 nvidia-smi 도 정상이다.
	@for f in $(ISO_SRC)/configs/grub/grub.cfg $(ISO_SRC)/configs/grub/loopback.cfg; do [ -f $$f ] && { sed -i 's/^timeout=0/timeout=10/; s/^timeout_style=hidden/timeout_style=menu/' $$f; sed -i '/^\s*linux .*INSTALL_DIR/{/memtest/!{/modprobe.blacklist=nvidia_drm/!{s/ quiet splash//; s/$$/ modprobe.blacklist=nvidia_drm/}}}' $$f; }; done
# 한글 입력 기동 배선. omarchy 소유 파일을 고쳐야 해서 airootfs 선배치는
# pacman 파일충돌을 낸다 - alpm PostTransaction 훅으로 설치 뒤에 손댄다.
	install -Dm755 aios-assets/hangul/aios-hangul-wire $(AIR)/usr/local/bin/aios-hangul-wire
	install -Dm644 aios-assets/hangul/zz-aios-hangul.hook $(AIR)/etc/pacman.d/hooks/zz-aios-hangul.hook
	@grep -q "/usr/local/bin/aios-hangul-wire" $(PROFDEF) || { awk -v e="  [\"/usr/local/bin/aios-hangul-wire\"]=\"0:0:755\"" '/^file_permissions=\(/{inb=1} inb && /^\)/ && !ins{print e; ins=1} {print}' $(PROFDEF) > $(PROFDEF).tmp && mv $(PROFDEF).tmp $(PROFDEF); }
	@echo "오버레이 얹음 -> $(ISO_SRC)"

# 얹힌 것이 실제로 들어갔는지 본다. 얹었다고 믿지 말고 확인한다.
check:
	@test -x $(AIR)/usr/local/bin/aios-hangul-wire && echo "  한글배선 OK" || echo "  한글배선 **없음**"
	@test "$$(readlink $(AIR)/etc/localtime)" = "/usr/share/zoneinfo/Asia/Seoul" && echo "  타임존 KST OK" || echo "  타임존 **UTC(수정필요)**"
	@grep -q "^timeout=10" $(ISO_SRC)/configs/grub/loopback.cfg 2>/dev/null && echo "  GRUB 메뉴 10초 OK" || echo "  GRUB **timeout=0(수정필요)**"
	@grep -q "modprobe.blacklist=nvidia_drm" $(ISO_SRC)/configs/grub/loopback.cfg 2>/dev/null && echo "  nvidia_drm 차단 OK" || echo "  nvidia_drm **없음(수정필요)**"
	@test -x $(AIR)/usr/local/bin/aios-assets && echo "  바이너리 OK" || echo "  바이너리 없음"
	@test -L $(AIR)/etc/systemd/system/multi-user.target.wants/aios-assets.service && echo "  자동시작 OK" || echo "  자동시작 없음"
	@test -x $(AIR)/usr/local/bin/aios-live-session && echo "  라이브세션 바이너리 OK" || echo "  라이브세션 바이너리 없음"
	@test -L $(AIR)/etc/systemd/system/graphical.target.wants/aios-live-session.service && echo "  라이브세션 자동시작 OK" || echo "  라이브세션 자동시작 없음"
	@test "$$(readlink $(AIR)/etc/systemd/system/default.target)" = "/usr/lib/systemd/system/graphical.target" && echo "  그래픽 부팅 OK" || echo "  그래픽 부팅 없음"
	@test -L $(AIR)/etc/systemd/system/display-manager.service && echo "  sddm 활성 OK" || echo "  sddm 활성 없음"
	@grep -q aios-live-session $(PROFDEF) && echo "  실행권한 선언 OK" || echo "  실행권한 선언 없음"
	@test -L $(AIR)/etc/systemd/system/getty.target.wants/getty@tty2.service && echo "  마법사 tty2 배선 OK" || echo "  마법사 tty2 배선 없음"
	@grep -q "/dev/tty2" $(ISO_SRC)/configs/airootfs/root/.automated_script.sh && echo "  마법사 tty 조건 OK" || echo "  마법사 tty 조건 미패치"
	@awk '/^airootfs_image_tool_options=\(/{inb=1} inb && /aios-/{bad=1} inb && /^\)/{inb=0} END{exit bad?1:0}' $(PROFDEF) && echo "  오삽입 없음 OK" || echo "  ★오삽입 - 압축인자 배열에 권한선언이 들어갔다"
	@grep -q AIOS_LIVE_DESKTOP $(ISO_SRC)/builder/build-iso.sh && echo "  라이브 패키지 패치 OK" || echo "  라이브 패키지 패치 없음"
	@test -f $(AIR)/etc/aios-release && echo "  배치판 표기 OK" || echo "  배치판 표기 없음"
	@n=$$(grep -l "cow_spacesize=8G" $(ENTRIES) 2>/dev/null | wc -l); test "$$n" = "3" && echo "  cowspace 8G 3항목 OK" || { echo "  ★cowspace8G $$n/3 - 라이브 쓰기공간이 모자란다"; exit 1; }
	@if [ "$(SERIAL)" = "1" ]; then n=$$(grep -l "console=ttyS0" $(ENTRIES) 2>/dev/null | wc -l); test "$$n" = "3" && echo "  시리얼 3항목 OK" || echo "  ★시리얼 $$n/3 - 실제 부트로더 항목을 못 고쳤다"; fi
	@test -f $(AIR)/usr/share/libalpm/hooks/zz-aios-initramfs.hook && echo "  initramfs 복구 훅 OK" || echo "  initramfs 복구 훅 없음"
	@n=$$(grep -l "cloud-init=disabled" $(ENTRIES) 2>/dev/null | wc -l); test "$$n" = "3" && echo "  cloud-init 차단 3항목 OK" || { echo "  ★cloud-init $$n/3"; exit 1; }
	@test -f $(AIR)/etc/cloud/cloud-init.disabled && echo "  cloud-init disabled 파일 OK" || echo "  ★disabled 파일 없음"
	@grep -q "8.8.8.8" $(AIR)/etc/systemd/resolved.conf.d/aios-dns.conf 2>/dev/null && echo "  DNS 폴백 OK" || echo "  ★DNS 폴백 없음"
	@test -L $(AIR)/etc/systemd/system/multi-user.target.wants/NetworkManager.service && echo "  NetworkManager 활성 OK" || echo "  ★NetworkManager 없음"
	@n=$$(grep -l "cow_device=" $(ENTRIES) 2>/dev/null | wc -l); test "$$n" -ge "2" && echo "  영구저장 메뉴 OK ($$n)" || { echo "  ★영구저장 메뉴 없음 - 저장한 것이 재부팅에 사라진다"; exit 1; }
	@n=$$(ls $(AIR)/etc/systemd/system/ 2>/dev/null | grep -cE "aios-(netjoin|provision|agentauth|assets)"); test "$$n" = "0" && echo "  [공개판] 자동 망합류 없음 OK" || { echo "  ★공개판인데 망합류 유닛 $$n 개가 남아있다"; exit 1; }
	@test ! -e $(AIR)/etc/aios && echo "  [공개판] 내부 설정 없음 OK" || { echo "  ★/etc/aios 가 남아있다"; exit 1; }

# ISO 가 잘렸는지 본다. sha256 도 dd 도 이 사고를 못 잡는다 - PVD 선언 크기와 대조해야 한다.
verify-iso:
	@test -n "$(ISO)" || { echo "ISO=<경로> 를 줘라"; exit 2; }
	@SZ=$$(stat -c %s "$(ISO)"); BLK=$$(dd if="$(ISO)" bs=1 skip=32848 count=4 2>/dev/null | od -An -tu4 | tr -d ' '); echo "  실제 $$SZ / 선언 $$((BLK*2048))"; if [ $$((BLK*2048)) -le $$SZ ]; then echo "  온전함"; else echo "  >>> 잘렸다 <<<"; exit 1; fi; echo "  FAT32 4GiB 여유: $$((4294967296 - SZ))"

clean:
	cargo clean --manifest-path aios-assets/Cargo.toml
