//! aios-assets — USB 의 자산을 부팅한 시스템에 물린다.
//!
//! ISO 에 모델·wheel 을 소성하면 FAT32 4GiB 상한에 걸린다(design.md 12장).
//! 그래서 자산은 같은 USB 의 데이터 파티션에 두고, 부팅 후 여기서 마운트해 쓴다.
//! 네트워크는 쓰지 않는다 — 같은 매체라 마운트만 하면 된다.
//!
//! 의존성 0. std 만 쓴다. 해시 대조는 coreutils 의 sha256sum 에 맡긴다.

use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use std::process::{Command, ExitCode};

const LABEL: &str = "/dev/disk/by-label/VENTOY";
const MOUNT: &str = "/run/aios/vtoy";
const ENV_OUT: &str = "/run/aios/assets.env";
/// ISO 가 심는 파일. 여기 적힌 API 번호가 이 ISO 가 읽을 수 있는 자산 배치를 뜻한다.
const RELEASE: &str = "/etc/aios-release";

fn main() -> ExitCode {
    match run() {
        Ok(n) => {
            println!("aios-assets: 자산 {n}건 준비됨");
            ExitCode::SUCCESS
        }
        Err(e) => {
            // 자산이 없어도 시스템은 떠야 한다. 실패를 말하되 부팅을 막지 않는다.
            eprintln!("aios-assets: {e}");
            ExitCode::SUCCESS
        }
    }
}

fn run() -> Result<usize, String> {
    let dev = Path::new(LABEL);
    if !dev.exists() {
        return Err(format!("USB 데이터 파티션을 찾지 못했다 ({LABEL})"));
    }

    fs::create_dir_all(MOUNT).map_err(|e| format!("{MOUNT} 생성 실패: {e}"))?;

    if !is_mounted(MOUNT) {
        // FAT32 는 실행 비트를 못 갖는다. umask 로 전체에 부여한다.
        let st = Command::new("mount")
            .args(["-o", "ro,exec,umask=022", LABEL, MOUNT])
            .status()
            .map_err(|e| format!("mount 실행 실패: {e}"))?;
        if !st.success() {
            return Err(format!("mount 실패 (rc={:?})", st.code()));
        }
    }

    let root = PathBuf::from(MOUNT).join("aios-assets");
    if !root.is_dir() {
        return Err(format!("자산 디렉토리가 없다 ({})", root.display()));
    }

    verify(&root)?;
    let warn = check_compat(&root);

    let mut found = Vec::new();

    let model = root.join("models/faster-whisper-large-v3");
    if model.join("model.bin").is_file() {
        found.push(("AIOS_WHISPER_MODEL", model.display().to_string()));
    }

    let wheels = root.join("wheels");
    if wheels.is_dir() {
        found.push(("AIOS_WHEELS", wheels.display().to_string()));
    }

    let bin = root.join("bin");
    if bin.is_dir() {
        found.push(("AIOS_BIN", bin.display().to_string()));
    }

    let mut f = fs::File::create(ENV_OUT).map_err(|e| format!("{ENV_OUT} 쓰기 실패: {e}"))?;
    for (k, v) in &found {
        writeln!(f, "{k}={v}").map_err(|e| format!("쓰기 실패: {e}"))?;
    }
    if let Some(w) = &warn {
        writeln!(f, "AIOS_ASSET_WARN={w}").map_err(|e| format!("쓰기 실패: {e}"))?;
        eprintln!("aios-assets: {w}");
    }

    Ok(found.len())
}

fn is_mounted(p: &str) -> bool {
    fs::read_to_string("/proc/mounts")
        .map(|s| s.lines().any(|l| l.split_whitespace().nth(1) == Some(p)))
        .unwrap_or(false)
}

/// MANIFEST.sha256 이 있으면 대조한다. 어긋나면 자산을 쓰지 않는다 —
/// 조용히 쓰는 것이 사고다(feedback_silent_failure_is_the_root).
fn verify(root: &Path) -> Result<(), String> {
    let manifest = root.join("MANIFEST.sha256");
    if !manifest.is_file() {
        eprintln!("aios-assets: MANIFEST.sha256 없음 — 무결성 대조를 건너뛴다");
        return Ok(());
    }
    let st = Command::new("sha256sum")
        .arg("-c")
        .arg("--quiet")
        .arg(&manifest)
        .current_dir(root)
        .status()
        .map_err(|e| format!("sha256sum 실행 실패: {e}"))?;
    if st.success() {
        Ok(())
    } else {
        Err("MANIFEST 대조 실패 — 자산이 손상됐다. 쓰지 않는다".into())
    }
}

/// ISO 와 자산의 배치 규약이 맞는지 본다.
///
/// 자산을 USB 에 따로 두는 설계의 대가는 **둘이 따로 놀 수 있다는 것**이다.
/// 그래서 배치 규약에 번호를 매기고, ISO 가 읽을 수 있는 상한과 대조한다.
/// 판 번호가 같으면 자산을 마음대로 갈아끼워도 된다 — 그것이 이 설계의 요점이므로
/// **여기서 차단하지 않는다.** 어긋난 사실만 분명히 남긴다.
fn check_compat(root: &Path) -> Option<String> {
    let asset = read_kv(&root.join("VERSION"), "ASSET_LAYOUT");
    let iso = read_kv(Path::new(RELEASE), "AIOS_ASSET_API");

    match (asset, iso) {
        (Some(a), Some(i)) if a == i => None,
        (Some(a), Some(i)) => Some(format!(
            "자산 배치판 {a} 와 ISO 가 읽는 판 {i} 가 다르다 — 일부를 못 읽을 수 있다"
        )),
        (Some(a), None) => Some(format!(
            "ISO 에 {RELEASE} 가 없다(구형) — 자산은 배치판 {a} 다"
        )),
        (None, _) => Some("자산에 VERSION 이 없다 — 배치판을 알 수 없다".into()),
    }
}

fn read_kv(p: &Path, key: &str) -> Option<String> {
    let s = fs::read_to_string(p).ok()?;
    for line in s.lines() {
        let line = line.trim();
        if let Some(v) = line.strip_prefix(key).and_then(|r| r.strip_prefix('=')) {
            return Some(v.trim().to_string());
        }
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::env;

    fn tmp(name: &str, body: &str) -> PathBuf {
        let p = env::temp_dir().join(format!("aios-test-{name}"));
        fs::write(&p, body).unwrap();
        p
    }

    #[test]
    fn 키값을_읽는다() {
        let p = tmp("kv", "# 주석\nASSET_LAYOUT=1\nMODEL=large-v3\n");
        assert_eq!(read_kv(&p, "ASSET_LAYOUT"), Some("1".into()));
        assert_eq!(read_kv(&p, "MODEL"), Some("large-v3".into()));
        assert_eq!(read_kv(&p, "없는키"), None);
    }

    #[test]
    fn 주석은_키로_읽지_않는다() {
        // "# ASSET_LAYOUT=9" 를 값으로 읽으면 어긋남을 못 잡는다.
        let p = tmp("cmt", "# ASSET_LAYOUT=9\nASSET_LAYOUT=1\n");
        assert_eq!(read_kv(&p, "ASSET_LAYOUT"), Some("1".into()));
    }

    #[test]
    fn 파일이_없으면_None() {
        assert_eq!(read_kv(Path::new("/없는/경로/xyz"), "K"), None);
    }

    #[test]
    fn 자산에_VERSION이_없으면_경고한다() {
        let d = env::temp_dir().join("aios-test-empty");
        fs::create_dir_all(&d).unwrap();
        let _ = fs::remove_file(d.join("VERSION"));
        assert!(check_compat(&d).is_some());
    }
}
