import SwiftUI
import AppKit

// MARK: - SwiftUI Sparkline for Dropdown reuse

struct MiniSparkline: View {
    let values: [Double]
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let barCount = max(values.count, 1)
            let barWidth = max(geo.size.width / CGFloat(barCount) - 2, 2)

            HStack(alignment: .bottom, spacing: 2) {
                ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                    RoundedRectangle(cornerRadius: 1)
                        .fill(color.opacity(0.6))
                        .frame(width: barWidth, height: max(2, geo.size.height * CGFloat(value / 100.0)))
                }
            }
        }
    }
}

// MARK: - Status Bar Renderer (Color, adapts to menu bar appearance)

enum StatusBarRenderer {

    @MainActor
    static func render(monitor: ServerMonitor) -> NSImage {
        let height: CGFloat = 18
        let padding: CGFloat = 4
        let dividerPadding: CGFloat = 5
        // Read system appearance directly (ignoring our app-level darkAqua override)
        let systemAppearanceName = UserDefaults.standard.string(forKey: "AppleInterfaceStyle")
        let isDark = systemAppearanceName == "Dark"

        let parts = monitor.servers.map { server in
            serverParts(server: server, state: monitor.state(for: server))
        }

        var totalWidth = padding * 2
        for (i, p) in parts.enumerated() {
            totalWidth += measureServer(p)
            if i < parts.count - 1 {
                totalWidth += dividerPadding + 1 + dividerPadding
            }
        }

        let image = NSImage(size: NSSize(width: max(totalWidth, 30), height: height))
        image.lockFocus()

        let textColor = isDark ? NSColor.white : NSColor.black

        var x = padding
        for (i, p) in parts.enumerated() {
            x = drawServer(p, at: x, height: height, textColor: textColor, isDark: isDark)
            if i < parts.count - 1 {
                x += dividerPadding
                textColor.withAlphaComponent(0.2).setFill()
                NSRect(x: x, y: 3, width: 1, height: height - 6).fill()
                x += 1 + dividerPadding
            }
        }

        image.unlockFocus()
        image.isTemplate = false // color mode
        return image
    }

    // MARK: - Color helper: green → yellow → red based on 0-100%

    private static func barColor(percent: Double) -> NSColor {
        let p = min(max(percent / 100.0, 0), 1)
        if p < 0.5 {
            // green to yellow
            let t = p / 0.5
            return NSColor(
                red: CGFloat(t),
                green: CGFloat(0.8 + 0.2 * (1 - t)),
                blue: 0.1,
                alpha: 1.0
            )
        } else {
            // yellow to red
            let t = (p - 0.5) / 0.5
            return NSColor(
                red: CGFloat(1.0),
                green: CGFloat(1.0 * (1 - t)),
                blue: 0.1,
                alpha: 1.0
            )
        }
    }

    // MARK: - Data

    private struct ServerRenderParts {
        let shortName: String
        let isReachable: Bool
        let cpuPercent: Double?
        let alerts: [(String, Int)]
    }

    private static func serverParts(server: ServerConfig, state: ServerState) -> ServerRenderParts {
        guard let data = state.data, state.isReachable else {
            return ServerRenderParts(shortName: server.shortName, isReachable: false, cpuPercent: nil, alerts: [])
        }
        var alerts: [(String, Int)] = []
        if data.cpu.total > server.cpuThreshold {
            alerts.append(("C", Int(data.cpu.total)))
        }
        if data.mem.percent > server.ramThreshold {
            alerts.append(("M", Int(data.mem.percent)))
        }
        if data.load.normalizedPercent > server.loadThreshold {
            alerts.append(("L", Int(data.load.normalizedPercent)))
        }
        return ServerRenderParts(shortName: server.shortName, isReachable: true, cpuPercent: data.cpu.total, alerts: alerts)
    }

    // MARK: - Measuring

    private static func measureServer(_ parts: ServerRenderParts) -> CGFloat {
        let nameW = textSize(parts.shortName, size: 10, weight: .semibold).width
        if !parts.isReachable {
            return nameW + 3 + textSize("⚠", size: 10, weight: .medium).width
        }
        let barW: CGFloat = 5
        let cpuText = "\(Int(parts.cpuPercent ?? 0))%"
        var w = nameW + 4 + barW + 4 + textSize(cpuText, size: 12, weight: .semibold, monospaced: true).width
        for (letter, value) in parts.alerts {
            w += 4 + textSize("\(letter)\(value)", size: 9, weight: .heavy).width
        }
        return w
    }

    // MARK: - Drawing

    @discardableResult
    private static func drawServer(_ parts: ServerRenderParts, at startX: CGFloat, height: CGFloat, textColor: NSColor, isDark: Bool) -> CGFloat {
        var x = startX
        let barHeight: CGFloat = 14
        let barWidth: CGFloat = 5
        let barY = (height - barHeight) / 2

        // Server name
        let nameStr = attrString(parts.shortName, size: 10, weight: .semibold, color: textColor.withAlphaComponent(0.65))
        let nameSize = nameStr.size()
        nameStr.draw(at: NSPoint(x: x, y: (height - nameSize.height) / 2))
        x += nameSize.width + 4

        if !parts.isReachable {
            let warnStr = attrString("⚠", size: 10, weight: .medium, color: NSColor.systemYellow)
            warnStr.draw(at: NSPoint(x: x, y: (height - warnStr.size().height) / 2))
            x += warnStr.size().width
            return x
        }

        // Vertical fill bar — colored green→yellow→red
        let percent = min(max((parts.cpuPercent ?? 0) / 100.0, 0), 1)
        let barRect = NSRect(x: x, y: barY, width: barWidth, height: barHeight)

        // Track
        textColor.withAlphaComponent(0.12).setFill()
        NSBezierPath(roundedRect: barRect, xRadius: 2, yRadius: 2).fill()

        // Fill
        let fillH = barHeight * CGFloat(percent)
        let fillRect = NSRect(x: x, y: barY, width: barWidth, height: fillH)
        barColor(percent: parts.cpuPercent ?? 0).setFill()
        NSBezierPath(roundedRect: fillRect, xRadius: 2, yRadius: 2).fill()

        x += barWidth + 4

        // CPU text
        let cpuText = "\(Int(parts.cpuPercent ?? 0))%"
        let cpuStr = attrString(cpuText, size: 12, weight: .semibold, color: textColor.withAlphaComponent(0.9), monospaced: true)
        let cpuSize = cpuStr.size()
        cpuStr.draw(at: NSPoint(x: x, y: (height - cpuSize.height) / 2))
        x += cpuSize.width

        // Alert badges in red
        for (letter, value) in parts.alerts {
            x += 4
            let alertColor = NSColor(red: 1, green: 0.25, blue: 0.25, alpha: 1)
            let alertStr = attrString("\(letter)\(value)", size: 9, weight: .heavy, color: alertColor)
            let alertSize = alertStr.size()
            alertStr.draw(at: NSPoint(x: x, y: (height - alertSize.height) / 2))
            x += alertSize.width
        }

        return x
    }

    // MARK: - Text helpers

    private static func attrString(_ text: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, monospaced: Bool = false) -> NSAttributedString {
        let font = monospaced
            ? NSFont.monospacedSystemFont(ofSize: size, weight: weight)
            : NSFont.systemFont(ofSize: size, weight: weight)
        return NSAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: color
        ])
    }

    private static func textSize(_ text: String, size: CGFloat, weight: NSFont.Weight, monospaced: Bool = false) -> NSSize {
        attrString(text, size: size, weight: weight, color: .white, monospaced: monospaced).size()
    }
}
