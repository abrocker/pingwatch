import Foundation
import PingCore

struct HostStatus {
    var state: HostState = .unknown
    var latencyMs: Double?
    var lastCheck: Date?
    /// HTTP status code of the last web check.
    var statusCode: Int?
    /// What the last web check came back with, e.g. "HTTP 200 OK" or "Zeitüberschreitung".
    var detail: String?
}

/// One ping result for the graph. `latencyMs` is nil when the host did not answer.
struct PingSample: Identifiable {
    let id = UUID()
    let date: Date
    let latencyMs: Double?
}

/// The pings to one router on the way to a host.
struct HopTrace {
    var address: String?
    var samples: [PingSample] = []
}

/// A hop of the route as shown in the table, limited to the selected time window.
struct HopInfo: Identifiable {
    let hop: Int
    let address: String?
    let samples: [PingSample]
    let stats: LatencyStats
    /// Latency this hop adds on top of the previous answering hop, from the averages.
    var delta: Double?

    var id: Int { hop }
}

@MainActor
final class Monitor: ObservableObject {
    @Published var hosts: [HostEntry] { didSet { save(); reconcile() } }
    @Published var running: Bool { didSet { save(); reconcile() } }
    /// Default seconds between checks for pings and for web checks; a host can have its own interval.
    @Published var pingInterval: Int { didSet { save() } }
    @Published var webInterval: Int { didSet { save() } }
    /// Mutes the alarm sounds (PING and DOWN). Banners are not affected.
    @Published var muted: Bool { didSet { if muted { sounds.stop() }; save() } }
    @Published var banners: Bool { didSet { save(); if banners { requestNotifications() } } }
    @Published private(set) var bannersDenied = false
    /// The last 50 hosts and web addresses that were added, offered again as suggestions.
    @Published private(set) var inputHistory = InputHistory() { didSet { save() } }
    @Published var pingCount: Int { didSet { save() } }
    @Published var downCount: Int { didSet { save() } }
    @Published var downAfter: Int { didSet { save() } }
    @Published var pingSound: String { didSet { save() } }
    @Published var downSound: String { didSet { save() } }
    @Published var selection: UUID? { didSet { save(); reconcileTrace() } }
    /// Length of the graph's time window in seconds; 0 shows everything kept.
    @Published var windowSeconds: Int { didSet { statsCache.removeAll(); save() } }

    // Measurements arrive for every ping of every host. They are not @Published one by one; instead
    // `markChanged()` refreshes the views at most four times a second, however many results come in.
    private(set) var status: [UUID: HostStatus] = [:] { didSet { markChanged() } }
    private(set) var history: [UUID: [PingSample]] = [:] { didSet { markChanged() } }
    private(set) var traces: [UUID: [Int: HopTrace]] = [:] { didSet { markChanged() } }
    private(set) var hostNames: [String: String] = [:] { didSet { markChanged() } }
    /// The IP address each hostname currently resolves to.
    private(set) var resolved: [String: String] = [:] { didSet { markChanged() } }

    static let historyLimit = 3600

    /// Names of the system sounds in /System/Library/Sounds, e.g. "Ping", "Basso".
    static let availableSounds: [String] = {
        let files = (try? FileManager.default.contentsOfDirectory(atPath: "/System/Library/Sounds")) ?? []
        let names = files.filter { $0.hasSuffix(".aiff") }.map { String($0.dropLast(5)) }.sorted()
        return names.isEmpty ? ["Ping", "Basso"] : names
    }()

    private let sounds = SoundPlayer()
    private let notifier = Notifier()
    /// The last HTTP status per web host; 0 stands for "no response".
    private var lastStatusCode: [UUID: Int] = [:]
    private var tasks: [UUID: Task<Void, Never>] = [:]
    private var traceTask: Task<Void, Never>?
    private var traceTarget: UUID?
    private var refreshScheduled = false
    private var statsCache: [UUID: LatencyStats] = [:]
    private var pendingNames = Set<String>()
    private var pendingResolves = Set<String>()
    private let defaults = UserDefaults.standard

    init() {
        let d = UserDefaults.standard
        hosts = (d.data(forKey: "hosts")).flatMap { try? JSONDecoder().decode([HostEntry].self, from: $0) } ?? []
        running = d.object(forKey: "running") as? Bool ?? true
        // "interval" is how earlier versions stored the single, shared interval.
        pingInterval = d.object(forKey: "pingInterval") as? Int ?? d.object(forKey: "interval") as? Int ?? 5
        webInterval = d.object(forKey: "webInterval") as? Int ?? 30
        muted = d.bool(forKey: "muted")
        banners = d.object(forKey: "banners") as? Bool ?? true
        inputHistory = d.data(forKey: "inputHistory").flatMap { try? JSONDecoder().decode(InputHistory.self, from: $0) }
            ?? InputHistory()
        pingCount = d.object(forKey: "pingCount") as? Int ?? 5
        downCount = d.object(forKey: "downCount") as? Int ?? 3
        downAfter = d.object(forKey: "downAfter") as? Int ?? 2
        windowSeconds = d.object(forKey: "windowSeconds") as? Int ?? 900
        selection = d.string(forKey: "selection").flatMap(UUID.init(uuidString:))
        let sounds = Self.availableSounds
        let savedPing = d.string(forKey: "pingSound") ?? "Ping"
        let savedDown = d.string(forKey: "downSound") ?? "Basso"
        pingSound = sounds.contains(savedPing) ? savedPing : sounds[0]
        downSound = sounds.contains(savedDown) ? savedDown : sounds[0]
        if let count = ProcessInfo.processInfo.environment["PINGWATCH_PREFILL"].flatMap(Int.init) {
            prefill(count)
        }
        reconcile()
        if banners { requestNotifications() }
    }

    private func requestNotifications() {
        Task {
            await notifier.requestAuthorization()
            bannersDenied = await notifier.isDenied()
        }
    }

    /// The default seconds between checks for a Ping or a Web host.
    func defaultInterval(for kind: CheckKind) -> Int {
        kind == .web ? webInterval : pingInterval
    }

    /// Seconds between two checks of the host: its own setting, else the default for its kind.
    func interval(of host: HostEntry) -> Int {
        max(1, host.interval ?? defaultInterval(for: host.kind))
    }

    /// Benchmark hook: PINGWATCH_PREFILL=3600 starts with that many synthetic pings per host
    /// and 10 synthetic hops per route, as if the app had been running for an hour.
    private func prefill(_ count: Int) {
        let now = Date()
        func samples(seed: Int) -> [PingSample] {
            (0..<count).map { i in
                PingSample(date: now.addingTimeInterval(Double(i - count)),
                           latencyMs: (i + seed) % 37 == 0 ? nil : Double((i * 7 + seed * 13) % 110 + 10))
            }
        }
        for (n, host) in hosts.enumerated() {
            history[host.id] = samples(seed: n)
            traces[host.id] = Dictionary(uniqueKeysWithValues: (1...10).map { hop in
                (hop, HopTrace(address: "10.0.\(n).\(hop)", samples: samples(seed: n * 10 + hop)))
            })
        }
    }

    /// Adds entries separated by spaces, commas or newlines. For a ping, web addresses such as
    /// "https://www.example.com/page" are reduced to their host; for a web check the address becomes
    /// a full URL ("example.com" turns into "https://example.com"). Returns the entries that were rejected.
    @discardableResult
    func add(_ input: String, kind: CheckKind = .ping) -> [String] {
        var rejected: [String] = []
        for entry in input.split(whereSeparator: { $0.isWhitespace || $0 == "," }).map(String.init) {
            let name = kind == .web ? WebTarget.normalize(entry) : HostName.extract(from: entry)
            guard let name else {
                rejected.append(entry)
                continue
            }
            inputHistory.record(name, kind: kind)
            let known = hosts.contains { $0.kind == kind && $0.name.caseInsensitiveCompare(name) == .orderedSame }
            if !known { hosts.append(HostEntry(name: name, kind: kind)) }
        }
        return rejected
    }

    func remove(_ id: UUID) {
        hosts.removeAll { $0.id == id }
    }

    /// The host that is shown in the detail view: the clicked one, else the first.
    var selectedHostID: UUID? {
        hosts.contains { $0.id == selection } ? selection : hosts.first?.id
    }

    private func inWindow(_ samples: [PingSample]) -> [PingSample] {
        guard windowSeconds > 0 else { return samples }
        let cutoff = Date().addingTimeInterval(-Double(windowSeconds))
        return samples.filter { $0.date >= cutoff }
    }

    /// The host's pings inside the selected time window.
    func samples(for id: UUID) -> [PingSample] {
        inWindow(history[id] ?? [])
    }

    /// The route to the host, one entry per hop, nearest router first.
    func hops(for id: UUID) -> [HopInfo] {
        let trace = traces[id] ?? [:]
        var hops = trace.keys.sorted().compactMap { hop in info(hop, trace[hop]) }
        let deltas = HopDelta.compute(averages: hops.map { $0.stats.avg })
        for i in hops.indices { hops[i].delta = deltas[i] }
        return hops
    }

    /// One hop of the route, without the latency it adds (that needs the whole route).
    func hop(_ number: Int, for id: UUID) -> HopInfo? {
        info(number, traces[id]?[number])
    }

    private func info(_ number: Int, _ trace: HopTrace?) -> HopInfo? {
        guard let trace else { return nil }
        let samples = inWindow(trace.samples)
        return HopInfo(hop: number, address: trace.address, samples: samples,
                       stats: LatencyStats(samples.map(\.latencyMs)))
    }

    /// Summary of the host's pings in the time window. Cached until the next refresh, because
    /// every table cell asks for it.
    func stats(for id: UUID) -> LatencyStats {
        if let cached = statsCache[id] { return cached }
        let stats = LatencyStats(samples(for: id).map(\.latencyMs))
        statsCache[id] = stats
        return stats
    }

    private func markChanged() {
        guard !refreshScheduled else { return }
        refreshScheduled = true
        Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            refreshScheduled = false
            statsCache.removeAll()
            objectWillChange.send()
        }
    }

    /// Plays a sound once, e.g. when it is picked in the settings.
    func preview(_ sound: String) { sounds.play(sound, times: 1) }

    func testPing() { sounds.play(pingSound, times: pingCount) }
    func testDown() { sounds.play(downSound, times: downCount) }

    // MARK: - Scheduling

    private func reconcile() {
        let wanted = Set(running ? hosts.filter(\.enabled).map(\.id) : [])
        for (id, task) in tasks where !wanted.contains(id) {
            task.cancel()
            tasks[id] = nil
            status[id] = nil
        }
        for host in hosts where wanted.contains(host.id) && tasks[host.id] == nil {
            tasks[host.id] = Task { await self.watch(host.id) }
        }
        status = status.filter { id, _ in hosts.contains { $0.id == id } }
        history = history.filter { id, _ in hosts.contains { $0.id == id } }
        traces = traces.filter { id, _ in hosts.contains { $0.id == id } }
        reconcileTrace()
        hosts.forEach { resolve($0.hostName) }
    }

    /// Looks up the IP address behind a hostname once, so it can be shown next to the name.
    private func resolve(_ name: String) {
        guard resolved[name] == nil, pendingResolves.insert(name).inserted else { return }
        Task {
            if let address = await ForwardDNS.lookup(name) { resolved[name] = address }
            pendingResolves.remove(name)
        }
    }

    /// The route is traced for the host shown in the detail view only, to keep the load low.
    private func reconcileTrace() {
        let target = running ? hosts.first(where: { $0.id == selectedHostID && $0.enabled })?.id : nil
        guard target != traceTarget else { return }
        traceTask?.cancel()
        traceTarget = target
        traceTask = target.map { id in Task { await self.traceLoop(id) } }
    }

    private func traceLoop(_ id: UUID) async {
        while !Task.isCancelled {
            guard let name = hosts.first(where: { $0.id == id })?.hostName else { return }
            let readings = await Traceroute.run(host: name)
            if Task.isCancelled { return }
            record(readings, for: id)
            let seconds = hosts.first(where: { $0.id == id }).map(interval(of:)) ?? 5
            try? await Task.sleep(nanoseconds: UInt64(max(2, seconds)) * 1_000_000_000)
        }
    }

    private func record(_ readings: [HopReading], for id: UUID) {
        guard let lastHop = readings.map(\.hop).max() else { return }
        let now = Date()
        // Hops beyond the destination of a shorter route disappear.
        var hops = (traces[id] ?? [:]).filter { $0.key <= lastHop }
        for reading in readings {
            var trace = hops[reading.hop] ?? HopTrace()
            if let address = reading.address {
                trace.address = address
                lookupName(for: address)
            }
            trace.samples.append(PingSample(date: now, latencyMs: reading.latencyMs))
            if trace.samples.count > Self.historyLimit {
                trace.samples.removeFirst(trace.samples.count - Self.historyLimit)
            }
            hops[reading.hop] = trace
        }
        traces[id] = hops
    }

    private func lookupName(for address: String) {
        guard hostNames[address] == nil, pendingNames.insert(address).inserted else { return }
        Task {
            // An empty name marks "no reverse entry", so the lookup is not repeated.
            hostNames[address] = await ReverseDNS.lookup(address) ?? ""
            pendingNames.remove(address)
        }
    }

    private struct CheckOutcome {
        let ok: Bool
        let latencyMs: Double?
        var statusCode: Int?
        var detail: String?
    }

    /// One check of a host. A web check only counts as a success with a 2xx status.
    private func run(_ host: HostEntry) async -> CheckOutcome {
        switch host.kind {
        case .ping:
            let result = await Pinger.ping(host: host.name)
            return CheckOutcome(ok: result.reachable, latencyMs: result.latencyMs)
        case .web:
            let result = await WebChecker.check(host.name)
            return CheckOutcome(ok: result.isOK, latencyMs: result.latencyMs,
                                statusCode: result.statusCode, detail: result.summary)
        }
    }

    private func watch(_ id: UUID) async {
        var tracker = StateTracker()
        while !Task.isCancelled {
            guard let host = hosts.first(where: { $0.id == id }) else { return }
            let check = await run(host)
            if Task.isCancelled { return }

            let before = tracker.state
            let event = tracker.record(success: check.ok, downAfter: downAfter)
            status[id] = HostStatus(state: tracker.state, latencyMs: check.latencyMs, lastCheck: Date(),
                                    statusCode: check.statusCode, detail: check.detail)
            history[id, default: []].append(PingSample(date: Date(), latencyMs: check.ok ? (check.latencyMs ?? 0) : nil))
            // Trim in batches, so the oldest pings are not shifted out on every single check.
            if history[id, default: []].count > Self.historyLimit + 200 {
                history[id]?.removeFirst(200)
            }
            switch event {
            case .becameUp: if !muted { sounds.play(pingSound, times: pingCount) }
            case .becameDown: if !muted { sounds.play(downSound, times: downCount) }
            case nil: break
            }
            notify(host, event: event, before: before, check: check)

            // Wait for the interval in short steps, so a changed interval takes effect at once.
            let started = Date()
            while !Task.isCancelled,
                  Date().timeIntervalSince(started) < Double(hosts.first(where: { $0.id == id }).map(interval(of:)) ?? 5) {
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }
    }

    // MARK: - Banners

    /// A banner when a host goes up or down, and for a web host also when its HTTP status changes.
    /// The first result after starting only gets a banner if the host is down.
    private func notify(_ host: HostEntry, event: HostEvent?, before: HostState, check: CheckOutcome) {
        let previousCode = lastStatusCode[host.id]
        if host.kind == .web { lastStatusCode[host.id] = check.statusCode ?? 0 }
        guard banners else { return }

        let time = check.latencyMs.map { String(format: " · %.0f ms", $0) } ?? ""
        switch event {
        case .becameUp:
            guard before != .unknown else { return }
            post(host, "\(host.name) ist wieder erreichbar", (check.detail ?? "Ping antwortet") + time)
        case .becameDown:
            post(host, "\(host.name) ist nicht erreichbar", check.detail ?? "keine Antwort auf Ping")
        case nil:
            guard host.kind == .web, let previousCode, previousCode != (check.statusCode ?? 0) else { return }
            let old = previousCode == 0 ? "keine Antwort" : HTTPStatus.summary(previousCode)
            post(host, "\(host.name): Status geändert", "\(old) → \(check.detail ?? "keine Antwort")")
        }
    }

    private func post(_ host: HostEntry, _ title: String, _ body: String) {
        notifier.post(key: "host-\(host.id.uuidString)", title: title, body: body)
    }

    // MARK: - Persistence

    private func save() {
        defaults.set(try? JSONEncoder().encode(hosts), forKey: "hosts")
        defaults.set(running, forKey: "running")
        defaults.set(pingInterval, forKey: "pingInterval")
        defaults.set(webInterval, forKey: "webInterval")
        defaults.set(try? JSONEncoder().encode(inputHistory), forKey: "inputHistory")
        defaults.set(muted, forKey: "muted")
        defaults.set(banners, forKey: "banners")
        defaults.set(pingCount, forKey: "pingCount")
        defaults.set(downCount, forKey: "downCount")
        defaults.set(downAfter, forKey: "downAfter")
        defaults.set(windowSeconds, forKey: "windowSeconds")
        defaults.set(selection?.uuidString, forKey: "selection")
        defaults.set(pingSound, forKey: "pingSound")
        defaults.set(downSound, forKey: "downSound")
    }
}
