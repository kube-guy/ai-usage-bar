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
/// 막대는 배터리처럼 **남은 양**을 칠한다. 쓸수록 줄어들고, 줄면서 색이 바뀐다.
/// 바탕을 덧칠하거나 채움 색을 바꾸는 장치는 두지 않는다. 남은 만큼만 그리고 색만 바꾼다.
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

    /// 메뉴에서 쓰는 색. 기준(잔여량)은 아이콘과 같지만 채도를 올렸다.
    /// 메뉴는 글자와 막대가 아이콘보다 훨씬 넓어 같은 색도 연하게 보인다.
    /// 다크/라이트는 시스템이 맞춰주므로 동적 색으로 돌려준다.
    static func levelColor(remaining: Double) -> NSColor {
        NSColor(name: nil) { appearance in
            let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            if remaining <= 10 {
                return dark
                    ? NSColor(srgbRed: 1.00, green: 0.23, blue: 0.19, alpha: 1)
                    : NSColor(srgbRed: 0.76, green: 0.03, blue: 0.03, alpha: 1)
            }
            if remaining <= 39 {
                return dark
                    ? NSColor(srgbRed: 1.00, green: 0.76, blue: 0.09, alpha: 1)
                    : NSColor(srgbRed: 0.70, green: 0.42, blue: 0.00, alpha: 1)
            }
            return dark
                ? NSColor(srgbRed: 0.20, green: 0.88, blue: 0.40, alpha: 1)
                : NSColor(srgbRed: 0.05, green: 0.55, blue: 0.18, alpha: 1)
        }
    }

    /// 남은 양에 따른 색. 넉넉하면 초록, 줄면 앰버, 얼마 없으면 레드.
    private static func level(remaining: Double, isDark: Bool) -> NSColor {
        if remaining <= 10 {
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
        let frame = NSRect(x: x, y: y, width: barWidth, height: barHeight)

        // 다 쓰면 칠할 게 없어 막대가 빈 회색으로 남는다. 가장 위험한 순간에 신호가
        // 사라지므로, 그때는 빈 트랙 자체를 빨갛게 둔다. 채우지 않고 색만 바꾸는 것이다.
        let trackColor =
            remaining <= 0
            ? level(remaining: 0, isDark: isDark).withAlphaComponent(isDark ? 0.72 : 0.62)
            : mono(isDark, 0.22)
        NSBezierPath(roundedRect: frame, xRadius: barHeight / 2, yRadius: barHeight / 2)
            .fill(with: trackColor)

        guard remaining > 0 else { return }
        // 조금이라도 남아 있으면 반드시 보이게 한다. 그냥 비율대로 그리면 2% 남았을 때
        // 폭이 0.28pt 라 사실상 사라져, 가장 위험한 순간에 빨간 신호가 없어진다.
        let filled = max(barWidth * CGFloat(remaining / 100), barHeight * 0.75)

        // 채움을 둥근 캡슐로 그리면 눈이 둥근 끝을 뺀 '몸통'을 비교해 실제보다 적어 보인다.
        // 트랙 모양으로 잘라내고 사각형을 채우면 보이는 길이가 값과 일치한다.
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: frame, xRadius: barHeight / 2, yRadius: barHeight / 2).addClip()
        level(remaining: remaining, isDark: isDark).set()
        NSRect(x: x, y: y, width: filled, height: barHeight).fill()
        NSGraphicsContext.restoreGraphicsState()
    }
}

extension NSBezierPath {
    fileprivate func fill(with color: NSColor) {
        color.set()
        fill()
    }
}
