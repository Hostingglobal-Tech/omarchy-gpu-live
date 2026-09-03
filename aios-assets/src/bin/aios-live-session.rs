// AI-OS 라이브 세션 준비기
//
// 상류 omarchy ISO 는 설치 전용이다 — 라이브 root 에 데스크톱이 없어서
// USB 로 부팅하면 설치 마법사만 뜬다. 이 프로그램이 라이브 root 안에
// 데스크톱 사용자를 만들어, 꽂으면 바로 Hyprland 가 뜨게 한다.
//
// 시딩은 우리가 하지 않는다. omarchy-settings 패키지가 /etc/skel 을 채우므로
// `useradd -m` 한 번이면 홈이 통째로 갖춰진다. 세션 정의도 같은 패키지가
// /usr/local/share/wayland-sessions/omarchy.desktop 로 넣어 준다.
//
// 실패해도 부팅을 막지 않는다. 데스크톱이 안 떠도 tty1 설치기는 살아 있어야 한다.

use std::fs;
use std::os::unix::fs::PermissionsExt;
use std::path::Path;
use std::process::Command;

const USER: &str = "aios";
const HOME: &str = "/home/aios";
const SESSION: &str = "omarchy.desktop";
const SDDM_DIR: &str = "/etc/sddm.conf.d";
const SESSION_SRC: &str = "/usr/local/share/wayland-sessions/omarchy.desktop";
const SESSION_DST: &str = "/usr/share/wayland-sessions/omarchy.desktop";
const STAMP: &str = "/run/aios/live-session.done";

// 있는 것만 넣는다. 없는 그룹을 넣으면 useradd 가 통째로 실패한다.
const GROUPS: &[&str] = &["wheel", "video", "input", "audio", "render", "storage", "network"];

fn sh(prog: &str, args: &[&str]) -> Result<(), String> {
    match Command::new(prog).args(args).output() {
        Ok(o) if o.status.success() => Ok(()),
        Ok(o) => Err(format!(
            "{} {:?} rc={:?} {}",
            prog,
            args,
            o.status.code(),
            String::from_utf8_lossy(&o.stderr).trim()
        )),
        Err(e) => Err(format!("{prog} 실행 불가: {e}")),
    }
}

fn user_exists() -> bool {
    fs::read_to_string("/etc/passwd")
        .map(|s| s.lines().any(|l| l.starts_with(&format!("{USER}:"))))
        .unwrap_or(false)
}

fn group_exists(g: &str) -> bool {
    fs::read_to_string("/etc/group")
        .map(|s| s.lines().any(|l| l.starts_with(&format!("{g}:"))))
        .unwrap_or(false)
}

/// 사용자를 만든다. -m 이 /etc/skel 을 홈으로 복사하고, 그 skel 을
/// omarchy-settings 가 이미 채워 놓았다 — 우리가 설정을 만들 필요가 없다.
fn ensure_user() -> Result<bool, String> {
    if user_exists() {
        return Ok(false);
    }
    let present: Vec<&str> = GROUPS.iter().copied().filter(|g| group_exists(g)).collect();
    let groups = present.join(",");
    let mut args = vec!["-m", "-d", HOME, "-s", "/bin/bash", "-c", "AI-OS Live"];
    if !groups.is_empty() {
        args.push("-G");
        args.push(&groups);
    }
    args.push(USER);
    sh("useradd", &args)?;
    // 라이브 매체다. 잠금 화면에서 빈 암호로 통과해야 한다.
    let _ = sh("passwd", &["-d", USER]);
    Ok(true)
}

/// sddm 0.21 은 /usr/local/share/wayland-sessions 도 읽지만, 판본에 따라
/// 안 읽는 경우가 있다. 세션이 목록에 없으면 자동로그인이 조용히 실패하므로
/// 표준 경로에도 복사해 둔다.
fn mirror_session() -> bool {
    if !Path::new(SESSION_SRC).exists() || Path::new(SESSION_DST).exists() {
        return false;
    }
    if fs::create_dir_all("/usr/share/wayland-sessions").is_err() {
        return false;
    }
    fs::copy(SESSION_SRC, SESSION_DST).is_ok()
}

/// tty1 은 설치기가 쓴다(archiso 가 root 를 자동로그인시켜 마법사를 띄운다).
/// sddm 은 표준대로 tty1 을 가진다. 설치 마법사는 tty2 로 옮겼다
/// (getty@tty2 자동로그인 + .automated_script.sh 의 tty 조건 패치).
fn write_autologin() -> Result<(), String> {
    fs::create_dir_all(SDDM_DIR).map_err(|e| format!("{SDDM_DIR}: {e}"))?;
    let path = format!("{SDDM_DIR}/99-aios-autologin.conf");
    let body = format!(
        "[Autologin]\nUser={USER}\nSession={SESSION}\nRelogin=false\n\n\
         [Users]\nRememberLastUser=true\nRememberLastSession=true\n"
    );
    fs::write(&path, body).map_err(|e| format!("{path}: {e}"))?;
    let _ = fs::set_permissions(&path, fs::Permissions::from_mode(0o644));
    Ok(())
}

fn run() -> Result<String, String> {
    if Path::new(STAMP).exists() {
        return Ok("이미 준비됨".into());
    }
    fs::create_dir_all("/run/aios").map_err(|e| format!("/run/aios: {e}"))?;

    let created = ensure_user()?;
    let mirrored = mirror_session();
    write_autologin()?;

    let _ = fs::write(STAMP, b"ok");
    Ok(format!(
        "사용자 {} / 홈 {} / 세션 {} — 생성={} 세션복사={}",
        USER,
        if Path::new(HOME).exists() { "OK" } else { "없음" },
        SESSION,
        if created { "예" } else { "이미있음" },
        if mirrored { "예" } else { "불필요" }
    ))
}

fn main() {
    // 어떤 실패도 부팅을 막지 않는다. 데스크톱이 안 떠도 tty1 설치기는 살아야 한다.
    match run() {
        Ok(msg) => println!("aios-live-session: {msg}"),
        Err(e) => eprintln!("aios-live-session: 준비 실패 — {e} (설치기는 tty1 에 그대로 있다)"),
    }
}
