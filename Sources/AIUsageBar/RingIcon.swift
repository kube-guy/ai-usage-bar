import AppKit

/// 메뉴바용 원형 게이지(링) 아이콘.
///
/// `NSImage(size:flipped:drawingHandler:)` 는 표시 배율에 맞춰 다시 그려주므로
/// 레티나에서도 선명하고, 파이썬 판과 달리 PNG 임시 파일을 거치지 않는다.
enum RingIcon {
    private static let trackColor = NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.27)

    static func make(pct: Double, letter: String, size: CGFloat = 20) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            let stroke = size * 0.13
            let radius = (size - stroke) / 2
            let center = NSPoint(x: size / 2, y: size / 2)

            // 배경 트랙(반투명 흰색 원) — 어떤 메뉴바 배경에서도 보이도록
            let track = NSBezierPath()
            track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
            track.lineWidth = stroke
            trackColor.set()
            track.stroke()

            let clamped = min(max(pct, 0), 100)
            if clamped > 0 {
                // AppKit 은 y축이 위쪽이라 12시(90도)에서 시계방향으로 그린다.
                let arc = NSBezierPath()
                arc.appendArc(
                    withCenter: center,
                    radius: radius,
                    startAngle: 90,
                    endAngle: 90 - 360 * clamped / 100,
                    clockwise: true
                )
                arc.lineWidth = stroke
                arc.lineCapStyle = .round
                Format.statusColor(clamped).set()
                arc.stroke()
            }

            let fontSize = size * 0.46
            let font = NSFont(name: "Arial-BoldMT", size: fontSize)
                ?? NSFont.boldSystemFont(ofSize: fontSize)

            let fill = NSAttributedString(
                string: letter,
                attributes: [.font: font, .foregroundColor: NSColor.white]
            )
            let bounds = fill.size()
            let origin = NSPoint(x: (size - bounds.width) / 2, y: (size - bounds.height) / 2)

            // 글자 바깥쪽에만 외곽선이 남도록 굵게 그린 뒤 흰 글자로 덮는다.
            // `.strokeWidth` 는 포인트가 아니라 글자 크기의 백분율이고, 이음을 둥글게
            // 하지 않으면 X 의 접합부에 뾰족한 스파이크가 생긴다.
            if let context = NSGraphicsContext.current?.cgContext {
                context.saveGState()
                context.setLineJoin(.round)
                NSAttributedString(string: letter, attributes: [
                    .font: font,
                    .foregroundColor: NSColor.clear,
                    .strokeColor: NSColor.black.withAlphaComponent(0.85),
                    .strokeWidth: 15.0,
                ]).draw(at: origin)
                context.restoreGState()
            }
            fill.draw(at: origin)

            return true
        }
        // 링 색이 상태를 나타내므로 템플릿 모드(단색 강제)를 쓰지 않는다.
        image.isTemplate = false
        return image
    }
}
