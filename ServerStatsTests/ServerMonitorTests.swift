import XCTest
@testable import ServerStats

final class ServerMonitorTests: XCTestCase {

    func makeResponse(cpuTotal: Double = 20, memPercent: Double = 50, memUsed: Int64 = 5_368_709_120, memTotal: Int64 = 10_737_418_240, loadMin1: Double = 0.5, cpucore: Int = 4) -> GlancesAllResponse {
        GlancesAllResponse(
            cpu: CPUData(total: cpuTotal),
            mem: MemoryData(percent: memPercent, used: memUsed, total: memTotal),
            load: LoadData(min1: loadMin1, min5: 0.4, min15: 0.3, cpucore: cpucore),
            fs: [FilesystemData(mntPoint: "/", percent: 45, used: 193_273_528_320, size: 429_496_729_600, deviceName: "/dev/sda1", fsType: "ext4")],
            network: [NetworkData(interfaceName: "eth0", bytesRecvRatePerSec: 1000, bytesSentRatePerSec: 2000, bytesAll: 100000, isUp: true)],
            uptime: "1 day, 0:00:00"
        )
    }

    func testRamThresholdExceeded() {
        var state = ServerState()
        state.data = makeResponse(memPercent: 92)
        XCTAssertTrue(ServerMonitor.isRamExceeded(state: state, threshold: 90))
        XCTAssertFalse(ServerMonitor.isRamExceeded(state: state, threshold: 95))
    }

    func testLoadThresholdExceeded() {
        var state = ServerState()
        state.data = makeResponse(loadMin1: 3.5, cpucore: 4)
        XCTAssertTrue(ServerMonitor.isLoadExceeded(state: state, threshold: 80))
        XCTAssertFalse(ServerMonitor.isLoadExceeded(state: state, threshold: 90))
    }

    func testHysteresisNotificationReset() {
        var state = ServerState()
        state.ramNotified = true

        state.data = makeResponse(memPercent: 92)
        XCTAssertFalse(ServerMonitor.shouldResetRamNotification(state: state, threshold: 90))

        state.data = makeResponse(memPercent: 87)
        XCTAssertFalse(ServerMonitor.shouldResetRamNotification(state: state, threshold: 90))

        state.data = makeResponse(memPercent: 84)
        XCTAssertTrue(ServerMonitor.shouldResetRamNotification(state: state, threshold: 90))
    }

    func testShouldNotifyOnlyOnFirstBreach() {
        var state = ServerState()
        state.data = makeResponse(memPercent: 92)
        state.ramNotified = false
        XCTAssertTrue(ServerMonitor.shouldNotifyRam(state: state, threshold: 90))

        state.ramNotified = true
        XCTAssertFalse(ServerMonitor.shouldNotifyRam(state: state, threshold: 90))
    }
}
