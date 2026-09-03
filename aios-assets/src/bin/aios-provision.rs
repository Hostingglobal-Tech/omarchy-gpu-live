// AI-OS GPU 스택 원격 수신
//
// ISO 에 NVIDIA 스택을 굽지 않는다. CUDA 툴킷 하나가 설치크기 4,823MB 라
// FAT32 4GiB 벽을 혼자 넘고, 커널 모듈은 chroot 안에서 DKMS 로 빌드해야 해서
// 실패하면 ISO 자체를 못 만든다. 그래서 부팅한 뒤 원격에서 받아 설치한다 —
// 실패해도 ISO 는 멀쩡하고 그 자리에서 다시 시도할 수 있다.
//
// GPU 가 없는 기기에서는 아무것도 받지 않고 끝낸다. 라이브 매체는 어디에 꽂힐지
// 모르므로, 없는 하드웨어를 위해 1GB 를 내려받으면 안 된다.

use std::fs;
use std::io::Write;
use std::path::Path;
use std::process::Command;

const STATUS: &str = "/run/aios/gpu.status";
// 라이브 root 의 /etc/pacman.conf 는 [offline] 하나뿐이고 file:// 미러를 가리킨다.
// AI-OS 는 그 미러를 ISO 에서 빼므로(4GiB 벽) 기본 설정으로는 저장소가 통째로 없다.
// 그래서 온라인 저장소 설정을 따로 싣고 여기서만 그것을 쓴다.
const PACCONF: &str = "/etc/pacman-online.conf";

fn status(msg: &str) {
    let _ = fs::create_dir_all("/run/aios");
    if let Ok(mut f) = fs::File::create(STATUS) {
        let _ = writeln!(f, "{msg}");
    }
    println!("{msg}");
}

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

/// PCI 클래스 0x03(디스플레이) 중 벤더 0x10de(NVIDIA)가 있는지 sysfs 로 직접 본다.
/// lspci 는 라이브 root 에 없을 수 있고, 있어도 출력 형식을 파싱해야 한다.
fn has_nvidia() -> bool {
    let dir = match fs::read_dir("/sys/bus/pci/devices") {
        Ok(d) => d,
        Err(_) => return false,
    };
    for e in dir.flatten() {
        let p = e.path();
        let vendor = fs::read_to_string(p.join("vendor")).unwrap_or_default();
        let class = fs::read_to_string(p.join("class")).unwrap_or_default();
        if vendor.trim() == "0x10de" && class.trim().starts_with("0x03") {
            return true;
        }
    }
    false
}

/// DKMS 는 지금 돌고 있는 커널의 헤더를 요구한다. 그 커널이 어느 패키지에서
/// 왔는지는 아치가 `pkgbase` 파일에 적어 둔다 - 이름을 박아 두면 ISO 가
/// linux/linux-lts/linux-zen 중 무엇으로 빌드됐는지에 따라 조용히 어긋난다.
fn headers_pkg() -> String {
    let rel = fs::read_to_string("/proc/sys/kernel/osrelease")
        .unwrap_or_default()
        .trim()
        .to_string();
    let base = fs::read_to_string(format!("/usr/lib/modules/{rel}/pkgbase"))
        .ok()
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| "linux".to_string());
    format!("{base}-headers")
}

fn install(pkgs: &[&str]) -> Result<String, String> {
    let mut args = vec!["-S", "--noconfirm", "--needed", "--config", PACCONF];
    args.extend_from_slice(pkgs);
    run("pacman", &args)
}

/// 모듈이 실제로 장치를 잡았는지까지 본다. 설치 성공은 인식의 증거가 아니다 -
/// 지원 목록에 없는 GPU 는 모듈이 올라가도 probe 에서 거부당한다.
fn gpu_alive() -> Option<String> {
    let _ = run("modprobe", &["nvidia"]);
    run(
        "nvidia-smi",
        &["--query-gpu=name,driver_version", "--format=csv,noheader"],
    )
    .ok()
    .filter(|s| !s.is_empty())
}

fn main() {
    if !has_nvidia() {
        status("skip NVIDIA 장치 없음 - 받지 않음");
        return;
    }

    // 1순위: ISO 에 이미 구워진 모듈. 이 길이 정상 경로다.
    // 라이브 루트는 RAM 이고 스왑이 없어서, 여기서 내려받아 빌드하면
    // OOM 으로 기계가 통째로 죽는다(실측 2026-08-24, RTX 5070·5060 연속).
    // 그래서 드라이버는 ISO 빌드 시점에 굽고 여기서는 올리기만 한다.
    if let Some(g) = gpu_alive() {
        status(&format!("ok GPU 인식 - {}", g.replace('\n', " / ")));
        return;
    }

    // 여기까지 왔다는 것은 구운 모듈이 이 카드를 못 잡았다는 뜻이다.
    // 예전에는 여기서 온라인 설치를 시도했으나 그것이 기계를 죽였다.
    // 실패는 실패로 남기고 데스크톱은 그대로 뜨게 둔다 - 시연의 본체는 화면이다.
    if !std::env::var("AIOS_ALLOW_RUNTIME_GPU").map(|v| v == "1").unwrap_or(false) {
        status("fail 구워진 드라이버가 이 GPU 를 못 잡았다 - 런타임 설치는 하지 않는다");
        return;
    }

    // 명시적으로 켰을 때만 옛 경로를 쓴다. RAM 을 태우므로 기본은 꺼져 있다.
    status("AIOS_ALLOW_RUNTIME_GPU=1 - 런타임 설치를 시도한다 (RAM 소모 큼)");
    if !Path::new(PACCONF).exists() {
        status("fail 온라인 저장소 설정이 없다");
        return;
    }
    if let Err(e) = run("pacman", &["-Sy", "--noconfirm", "--config", PACCONF]) {
        status(&format!("fail 패키지 목록 동기화 실패: {e}"));
        return;
    }
    let hdr = headers_pkg();
    if let Err(e) = install(&[&hdr]) {
        status(&format!("fail 커널 헤더({hdr}) 설치 실패: {e}"));
        return;
    }
    if let Err(e) = install(&["nvidia-open-dkms", "nvidia-utils"]) {
        status(&format!("fail 드라이버 설치 실패: {e}"));
        return;
    }
    match gpu_alive() {
        Some(g) => status(&format!("ok GPU 인식 - {}", g.replace('\n', " / "))),
        None => status("fail 드라이버를 깔았으나 이 GPU 를 잡지 못했다"),
    }
}
