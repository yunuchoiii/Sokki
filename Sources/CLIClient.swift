import Foundation

enum CLIError: LocalizedError {
    case notFound
    case notLoggedIn(String)
    case failed(Int32, String)
    case emptyOutput
    case timedOut

    var errorDescription: String? {
        switch self {
        case .notFound:
            return """
                claude 명령을 찾지 못했습니다.
                터미널에서 `which claude`를 실행해 경로를 확인하고, 메뉴 > 진단 > 'CLI 경로 지정'에서 넣어 주세요.
                """
        case .notLoggedIn(let detail):
            return "Claude Code에 로그인되어 있지 않습니다. 터미널에서 `claude auth login`을 먼저 실행하세요.\n\n\(detail)"
        case .failed(let code, let stderr):
            return "claude CLI 오류 (종료 코드 \(code))\n\n\(stderr.prefix(400))"
        case .emptyOutput:
            return "claude CLI가 빈 응답을 반환했습니다."
        case .timedOut:
            return "claude CLI 응답이 30초를 넘겨 중단했습니다."
        }
    }
}

/// Claude Code CLI(`claude -p`)를 호출한다.
/// API 크레딧이 아니라 claude.ai 구독(Pro/Max) 사용량으로 처리된다.
struct CLIClient {

    static let shared = CLIClient()

    /// GUI 앱은 로그인 셸 PATH를 물려받지 못해서 직접 찾아야 한다.
    static func resolveExecutable() -> String? {
        let fm = FileManager.default

        if let saved = Prefs.cliPath, !saved.isEmpty, fm.isExecutableFile(atPath: saved) {
            return saved
        }

        let home = NSHomeDirectory()
        let candidates = [
            "\(home)/.local/bin/claude",
            "\(home)/.claude/local/claude",
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            "\(home)/.bun/bin/claude",
            "\(home)/.volta/bin/claude",
            "\(home)/.nvm/versions/node/current/bin/claude"
        ]
        for path in candidates where fm.isExecutableFile(atPath: path) {
            return path
        }

        return whichViaLoginShell()
    }

    private static func whichViaLoginShell() -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/zsh")
        proc.arguments = ["-lc", "command -v claude"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        do { try proc.run() } catch { return nil }
        proc.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let path = (String(data: data, encoding: .utf8) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return FileManager.default.isExecutableFile(atPath: path) ? path : nil
    }

    /// CLI는 별칭(haiku/sonnet/opus)을 받는 게 가장 안전하다.
    private func alias(for model: String) -> String {
        if model.contains("haiku") { return "haiku" }
        if model.contains("opus")  { return "opus" }
        return "sonnet"
    }

    /// 기본값은 비어 있다.
    ///
    /// 예전에는 --tools, --bare, --max-turns, --permission-prompts 같은 걸 붙였다.
    /// 속도와 안전장치 목적이었는데 결과 품질에는 아무 영향이 없으면서,
    /// 버전마다 있고 없고가 달라 실패 지점만 늘렸다. 그래서 전부 뺐다.
    ///
    /// 실제로 쓰는 건 -p / --system-prompt / --model / --output-format 넷뿐이고,
    /// 넷 다 오래전부터 있던 안정적인 플래그다.
    /// 시스템 프롬프트가 이미 "설명 없이 정리된 텍스트만 출력"을 지시하므로
    /// 도구 제한 없이도 코딩 에이전트처럼 굴지 않는다.
    /// 속도용 플래그. 실패하면 재시도 루프가 그룹째로 빼고 다시 실행한다.
    ///
    /// 매 호출마다 Claude Code가 MCP 서버(Notion, Slack, Figma 등)를 전부 연결하고
    /// 스킬·커맨드를 스캔하느라 10~25초가 걸린다. 받아쓰기 정리에는 하나도 필요 없다.
    ///
    /// --bare 는 쓰지 않는다. v2.1.257에서 이걸 붙이면 로그인 상태를 못 읽고
    /// "Not logged in"으로 실패한다.
    private static let optionalFlags: [(name: String, args: [String])] = [
        // 커스터마이즈를 전부 끈다: CLAUDE.md, 스킬, 플러그인, 훅, MCP, 커스텀 커맨드,
        // 상태줄, LSP 등. 문서상 "인증, 모델 선택, 기본 도구, 권한은 정상 동작"하며
        // 이 점이 --bare 와 다르다. 앞에 둘수록 나중까지 살아남는다(제거는 뒤에서부터).
        ("safe", ["--safe-mode"]),
        // 진짜 병목. claude --version 이 0.0초인 걸로 프로세스 시작은 빠른 게 확인됐고,
        // 20초는 전부 모델 호출에서 나온다. Claude Code는 코딩용이라 기본 effort가 높아
        // 문장 다듬기 같은 일에도 한참 생각한다. 최저로 내린다.
        ("effort", ["--effort", "low"]),
        // 도구 스키마 제거. Claude Code는 코딩 에이전트라 매 요청에 Bash·Read·Edit·Grep 등
        // 도구 정의를 수천 토큰씩 실어 보낸다. 문장 다듬기에는 하나도 안 쓴다.
        ("tools", ["--tools", "", "--disallowedTools", "mcp__*"]),
        // 세션 기록 파일 쓰기 생략
        ("session", ["--no-session-persistence"]),
        // --safe-mode 가 없는 버전을 위한 예비책
        ("mcp", ["--strict-mcp-config", "--mcp-config", #"{"mcpServers":{}}"#]),
        ("slash", ["--disable-slash-commands"])
    ]

    private func arguments(raw: String, model: String, style: PolishStyle,
                           skipping: Set<String>) -> [String] {
        var args = [
            "-p", Prompts.userMessage(raw),
            "--system-prompt", Prompts.system(for: style),
            "--model", alias(for: model),
            "--output-format", "text"
        ]
        for group in Self.optionalFlags where !skipping.contains(group.name) {
            args.append(contentsOf: group.args)
        }
        return args
    }

    /// stderr에서 "unknown option '--xxx'" 같은 문구를 찾아 플래그 이름을 뽑는다.
    private func unsupportedFlag(in stderr: String) -> String? {
        let lowered = stderr.lowercased()
        guard lowered.contains("unknown option")
                || lowered.contains("unknown argument")
                || lowered.contains("unrecognized option")
                || lowered.contains("unknown flag") else { return nil }

        guard let regex = try? NSRegularExpression(pattern: "--[a-zA-Z][a-zA-Z0-9-]*") else { return nil }
        let range = NSRange(stderr.startIndex..., in: stderr)
        for match in regex.matches(in: stderr, range: range) {
            guard let r = Range(match.range, in: stderr) else { continue }
            let flag = String(stderr[r])
            // 그 플래그를 포함한 그룹을 통째로 찾는다.
            if let group = Self.optionalFlags.first(where: { $0.args.contains(flag) }) {
                return group.name
            }
        }
        return nil
    }

    func polish(_ raw: String,
                model: String,
                style: PolishStyle,
                completion: @escaping (Result<String, Error>) -> Void) {

        DispatchQueue.global(qos: .userInitiated).async {
            guard let exe = Self.resolveExecutable() else {
                completion(.failure(CLIError.notFound))
                return
            }

            var skipping = Prefs.unsupportedCLIFlags

            // 실패하면 선택 플래그를 하나씩 걷어내며 재시도한다.
            // 이름을 콕 집어주면 그걸 빼고, 원인이 안 보이면 뒤에서부터 순서대로 뺀다.
            for attempt in 0...(Self.optionalFlags.count + 1) {
                let args = self.arguments(raw: raw, model: model, style: style, skipping: skipping)

                // 긴 값(원문, 시스템 프롬프트)은 길이만 남기고 실제 인자를 그대로 찍는다.
                let shown = args.map { $0.count > 40 ? "<\($0.count)자>" : $0 }.joined(separator: " ")
                Log.write("CLI 실행(시도 \(attempt + 1)): claude \(shown)")

                switch self.run(exe: exe, args: args) {

                case .success(let stdout):
                    Prefs.unsupportedCLIFlags = skipping
                    completion(stdout.isEmpty ? .failure(CLIError.emptyOutput) : .success(stdout))
                    return

                case .launchFailed(let error):
                    completion(.failure(error))
                    return

                case .failure(let code, let stderr, let stdout):
                    let combined = [stderr, stdout]
                        .filter { !$0.isEmpty }
                        .joined(separator: "\n")

                    let lowered = combined.lowercased()
                    let looksLikeAuth = lowered.contains("not logged in")
                        || lowered.contains("authenticate")
                        || lowered.contains("credential")
                        || lowered.contains("api key")

                    // 인증 실패로 보여도 곧바로 단정하지 않는다.
                    // --bare 처럼 멀쩡한 로그인을 못 읽게 만드는 플래그가 있었다.
                    // 선택 플래그가 남아 있으면 먼저 걷어내고 다시 시도한다.
                    let hasFlagsLeft = Self.optionalFlags.contains { !skipping.contains($0.name) }
                    if looksLikeAuth && !hasFlagsLeft {
                        completion(.failure(CLIError.notLoggedIn(combined)))
                        return
                    }

                    // 1순위: 지원 안 되는 플래그 이름이 메시지에 있는 경우
                    if let bad = self.unsupportedFlag(in: combined), !skipping.contains(bad) {
                        Log.write("이 버전은 \(bad) 그룹을 모릅니다 — 빼고 재시도")
                        skipping.insert(bad)
                        continue
                    }

                    // 2순위: 원인 불명 — 덜 중요한 플래그부터 걷어낸다
                    if let next = Self.optionalFlags.reversed()
                        .first(where: { !skipping.contains($0.name) }) {
                        Log.write("실패(\(combined.prefix(120))) — \(next.name) 그룹 빼고 재시도")
                        skipping.insert(next.name)
                        continue
                    }

                    if looksLikeAuth {
                        completion(.failure(CLIError.notLoggedIn(combined)))
                        return
                    }

                    // 선택 플래그를 전부 뺐는데도 실패
                    completion(.failure(CLIError.failed(code, combined)))
                    return
                }
            }

            completion(.failure(CLIError.failed(1, "지원되는 플래그 조합을 찾지 못했습니다.")))
        }
    }

    private enum RunResult {
        case success(String)
        case failure(Int32, String, String)   // 종료 코드, stderr, stdout
        case launchFailed(Error)
    }

    private func run(exe: String, args: [String]) -> RunResult {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: exe)
        proc.arguments = args

        // GUI 앱 환경에는 PATH가 거의 비어 있다.
        var env = ProcessInfo.processInfo.environment
        let extra = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin",
                     "\(NSHomeDirectory())/.local/bin"]
        env["PATH"] = ((env["PATH"]?.split(separator: ":").map(String.init) ?? []) + extra)
            .reduce(into: [String]()) { acc, p in if !acc.contains(p) { acc.append(p) } }
            .joined(separator: ":")
        env["HOME"] = NSHomeDirectory()

        // 시작할 때 나가는 부수적 네트워크 요청을 끈다.
        // 자동 업데이트 확인, 텔레메트리, 오류 보고, 릴리스 노트, 기능 플래그 조회,
        // 플러그인 마켓플레이스 command 소스의 백그라운드 실행까지 포함된다.
        env["CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC"] = "1"
        env["DISABLE_TELEMETRY"] = "1"
        env["DISABLE_ERROR_REPORTING"] = "1"

        proc.environment = env
        proc.currentDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory())

        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe

        let started = Date()
        do {
            try proc.run()
        } catch {
            Log.write("CLI 실행 실패: \(error)")
            return .launchFailed(error)
        }

        let watchdog = DispatchWorkItem {
            if proc.isRunning {
                Log.write("CLI 타임아웃 — 프로세스 종료")
                proc.terminate()
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + 30, execute: watchdog)

        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        proc.waitUntilExit()
        watchdog.cancel()

        let stdout = (String(data: outData, encoding: .utf8) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let stderr = (String(data: errData, encoding: .utf8) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let elapsed = String(format: "%.1f", Date().timeIntervalSince(started))
        Log.write("CLI 종료 코드 \(proc.terminationStatus), stdout \(stdout.count)자, \(elapsed)초 소요")
        if !stderr.isEmpty { Log.write("CLI stderr: \(stderr.prefix(400))") }
        // 실패했을 땐 stdout에 에러 문구가 담겨 오는 경우가 있어서 같이 남긴다.
        if proc.terminationStatus != 0, !stdout.isEmpty {
            Log.write("CLI stdout: \(stdout.prefix(400))")
        }

        return proc.terminationStatus == 0
            ? .success(stdout)
            : .failure(proc.terminationStatus, stderr, stdout)
    }

    /// 진단용 — 설치 경로와 로그인 상태를 확인한다.
    func status(_ completion: @escaping (String) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            guard let exe = Self.resolveExecutable() else {
                completion("claude 실행 파일을 찾지 못했습니다.")
                return
            }
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: exe)
            proc.arguments = ["auth", "status", "--text"]
            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = pipe
            var env = ProcessInfo.processInfo.environment
            env["HOME"] = NSHomeDirectory()
            proc.environment = env
            do { try proc.run() } catch {
                completion("경로: \(exe)\n실행 실패: \(error.localizedDescription)")
                return
            }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            proc.waitUntilExit()
            let text = (String(data: data, encoding: .utf8) ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            var version = "확인 실패"
            if case .success(let v) = self.run(exe: exe, args: ["--version"]) { version = v }

            let skipped = Prefs.unsupportedCLIFlags.sorted()
            completion("""
                경로: \(exe)
                버전: \(version)
                로그인: \(proc.terminationStatus == 0 ? "됨" : "안 됨")
                미지원으로 제외한 플래그: \(skipped.isEmpty ? "없음" : skipped.joined(separator: " "))

                \(text)
                """)
        }
    }
}
