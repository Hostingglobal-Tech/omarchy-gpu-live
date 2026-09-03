// 라이브 세션 화면 자동 녹화
//
// 시연을 남의 장소(실물 GPU 가 있는 PC)에서 하면 그 자리에서 화면을 담을 방법이
// 폰 촬영뿐이다. 데스크톱이 뜨는 순간부터 스스로 녹화해 두면 폰도 필요 없다.
//
// ★쓰는 자리가 핵심이다. 램(cowspace)에 쓰면 전원을 내리는 순간 통째로 사라져,
// 끄기 전에 반드시 회수해야 한다. 사장님 질문이 정확히 그것이었다 —
// "usb 가 live 인데 notebook 을 끄면 어떻게 회수하지?"
// 그래서 부팅 매체의 쓰기 가능한 파티션을 먼저 찾아 거기 직접 쓴다.
// 갑자기 전원이 나가도 그때까지 찍힌 것이 남고, 회수 절차 자체가 없어진다.

use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

/// 이 파일시스템에 실제로 쓸 수 있는가. 마운트 옵션(ro)과 권한을 동시에 본다 -
/// exFAT 은 유닉스 권한이 없어 겉보기 777 이어도 ro 마운트면 못 쓴다.
fn writable(dir: &Path) -> bool {
    let probe = dir.join(".aios-write-test");
    match fs::write(&probe, b"x") {
        Ok(_) => {
            let _ = fs::remove_file(&probe);
            true
        }
        Err(_) => false,
    }
}

/// 최소 여유 공간(바이트). 720p 20fps crf28 이 대략 분당 20~40MB 이므로
/// 2GB 면 한 시간 넘게 담긴다. 그보다 적으면 램으로 가는 편이 낫다.
const MIN_FREE: u64 = 2 * 1024 * 1024 * 1024;

fn free_bytes(dir: &Path) -> u64 {
    // df 를 부르는 편이 statvfs FFI 보다 짧고, 실패해도 0 으로 떨어져 안전하다.
    let out = Command::new("df").args(["-B1", "--output=avail"]).arg(dir).output();
    match out {
        Ok(o) if o.status.success() => String::from_utf8_lossy(&o.stdout)
            .lines()
            .nth(1)
            .and_then(|l| l.trim().parse::<u64>().ok())
            .unwrap_or(0),
        _ => 0,
    }
}

/// 부팅 매체에서 쓸 수 있는 자리를 찾는다.
///
/// archiso 는 부팅 매체를 /run/archiso/bootmnt 에 ro 로 물린다. 그 장치의
/// 다른 파티션(Ventoy 의 exFAT 데이터 영역 등)이 자동 마운트돼 있으면
/// /run/media 아래 있다. 둘 다 훑어 쓰기 가능하고 여유가 있는 곳을 고른다.
fn media_dir() -> Option<PathBuf> {
    let mut cands: Vec<PathBuf> = Vec::new();

    // /run/media/<user>/<label> 형태를 두 단계까지 펼친다
    for base in ["/run/media", "/media"] {
        if let Ok(d) = fs::read_dir(base) {
            for e in d.flatten() {
                let p = e.path();
                if !p.is_dir() {
                    continue;
                }
                cands.push(p.clone());
                if let Ok(d2) = fs::read_dir(&p) {
                    for e2 in d2.flatten() {
                        if e2.path().is_dir() {
                            cands.push(e2.path());
                        }
                    }
                }
            }
        }
    }
    // 부팅 매체 자체는 대개 ro 라 뒤로 둔다. 그래도 확인은 한다.
    cands.push(PathBuf::from("/run/archiso/bootmnt"));

    cands
        .into_iter()
        .find(|p| writable(p) && free_bytes(p) >= MIN_FREE)
}

fn out_path() -> (String, bool) {
    // 1순위 - 부팅 매체. 전원이 나가도 남는다.
    if let Some(m) = media_dir() {
        let dir = m.join("aios-record");
        if fs::create_dir_all(&dir).is_ok() && writable(&dir) {
            return (dir.join("aios-demo.mp4").to_string_lossy().into_owned(), true);
        }
        return (m.join("aios-demo.mp4").to_string_lossy().into_owned(), true);
    }

    // 2순위 - 램. /run/aios 는 root 소유 755 라 aios 사용자로 도는 wf-recorder 가
    // 파일을 못 만든다(실측 2026-08-24: ffmpeg 이 avio_open failed, rc=255).
    if let Ok(d) = std::env::var("XDG_RUNTIME_DIR") {
        if !d.is_empty() {
            return (format!("{d}/aios-demo.mp4"), false);
        }
    }
    let home = std::env::var("HOME").unwrap_or_else(|_| "/tmp".into());
    (format!("{home}/aios-demo.mp4"), false)
}

fn which(prog: &str) -> bool {
    for d in ["/usr/bin", "/usr/local/bin", "/bin"] {
        if Path::new(d).join(prog).exists() {
            return true;
        }
    }
    false
}

fn main() {
    let _ = fs::create_dir_all("/run/aios");
    if !which("wf-recorder") {
        // 없다고 부팅을 막지 않는다. 시연의 본체는 화면이지 녹화가 아니다.
        eprintln!("wf-recorder 없음 - 자동 녹화를 건너뛴다");
        return;
    }

    let (out, persistent) = out_path();
    if persistent {
        eprintln!("녹화 파일: {out}  (부팅 매체 - 전원을 내려도 남는다)");
    } else {
        eprintln!("녹화 파일: {out}  ★램이다 - 끄기 전에 회수해야 한다");
    }
    // 어디에 쓰는지 남겨 둔다. 나중에 사람이 찾을 때 이 파일만 보면 된다.
    let _ = fs::write("/run/aios/record.path", format!("{out}\n"));

    // -c 를 지정하지 않으면 무손실로 떨어져 램·USB 를 순식간에 채운다.
    // USB 는 느리므로 프레임을 20 으로 묶고 veryfast 로 인코딩 부담을 낮춘다.
    let st = Command::new("wf-recorder")
        .args([
            "-f", &out, "-c", "libx264", "-p", "crf=28", "-p", "preset=veryfast", "-r", "20",
        ])
        .status();
    match st {
        Ok(s) => eprintln!("녹화 종료 rc={:?}", s.code()),
        Err(e) => eprintln!("녹화 실행 불가: {e}"),
    }
}
