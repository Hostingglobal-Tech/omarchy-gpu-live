// AI-OS 자동 망 합류
//
// 부팅하면 사람 손 없이 우리 tailscale 망에 붙는다. 붙어야 그 다음이 가능하다 —
// 사내 AI 프록시, 배포 서버, 일감 큐가 전부 그 망 안에 있다.
//
// 인증키는 ISO 에 굽지 않는다. ISO 가 곧 키가 되기 때문이다. 부팅 매체의
// /etc/aios/tailscale.key (0600) 를 읽고, 없으면 조용히 건너뛴다 — 키가 없는 것은
// 고장이 아니라 "이 매체는 망에 안 붙는 배포본" 이라는 뜻이다.
//
// 키는 어떤 경로로도 화면·로그에 나오지 않는다. 길이만 찍는다.

use std::fs;
use std::io::Write;
use std::process::Command;

const KEY_PATH: &str = "/etc/aios/tailscale.key";
const STATUS: &str = "/run/aios/netjoin.status";

fn run(prog: &str, args: &[&str]) -> Result<String, String> {
    match Command::new(prog).args(args).output() {
        Ok(o) if o.status.success() => Ok(String::from_utf8_lossy(&o.stdout).trim().to_string()),
        Ok(o) => Err(format!(
            "rc={:?} {}",
            o.status.code(),
            String::from_utf8_lossy(&o.stderr).trim()
        )),
        Err(e) => Err(format!("{prog} 실행 불가: {e}")),
    }
}

/// 노드 이름은 매체마다 달라야 한다. 같은 ISO 를 여러 대에 꽂으면 같은 이름으로
/// 붙어 서로를 밀어낸다. machine-id 앞 6자를 붙여 구분한다.
fn hostname() -> String {
    let id = fs::read_to_string("/etc/machine-id")
        .map(|s| s.trim().chars().take(6).collect::<String>())
        .unwrap_or_default();
    if id.is_empty() {
        "aios-live".to_string()
    } else {
        format!("aios-live-{id}")
    }
}

fn status(msg: &str) {
    let _ = fs::create_dir_all("/run/aios");
    if let Ok(mut f) = fs::File::create(STATUS) {
        let _ = writeln!(f, "{msg}");
    }
    println!("{msg}");
}

fn main() {
    let key = match fs::read_to_string(KEY_PATH) {
        Ok(k) => k.trim().to_string(),
        Err(_) => {
            status("skip 인증키 없음 - 망 합류 건너뜀");
            return;
        }
    };
    if key.is_empty() {
        status("skip 인증키가 비어 있음");
        return;
    }
    println!("인증키 확인 ({}자)", key.len());

    if let Err(e) = run("systemctl", &["start", "tailscaled"]) {
        status(&format!("fail tailscaled 기동 실패: {e}"));
        return;
    }

    let host = hostname();
    // --ephemeral 은 키 쪽 속성이라 여기서 주지 않는다. 여기서는 우리 정책만 건다:
    // 라이브 매체가 남의 경로를 광고하거나 받지 않게 하고, SSH 진입점도 열지 않는다.
    let args = [
        "up",
        "--auth-key",
        key.as_str(),
        "--hostname",
        host.as_str(),
        "--accept-routes=false",
        "--advertise-routes=",
        "--ssh=false",
        "--timeout",
        "60s",
    ];
    match run("tailscale", &args) {
        Ok(_) => status(&format!("ok 망 합류함 - 노드명 {host}")),
        Err(e) => status(&format!("fail 망 합류 실패: {e}")),
    }
}
