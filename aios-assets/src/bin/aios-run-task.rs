// AI-OS 일감 실행기
//
// 일감 디렉토리에서 PROMPT.txt 를 읽어 에이전트에 넘기고, 출력을 그대로
// 화면에 흘린다. 요약하거나 다듬지 않는다 — 사람이 보는 것은 우리가 만든
// 문장이 아니라 에이전트가 실제로 낸 답이어야 한다.
//
// codex 를 먼저 쓰고 없으면 claude 로 간다. 이건 폴백이 아니라 선택이다 —
// 외부로 나가는 발송이 아니라 읽기 전용 질의라서 어느 쪽이 답해도 같은 일이다.

use std::env;
use std::fs;
use std::path::Path;
use std::process::{Command, Stdio};

fn have(prog: &str) -> bool {
    Command::new(prog)
        .arg("--version")
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
}

fn main() {
    let dir = env::args().nth(1).unwrap_or_else(|| "/opt/aios/task".to_string());
    let prompt_path = format!("{dir}/PROMPT.txt");
    let prompt = match fs::read_to_string(&prompt_path) {
        Ok(p) if !p.trim().is_empty() => p,
        _ => {
            eprintln!("일감이 없다: {prompt_path}");
            std::process::exit(2);
        }
    };

    if Path::new(&dir).is_dir() {
        let _ = env::set_current_dir(&dir);
    }

    let (prog, args): (&str, Vec<String>) = if have("codex") {
        ("codex", vec!["exec".into(), "--skip-git-repo-check".into(), prompt.clone()])
    } else if have("claude") {
        ("claude", vec!["-p".into(), prompt.clone()])
    } else {
        eprintln!("에이전트가 없다 - codex 도 claude 도 실행되지 않는다");
        std::process::exit(3);
    };

    let st = Command::new(prog)
        .args(&args)
        .stdout(Stdio::inherit())
        .stderr(Stdio::inherit())
        .status();

    match st {
        Ok(s) => std::process::exit(s.code().unwrap_or(1)),
        Err(e) => {
            eprintln!("{prog} 실행 불가: {e}");
            std::process::exit(4);
        }
    }
}
