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

메뉴바 아이콘은 링 두 개로 이루어집니다.

| | 뜻 | 색 |
|---|---|---|
| 안쪽 링 | 5시간 세션 사용률 | 초록(0–60%) → 주황(61–85%) → 빨강(86–99%) → 흰색(100%) |
| 바깥 링 | 5시간 세션 창이 지난 정도 | 무채색 (메뉴바 배경에 맞춰 반전) |

두 링 모두 **차오르는 방향**입니다. 바깥 링이 줄어드는 방향이면 안쪽 링과 반대로 움직여
한눈에 읽기 어렵습니다. 같은 방향이면 리셋 순간에 둘이 함께 완성됩니다 — 안쪽이 꽉 차고
바깥도 꽉 찼다면 "다 썼지만 곧 리셋된다" 가 그림 하나로 읽힙니다.

바깥 링을 무채색으로 둔 것은 색이 오직 사용량만 뜻하게 하기 위해서입니다.
두 링에 모두 색을 쓰면 어느 쪽 색이 무슨 뜻인지 매번 되짚어야 합니다.

밝기 판단은 시스템 외형 설정이 아니라 상태 아이템 버튼의 `effectiveAppearance` 로 합니다.
배경화면 때문에 메뉴바만 어두워진 경우까지 반영됩니다.

Codex 는 사용량 API 가 창 길이(`limit_window_seconds`)를 함께 주지만, Claude 는 리셋 시각만
주고 창 길이를 주지 않아 5시간으로 가정해 계산합니다.

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
