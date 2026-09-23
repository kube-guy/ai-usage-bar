import AppKit

let version = "0.5.1"

// MARK: - 명령줄 인자

func usage() -> String {
    """
    usage: ai-usage-bar [--only claude|codex] [--version] [--help]

    Claude Code / Codex CLI 사용량을 맥 메뉴바에 표시합니다.

    옵션:
      --only {claude,codex}  지정한 메뉴바만 띄웁니다. 여러 번 줄 수 있습니다. (기본: 둘 다)
      --dump                 메뉴바를 띄우는 대신 읽어온 내용을 터미널에 출력합니다.
      --version              버전을 출력합니다.
      --help                 이 도움말을 출력합니다.
    """
}

var selected: [String] = []
var dump = false
var arguments = Array(CommandLine.arguments.dropFirst())

while let argument = arguments.first {
    arguments.removeFirst()
    switch argument {
    case "--version":
        print("ai-usage-bar \(version)")
        exit(0)
    case "--help", "-h":
        print(usage())
        exit(0)
    case "--dump":
        dump = true
    case "--only":
        guard let value = arguments.first else {
            FileHandle.standardError.write(Data("--only 에 claude 또는 codex 가 필요합니다.\n".utf8))
            exit(2)
        }
        arguments.removeFirst()
        guard ["claude", "codex"].contains(value) else {
            FileHandle.standardError.write(Data("알 수 없는 값입니다: \(value)\n".utf8))
            exit(2)
        }
        if !selected.contains(value) { selected.append(value) }
    default:
        FileHandle.standardError.write(Data("알 수 없는 옵션입니다: \(argument)\n\(usage())\n".utf8))
        exit(2)
    }
}

let names = selected.isEmpty ? ["claude", "codex"] : selected

func provider(named name: String) -> UsageProvider {
    name == "claude" ? ClaudeProvider() : CodexProvider()
}

// MARK: - 터미널 출력 모드

if dump {
    var failed = false
    for name in names {
        let source = provider(named: name)
        print("── \(source.name) [\(source.letter)] ─────────────")
        do {
            let result = try source.fetch()
            print("  세션 사용률: \(Format.percent(result.sessionPercent))  (글자 색)")
            print("  주간 사용률: \(Format.percent(result.weeklyPercent))  (바깥 링)")
            if let elapsed = result.sessionElapsed {
                print("  세션 창 경과: \(Format.percent(elapsed * 100))  (안쪽 링)")
            } else {
                print("  세션 창 경과: 알 수 없음 (안쪽 링 미표시)")
            }
            for row in result.rows {
                switch row {
                case .separator: print("")
                case .text(let line), .mono(let line): print(line)
                }
            }
        } catch {
            print("  \(error.localizedDescription)")
            failed = true
        }
        print("")
    }
    exit(failed ? 1 : 0)
}

// MARK: - 앱 기동

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controllers: [StatusItemController] = []
    private let names: [String]

    init(names: [String]) {
        self.names = names
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        for name in names {
            controllers.append(StatusItemController(provider: provider(named: name)))
        }
    }
}

let app = NSApplication.shared
// 메뉴바 전용 앱 — Dock 아이콘과 메뉴 막대를 띄우지 않는다 (.app 번들 없이도 동작).
app.setActivationPolicy(.accessory)
let delegate = AppDelegate(names: names)
app.delegate = delegate
app.run()
