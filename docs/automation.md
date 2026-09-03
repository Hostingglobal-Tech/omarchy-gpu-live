# 사람 손이 들어가는 지점 — 전부 없앤다 (2026-08-23 사장님 지시)

> "가능하면 완전 자동화를 추구하라"

## 현재 남은 수동 지점과 처리

| # | 지점 | 상태 | 처리 |
|---|---|---|---|
| 1 | ISO 빌드 → 로컬 저장 → Release 업로드 | **자동화 완료** | wsl `~/bin/aios-publish` 상주. ISO 완성 감지 → 형식 확인 → sha256 → Release 생성 → 업로드. flock 단일 인스턴스 |
| 2 | USB 부팅 (PC방 BIOS) | **사람 손 남음** | 물리 조작이라 불가피. 사장님이 "어렵지 않다" 확인 |
| 3 | Secure Boot MOK 등록 | **회피** | 매장에서 SB off 가능한 자리 우선. MOK 는 호스트 NVRAM 에 키를 영구 기록하므로 호스트 불가침 원칙과도 충돌 |
| 4 | 부팅 후 로그인 | **자동** | SDDM 자동로그인 (Omarchy 기본) |
| 5 | Tailscale join | **자동** | 첫 부팅에 authkey 파일로 join, 이후 persistence 에 노드키 잔류 → 재등록 없음 |
| 6 | 에이전트 로그인 | **자동** | persistence 에 `~/.claude`·`~/.codex` 잔류. 최초 1회만 사람이 로그인 |
| 7 | GPU 판별 · 워커 기동 | **자동** | `bootstrapd` 가 3단 프로브 후 스스로 기동 |
| 8 | ~~LUKS 패스프레이즈~~ | **제거됨** | 암호화층 자체를 걷어냈다 |

**결국 사람이 하는 것은 2번(BIOS에서 USB 부팅) 하나뿐이다.**
그 뒤로는 꽂고 켜면 업무 화면까지 자동으로 간다.

## aios-publish (wsl 상주)

```bash
~/bin/aios-publish          # 감시 시작 (중복 실행하면 조용히 종료)
tail -f ~/aios-publish.log  # 진행 상황
```

동작:
1. `~/DEVEL/omarchy-iso/release/*.iso` 를 60초 주기로 확인
2. 파일 크기가 5초간 안 변하면 쓰기 완료로 판정
3. `file` 로 ISO 형식 확인 (아니면 경고를 로그에 남기고 계속)
4. sha256 계산 → `SHA256SUMS` 생성
5. `gh release create iso-YYYYMMDD-HHMM` → ISO + SHA256SUMS 업로드
6. 빌드 컨테이너가 사라졌는데 ISO 가 없으면 빌드 로그 20줄을 남기고 실패 종료

**조용한 실패를 만들지 않는다** — 성공/실패 양쪽 다 로그에 남는다.
