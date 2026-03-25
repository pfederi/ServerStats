import XCTest
@testable import ServerStats

final class ServerDataTests: XCTestCase {

    let sampleJSON = """
    {
        "cpu": {"total": 23.4, "system": 5.1, "user": 18.3},
        "mem": {"percent": 64.2, "used": 6871842816, "total": 10737418240},
        "load": {"min1": 1.24, "min5": 0.98, "min15": 0.76, "cpucore": 4},
        "fs": [
            {"mnt_point": "/", "percent": 45.1, "used": 193273528320, "size": 429496729600, "device_name": "/dev/sda1", "fs_type": "ext4"},
            {"mnt_point": "/boot", "percent": 20.0, "used": 104857600, "size": 524288000, "device_name": "/dev/sda2", "fs_type": "ext4"}
        ],
        "network": [
            {"interface_name": "lo", "bytes_recv_rate_per_sec": 0, "bytes_sent_rate_per_sec": 0, "bytes_all": 0, "is_up": true},
            {"interface_name": "eth0", "bytes_recv_rate_per_sec": 356000, "bytes_sent_rate_per_sec": 1258000, "bytes_all": 98765432, "is_up": true}
        ],
        "uptime": "14 days, 3:22:10"
    }
    """.data(using: .utf8)!

    func testParseGlancesResponse() throws {
        let response = try JSONDecoder().decode(GlancesAllResponse.self, from: sampleJSON)
        XCTAssertEqual(response.cpu.total, 23.4, accuracy: 0.1)
        XCTAssertEqual(response.mem.percent, 64.2, accuracy: 0.1)
        XCTAssertEqual(response.mem.used, 6871842816)
        XCTAssertEqual(response.mem.total, 10737418240)
        XCTAssertEqual(response.load.min1, 1.24, accuracy: 0.01)
        XCTAssertEqual(response.load.min5, 0.98, accuracy: 0.01)
        XCTAssertEqual(response.load.min15, 0.76, accuracy: 0.01)
        XCTAssertEqual(response.load.cpucore, 4)
        XCTAssertEqual(response.uptime, "14 days, 3:22:10")
    }

    func testFilterRootFilesystem() throws {
        let response = try JSONDecoder().decode(GlancesAllResponse.self, from: sampleJSON)
        let root = try XCTUnwrap(response.rootFilesystem)
        XCTAssertEqual(root.mntPoint, "/")
        XCTAssertEqual(root.percent, 45.1, accuracy: 0.1)
    }

    func testFilterPrimaryNetwork() throws {
        let response = try JSONDecoder().decode(GlancesAllResponse.self, from: sampleJSON)
        let primary = response.primaryNetwork
        XCTAssertNotNil(primary)
        XCTAssertEqual(primary?.interfaceName, "eth0")
    }

    func testLoadNormalization() throws {
        let response = try JSONDecoder().decode(GlancesAllResponse.self, from: sampleJSON)
        XCTAssertEqual(response.load.normalizedPercent, 31.0, accuracy: 0.1)
    }

    func testServerConfigDefaults() {
        XCTAssertTrue(ServerConfig.defaultServers.isEmpty)
    }

    func testServerConfigAPIURL() {
        let config = ServerConfig(id: UUID(), name: "Test", shortName: "T", baseURL: "https://example.com", cpuThreshold: 80, ramThreshold: 80, loadThreshold: 80)
        XCTAssertEqual(config.apiURL?.absoluteString, "https://example.com/api/4/all")
    }

    func testServerConfigRejectsHTTP() {
        let config = ServerConfig(id: UUID(), name: "Test", shortName: "T", baseURL: "http://example.com", cpuThreshold: 80, ramThreshold: 80, loadThreshold: 80)
        XCTAssertNil(config.apiURL, "HTTP URLs should be rejected")
    }
}
