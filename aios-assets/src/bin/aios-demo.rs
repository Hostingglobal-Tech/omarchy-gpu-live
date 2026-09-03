// AI-OS 라이브 세션 표시판
//
// 데스크톱이 뜨면 터미널 하나에서 이것이 돈다. 사람이 명령을 치지 않아도
// 이 기계가 무엇이 되었는지 스스로 보고한다 — 어떤 하드웨어 위에 있고,
// 어느 망에 붙었고, 어떤 에이전트가 살아 있고, 무슨 일을 처리했는지.
//
// 화면에 내보내지 않는 것:
//   - tailscale IP·인증키·토큰 등 내부 주소와 자격 일체
//   - 음성 전사 내용
// 노출 금지는 사후 편집에 맡기지 않는다. 애초에 찍히지 않게 여기서 거른다.

use std::fs;
use std::io::Write;
use std::process::Command;
use std::thread::sleep;
use std::time::Duration;

const RESET: &str = "\x1b[0m";
const HEAD: &str = "\x1b[1;30;103m"; // 검정 굵은 글자 + 밝은 노랑 배경
const OK: &str = "\x1b[1;32m";
const BAD: &str = "\x1b[1;31m";
const DIM: &str = "\x1b[90m";

fn out(s: &str) {
    println!("{s}");
    let _ = std::io::stdout().flush();
}

fn head(n: u8, total: u8, title: &str) {
    out("");
    out(&format!("{HEAD} [{n}/{total}] {title} {RESET}"));
    sleep(Duration::from_millis(400));
}

fn row(k: &str, v: &str) {
    out(&format!("  {k:<12} {v}"));
    sleep(Duration::from_millis(180));
}

fn cap(prog: &str, args: &[&str]) -> Option<String> {
    let o = Command::new(prog).args(args).output().ok()?;
    if !o.status.success() {
        return None;
    }
    let s = String::from_utf8_lossy(&o.stdout).trim().to_string();
    if s.is_empty() {
        None
    } else {
        Some(s)
    }
}

fn first_line(s: &str) -> String {
    s.lines().next().unwrap_or("").trim().to_string()
}

/// tailscale 출력에는 IP 가 그대로 들어 있다. 화면에 내보낼 수 없으므로
/// 100.x.y.z / fd7a: 로 시작하는 토큰을 통째로 지운다. 마스킹이 아니라 제거다 —
/// 자릿수만 남겨도 망 구조가 드러난다.
fn strip_addrs(s: &str) -> String {
    s.split_whitespace()
        .filter(|t| !t.starts_with("100.") && !t.starts_with("fd7a:") && !t.contains("/32"))
        .collect::<Vec<_>>()
        .join(" ")
}

fn stamp(path: &str) -> Option<String> {
    fs::read_to_string(path).ok().map(|s| first_line(&s))
}

fn verdict(s: &Option<String>) -> (&'static str, String) {
    match s {
        Some(v) if v.starts_with("ok ") => (OK, v[3..].to_string()),
        Some(v) if v.starts_with("skip ") => (DIM, v[5..].to_string()),
        Some(v) if v.starts_with("fail ") => (BAD, v[5..].to_string()),
        Some(v) => (DIM, v.clone()),
        None => (DIM, "기록 없음".to_string()),
    }
}

fn banner() {
    let commit = fs::read_to_string("/etc/aios-release")
        .ok()
        .and_then(|s| {
            s.lines()
                .find(|l| l.starts_with("AIOS_COMMIT="))
                .map(|l| l.trim_start_matches("AIOS_COMMIT=").trim_matches('"').to_string())
        })
        .unwrap_or_else(|| "unknown".into());
    let boot = cap("systemd-analyze", &[]).map(|s| first_line(&s)).unwrap_or_default();
    out("");
    out(&format!("{HEAD}  A I - O S   라이브 세션  {RESET}"));
    out(&format!("{DIM}  커밋 {commit}{RESET}"));
    if !boot.is_empty() {
        out(&format!("{DIM}  {boot}{RESET}"));
    }
    sleep(Duration::from_millis(600));
}

fn scene_hardware() {
    head(1, 5, "하드웨어");
    let cpu = fs::read_to_string("/proc/cpuinfo")
        .ok()
        .and_then(|s| {
            s.lines()
                .find(|l| l.starts_with("model name"))
                .and_then(|l| l.split(':').nth(1))
                .map(|v| v.trim().to_string())
        })
        .unwrap_or_else(|| "미상".into());
    let cores = std::thread::available_parallelism().map(|n| n.get()).unwrap_or(0);
    row("CPU", &format!("{cpu} · {cores}코어"));

    let memkb = fs::read_to_string("/proc/meminfo")
        .ok()
        .and_then(|s| {
            s.lines()
                .find(|l| l.starts_with("MemTotal:"))
                .and_then(|l| l.split_whitespace().nth(1))
                .and_then(|v| v.parse::<u64>().ok())
        })
        .unwrap_or(0);
    row("메모리", &format!("{:.1} GB", memkb as f64 / 1048576.0));

    match cap(
        "nvidia-smi",
        &["--query-gpu=name,driver_version,memory.total", "--format=csv,noheader"],
    ) {
        Some(g) => {
            row("GPU", &first_line(&g).replace(", ", " · "));
            if let Some(v) = cap("nvidia-smi", &[]) {
                if let Some(l) = v.lines().find(|l| l.contains("CUDA Version")) {
                    if let Some(c) = l.split("CUDA Version:").nth(1) {
                        row("CUDA", &format!("{OK}{}{RESET}", c.trim().trim_end_matches('|').trim()));
                    }
                }
            }
        }
        None => wait_for_gpu(),
    }
}

/// 설치가 끝났거나(실패·건너뜀 포함) 더 기다릴 이유가 없는 상태인가.
fn done(s: &Option<String>) -> bool {
    matches!(s, Some(v) if v.starts_with("skip ") || v.starts_with("fail "))
}

/// GPU 스택은 부팅 뒤 원격에서 받아 DKMS 로 빌드한다 — 몇 분 걸린다.
/// 먼저 지나가 버리면 이 화면에 GPU 가 영영 안 나오므로, 설치가 진행 중이면
/// 끝날 때까지 기다린다. 기다리는 구간은 편집에서 잘라낸다.
fn wait_for_gpu() {
    let s = stamp("/run/aios/gpu.status");
    if done(&s) {
        let (c, m) = verdict(&s);
        row("GPU", &format!("{c}{m}{RESET}"));
        return;
    }
    print!("  {:<12} {DIM}드라이버 수신·커널모듈 빌드 중{RESET} ", "GPU");
    let _ = std::io::stdout().flush();
    let mut waited = 0u64;
    loop {
        if let Some(g) = cap(
            "nvidia-smi",
            &["--query-gpu=name,driver_version,memory.total", "--format=csv,noheader"],
        ) {
            out("");
            row("GPU", &format!("{OK}{}{RESET}", first_line(&g).replace(", ", " · ")));
            if let Some(v) = cap("nvidia-smi", &[]) {
                if let Some(l) = v.lines().find(|l| l.contains("CUDA Version")) {
                    if let Some(c) = l.split("CUDA Version:").nth(1) {
                        row("CUDA", &format!("{OK}{}{RESET}", c.trim().trim_end_matches('|').trim()));
                    }
                }
            }
            return;
        }
        let s = stamp("/run/aios/gpu.status");
        if done(&s) {
            out("");
            let (c, m) = verdict(&s);
            row("GPU", &format!("{c}{m}{RESET}"));
            return;
        }
        if waited >= 1500 {
            out("");
            row("GPU", &format!("{BAD}설치가 25분을 넘겼다 - 건너뜀{RESET}"));
            return;
        }
        print!(".");
        let _ = std::io::stdout().flush();
        sleep(Duration::from_secs(5));
        waited += 5;
    }
}

fn scene_network() {
    head(2, 5, "망 합류");
    let (c, m) = verdict(&stamp("/run/aios/netjoin.status"));
    row("tailscale", &format!("{c}{m}{RESET}"));

    if let Some(s) = cap("tailscale", &["status", "--peers=true"]) {
        let peers = s.lines().filter(|l| !l.trim().is_empty()).count().saturating_sub(1);
        row("도달 가능", &format!("사내 {peers}대"));
        if let Some(me) = s.lines().next() {
            row("이 노드", &strip_addrs(me));
        }
    }
    out(&format!("{DIM}  (내부 주소는 표시하지 않는다){RESET}"));
}

fn scene_agents() {
    head(3, 5, "에이전트");
    for (name, prog) in [("Claude Code", "claude"), ("Codex", "codex")] {
        match cap(prog, &["--version"]) {
            Some(v) => row(name, &format!("{OK}{}{RESET}", first_line(&v))),
            None => row(name, &format!("{BAD}없음{RESET}")),
        }
    }
    let (c, m) = verdict(&stamp("/run/aios/agentauth.status"));
    row("자격", &format!("{c}{m}{RESET}"));
}

fn main() {
    let total_from_arg: Option<String> = std::env::args().nth(1);
    banner();
    scene_hardware();
    scene_network();
    scene_agents();

    head(4, 5, "일감 수신");
    let task = total_from_arg.unwrap_or_else(|| "/opt/aios/task".to_string());
    match fs::read_to_string(format!("{task}/PROMPT.txt")) {
        Ok(p) => {
            for l in p.lines().take(6) {
                out(&format!("  {DIM}|{RESET} {l}"));
                sleep(Duration::from_millis(120));
            }
        }
        Err(_) => out(&format!("  {DIM}일감 없음 - {task}/PROMPT.txt 가 없다{RESET}")),
    }

    head(5, 5, "자동 처리");
    out(&format!("{DIM}  에이전트에 넘긴다. 출력은 그대로 흘린다.{RESET}"));
    out("");
    let st = Command::new("/usr/local/bin/aios-run-task").arg(&task).status();
    match st {
        Ok(s) if s.success() => out(&format!("\n{OK}  처리 완료{RESET}")),
        Ok(s) => out(&format!("\n{BAD}  처리 실패 rc={:?}{RESET}", s.code())),
        Err(e) => out(&format!("\n{BAD}  실행 불가: {e}{RESET}")),
    }
}
