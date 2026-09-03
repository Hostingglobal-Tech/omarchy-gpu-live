// AI-OS 에이전트 자격 원격 수신
//
// claude / codex 는 계정 자격이 있어야 일한다. 그 자격을 ISO 에 굽지 않는다 —
// 구운 순간 ISO 를 가진 사람이 곧 계정을 가진 사람이 되고, 그 ISO 는
// 되돌릴 수 없다. 대신 부팅해서 우리 망에 붙은 뒤 그 안에서만 받는다.
//
// 받을 곳은 /etc/aios/provision.url 에 있다. tailscale 내부 주소이므로
// 망 밖에서는 이름조차 해석되지 않는다. 파일이 없으면 조용히 건너뛴다 —
// 자격 없이 도는 것이 배포본의 정상 상태다.
//
// URL 은 어떤 경로로도 화면·로그에 찍지 않는다. 경로에 토큰이 들어 있다.

use std::fs;
use std::io::Write;
use std::os::unix::fs::PermissionsExt;
use std::path::Path;
use std::process::Command;

const URL_PATH: &str = "/etc/aios/provision.url";
const STATUS: &str = "/run/aios/agentauth.status";
const HOME: &str = "/home/aios";
const USER: &str = "aios";
const TMP: &str = "/run/aios/agent-auth.tar.gz";

fn status(msg: &str) {
    let _ = fs::create_dir_all("/run/aios");
    if let Ok(mut f) = fs::File::create(STATUS) {
        let _ = writeln!(f, "{msg}");
    }
    println!("{msg}");
}

fn run(prog: &str, args: &[&str]) -> Result<(), String> {
    match Command::new(prog).args(args).output() {
        Ok(o) if o.status.success() => Ok(()),
        Ok(o) => Err(format!(
            "rc={:?} {}",
            o.status.code(),
            String::from_utf8_lossy(&o.stderr).trim()
        )),
        Err(e) => Err(format!("{prog} 실행 불가: {e}")),
    }
}

fn main() {
    let url = match fs::read_to_string(URL_PATH) {
        Ok(u) => u.trim().to_string(),
        Err(_) => {
            status("skip 수신 주소 없음 - 자격 없이 진행");
            return;
        }
    };
    if url.is_empty() {
        status("skip 수신 주소가 비어 있음");
        return;
    }

    let _ = fs::create_dir_all("/run/aios");
    // -f: 4xx/5xx 를 실패로 취급한다. 이게 없으면 오류 페이지를 tar 로 착각한다.
    if let Err(e) = run(
        "curl",
        &["-fsS", "--max-time", "120", "-o", TMP, &format!("{url}/agent-auth.tar.gz")],
    ) {
        // e 에 URL 이 섞여 나올 수 있다. 사유만 남기고 본문은 버린다.
        let _ = e;
        status("fail 자격 수신 실패 - 주소 도달 불가 또는 응답 오류");
        return;
    }
    if let Ok(m) = fs::metadata(TMP) {
        let _ = fs::set_permissions(TMP, fs::Permissions::from_mode(0o600));
        println!("자격 꾸러미 수신 ({} 바이트)", m.len());
    }

    if !Path::new(HOME).is_dir() {
        status("fail 홈이 아직 없다 - live-session 이 먼저 돌아야 한다");
        return;
    }
    if let Err(e) = run("tar", &["-xzf", TMP, "-C", HOME]) {
        status(&format!("fail 자격 전개 실패: {e}"));
        return;
    }
    let _ = fs::remove_file(TMP);

    if let Err(e) = run("chown", &["-R", &format!("{USER}:{USER}"), HOME]) {
        status(&format!("fail 소유권 이전 실패: {e}"));
        return;
    }

    let mut got: Vec<&str> = Vec::new();
    if Path::new(&format!("{HOME}/.claude")).exists() {
        got.push("claude");
    }
    if Path::new(&format!("{HOME}/.codex")).exists() {
        got.push("codex");
    }
    if got.is_empty() {
        status("fail 꾸러미에 자격이 없다");
    } else {
        status(&format!("ok 자격 수신함 - {}", got.join(", ")));
    }
}
