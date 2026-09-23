# ai-usage-bar

Claude Code 와 Codex CLI 의 사용량 한도를 macOS 메뉴바에 링 게이지로 표시합니다.

```
 20%   ← Claude Code (5시간 세션 사용률)
  3%   ← Codex CLI  (5시간 세션 사용률)
```

클릭하면 플랜, 5시간 세션 / 주간 한도, 리셋 시각, 이번 달 모델별 사용 비중이 보입니다.

Swift 네이티브 앱이라 런타임 의존성이 없습니다 — 파이썬도, 별도 프레임워크도 설치하지 않습니다.

## 설치

```sh
brew tap kube-guy/kit
brew trust --formula kube-guy/kit/ai-usage-bar
brew install ai-usage-bar
```

Homebrew 7.0 부터는 서드파티 tap 의 formula 를 쓰려면 `brew trust` 로 한 번 신뢰를 표시해야 합니다.
(`brew trust kube-guy/kit` 로 tap 전체를 신뢰할 수도 있지만, 위처럼 formula 하나만 신뢰하는 쪽이 좁습니다.)

## 로그인

사용량은 각 CLI 가 이미 저장해둔 로그인 정보로 읽습니다. 별도의 세션키 복사 과정이 없습니다.

| | 로그인 방법 | 토큰 위치 |
|---|---|---|
| Claude Code | 터미널에서 `claude` 실행 후 로그인 | macOS Keychain (`Claude Code-credentials`) |
| Codex CLI | 터미널에서 `codex` 실행 후 ChatGPT 계정 로그인 | `~/.codex/auth.json` |

Keychain 토큰은 `security` 명령으로 읽습니다. Security 프레임워크를 직접 호출하면 서명되지 않은
이 바이너리에 대해 키체인 접근 승인 창이 새로 뜨지만, `security` 는 이미 승인돼 있어 추가 승인이 필요 없습니다.

Codex 는 ChatGPT 구독 로그인 전용 엔드포인트를 쓰므로, `OPENAI_API_KEY` 만 쓰는 경우에는 사용량이 표시되지 않습니다.

## 실행

로그인 시 자동으로 뜨게 하려면:

```sh
brew services start ai-usage-bar
```

수동으로 띄우거나, 터미널에서 값만 확인하려면:

```sh
ai-usage-bar                 # Claude + Codex 둘 다
ai-usage-bar --only claude
ai-usage-bar --dump          # 메뉴바 대신 터미널에 출력 (GUI 없는 환경에서 진단용)
```

중지 / 제거:

```sh
brew services stop ai-usage-bar
brew uninstall ai-usage-bar
```

로그는 `$(brew --prefix)/var/log/ai-usage-bar.log` 와 `ai-usage-bar.err.log` 에 쌓입니다.

## 표시 내용

**Claude Code**

- 5시간 세션 / 주간 한도 사용률과 리셋 시각 — `https://api.anthropic.com/api/oauth/usage`
- 이번 달 모델별(opus/sonnet/haiku) 메시지 비중, 오늘 / 최근 7일 / 전체 메시지 수 — `~/.claude/projects/**/*.jsonl` 을 로컬에서 읽어 집계 (외부로 전송하지 않음)

**Codex CLI**

- 5시간 세션 / 주간 한도 사용률과 리셋 시각, 크레딧 잔액 — `https://chatgpt.com/backend-api/wham/usage`

두 엔드포인트 모두 각 CLI 가 `/status` 표시에 실제로 쓰는 것이지만 공식 문서화된 API 는 아니므로, 제공사 쪽 변경으로 동작이 바뀔 수 있습니다.

메뉴바 항목은 숫자 없이 그림만으로 네 가지를 보여줍니다.

```
(X) ▬▬▬▬     위 바  = 5시간 한도 잔량
    ▬▬▬▬     아래 바 = 주간 한도 잔량
```

| 요소 | 뜻 |
|---|---|
| 글자 | 서비스 구분 (C = Claude Code, X = Codex). 원 안에 둡니다 |
| 안쪽 원 | 5시간 리셋까지의 진행 |
| 바깥 원 | 주간 리셋까지의 진행 |
| 위 가로 바 | 5시간 한도 **잔량** |
| 아래 가로 바 | 주간 한도 **잔량** |

**정보 성격에 따라 형태를 나눴습니다.** 시간은 돌아오니 원, 한도는 쓰면 줄어드니 막대입니다.
같은 형태를 크기만 달리해 여러 개 놓으면 무엇이 무엇인지 매번 되짚게 됩니다.

막대는 **배터리처럼 남은 양**을 칠합니다. 가득 찬 초록에서 시작해 줄면서 앰버가 됩니다.

**얼마 안 남으면(10% 이하) 막대 전체가 빨개지고 남은 양이 흰색으로 얹힙니다.** 거의 비었을 때
남은 부분만 칠하면 면적이 없어 색 신호가 사라지기 때문입니다. macOS 배터리도 같은 한계가
있지만 그쪽은 옆에 %를 함께 띄웁니다. 이 앱은 숫자를 두지 않으므로 막대 하나로 말해야 합니다.

원은 둘 다 차오르는 방향이고 리셋 순간에 완성됩니다.

밝기 판단은 시스템 외형 설정이 아니라 상태 아이템 버튼의 `effectiveAppearance` 로 합니다.
배경화면 때문에 메뉴바만 어두워진 경우까지 반영됩니다.

정확한 수치와 리셋 시각은 아이콘을 클릭하면 나오는 메뉴에 있습니다.

Codex 는 사용량 API 가 창 길이(`limit_window_seconds`)를 함께 주지만, Claude 는 리셋 시각만
주고 창 길이를 주지 않아 5시간 / 7일로 가정해 계산합니다.

## 구조

한 프로세스 안에서 `NSStatusItem` 을 두 개 만듭니다. 메뉴바 항목마다 별도 프로세스를 띄우고
이를 감시할 런처가 필요했던 파이썬 판과 달리, 감시 대상이 프로세스 하나뿐이라
`brew services` 설정도 그대로 단순합니다.

```
Sources/AIUsageBar/
  main.swift                 인자 처리, NSApplication 기동 (.accessory = Dock 아이콘 없음)
  StatusItemController.swift 메뉴바 항목 하나 — 1분 타이머, 링 갱신, 메뉴 구성
  RingIcon.swift             NSBezierPath 로 그리는 원형 게이지
  Format.swift               막대 / 리셋 시각 / 상태 색
  UsageProvider.swift        공통 프로토콜, HTTP, 오류 타입
  ClaudeProvider.swift       Keychain + usage API + JSONL 집계
  CodexProvider.swift        auth.json + usage API
```

`.app` 번들 없이 단일 실행 파일로 동작합니다 — `NSApplication.setActivationPolicy(.accessory)` 가
Dock 아이콘과 메뉴 막대를 없애는 역할을 대신합니다.

## 개발

```sh
git clone https://github.com/kube-guy/ai-usage-bar
cd ai-usage-bar
swift build -c release
./.build/release/AIUsageBar --dump
```

새 버전 릴리스 (버전 갱신 + 빌드 확인 + 태그 푸시 + tap 의 formula 갱신):

```sh
./scripts/release.sh 0.3.0
```

## 파이썬 판

0.1.0 까지는 `rumps` + `pyobjc` 기반 파이썬 앱이었고, `python@3.13` 을 의존성으로 끌어와
프로세스 3개(런처 + 메뉴바 2개)로 동작했습니다. 0.2.0 에서 Swift 로 다시 쓰면서
런타임 의존성이 없어졌습니다.

| | 0.1.0 (Python) | 0.2.0 (Swift) |
|---|---|---|
| 런타임 의존성 | `python@3.13` + rumps + pyobjc | 없음 |
| 프로세스 수 | 3 | 1 |
| 설치 시 빌드 시간 | 약 12분 (pyobjc 컴파일) | 약 1분 |

## 라이선스

MIT
