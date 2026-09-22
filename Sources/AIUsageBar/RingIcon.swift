import AppKit

/// 메뉴바용 이중 링 아이콘.
///
/// - 바깥 링 : 현재 한도 창이 리셋되기까지 남은 시간 (무채색)
/// - 안쪽 링 : 사용률 (초록 → 주황 → 빨강 → 흰색)
///
/// 바깥 링을 무채색으로 두는 이유는, 색이 오직 사용량만 뜻하게 하기 위해서다.
/// 두 링에 모두 색을 쓰면 어느 쪽 색이 무슨 뜻인지 매번 되짚어야 한다.
///
/// `NSImage(size:flipped:drawingHandler:)` 는 표시 배율에 맞춰 다시 그려주므로
/// 레티나에서도 선명하고, 파이썬 판과 달리 PNG 임시 파일을 거치지 않는다.
enum RingIcon {
    /// 메뉴바 배경이 어두운지에 따라 무채색 톤을 뒤집는다.
    private struct Palette {
        let outerArc: NSColor
        let outerTrack: NSColor
        let innerTrack: NSColor

        init(isDark: Bool) {
            if isDark {
                outerArc = NSColor(white: 1, alpha: 0.85)
                outerTrack = NSColor(white: 1, alpha: 0.20)
                innerTrack = NSColor(white: 1, alpha: 0.27)
            } else {
                outerArc = NSColor(white: 0, alpha: 0.55)
                outerTrack = NSColor(white: 0, alpha: 0.13)
                innerTrack = NSColor(white: 0, alpha: 0.15)
            }
        }
    }

    /// - Parameters:
    ///   - pct: 사용률 0~100
    ///   - remaining: 리셋까지 남은 비율 0~1. nil 이면 바깥 링을 그리지 않는다.
    ///   - isDark: 메뉴바 배경이 어두운지
    static func make(
        pct: Double, remaining: Double?, letter: String, isDark: Bool, size: CGFloat = 20
    ) -> NSImage {
        let palette = Palette(isDark: isDark)

        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            let center = NSPoint(x: size / 2, y: size / 2)

            let outerWidth = size * 0.075
            let outerRadius = (size - outerWidth) / 2
            let gap = size * 0.045
            let innerWidth = size * 0.125
            let innerRadius = outerRadius - outerWidth / 2 - gap - innerWidth / 2

            // 바깥 링 — 남은 시간
            circle(center: center, radius: outerRadius, width: outerWidth, color: palette.outerTrack)
            if let remaining {
                arc(
                    center: center, radius: outerRadius, fraction: remaining,
                    width: outerWidth, color: palette.outerArc, rounded: false)
            }

            // 안쪽 링 — 사용률
            circle(center: center, radius: innerRadius, width: innerWidth, color: palette.innerTrack)
            let clamped = min(max(pct, 0), 100)
            if clamped > 0 {
                arc(
                    center: center, radius: innerRadius, fraction: clamped / 100,
                    width: innerWidth, color: Format.statusColor(clamped), rounded: true)
            }

            drawLetter(letter, center: center, radius: innerRadius)
            return true
        }
        // 링 색이 상태를 나타내므로 템플릿 모드(단색 강제)를 쓰지 않는다.
        image.isTemplate = false
        return image
    }

    private static func circle(center: NSPoint, radius: CGFloat, width: CGFloat, color: NSColor) {
        let path = NSBezierPath()
        path.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
        path.lineWidth = width
        color.set()
        path.stroke()
    }

    /// 12시에서 시계방향으로 `fraction` 만큼. AppKit 은 y축이 위쪽이라 90도가 12시다.
    private static func arc(
        center: NSPoint, radius: CGFloat, fraction: Double, width: CGFloat,
        color: NSColor, rounded: Bool
    ) {
        let clamped = min(max(fraction, 0), 1)
        guard clamped > 0 else { return }
        let path = NSBezierPath()
        path.appendArc(
            withCenter: center, radius: radius,
            startAngle: 90, endAngle: 90 - 360 * clamped, clockwise: true)
        path.lineWidth = width
        if rounded { path.lineCapStyle = .round }
        color.set()
        path.stroke()
    }

    /// 안쪽 링 안에 로고 글자. 링이 둘이라 공간이 좁으므로 안쪽 반지름에 맞춘다.
    private static func drawLetter(_ letter: String, center: NSPoint, radius: CGFloat) {
        let fontSize = radius * 1.15
        let font = NSFont(name: "Arial-BoldMT", size: fontSize)
            ?? NSFont.boldSystemFont(ofSize: fontSize)

        let fill = NSAttributedString(
            string: letter, attributes: [.font: font, .foregroundColor: NSColor.white])
        let bounds = fill.size()
        let origin = NSPoint(x: center.x - bounds.width / 2, y: center.y - bounds.height / 2)

        // 글자 바깥쪽에만 외곽선이 남도록 굵게 먼저 그리고 흰 글자로 덮는다.
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
    }
}
