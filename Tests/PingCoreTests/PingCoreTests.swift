import XCTest
@testable import PingCore

final class StateTrackerTests: XCTestCase {
    func testFirstSuccessReportsUp() {
        var t = StateTracker()
        XCTAssertEqual(t.record(success: true, downAfter: 2), .becameUp)
        XCTAssertNil(t.record(success: true, downAfter: 2))
    }

    func testDownOnlyAfterThreshold() {
        var t = StateTracker()
        _ = t.record(success: true, downAfter: 2)
        XCTAssertNil(t.record(success: false, downAfter: 2))
        XCTAssertEqual(t.state, .up)
        XCTAssertEqual(t.record(success: false, downAfter: 2), .becameDown)
        XCTAssertNil(t.record(success: false, downAfter: 2))
    }

    func testSingleFailureBetweenSuccessesIsIgnored() {
        var t = StateTracker()
        _ = t.record(success: true, downAfter: 2)
        _ = t.record(success: false, downAfter: 2)
        XCTAssertNil(t.record(success: true, downAfter: 2))
        XCTAssertNil(t.record(success: false, downAfter: 2))
    }

    func testRecoveryReportsUpAgain() {
        var t = StateTracker()
        _ = t.record(success: false, downAfter: 1)
        XCTAssertEqual(t.state, .down)
        XCTAssertEqual(t.record(success: true, downAfter: 1), .becameUp)
    }

    func testInitiallyDownReportsDown() {
        var t = StateTracker()
        XCTAssertNil(t.record(success: false, downAfter: 2))
        XCTAssertEqual(t.state, .unknown)
        XCTAssertEqual(t.record(success: false, downAfter: 2), .becameDown)
    }
}

final class PingerTests: XCTestCase {
    func testHostValidation() {
        XCTAssertTrue(HostName.isValid("example.com"))
        XCTAssertTrue(HostName.isValid("192.168.1.1"))
        XCTAssertTrue(HostName.isValid("fe80::1%en0"))
        XCTAssertFalse(HostName.isValid("-c 100"))
        XCTAssertFalse(HostName.isValid("a b"))
        XCTAssertFalse(HostName.isValid(""))
        XCTAssertFalse(HostName.isValid("a;b"))
    }

    func testParseLatency() {
        XCTAssertEqual(Pinger.parseLatency("64 bytes from 1.1.1.1: icmp_seq=0 ttl=59 time=32.904 ms"), 32.904)
        XCTAssertNil(Pinger.parseLatency("no reply"))
    }
}

final class LatencyStatsTests: XCTestCase {
    func testMixedResults() {
        let s = LatencyStats([10, nil, 30, 20, nil])
        XCTAssertEqual(s.count, 5)
        XCTAssertEqual(s.lost, 2)
        XCTAssertEqual(s.lossPercent, 40)
        XCTAssertEqual(s.avg, 20)
        XCTAssertEqual(s.min, 10)
        XCTAssertEqual(s.max, 30)
        XCTAssertNil(s.last)
    }

    func testLastIsMostRecentAnswer() {
        XCTAssertEqual(LatencyStats([5, 7]).last, 7)
    }

    func testEmptyAndAllLost() {
        XCTAssertEqual(LatencyStats([]).lossPercent, 0)
        XCTAssertNil(LatencyStats([]).avg)
        let lost = LatencyStats([nil, nil])
        XCTAssertEqual(lost.lossPercent, 100)
        XCTAssertNil(lost.avg)
        XCTAssertNil(lost.max)
    }
}

final class TracerouteTests: XCTestCase {
    func testParsesHopsAndTimeouts() {
        let output = """
        traceroute to 1.1.1.1 (1.1.1.1), 20 hops max, 40 byte packets
         1  192.168.2.1  6.710 ms
         2  100.124.1.52  12.002 ms
         3  *
         4  *
         7  1.1.1.1  16.498 ms
        """
        let hops = Traceroute.parse(output)
        XCTAssertEqual(hops.count, 5)
        XCTAssertEqual(hops[0], HopReading(hop: 1, address: "192.168.2.1", latencyMs: 6.71))
        XCTAssertEqual(hops[2], HopReading(hop: 3, address: nil, latencyMs: nil))
        XCTAssertEqual(hops[4].address, "1.1.1.1")
    }

    func testIgnoresRepeatedHopAndGarbage() {
        let hops = Traceroute.parse("1  10.0.0.1  1.0 ms\n  10.0.0.2  2.0 ms\n1  10.0.0.3  3.0 ms\nnonsense")
        XCTAssertEqual(hops.map(\.address), ["10.0.0.1"])
    }

    func testEmptyOutput() {
        XCTAssertTrue(Traceroute.parse("").isEmpty)
    }
}

final class HostExtractionTests: XCTestCase {
    func testUrlsAndPlainHosts() {
        XCTAssertEqual(HostName.extract(from: "https://www.example.com/path?x=1#top"), "www.example.com")
        XCTAssertEqual(HostName.extract(from: "http://example.com:8080"), "example.com")
        XCTAssertEqual(HostName.extract(from: "  www.example.com  "), "www.example.com")
        XCTAssertEqual(HostName.extract(from: "//cdn.example.com/x"), "cdn.example.com")
        XCTAssertEqual(HostName.extract(from: "https://user:pw@example.com/"), "example.com")
        XCTAssertEqual(HostName.extract(from: "example.com."), "example.com")
        XCTAssertEqual(HostName.extract(from: "example.com:443"), "example.com")
    }

    func testAddresses() {
        XCTAssertEqual(HostName.extract(from: "192.168.1.1"), "192.168.1.1")
        XCTAssertEqual(HostName.extract(from: "http://10.0.0.1:81/a"), "10.0.0.1")
        XCTAssertEqual(HostName.extract(from: "http://[2001:db8::1]:8080/x"), "2001:db8::1")
        XCTAssertEqual(HostName.extract(from: "fe80::1%en0"), "fe80::1%en0")
    }

    func testRejectsNonsense() {
        XCTAssertNil(HostName.extract(from: ""))
        XCTAssertNil(HostName.extract(from: "http://"))
        XCTAssertNil(HostName.extract(from: "-c 100"))
        XCTAssertNil(HostName.extract(from: "a b"))
    }
}

final class HopDeltaTests: XCTestCase {
    func testDeltasSkipHopsWithoutData() {
        let deltas = HopDelta.compute(averages: [5, nil, 25, 20, nil, 120])
        XCTAssertEqual(deltas, [5, nil, 20, -5, nil, 100])
    }

    func testEmpty() {
        XCTAssertTrue(HopDelta.compute(averages: []).isEmpty)
    }
}

final class WebTargetTests: XCTestCase {
    func testNormalize() {
        XCTAssertEqual(WebTarget.normalize("example.com"), "https://example.com")
        XCTAssertEqual(WebTarget.normalize("http://example.com/a?b=1"), "http://example.com/a?b=1")
        XCTAssertEqual(WebTarget.normalize("HTTPS://Example.com"), "https://Example.com")
        XCTAssertEqual(WebTarget.normalize("example.com:8080/p"), "https://example.com:8080/p")
        XCTAssertEqual(WebTarget.normalize("//cdn.example.com"), "https://cdn.example.com")
        XCTAssertEqual(WebTarget.normalize("  www.example.com "), "https://www.example.com")
    }

    func testNormalizeRejects() {
        XCTAssertNil(WebTarget.normalize(""))
        XCTAssertNil(WebTarget.normalize("ftp://example.com"))
        XCTAssertNil(WebTarget.normalize("a b"))
        XCTAssertNil(WebTarget.normalize("http://"))
    }

    func testHostOfUrl() {
        XCTAssertEqual(WebTarget.host(of: "https://www.example.com:8443/a"), "www.example.com")
    }

    func testResultSummaryAndOK() {
        XCTAssertTrue(WebResult(statusCode: 200, latencyMs: 12, error: nil).isOK)
        XCTAssertTrue(WebResult(statusCode: 204, latencyMs: 12, error: nil).isOK)
        XCTAssertFalse(WebResult(statusCode: 404, latencyMs: 12, error: nil).isOK)
        XCTAssertFalse(WebResult(statusCode: nil, latencyMs: nil, error: "Zeitüberschreitung").isOK)
        XCTAssertEqual(WebResult(statusCode: 200, latencyMs: 1, error: nil).summary, "HTTP 200 OK")
        XCTAssertEqual(WebResult(statusCode: 418, latencyMs: 1, error: nil).summary, "HTTP 418")
        XCTAssertEqual(WebResult(statusCode: nil, latencyMs: nil, error: "Zeitüberschreitung").summary, "Zeitüberschreitung")
    }
}

/// Talks to a throwaway local web server (python3), so no internet is needed.
final class WebCheckerTests: XCTestCase {
    func testStatusCodesAndTiming() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pingwatch-web-test")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "hello".write(to: dir.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)

        let server = Process()
        server.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        server.arguments = ["-m", "http.server", "18765", "--bind", "127.0.0.1", "--directory", dir.path]
        server.standardOutput = FileHandle.nullDevice
        server.standardError = FileHandle.nullDevice
        do { try server.run() } catch { throw XCTSkip("python3 not available") }
        defer { server.terminate() }
        try await Task.sleep(nanoseconds: 1_000_000_000)

        let ok = await WebChecker.check("http://127.0.0.1:18765/")
        XCTAssertEqual(ok.statusCode, 200)
        XCTAssertTrue(ok.isOK)
        XCTAssertNotNil(ok.latencyMs)

        let missing = await WebChecker.check("http://127.0.0.1:18765/gibt-es-nicht")
        XCTAssertEqual(missing.statusCode, 404)
        XCTAssertFalse(missing.isOK)

        let refused = await WebChecker.check("http://127.0.0.1:1/")
        XCTAssertNil(refused.statusCode)
        XCTAssertFalse(refused.isOK)
        XCTAssertNotNil(refused.error)
    }
}

final class HostEntryTests: XCTestCase {
    func testHostsSavedByEarlierVersionsStayPings() throws {
        let old = #"[{"id":"4990BA6B-0000-4000-8000-000000000001","name":"1.1.1.1","enabled":false}]"#
        let hosts = try JSONDecoder().decode([HostEntry].self, from: Data(old.utf8))
        XCTAssertEqual(hosts.count, 1)
        XCTAssertEqual(hosts[0].name, "1.1.1.1")
        XCTAssertFalse(hosts[0].enabled)
        XCTAssertEqual(hosts[0].kind, .ping)
    }

    func testRoundTripKeepsKind() throws {
        let web = HostEntry(name: "https://www.example.com/a", kind: .web)
        let decoded = try JSONDecoder().decode([HostEntry].self, from: JSONEncoder().encode([web]))
        XCTAssertEqual(decoded, [web])
        XCTAssertEqual(decoded[0].hostName, "www.example.com")
        XCTAssertEqual(HostEntry(name: "1.1.1.1").hostName, "1.1.1.1")
    }
}

final class TracerouteMergeTests: XCTestCase {
    func testRangesBehindTheDestinationAreCutOff() {
        let first = """
        traceroute to 1.1.1.1 (1.1.1.1), 3 hops max, 40 byte packets
         1  192.168.2.1  6.0 ms
         2  100.124.1.52  12.0 ms
         3  *
        """
        let second = """
        traceroute to 1.1.1.1 (1.1.1.1), 6 hops max, 40 byte packets
         4  80.81.194.180  11.0 ms
         5  1.1.1.1  16.0 ms
        """
        let third = """
        traceroute to 1.1.1.1 (1.1.1.1), 9 hops max, 40 byte packets
         7  1.1.1.1  16.5 ms
        """
        let route = Traceroute.merge([third, first, second])
        XCTAssertEqual(route.map(\.hop), [1, 2, 3, 4, 5])
        XCTAssertEqual(route.last?.address, "1.1.1.1")
        XCTAssertNil(route[2].address)
    }

    func testWithoutReachingTheTargetEverythingStays() {
        let a = "traceroute to 10.255.255.1 (10.255.255.1), 3 hops max\n 1  192.168.2.1  1.0 ms\n 2  *\n 3  *"
        let b = "traceroute to 10.255.255.1 (10.255.255.1), 6 hops max\n 4  *\n 5  *\n 6  *"
        XCTAssertEqual(Traceroute.merge([a, b]).map(\.hop), [1, 2, 3, 4, 5, 6])
    }

    func testDestinationHeader() {
        XCTAssertEqual(Traceroute.destination(in: "traceroute to www.apple.com (23.1.2.3), 20 hops max"), "23.1.2.3")
        XCTAssertNil(Traceroute.destination(in: " 1  10.0.0.1  1.0 ms"))
    }
}

final class DownsampleTests: XCTestCase {
    func testShortHistoryIsNotReduced() {
        XCTAssertEqual(Downsample.ranges(count: 3, limit: 10).count, 3)
        XCTAssertTrue(Downsample.ranges(count: 0, limit: 10).isEmpty)
    }

    func testLongHistoryIsBoundedAndCoversEverything() {
        let ranges = Downsample.ranges(count: 3600, limit: 400)
        XCTAssertLessThanOrEqual(ranges.count, 400)
        XCTAssertEqual(ranges.first?.lowerBound, 0)
        XCTAssertEqual(ranges.last?.upperBound, 3600)
        XCTAssertEqual(ranges.map(\.count).reduce(0, +), 3600)
    }
}

final class HostIntervalTests: XCTestCase {
    func testIntervalSurvivesSavingAndOldDataHasNone() throws {
        let custom = HostEntry(name: "1.1.1.1", interval: 2)
        let decoded = try JSONDecoder().decode([HostEntry].self, from: JSONEncoder().encode([custom]))
        XCTAssertEqual(decoded[0].interval, 2)

        let old = #"[{"id":"4990BA6B-0000-4000-8000-000000000001","name":"1.1.1.1"}]"#
        XCTAssertNil(try JSONDecoder().decode([HostEntry].self, from: Data(old.utf8))[0].interval)
    }

    func testStatusSummary() {
        XCTAssertEqual(HTTPStatus.summary(200), "HTTP 200 OK")
        XCTAssertEqual(HTTPStatus.summary(503), "HTTP 503 Nicht verfügbar")
        XCTAssertEqual(HTTPStatus.summary(418), "HTTP 418")
    }
}

final class InputHistoryTests: XCTestCase {
    func testNewestFirstWithoutDuplicates() {
        var history = InputHistory()
        history.record("a.com", kind: .ping)
        history.record("https://b.com", kind: .web)
        history.record("A.com", kind: .ping)
        XCTAssertEqual(history.items.map(\.text), ["A.com", "https://b.com"])
    }

    func testSameTextInBothKindsIsKeptSeparately() {
        var history = InputHistory()
        history.record("example.com", kind: .ping)
        history.record("example.com", kind: .web)
        XCTAssertEqual(history.items.count, 2)
    }

    func testKeepsOnlyTheLast50() {
        var history = InputHistory()
        for i in 0..<60 { history.record("host\(i).example", kind: .ping) }
        XCTAssertEqual(history.items.count, 50)
        XCTAssertEqual(history.items.first?.text, "host59.example")
        XCTAssertEqual(history.items.last?.text, "host10.example")
    }

    func testSuggestionsFilterByKindAndText() {
        var history = InputHistory()
        history.record("1.1.1.1", kind: .ping)
        history.record("www.apple.com", kind: .ping)
        history.record("https://www.apple.com", kind: .web)
        XCTAssertEqual(history.suggestions(for: "app", kind: .ping), ["www.apple.com"])
        XCTAssertEqual(history.suggestions(for: "APP", kind: .web), ["https://www.apple.com"])
        XCTAssertEqual(history.suggestions(for: "", kind: .ping), ["www.apple.com", "1.1.1.1"])
        XCTAssertEqual(history.suggestions(for: "www.apple.com", kind: .ping), [])
    }

    func testSurvivesSaving() throws {
        var history = InputHistory()
        history.record("1.1.1.1", kind: .ping)
        let decoded = try JSONDecoder().decode(InputHistory.self, from: JSONEncoder().encode(history))
        XCTAssertEqual(decoded, history)
    }
}
