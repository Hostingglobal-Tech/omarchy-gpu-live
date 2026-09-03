// AI-OS 부팅 브리핑 — AI 가 먼저 말을 건다
//
// 이 프로그램이 AI-OS 를 "AI 도구가 깔린 리눅스" 에서 "AI 가 주인인 OS" 로
// 넘기는 첫 걸음이다. 사람이 터미널을 열어 물어보는 것이 아니라,
// 부팅하면 기계가 먼저 사장님 상황을 읽고 말을 건다.
//
// 핵심은 화면 조작이 아니라 **아는 것**이다. 남들이 만드는 AI 데스크톱은
// 챗봇에 클릭을 붙인 것이라 정작 할 말이 없다. 우리는 클러스터가 있다 —
// 결제일·미납·카톡·통화·일정이 전부 내부망 DB 에 있다.
//
// 실패해도 부팅을 막지 않는다. 브리핑이 없는 것은 고장이 아니라
// "오늘은 말할 것이 없다" 이다.

use std::fs;
use std::io::Write;
use std::process::Command;
use std::time::Duration;

const STATUS: &str = "/run/aios/brief.status";
const OUT: &str = "/run/aios/brief.txt";
/// 에이전트에 넘길 프롬프트. 무엇을 물을지가 브리핑 품질을 정한다.
const ASK: &str = "\
당신은 신수철 사장님의 AI 비서다. 지금 막 부팅했다.\n\
아래 자료만 근거로, 사장님이 오늘 실제로 해야 할 일을 3건 이내로 골라라.\n\
\n\
규칙:\n\
- 근거가 없으면 지어내지 마라. 자료에 없으면 그 항목을 빼라.\n\
- 각 줄은 한 문장. 무엇을, 왜 지금인지가 보여야 한다.\n\
- 날짜·금액·상대 이름 같은 구체값을 반드시 넣어라.\n\
- 인사말·설명·머리말을 쓰지 마라. 항목만 출력하라.\n\
- 할 일이 없으면 '오늘 급한 것은 없습니다' 한 줄만 출력하라.\n";

fn status(msg: &str) {
    let _ = fs::create_dir_all("/run/aios");
    if let Ok(mut f) = fs::File::create(STATUS) {
        let _ = writeln!(f, "{msg}");
    }
    println!("{msg}");
}

fn have(prog: &str) -> bool {
    ["/usr/bin", "/usr/local/bin", "/bin"]
        .iter()
        .any(|d| std::path::Path::new(d).join(prog).exists())
}

/// 브리핑의 재료를 모은다. 실패한 항목은 조용히 빠진다 —
/// 자료 하나가 없다고 브리핑 전체를 포기하지 않는다.
fn gather() -> String {
    let mut facts = String::new();

    // 망에 붙었는지. 안 붙었으면 내부 자료를 못 읽으므로 그것부터 안다.
    if let Ok(s) = fs::read_to_string("/run/aios/netjoin.status") {
        facts.push_str(&format!("망: {}", s));
    }
    if let Ok(s) = fs::read_to_string("/run/aios/gpu.status") {
        facts.push_str(&format!("GPU: {}", s));
    }
    if let Ok(s) = fs::read_to_string("/run/aios/agentauth.status") {
        facts.push_str(&format!("에이전트 자격: {}", s));
    }

    // 내부망 도구가 있으면 그것으로 실제 업무를 읽는다.
    // 없으면 이 부분이 통째로 비고, 에이전트는 시스템 상태만 말하게 된다.
    for (label, prog, args) in [
        ("미결 인수인계", "handover", vec!["list", "--open"]),
        ("오늘 일정", "gtask", vec!["list"]),
    ] {
        if !have(prog) {
            continue;
        }
        if let Ok(o) = Command::new(prog).args(&args).output() {
            let t = String::from_utf8_lossy(&o.stdout);
            let t = t.trim();
            if !t.is_empty() {
                // 너무 길면 앞부분만. 토큰을 아낀다.
                let head: String = t.lines().take(20).collect::<Vec<_>>().join("\n");
                facts.push_str(&format!("\n[{label}]\n{head}\n"));
            }
        }
    }

    facts
}

/// 에이전트를 부른다. codex 를 먼저 쓴다 - 유료 API 직결이라 한도 걱정이 없다.
fn ask_agent(prompt: &str) -> Option<String> {
    let tries: Vec<(&str, Vec<&str>)> = vec![
        ("codex", vec!["exec", "--skip-git-repo-check", prompt]),
        ("claude", vec!["-p", prompt]),
    ];
    for (prog, args) in tries {
        if !have(prog) {
            continue;
        }
        let out = Command::new("timeout")
            .arg("120")
            .arg(prog)
            .args(&args)
            .output();
        if let Ok(o) = out {
            let t = String::from_utf8_lossy(&o.stdout);
            let t = clean(&t);
            if !t.is_empty() {
                return Some(t);
            }
        }
    }
    None
}

/// 에이전트 출력에서 사람이 읽을 줄만 남긴다.
/// CLI 가 세션 id·토큰수·배너를 같이 뱉으므로 그대로 화면에 쓰면 지저분하다.
fn clean(raw: &str) -> String {
    raw.lines()
        .map(|l| l.trim())
        .filter(|l| !l.is_empty())
        .filter(|l| {
            let low = l.to_lowercase();
            !(low.starts_with("session id")
                || low.starts_with("tokens used")
                || low.starts_with("workdir")
                || low.starts_with("model:")
                || low.starts_with("provider")
                || low.starts_with("reasoning")
                || low.starts_with("sandbox")
                || low.starts_with("--------")
                || low == "user"
                || low == "codex"
                || low == "assistant")
        })
        .collect::<Vec<_>>()
        .join("\n")
}

fn speak(text: &str) {
    // TTS 가 있으면 말한다. 없으면 조용히 넘어간다 - 글자는 이미 화면에 있다.
    for (prog, args) in [
        ("aios-say", vec![]),
        ("spd-say", vec!["-w"]),
    ] {
        if have(prog) {
            let mut c = Command::new(prog);
            c.args(&args).arg(text);
            let _ = c.status();
            return;
        }
    }
}

fn main() {
    let _ = fs::create_dir_all("/run/aios");

    // 망 합류를 잠깐 기다린다. 내부 자료가 브리핑의 본체이기 때문이다.
    // 안 붙어도 진행한다 - 시스템 상태만으로도 할 말은 있다.
    for _ in 0..30 {
        if fs::read_to_string("/run/aios/netjoin.status")
            .map(|s| s.starts_with("ok "))
            .unwrap_or(false)
        {
            break;
        }
        std::thread::sleep(Duration::from_secs(2));
    }

    let facts = gather();
    if facts.trim().is_empty() {
        status("skip 브리핑할 자료가 없다");
        return;
    }

    let prompt = format!("{ASK}\n[자료]\n{facts}");
    match ask_agent(&prompt) {
        Some(text) => {
            let _ = fs::write(OUT, format!("{text}\n"));
            status(&format!("ok 브리핑 {}줄", text.lines().count()));
            println!("\n{text}\n");
            speak(&text.replace('\n', ". "));
        }
        None => status("fail 에이전트가 답하지 않았다"),
    }
}
