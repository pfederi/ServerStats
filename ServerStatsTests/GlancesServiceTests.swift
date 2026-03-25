import XCTest
@testable import ServerStats

final class MockURLProtocol: URLProtocol {
    static var mockData: Data?
    static var mockError: Error?
    static var mockStatusCode: Int = 200

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        if let error = MockURLProtocol.mockError {
            client?.urlProtocol(self, didFailWithError: error)
        } else {
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: MockURLProtocol.mockStatusCode,
                httpVersion: nil,
                headerFields: nil
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            if let data = MockURLProtocol.mockData {
                client?.urlProtocol(self, didLoad: data)
            }
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class GlancesServiceTests: XCTestCase {

    var service: GlancesService!

    override func setUp() {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        let session = URLSession(configuration: config)
        service = GlancesService(session: session)
    }

    override func tearDown() {
        MockURLProtocol.mockData = nil
        MockURLProtocol.mockError = nil
        MockURLProtocol.mockStatusCode = 200
    }

    let validJSON = """
    {
        "cpu": {"total": 45.1},
        "mem": {"percent": 71.3, "used": 12884901888, "total": 17179869184},
        "load": {"min1": 2.1, "min5": 1.85, "min15": 1.62, "cpucore": 8},
        "fs": [{"mnt_point": "/", "percent": 67.8, "used": 290978201600, "size": 429496729600, "device_name": "/dev/sda1", "fs_type": "ext4"}],
        "network": [{"interface_name": "eth0", "bytes_recv_rate_per_sec": 1153434, "bytes_sent_rate_per_sec": 5662310, "bytes_all": 543210987, "is_up": true}],
        "uptime": "3 days, 8:15:42"
    }
    """.data(using: .utf8)!

    func testFetchSuccess() async throws {
        MockURLProtocol.mockData = validJSON
        let result = try await service.fetchURL(URL(string: "https://test.example.com/api/4/all")!)
        XCTAssertEqual(result.cpu.total, 45.1, accuracy: 0.1)
        XCTAssertEqual(result.uptime, "3 days, 8:15:42")
    }

    func testFetchNetworkError() async {
        MockURLProtocol.mockError = URLError(.notConnectedToInternet)
        do {
            _ = try await service.fetchURL(URL(string: "https://test.example.com/api/4/all")!)
            XCTFail("Should have thrown")
        } catch {
            XCTAssertTrue(error is URLError)
        }
    }

    func testFetchInvalidJSON() async {
        MockURLProtocol.mockData = "not json".data(using: .utf8)!
        do {
            _ = try await service.fetchURL(URL(string: "https://test.example.com/api/4/all")!)
            XCTFail("Should have thrown")
        } catch {
            XCTAssertTrue(error is DecodingError)
        }
    }
}
