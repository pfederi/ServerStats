import Foundation

// MARK: - API Response Models

struct GlancesAllResponse: Codable {
    let cpu: CPUData
    let mem: MemoryData
    let load: LoadData
    let fs: [FilesystemData]
    let network: [NetworkData]
    let uptime: String

    var rootFilesystem: FilesystemData? {
        fs.first(where: { $0.mntPoint == "/" })
            ?? fs.max(by: { $0.size < $1.size })
    }

    var primaryNetwork: NetworkData? {
        network
            .filter { $0.interfaceName != "lo" }
            .max(by: { ($0.bytesAll ?? 0) < ($1.bytesAll ?? 0) })
    }
}

struct CPUData: Codable {
    let total: Double
}

struct MemoryData: Codable {
    let percent: Double
    let used: Int64
    let total: Int64

    var usedGB: Double { Double(used) / 1_073_741_824 }
    var totalGB: Double { Double(total) / 1_073_741_824 }
}

struct LoadData: Codable {
    let min1: Double
    let min5: Double
    let min15: Double
    let cpucore: Int

    var normalizedPercent: Double {
        guard cpucore > 0 else { return 0 }
        return (min1 / Double(cpucore)) * 100
    }
}

struct FilesystemData: Codable {
    let mntPoint: String
    let percent: Double
    let used: Int64
    let size: Int64
    let deviceName: String
    let fsType: String

    var usedGB: Double { Double(used) / 1_073_741_824 }
    var sizeGB: Double { Double(size) / 1_073_741_824 }

    enum CodingKeys: String, CodingKey {
        case mntPoint = "mnt_point"
        case percent, used, size
        case deviceName = "device_name"
        case fsType = "fs_type"
    }
}

struct NetworkData: Codable {
    let interfaceName: String
    let bytesRecvRatePerSec: Double?
    let bytesSentRatePerSec: Double?
    let bytesAll: Int64?
    let isUp: Bool?

    enum CodingKeys: String, CodingKey {
        case interfaceName = "interface_name"
        case bytesRecvRatePerSec = "bytes_recv_rate_per_sec"
        case bytesSentRatePerSec = "bytes_sent_rate_per_sec"
        case bytesAll = "bytes_all"
        case isUp = "is_up"
    }

    var formattedRecvRate: String { Self.formatRate(bytesRecvRatePerSec ?? 0) }
    var formattedSentRate: String { Self.formatRate(bytesSentRatePerSec ?? 0) }

    static func formatRate(_ bytesPerSec: Double) -> String {
        if bytesPerSec >= 1_048_576 {
            return String(format: "%.1f MB/s", bytesPerSec / 1_048_576)
        } else if bytesPerSec >= 1024 {
            return String(format: "%.0f KB/s", bytesPerSec / 1024)
        } else {
            return String(format: "%.0f B/s", bytesPerSec)
        }
    }
}

// MARK: - Server Configuration (user-configurable, persisted as JSON in UserDefaults)

struct ServerConfig: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var shortName: String
    var baseURL: String        // e.g. "https://glances.example.com"
    var cpuThreshold: Double
    var ramThreshold: Double
    var loadThreshold: Double

    var apiURL: URL? {
        guard let url = URL(string: baseURL.hasSuffix("/") ? "\(baseURL)api/4/all" : "\(baseURL)/api/4/all"),
              url.scheme == "https" else { return nil }
        return url
    }

    var dashboardURL: URL? {
        URL(string: baseURL)
    }

    static let defaultServers: [ServerConfig] = []
}

// MARK: - Server State (per server, held by ServerMonitor)

struct ServerState {
    var data: GlancesAllResponse?
    var lastUpdated: Date?
    var error: Error?
    var isReachable: Bool { error == nil && data != nil }
    var cpuHistory: [Double] = []

    var cpuNotified: Bool = false
    var ramNotified: Bool = false
    var loadNotified: Bool = false
}

// MARK: - Persistence

enum ServerConfigStore {
    private static let key = "serverConfigs"

    static func load() -> [ServerConfig] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let configs = try? JSONDecoder().decode([ServerConfig].self, from: data) else {
            return ServerConfig.defaultServers
        }
        return configs
    }

    static func save(_ configs: [ServerConfig]) {
        if let data = try? JSONEncoder().encode(configs) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

// MARK: - UserDefaults KVO Extension

extension UserDefaults {
    @objc dynamic var refreshInterval: Double {
        double(forKey: "refreshInterval")
    }
}
