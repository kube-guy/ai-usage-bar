#!/usr/bin/env bash
# 새 버전을 태그해 푸시하고, tap 의 formula 를 새 tarball 로 갱신한다.
#
#   ./scripts/release.sh 0.2.0
#
# 전제: gh 또는 git 으로 github.com/kube-guy/ai-usage-bar 와
#       github.com/kube-guy/homebrew-kit 에 푸시할 수 있어야 한다.
set -euo pipefail

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
  echo "usage: $0 <version>   (예: $0 0.2.0)" >&2
  exit 1
fi

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TAP_DIR="${TAP_DIR:-$HOME/homebrew-kit}"
FORMULA="$TAP_DIR/Formula/ai-usage-bar.rb"
TARBALL_URL="https://github.com/kube-guy/ai-usage-bar/archive/refs/tags/v${VERSION}.tar.gz"

[[ -f "$FORMULA" ]] || { echo "formula 를 찾을 수 없습니다: $FORMULA" >&2; exit 1; }

cd "$REPO_DIR"

# 1. 버전 문자열을 소스와 맞춘다
sed -i '' -E "s/^let version = \".*\"/let version = \"${VERSION}\"/" Sources/AIUsageBar/main.swift

# 버전이 실제로 반영됐는지 확인 (sed 가 조용히 아무것도 안 바꾸는 경우 방지)
grep -q "let version = \"${VERSION}\"" Sources/AIUsageBar/main.swift \
  || { echo "main.swift 의 버전을 갱신하지 못했습니다." >&2; exit 1; }

# 2. 빌드가 되는지 먼저 확인하고 커밋
swift build -c release
./.build/release/AIUsageBar --version

if ! git diff --quiet; then
  git commit -am "Release v${VERSION}"
fi

# 3. 이 버전의 메뉴바 항목을 그려 남긴다. 아이콘을 눈으로 보고 고른 릴리스가 많아
#    글로만 적어두면 나중에 되짚을 수가 없다. 태그가 제 그림을 담도록 태그 전에 커밋한다.
"$REPO_DIR/scripts/render-icon.sh" HEAD "docs/releases/v${VERSION}.png" >/dev/null
git add "docs/releases/v${VERSION}.png"
git diff --cached --quiet || git commit -q -m "docs: v${VERSION} 메뉴바 모습"

# 4. 태그 푸시 — GitHub 가 이 태그로 tarball 을 만들어준다
git tag -a "v${VERSION}" -m "v${VERSION}"
git push origin main
git push origin "v${VERSION}"

# 5. tarball 해시 계산 (태그 생성 직후에는 잠시 404 일 수 있어 재시도)
echo "tarball 해시 계산 중: $TARBALL_URL"
SHA=""
for _ in 1 2 3 4 5; do
  if SHA="$(curl -fsSL "$TARBALL_URL" | shasum -a 256 | awk '{print $1}')" && [[ -n "$SHA" ]]; then
    break
  fi
  sleep 3
done
[[ -n "$SHA" ]] || { echo "tarball 을 받지 못했습니다: $TARBALL_URL" >&2; exit 1; }
echo "sha256 = $SHA"

# 6. tap 의 formula 갱신 후 푸시
sed -i '' -E "s|^  url \".*\"|  url \"${TARBALL_URL}\"|" "$FORMULA"
sed -i '' -E "s|^  sha256 \".*\"|  sha256 \"${SHA}\"|" "$FORMULA"

cd "$TAP_DIR"
git commit -am "ai-usage-bar ${VERSION}"
git push origin main

# 7. GitHub 릴리스 — 목록에서 버전별 모습을 바로 볼 수 있게 그림을 함께 올린다.
#    본문은 뼈대만 만든다. 왜 그렇게 바꿨는지는 사람이 적어야 쓸모가 있다.
cd "$REPO_DIR"
if command -v gh >/dev/null 2>&1; then
  NOTES="$(mktemp)"
  {
    git log -1 --format='%s' "v${VERSION}^{commit}"
    cat <<MD

![v${VERSION} 메뉴바 모습](https://raw.githubusercontent.com/kube-guy/ai-usage-bar/v${VERSION}/docs/releases/v${VERSION}.png)

<sub>가로 네 칸은 같은 상황입니다 — 여유(29% 사용) · 주의(68%) · 임박(94%) · 소진(100%).
세로 세 줄은 메뉴바 배경입니다 — 색이 있는 배경 · 어두운 배경 · 밝은 배경.
설명용으로 다시 그린 그림이 아니라, 이 태그의 아이콘 소스를 그대로 꺼내 컴파일해 그린 것입니다.</sub>

## 설치

\`\`\`sh
brew tap kube-guy/kit
brew trust --formula kube-guy/kit/ai-usage-bar
brew install ai-usage-bar
brew services start ai-usage-bar
\`\`\`

이 버전을 지정해 설치하려면 (최신이 아니어도 됩니다):

\`\`\`sh
"\$(brew --repo kube-guy/kit)"/install-version.sh ai-usage-bar ${VERSION}
"\$(brew --repo kube-guy/kit)"/install-version.sh ai-usage-bar latest   # 되돌리기
\`\`\`

버전별 모습을 한자리에 모아둔 곳: [릴리스별 모습](https://github.com/kube-guy/ai-usage-bar/blob/main/docs/releases/README.md)
MD
  } > "$NOTES"
  gh release create "v${VERSION}" --title "v${VERSION}" --notes-file "$NOTES" --latest \
    "docs/releases/v${VERSION}.png"
  rm -f "$NOTES"
  echo "릴리스 본문에 제목과 설명을 채워 넣으세요: gh release edit v${VERSION}"
else
  echo "gh 가 없어 GitHub 릴리스는 건너뜁니다." >&2
fi

echo
echo "완료. 확인:"
echo "  brew update && brew upgrade ai-usage-bar"
