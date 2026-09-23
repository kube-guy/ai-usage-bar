#!/bin/bash
# 태그의 소스를 그대로 꺼내 메뉴바 항목을 그린다. 결과는 PNG 한 장.
#
#   scripts/render-icon.sh <태그|커밋> <출력.png>
#
# 아이콘 API 는 세 세대로 나뉜다. 어느 세대인지는 꺼낸 소스를 보고 정한다.
#   1세대 v0.2.0        RingIcon.make(pct:letter:)                  + 숫자 제목
#   2세대 v0.3.0~v0.5.1 RingIcon.make(pct:remaining|elapsed:...)    + 숫자 제목
#   3세대 v0.6.0~       StatusIcon.make(letter:sessionPct:...)      숫자 없음
#
# 세 배경 위에 같은 세 가지 상태를 그린다. 버전끼리 나란히 비교하려면 조건이 같아야 한다.
set -euo pipefail

ref=${1:?사용법: scripts/render-icon.sh <태그> <출력.png>}
out=${2:?사용법: scripts/render-icon.sh <태그> <출력.png>}
repo=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

src=Sources/AIUsageBar
if git -C "$repo" cat-file -e "$ref:$src/StatusIcon.swift" 2>/dev/null; then
    git -C "$repo" show "$ref:$src/StatusIcon.swift" > "$work/Icon.swift"
else
    git -C "$repo" show "$ref:$src/RingIcon.swift" > "$work/Icon.swift"
fi

# 초기 아이콘은 색을 Format 에서 가져다 썼다. 있으면 같이 꺼낸다.
extra=()
if git -C "$repo" cat-file -e "$ref:$src/Format.swift" 2>/dev/null; then
    git -C "$repo" show "$ref:$src/Format.swift" > "$work/Format.swift"
    extra+=("$work/Format.swift")
fi

# 1·2세대는 아이콘 옆에 사용률 숫자가 제목으로 붙었다. 그때 메뉴바에 보이던 모습이
# 아이콘만이 아니라 '아이콘 + 숫자' 였으므로 그것까지 그려야 근거 구실을 한다.
# 인자 이름이 바뀔 때마다 세대가 갈렸다. 세대 번호 대신 실제 시그니처를 보고 고른다.
# label=true 면 그 시절 메뉴바처럼 아이콘 옆에 사용률 숫자를 함께 그린다.
label=true
if grep -q 'letter: String,$' "$work/Icon.swift" && grep -q 'sessionElapsed' "$work/Icon.swift"; then
    call='StatusIcon.make(letter: c.0, sessionPct: c.1, weeklyPct: c.2, sessionElapsed: c.3, weeklyElapsed: c.4, isDark: bg.1)'
    label=false
elif grep -q 'sessionPct: Double, weeklyPct: Double, elapsed' "$work/Icon.swift"; then
    call='RingIcon.make(sessionPct: c.1, weeklyPct: c.2, elapsed: c.3, letter: c.0, isDark: bg.1)'
elif grep -q 'elapsed: Double?' "$work/Icon.swift"; then
    call='RingIcon.make(pct: c.1, elapsed: c.3, letter: c.0, isDark: bg.1)'
elif grep -q 'remaining: Double?' "$work/Icon.swift"; then
    call='RingIcon.make(pct: c.1, remaining: 1 - c.3, letter: c.0, isDark: bg.1)'
else
    call='RingIcon.make(pct: c.1, letter: c.0)'
fi

cat > "$work/main.swift" <<SW
import AppKit

// (글자, 세션 사용률, 주간 사용률, 세션 경과, 주간 경과)
let cases: [(String, Double, Double, Double, Double)] = [
    ("C", 29, 20, 0.35, 0.18),   // 여유
    ("C", 68, 55, 0.72, 0.50),   // 주의
    ("X", 94, 88, 0.90, 0.80),   // 임박
    ("X", 100, 96, 0.99, 0.92),  // 소진 — 다 썼을 때를 빼면 버전 차이가 안 드러난다
]
func rgb(_ h: Int) -> NSColor {
    NSColor(srgbRed: CGFloat((h >> 16) & 0xff) / 255, green: CGFloat((h >> 8) & 0xff) / 255,
            blue: CGFloat(h & 0xff) / 255, alpha: 1)
}
// 메뉴바는 반투명이라 배경화면이 비친다. 밝기만이 아니라 색이 있는 경우도 본다.
let bgs: [(NSColor, Bool)] = [
    (rgb(0x2F82AE), true), (NSColor(white: 0.12, alpha: 1), true), (NSColor(white: 0.93, alpha: 1), false),
]
let showsLabel = $label
let scale: CGFloat = 5, pad: CGFloat = 8, rowPt: CGFloat = 22
let font = NSFont.menuBarFont(ofSize: 0)

func itemWidth(_ c: (String, Double, Double, Double, Double), _ isDark: Bool) -> CGFloat {
    let bg = (NSColor.black, isDark); _ = bg  // 폭 계산에도 같은 호출을 쓴다
    var w = ($call).size.width
    if showsLabel { w += NSAttributedString(string: " \(Int(c.1.rounded()))%", attributes: [.font: font]).size().width }
    return w
}
let cellPt = (cases.map { itemWidth(\$0, true) }.max() ?? 40) + pad * 2
let W = Int(cellPt * CGFloat(cases.count) * scale), rowPx = Int(rowPt * scale)
let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: W, pixelsHigh: rowPx * bgs.count, bitsPerSample: 8,
    samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
    bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
for (i, bg) in bgs.enumerated() {
    let y = CGFloat(rep.pixelsHigh - (i + 1) * rowPx)
    bg.0.set()
    NSRect(x: 0, y: y, width: CGFloat(W), height: CGFloat(rowPx)).fill()
    for (j, c) in cases.enumerated() {
        let image = $call
        var x = (CGFloat(j) * cellPt + pad) * scale
        let h = image.size.height * scale
        let iy = y + (CGFloat(rowPx) - h) / 2
        image.draw(in: NSRect(x: x, y: iy, width: image.size.width * scale, height: h))
        x += image.size.width * scale
        if showsLabel {
            let text = NSAttributedString(
                string: " \(Int(c.1.rounded()))%",
                attributes: [.font: NSFont.menuBarFont(ofSize: font.pointSize * scale),
                             .foregroundColor: bg.1 ? NSColor.white : NSColor.black])
            text.draw(at: NSPoint(x: x, y: y + (CGFloat(rowPx) - text.size().height) / 2))
        }
    }
}
NSGraphicsContext.restoreGraphicsState()
try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
SW

swiftc -O "$work/Icon.swift" "${extra[@]}" "$work/main.swift" -o "$work/render" 2>&1 | grep -v '^$' >&2 || true
[ -x "$work/render" ] || { echo "컴파일 실패: $ref" >&2; exit 1; }
mkdir -p "$(dirname "$out")"
"$work/render" "$out"
echo "$ref → $out"
