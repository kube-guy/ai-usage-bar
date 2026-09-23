import AppKit

/// 메뉴바 항목 전체를 하나의 이미지로 그린다. 숫자 텍스트는 쓰지 않는다.
///
///     (X) ▬▬▬▬
///         ▬▬▬▬
///
/// - 글자      : 서비스 구분(C/X). 원 안에 둔다
/// - 이중 원   : 리셋까지의 진행. 안쪽이 5시간, 바깥이 주간
/// - 가로 바   : 남은 한도. 위가 5시간, 아래가 주간
///
/// 정보 성격에 따라 형태를 나눴다. 시간은 돌아오니 원, 한도는 쓰면 줄어드니 막대다.
/// 같은 형태를 크기만 달리해 여러 개 놓으면 무엇이 무엇인지 매번 되짚게 된다.
///
/// 막대는 배터리처럼 **남은 양**을 칠한다. 가득 찬 초록에서 시작해 줄면서 앰버가 되고,
/// 얼마 안 남으면 막대 전체가 빨개지고 남은 양이 흰색으로 얹힌다.
enum StatusIcon {
    /// 메뉴바 높이(~22pt)를 넘기면 이미지가 축소되어 전부 작아진다. 20 을 넘기지 않는다.
    private static let height: CGFloat = 20
    private static let ringSize: CGFloat = 19
    private static let gapBeforeBars: CGFloat = 4
    private static let barWidth: CGFloat = 14
    private static let barHeight: CGFloat = 4.6
    private static let barGap: CGFloat = 1.8

    static var width: CGFloat { ringSize + gapBeforeBars + barWidth }

    private static func mono(_ isDark: Bool, _ alpha: CGFloat) -> NSColor {
        isDark ? NSColor(white: 1, alpha: alpha) : NSColor(white: 0.08, alpha: alpha)
    }

    /// 남은 한도에 따른 색. 넉넉하면 초록, 줄면 앰버, 얼마 없으면 레드.
    private static func level(remaining: Double, isDark: Bool) -> NSColor {
        if remaining <= 14 {
            return isDark
                ? NSColor(srgbRed: 1.00, green: 0.27, blue: 0.23, alpha: 1)
                : NSColor(srgbRed: 0.72, green: 0.07, blue: 0.07, alpha: 1)
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

            let ringCenter = NSPoint(x: ringSize / 2, y: centerY)
            drawRings(
                center: ringCenter, letter: letter, sessionElapsed: sessionElapsed,
                weeklyElapsed: weeklyElapsed, isDark: isDark)

            let barX = ringSize + gapBeforeBars
            drawBar(
                x: barX, y: centerY + barGap / 2, used: sessionPct, isDark: isDark)
            drawBar(
                x: barX, y: centerY - barGap / 2 - barHeight, used: weeklyPct, isDark: isDark)
            return true
        }
        image.isTemplate = false
        return image
    }

    private static func drawGlyph(_ letter: String, center: NSPoint, size: CGFloat, isDark: Bool) {
        let font = NSFont.systemFont(ofSize: size, weight: .semibold)
        let text = NSAttributedString(
            string: letter, attributes: [.font: font, .foregroundColor: mono(isDark, 0.95)])
        let bounds = text.size()
        text.draw(at: NSPoint(x: center.x - bounds.width / 2, y: center.y - bounds.height / 2))
    }

    /// 바깥이 주간, 안쪽이 5시간. 둘 다 리셋을 향해 차오른다.
    private static func drawRings(
        center: NSPoint, letter: String, sessionElapsed: Double?, weeklyElapsed: Double?,
        isDark: Bool
    ) {
        // 선을 얇게 둘수록 안쪽 글자 자리가 넓어진다. 글자를 원 안에 넣으려면 이 균형이 전부다.
        let stroke = ringSize * 0.070
        let outerRadius = (ringSize - stroke) / 2
        let innerRadius = outerRadius - stroke / 2 - ringSize * 0.058 - stroke / 2

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
        drawGlyph(letter, center: center, size: (innerRadius - stroke / 2) * 1.50, isDark: isDark)
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
        let critical = remaining <= 14
        let color = level(remaining: remaining, isDark: isDark)
        let frame = NSRect(x: x, y: y, width: barWidth, height: barHeight)

        // 거의 비면 칠할 면적이 없어 색 신호가 사라진다. 그때는 막대 전체를 빨갛게
        // 칠하고 남은 양을 흰색으로 얹어, '빨갛게 비어 있음'이 한눈에 보이게 한다.
        // 앰버 구간까지 물들이면 바탕과 채움이 같은 색 계열이라 탁해지므로 건드리지 않는다.
        NSBezierPath(roundedRect: frame, xRadius: barHeight / 2, yRadius: barHeight / 2)
            .fill(with: critical ? color.withAlphaComponent(0.92) : mono(isDark, 0.22))

        let filled = barWidth * CGFloat(remaining / 100)
        guard filled > 0.3 else { return }
        let fillColor = critical ? NSColor(white: 1, alpha: isDark ? 1.0 : 0.95) : color
        NSBezierPath(
            roundedRect: NSRect(x: x, y: y, width: max(filled, barHeight), height: barHeight),
            xRadius: barHeight / 2, yRadius: barHeight / 2
        ).fill(with: fillColor)
    }
}

extension NSBezierPath {
    fileprivate func fill(with color: NSColor) {
        color.set()
        fill()
    }
}
