#!/usr/bin/env bash
# 새 버전을 태그해 푸시하고, tap 의 formula 를 새 tarball 로 갱신한다.
#
#   ./scripts/release.sh 0.2.0
#
# 전제: gh 또는 git 으로 github.com/kube-guy/ai-usage-bar 와
#       github.com/kube-guy/homebrew-ai-usage-bar 에 푸시할 수 있어야 한다.
set -euo pipefail

VERSION="${1:-}"
if [[ -z "$VERSION" ]]; then
  echo "usage: $0 <version>   (예: $0 0.2.0)" >&2
  exit 1
fi

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TAP_DIR="${TAP_DIR:-$HOME/homebrew-ai-usage-bar}"
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

# 3. 태그 푸시 — GitHub 가 이 태그로 tarball 을 만들어준다
git tag -a "v${VERSION}" -m "v${VERSION}"
git push origin main
git push origin "v${VERSION}"

# 4. tarball 해시 계산 (태그 생성 직후에는 잠시 404 일 수 있어 재시도)
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

# 5. tap 의 formula 갱신 후 푸시
sed -i '' -E "s|^  url \".*\"|  url \"${TARBALL_URL}\"|" "$FORMULA"
sed -i '' -E "s|^  sha256 \".*\"|  sha256 \"${SHA}\"|" "$FORMULA"

cd "$TAP_DIR"
git commit -am "ai-usage-bar ${VERSION}"
git push origin main

echo
echo "완료. 확인:"
echo "  brew update && brew upgrade ai-usage-bar"
