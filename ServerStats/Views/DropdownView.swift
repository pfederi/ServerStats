import SwiftUI

struct DropdownView: View {
    @ObservedObject var monitor: ServerMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(monitor.servers.enumerated()), id: \.element.id) { index, server in
                if index > 0 {
                    Divider().opacity(0.15)
                }
                ServerSection(
                    config: server,
                    state: monitor.state(for: server),
                    cpuHistory: monitor.cpuHistory(for: server),
                    cpuThreshold: server.cpuThreshold,
                    ramThreshold: server.ramThreshold,
                    loadThreshold: server.loadThreshold
                )
            }
            Divider().opacity(0.15)
            FooterView(monitor: monitor)
        }
        .frame(width: 360)
        .preferredColorScheme(.dark)
    }
}

// MARK: - Server Section

struct ServerSection: View {
    let config: ServerConfig
    let state: ServerState
    let cpuHistory: [Double]
    let cpuThreshold: Double
    let ramThreshold: Double
    let loadThreshold: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(serverGradient(for: config))
                        .frame(width: 28, height: 28)
                    Image(systemName: "server.rack")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                }
                Text(config.name)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                HStack(spacing: 4) {
                    Circle()
                        .fill(state.isReachable ? Color.green : Color.red)
                        .frame(width: 6, height: 6)
                    Text(state.isReachable ? "Online" : "Offline")
                        .font(.system(size: 11))
                        .foregroundColor(Color.white.opacity(0.5))
                }
            }

            if let data = state.data {
                MetricsGrid(data: data, cpuHistory: cpuHistory, cpuThreshold: cpuThreshold, ramThreshold: ramThreshold, loadThreshold: loadThreshold)
            } else if state.error != nil {
                Text("Unreachable")
                    .foregroundColor(Color.white.opacity(0.5))
                    .font(.system(size: 12))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            }

            // Uptime + dashboard link
            if let data = state.data {
                HStack {
                    Text("Uptime: \(data.uptime)")
                        .font(.system(size: 11))
                        .foregroundColor(Color.white.opacity(0.45))
                    Spacer()
                    if let url = config.dashboardURL {
                        Button(action: { NSWorkspace.shared.open(url) }) {
                            Text("Open Dashboard →")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.link)
                        .foregroundColor(.indigo)
                    }
                }
            }
        }
        .padding(16)
    }

    private func serverGradient(for config: ServerConfig) -> LinearGradient {
        let colors: [Color] = {
            let hash = abs(config.name.hashValue)
            let gradients: [[Color]] = [
                [.blue, .indigo], [.green, .mint], [.orange, .red],
                [.purple, .pink], [.cyan, .blue], [.teal, .green]
            ]
            return gradients[hash % gradients.count]
        }()
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

// MARK: - Metrics Grid

struct MetricsGrid: View {
    let data: GlancesAllResponse
    let cpuHistory: [Double]
    let cpuThreshold: Double
    let ramThreshold: Double
    let loadThreshold: Double

    var body: some View {
        Grid(horizontalSpacing: 10, verticalSpacing: 10) {
            // Row 1: CPU + Memory
            GridRow {
                MetricCard {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("CPU").metricLabel()
                        Text(String(format: "%.1f%%", data.cpu.total))
                            .metricValue(alert: data.cpu.total > cpuThreshold)
                        Text(" ").metricSub()
                        ProgressBar(value: data.cpu.total / 100, isHigh: data.cpu.total > cpuThreshold)
                            .frame(height: 5)
                    }
                }

                MetricCard {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Memory").metricLabel()
                        Text(String(format: "%.1f%%", data.mem.percent))
                            .metricValue(alert: data.mem.percent > ramThreshold)
                        Text(String(format: "%.1f / %.1f GB", data.mem.usedGB, data.mem.totalGB))
                            .metricSub()
                        ProgressBar(value: data.mem.percent / 100, isHigh: data.mem.percent > ramThreshold)
                            .frame(height: 5)
                    }
                }
            }

            // Row 2: Load + Disk
            GridRow {
                MetricCard {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Load").metricLabel()
                        Text(String(format: "%.2f", data.load.min1))
                            .metricValue(alert: data.load.normalizedPercent > loadThreshold)
                        Text(String(format: "%.2f / %.2f / %.2f", data.load.min1, data.load.min5, data.load.min15))
                            .metricSub()
                        Color.clear.frame(height: 5) // match progress bar height
                    }
                }

                if let fs = data.rootFilesystem {
                    MetricCard {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Disk /").metricLabel()
                            Text(String(format: "%.1f%%", fs.percent))
                                .metricValue()
                            Text(String(format: "%.0f / %.0f GB", fs.usedGB, fs.sizeGB))
                                .metricSub()
                            ProgressBar(value: fs.percent / 100, isHigh: fs.percent > 85)
                                .frame(height: 5)
                        }
                    }
                }
            }

            // Row 3: Network (full width)
            if let net = data.primaryNetwork {
                GridRow {
                    MetricCard {
                        HStack {
                            Text("Network").metricLabel()
                            Spacer()
                            HStack(spacing: 16) {
                                HStack(spacing: 3) {
                                    Text("▲").font(.system(size: 10)).foregroundColor(.green)
                                    Text(net.formattedSentRate)
                                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                                }
                                HStack(spacing: 3) {
                                    Text("▼").font(.system(size: 10)).foregroundColor(.blue)
                                    Text(net.formattedRecvRate)
                                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                                }
                            }
                        }
                    }
                    .gridCellColumns(2)
                }
            }
        }
    }
}

// MARK: - Reusable Components

struct MetricCard<Content: View>: View {
    let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        content()
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(Color.white.opacity(0.06))
            .cornerRadius(10)
    }
}

struct ProgressBar: View {
    let value: Double
    let isHigh: Bool

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white.opacity(0.06))
                RoundedRectangle(cornerRadius: 3)
                    .fill(
                        isHigh
                        ? LinearGradient(colors: [.orange, .red], startPoint: .leading, endPoint: .trailing)
                        : LinearGradient(colors: [.blue, .indigo], startPoint: .leading, endPoint: .trailing)
                    )
                    .frame(width: geo.size.width * min(max(value, 0), 1))
            }
        }
    }
}

// MARK: - Footer

struct FooterView: View {
    @ObservedObject var monitor: ServerMonitor
    @Environment(\.openSettings) private var openSettings

    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "en_US")
        f.unitsStyle = .abbreviated
        return f
    }()

    var body: some View {
        HStack {
            if let lastRefresh = monitor.lastRefresh {
                Text("Updated: \(Self.relativeDateFormatter.localizedString(for: lastRefresh, relativeTo: Date()))")
                    .font(.system(size: 10))
                    .foregroundColor(Color.white.opacity(0.45))
            }
            Spacer()
            HStack(spacing: 6) {
                Button(action: { monitor.refresh() }) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderless)
                .help("Aktualisieren")

                Button(action: {
                    NSApp.activate(ignoringOtherApps: true)
                    openSettings()
                }) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderless)
                .help("Einstellungen")

                Button(action: { NSApplication.shared.terminate(nil) }) {
                    Image(systemName: "power")
                        .font(.system(size: 11))
                }
                .buttonStyle(.borderless)
                .help("Beenden")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

// MARK: - Text Style Extensions

extension Text {
    func metricLabel() -> some View {
        self.font(.system(size: 10, weight: .medium))
            .foregroundColor(Color.white.opacity(0.55))
            .textCase(.uppercase)
    }

    func metricValue(alert: Bool = false) -> some View {
        self.font(.system(size: 20, weight: .semibold, design: .rounded))
            .foregroundColor(alert ? .red : .primary)
    }

    func metricSub() -> some View {
        self.font(.system(size: 10))
            .foregroundColor(Color.white.opacity(0.45))
    }
}
