import AppKit

/// 메뉴바용 이중 링 아이콘.
///
/// - 바깥 링 : 주간 한도 사용률
/// - 안쪽 링 : 현재 5시간 창이 얼마나 지났는지
/// - 가운데 글자        : 서비스 구분. 세션 사용률이 높을 때만 색이 붙는다
///
/// 설계 원칙은 "평소엔 무채색, 바빠질 때만 색"이다. 여유로울 때까지 초록을 칠하면
/// 메뉴바가 늘 시끄럽고, 정작 경고가 눈에 띄지 않는다. 색이 나타나는 것 자체가 신호다.
///
/// 두 링은 색 대신 굵기와 농도로 구분한다(안쪽이 조금 더 굵고 진하다).
/// 색은 경고 전용으로 남겨둔다. 바깥 링은 처음에 더 얇고 옅었는데
/// 두 약점이 겹쳐 잘 보이지 않아, 두께와 농도를 함께 올렸다.
///
/// 글자에 외곽선을 두르지 않는 것도 같은 이유다. 예전에는 흰 글자를 고집하느라
/// 검정 테두리가 필요했는데, 배경에 맞춰 글자색을 뒤집으면 테두리 없이도 읽힌다.
enum RingIcon {
    /// 메뉴바 배경이 어두운지에 따라 무채색을 뒤집는다.
    private static func mono(_ isDark: Bool, _ alpha: CGFloat) -> NSColor {
        isDark ? NSColor(white: 1, alpha: alpha) : NSColor(white: 0.08, alpha: alpha)
    }

    /// 세션 사용률이 높을 때만 색을 돌려준다. 여유로우면 nil.
    /// 원색보다 채도를 낮춰 메뉴바에서 튀지 않게 한다.
    private static func warning(_ pct: Double, isDark: Bool) -> NSColor? {
        if pct >= 86 {
            return isDark
                ? NSColor(srgbRed: 1.00, green: 0.41, blue: 0.38, alpha: 1)
                : NSColor(srgbRed: 0.78, green: 0.18, blue: 0.18, alpha: 1)
        }
        if pct >= 61 {
            return isDark
                ? NSColor(srgbRed: 0.96, green: 0.71, blue: 0.31, alpha: 1)
                : NSColor(srgbRed: 0.75, green: 0.47, blue: 0.08, alpha: 1)
        }
        return nil
    }

    /// - Parameters:
    ///   - sessionPct: 5시간 세션 사용률 0~100. 글자 색을 정한다.
    ///   - weeklyPct: 주간 한도 사용률 0~100. 바깥 링.
    ///   - elapsed: 현재 5시간 창이 지난 비율 0~1. 안쪽 링. nil 이면 그리지 않는다.
    ///   - isDark: 메뉴바 배경이 어두운지
    static func make(
        sessionPct: Double, weeklyPct: Double, elapsed: Double?,
        letter: String, isDark: Bool, size: CGFloat = 20
    ) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { _ in
            let center = NSPoint(x: size / 2, y: size / 2)

            let outerWidth = size * 0.068
            let outerRadius = (size - outerWidth) / 2
            let innerWidth = size * 0.078
            let innerRadius = outerRadius - outerWidth / 2 - size * 0.052 - innerWidth / 2

            circle(center: center, radius: outerRadius, width: outerWidth, color: mono(isDark, 0.16))
            circle(center: center, radius: innerRadius, width: innerWidth, color: mono(isDark, 0.16))

            arc(
                center: center, radius: outerRadius, fraction: min(max(weeklyPct, 0), 100) / 100,
                width: outerWidth, color: mono(isDark, 0.82))
            if let elapsed {
                arc(
                    center: center, radius: innerRadius, fraction: elapsed,
                    width: innerWidth, color: mono(isDark, 0.95))
            }

            drawLetter(
                letter, center: center, radius: innerRadius - innerWidth * 0.9,
                color: warning(sessionPct, isDark: isDark) ?? mono(isDark, 0.95))
            return true
        }
        // 색이 상태를 나타내므로 템플릿 모드(단색 강제)를 쓰지 않는다.
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
        center: NSPoint, radius: CGFloat, fraction: Double, width: CGFloat, color: NSColor
    ) {
        let clamped = min(max(fraction, 0), 1)
        guard clamped > 0 else { return }
        let path = NSBezierPath()
        path.appendArc(
            withCenter: center, radius: radius,
            startAngle: 90, endAngle: 90 - 360 * clamped, clockwise: true)
        path.lineWidth = width
        path.lineCapStyle = .round
        color.set()
        path.stroke()
    }

    /// 시스템 폰트로 그린다. Arial Bold 는 메뉴바에서 이질적이다.
    private static func drawLetter(
        _ letter: String, center: NSPoint, radius: CGFloat, color: NSColor
    ) {
        let font = NSFont.systemFont(ofSize: radius * 1.30, weight: .semibold)
        let text = NSAttributedString(
            string: letter, attributes: [.font: font, .foregroundColor: color])
        let bounds = text.size()
        text.draw(at: NSPoint(x: center.x - bounds.width / 2, y: center.y - bounds.height / 2))
    }
}
