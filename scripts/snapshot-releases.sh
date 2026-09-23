#!/usr/bin/env bash
# 태그마다 메뉴바 항목을 그려 docs/releases/ 에 넣는다. 전부 다시 만들어도 된다.
#
#   scripts/snapshot-releases.sh            # 빠진 것만
#   scripts/snapshot-releases.sh --all      # 전부 다시
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
out="$here/../docs/releases"
mkdir -p "$out"
all=${1:-}
for tag in $(git -C "$here/.." tag --sort=v:refname); do
    png="$out/$tag.png"
    if [[ -f "$png" && "$all" != "--all" ]]; then continue; fi
    "$here/render-icon.sh" "$tag" "$png" >/dev/null
    echo "$tag"
done
