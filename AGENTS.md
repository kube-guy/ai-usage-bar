# ai-usage-bar

Claude Code / Codex CLI 사용량을 macOS 메뉴바에 표시하는 Swift 네이티브 앱.

## 커밋 신원 — 전역 git 설정을 쓰지 않는다

이 저장소는 공개 저장소다. 커밋 작성자는 반드시 아래로 고정한다.

```
kube-guy <324278276+kube-guy@users.noreply.github.com>
```

**전역 `~/.gitconfig` 가 이 저장소의 커밋에 쓰이게 두지 않는다.** 거기에는 업무용 신원
(실명 + 회사 이메일)이 들어 있고, 한 번 푸시되면 되돌릴 수 없다.

커밋을 만드는 작업 전에 매번 확인한다.

```sh
git var GIT_AUTHOR_IDENT   # kube-guy <324278276+kube-guy@users.noreply.github.com> 여야 한다
```

- 값이 다르면 커밋하지 말고 `git config user.name` / `user.email` 을 먼저 설정한다.
- **`-c user.email=...` 을 커밋마다 붙이는 방식에 의존하지 않는다.** `git merge`,
  `git rebase`, `git cherry-pick`, `git revert` 는 커밋을 만들면서도 이 지정이 빠지기 쉽다.
  실제로 이 저장소는 머지 커밋 하나 때문에 공개 이력에 실명과 회사 이메일이 남아,
  저장소를 지우고 다시 만든 적이 있다.
- 푸시 전에 `git log --format='%an <%ae>'` 로 **전체** 커밋의 작성자를 확인한다.
- `.git/config` 와 `~/.gitconfig` 의 `[includeIf "gitdir:~/ai-usage-bar/"]` 양쪽에
  같은 신원이 걸려 있다. 하나가 사라져도 나머지가 막아준다.
- 공개될 파일에 실명·회사 이메일·개인 이메일을 적지 않는다.

이 파일이 정본이고 `CLAUDE.md` 는 이 파일을 가리키는 심볼릭 링크다.
Claude Code 와 Codex 가 같은 내용을 읽는다.

## 빌드

```sh
swift build -c release
./.build/release/AIUsageBar --dump   # 메뉴바 없이 값만 확인
```

## 릴리스

```sh
./scripts/release.sh 0.3.0
```

버전 갱신 → 빌드 확인 → 태그 푸시 → tap 저장소(`~/homebrew-kit`)의
formula `url`/`sha256` 갱신까지 처리한다. 릴리스 노트는 `gh release create` 로 따로 붙인다.

## 구조 메모

- 메뉴바 항목마다 프로세스를 띄울 필요가 없다. 한 `NSApplication` 에서 `NSStatusItem` 을
  여러 개 만들 수 있다.
- Keychain 토큰은 `security` CLI 로 읽는다. Security 프레임워크를 직접 호출하면 서명되지 않은
  바이너리에 대해 키체인 접근 승인 창이 새로 뜬다.
- `NSAttributedString` 의 `.strokeWidth` 는 포인트가 아니라 **글자 크기의 백분율**이다.
  음수는 외곽선 + 채움, 양수는 외곽선만. X 처럼 획이 교차하는 글자는 `setLineJoin(.round)`
  를 주지 않으면 접합부에 스파이크가 생긴다.
- `legacy/` 는 0.1.0 파이썬 판 보관용이며 `.gitignore` 로 추적에서 제외한다. 공개하지 않는다.
