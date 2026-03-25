import Foundation
import SwiftUI
import UserNotifications

@MainActor
final class ServerMonitor: ObservableObject {
    @Published var servers: [ServerConfig] = []
    @Published var states: [UUID: ServerState] = [:]
    @Published var lastRefresh: Date?

    @AppStorage("refreshInterval") var refreshInterval: Double = 30

    private let service: GlancesService
    private var timer: Timer?
    private var refreshIntervalObserver: NSKeyValueObservation?
    private let maxHistory = 20

    init(service: GlancesService = GlancesService()) {
        self.service = service
        self.servers = ServerConfigStore.load()
        for server in servers {
            states[server.id] = ServerState()
        }
    }

    // MARK: - Server Management

    func updateServers(_ newServers: [ServerConfig]) {
        let oldIDs = Set(servers.map(\.id))
        let newIDs = Set(newServers.map(\.id))

        // Remove states for deleted servers
        for id in oldIDs.subtracting(newIDs) {
            states.removeValue(forKey: id)
        }
        // Add states for new servers
        for id in newIDs.subtracting(oldIDs) {
            states[id] = ServerState()
        }

        servers = newServers
        ServerConfigStore.save(newServers)
    }

    func state(for server: ServerConfig) -> ServerState {
        states[server.id] ?? ServerState()
    }

    func cpuHistory(for server: ServerConfig) -> [Double] {
        states[server.id]?.cpuHistory ?? []
    }

    // MARK: - Polling

    func startPolling() {
        requestNotificationPermission()
        refresh()
        scheduleTimer()

        refreshIntervalObserver = UserDefaults.standard.observe(\.refreshInterval, options: [.new]) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.scheduleTimer()
            }
        }
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
        refreshIntervalObserver?.invalidate()
        refreshIntervalObserver = nil
    }

    func scheduleTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
    }

    func refresh() {
        Task {
            await withTaskGroup(of: (UUID, Result<GlancesAllResponse, Error>).self) { group in
                for server in servers {
                    guard let url = server.apiURL else { continue }
                    group.addTask { [service] in
                        do {
                            let data = try await service.fetchURL(url)
                            return (server.id, .success(data))
                        } catch {
                            return (server.id, .failure(error))
                        }
                    }
                }

                for await (id, result) in group {
                    switch result {
                    case .success(let data):
                        states[id, default: ServerState()].data = data
                        states[id]?.lastUpdated = Date()
                        states[id]?.error = nil
                        states[id]?.cpuHistory.append(data.cpu.total)
                        if (states[id]?.cpuHistory.count ?? 0) > maxHistory {
                            states[id]?.cpuHistory.removeFirst()
                        }
                    case .failure(let error):
                        states[id, default: ServerState()].error = error
                    }
                }
            }

            lastRefresh = Date()
            checkAllThresholds()
        }
    }

    // MARK: - Thresholds

    private func checkAllThresholds() {
        for server in servers {
            guard var s = states[server.id] else { continue }

            // CPU
            checkAndNotify(
                state: &s,
                isExceeded: Self.isCpuExceeded(state: s, threshold: server.cpuThreshold),
                shouldReset: Self.shouldResetCpuNotification(state: s, threshold: server.cpuThreshold),
                shouldNotify: Self.shouldNotifyCpu(state: s, threshold: server.cpuThreshold),
                notifiedKeyPath: \.cpuNotified,
                serverName: server.name, metricName: "CPU",
                currentValue: s.data?.cpu.total, threshold: server.cpuThreshold
            )

            // RAM
            checkAndNotify(
                state: &s,
                isExceeded: Self.isRamExceeded(state: s, threshold: server.ramThreshold),
                shouldReset: Self.shouldResetRamNotification(state: s, threshold: server.ramThreshold),
                shouldNotify: Self.shouldNotifyRam(state: s, threshold: server.ramThreshold),
                notifiedKeyPath: \.ramNotified,
                serverName: server.name, metricName: "Memory",
                currentValue: s.data?.mem.percent, threshold: server.ramThreshold
            )

            // Load
            checkAndNotify(
                state: &s,
                isExceeded: Self.isLoadExceeded(state: s, threshold: server.loadThreshold),
                shouldReset: Self.shouldResetLoadNotification(state: s, threshold: server.loadThreshold),
                shouldNotify: Self.shouldNotifyLoad(state: s, threshold: server.loadThreshold),
                notifiedKeyPath: \.loadNotified,
                serverName: server.name, metricName: "Load",
                currentValue: s.data?.load.normalizedPercent, threshold: server.loadThreshold
            )

            states[server.id] = s
        }
    }

    private func checkAndNotify(
        state: inout ServerState, isExceeded: Bool, shouldReset: Bool, shouldNotify: Bool,
        notifiedKeyPath: WritableKeyPath<ServerState, Bool>, serverName: String,
        metricName: String, currentValue: Double?, threshold: Double
    ) {
        if shouldReset { state[keyPath: notifiedKeyPath] = false }
        if shouldNotify {
            state[keyPath: notifiedKeyPath] = true
            sendNotification(serverName: serverName, metricName: metricName, currentValue: currentValue ?? 0, threshold: threshold)
        }
    }

    // MARK: - Threshold Logic (static for testability)

    nonisolated static func isCpuExceeded(state: ServerState, threshold: Double) -> Bool {
        guard let data = state.data else { return false }
        return data.cpu.total > threshold
    }

    nonisolated static func shouldResetCpuNotification(state: ServerState, threshold: Double) -> Bool {
        guard state.cpuNotified, let data = state.data else { return false }
        return data.cpu.total < (threshold - 5)
    }

    nonisolated static func shouldNotifyCpu(state: ServerState, threshold: Double) -> Bool {
        guard !state.cpuNotified else { return false }
        return isCpuExceeded(state: state, threshold: threshold)
    }

    nonisolated static func isRamExceeded(state: ServerState, threshold: Double) -> Bool {
        guard let data = state.data else { return false }
        return data.mem.percent > threshold
    }

    nonisolated static func isLoadExceeded(state: ServerState, threshold: Double) -> Bool {
        guard let data = state.data else { return false }
        return data.load.normalizedPercent > threshold
    }

    nonisolated static func shouldResetRamNotification(state: ServerState, threshold: Double) -> Bool {
        guard state.ramNotified, let data = state.data else { return false }
        return data.mem.percent < (threshold - 5)
    }

    nonisolated static func shouldResetLoadNotification(state: ServerState, threshold: Double) -> Bool {
        guard state.loadNotified, let data = state.data else { return false }
        return data.load.normalizedPercent < (threshold - 5)
    }

    nonisolated static func shouldNotifyRam(state: ServerState, threshold: Double) -> Bool {
        guard !state.ramNotified else { return false }
        return isRamExceeded(state: state, threshold: threshold)
    }

    nonisolated static func shouldNotifyLoad(state: ServerState, threshold: Double) -> Bool {
        guard !state.loadNotified else { return false }
        return isLoadExceeded(state: state, threshold: threshold)
    }

    // MARK: - Notifications

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func sendNotification(serverName: String, metricName: String, currentValue: Double, threshold: Double) {
        let content = UNMutableNotificationContent()
        content.title = "ServerStats"
        content.body = "\(serverName): \(metricName) bei \(String(format: "%.0f", currentValue))% (Schwellenwert: \(String(format: "%.0f", threshold))%)"
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "\(serverName)-\(metricName)-\(Date().timeIntervalSince1970)",
            content: content, trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
