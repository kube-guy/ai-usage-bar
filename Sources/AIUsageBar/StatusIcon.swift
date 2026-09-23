import AppKit

/// 메뉴바 항목 전체를 하나의 이미지로 그린다. 숫자 텍스트는 쓰지 않는다.
///
///     X  ◎  ▬▬▬▬
///           ▬▬▬▬
///
/// - 글자      : 서비스 구분(C/X). 왼쪽에 크게 둔다
/// - 이중 원   : 리셋까지의 진행. 안쪽이 5시간, 바깥이 주간
/// - 가로 바   : 남은 한도. 위가 5시간, 아래가 주간
///
/// 정보 성격에 따라 형태를 나눴다. 시간은 돌아오니 원, 한도는 쓰면 줄어드니 막대다.
/// 같은 형태를 크기만 달리해 여러 개 놓으면 무엇이 무엇인지 매번 되짚게 된다.
///
/// 막대는 배터리처럼 **남은 양**을 칠한다. 가득 찬 초록에서 시작해 줄면서 노랑·빨강이 된다.
enum StatusIcon {
    // 레이아웃 (pt). 메뉴바 높이가 ~22pt 라 세로는 18 을 넘기지 않는다.
    private static let height: CGFloat = 18
    private static let glyphBoxWidth: CGFloat = 11
    private static let ringSize: CGFloat = 15
    private static let gapBeforeBars: CGFloat = 4
    private static let barWidth: CGFloat = 14
    private static let barHeight: CGFloat = 4.6
    private static let barGap: CGFloat = 1.8

    static var width: CGFloat { glyphBoxWidth + ringSize + gapBeforeBars + barWidth }

    private static func mono(_ isDark: Bool, _ alpha: CGFloat) -> NSColor {
        isDark ? NSColor(white: 1, alpha: alpha) : NSColor(white: 0.08, alpha: alpha)
    }

    /// 남은 한도에 따른 색. 넉넉하면 초록, 줄면 앰버, 얼마 없으면 레드.
    private static func level(remaining: Double, isDark: Bool) -> NSColor {
        if remaining <= 14 {
            return isDark
                ? NSColor(srgbRed: 1.00, green: 0.42, blue: 0.39, alpha: 1)
                : NSColor(srgbRed: 0.80, green: 0.16, blue: 0.16, alpha: 1)
        }
        if remaining <= 39 {
            return isDark
                ? NSColor(srgbRed: 1.00, green: 0.80, blue: 0.30, alpha: 1)
                : NSColor(srgbRed: 0.76, green: 0.50, blue: 0.03, alpha: 1)
        }
        return isDark
            ? NSColor(srgbRed: 0.42, green: 0.85, blue: 0.50, alpha: 1)
            : NSColor(srgbRed: 0.16, green: 0.62, blue: 0.28, alpha: 1)
    }

    static func make(
        letter: String,
        sessionPct: Double, weeklyPct: Double,
        sessionElapsed: Double?, weeklyElapsed: Double?,
        isDark: Bool
    ) -> NSImage {
        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { _ in
            let centerY = height / 2

            drawGlyph(letter, center: NSPoint(x: glyphBoxWidth / 2 + 0.5, y: centerY), isDark: isDark)

            let ringCenter = NSPoint(x: glyphBoxWidth + ringSize / 2, y: centerY)
            drawRings(
                center: ringCenter, sessionElapsed: sessionElapsed,
                weeklyElapsed: weeklyElapsed, isDark: isDark)

            let barX = glyphBoxWidth + ringSize + gapBeforeBars
            drawBar(
                x: barX, y: centerY + barGap / 2, used: sessionPct, isDark: isDark)
            drawBar(
                x: barX, y: centerY - barGap / 2 - barHeight, used: weeklyPct, isDark: isDark)
            return true
        }
        image.isTemplate = false
        return image
    }

    private static func drawGlyph(_ letter: String, center: NSPoint, isDark: Bool) {
        let font = NSFont.systemFont(ofSize: 14.5, weight: .semibold)
        let text = NSAttributedString(
            string: letter, attributes: [.font: font, .foregroundColor: mono(isDark, 0.95)])
        let bounds = text.size()
        text.draw(at: NSPoint(x: center.x - bounds.width / 2, y: center.y - bounds.height / 2))
    }

    /// 바깥이 주간, 안쪽이 5시간. 둘 다 리셋을 향해 차오른다.
    private static func drawRings(
        center: NSPoint, sessionElapsed: Double?, weeklyElapsed: Double?, isDark: Bool
    ) {
        let stroke = ringSize * 0.115
        let outerRadius = (ringSize - stroke) / 2
        let innerRadius = outerRadius - stroke / 2 - ringSize * 0.075 - stroke / 2

        ring(center: center, radius: outerRadius, width: stroke, color: mono(isDark, 0.20))
        ring(center: center, radius: innerRadius, width: stroke, color: mono(isDark, 0.20))
        if let weeklyElapsed {
            ring(
                center: center, radius: outerRadius, width: stroke,
                color: mono(isDark, 0.55), fraction: weeklyElapsed)
        }
        if let sessionElapsed {
            ring(
                center: center, radius: innerRadius, width: stroke,
                color: mono(isDark, 0.92), fraction: sessionElapsed)
        }
    }

    /// fraction 이 nil 이면 트랙(전체 원)을 그린다.
    private static func ring(
        center: NSPoint, radius: CGFloat, width: CGFloat, color: NSColor, fraction: Double? = nil
    ) {
        let path = NSBezierPath()
        if let fraction {
            let clamped = min(max(fraction, 0), 1)
            guard clamped > 0 else { return }
            // 12시에서 시계방향. AppKit 은 y축이 위쪽이라 90도가 12시다.
            path.appendArc(
                withCenter: center, radius: radius,
                startAngle: 90, endAngle: 90 - 360 * clamped, clockwise: true)
            path.lineCapStyle = .round
        } else {
            path.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
        }
        path.lineWidth = width
        color.set()
        path.stroke()
    }

    private static func drawBar(x: CGFloat, y: CGFloat, used: Double, isDark: Bool) {
        let remaining = 100 - min(max(used, 0), 100)
        let color = level(remaining: remaining, isDark: isDark)
        let frame = NSRect(x: x, y: y, width: barWidth, height: barHeight)

        // 거의 비면 칠할 면적이 없어 색 신호가 사라진다. 트랙을 같은 색으로 물들여
        // '빨갛게 비어 있음'이 보이게 한다. 배터리가 저전력일 때 빨개지는 것과 같다.
        let trackColor =
            remaining <= 39
            ? color.withAlphaComponent(remaining <= 14 ? 0.38 : 0.26)
            : mono(isDark, 0.22)
        NSBezierPath(roundedRect: frame, xRadius: barHeight / 2, yRadius: barHeight / 2)
            .fill(with: trackColor)

        let filled = barWidth * CGFloat(remaining / 100)
        guard filled > 0.3 else { return }
        NSBezierPath(
            roundedRect: NSRect(x: x, y: y, width: max(filled, barHeight), height: barHeight),
            xRadius: barHeight / 2, yRadius: barHeight / 2
        ).fill(with: color)
    }
}

extension NSBezierPath {
    fileprivate func fill(with color: NSColor) {
        color.set()
        fill()
    }
}
