import SwiftUI
import PingCore

func formatMs(_ value: Double?) -> String {
    value.map { String(format: "%.0f ms", $0) } ?? "–"
}

/// A rounded Liquid Glass panel.
struct GlassCard: ViewModifier {
    var padding: CGFloat = 14

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .glassEffect(.regular, in: .rect(cornerRadius: 24))
    }
}

extension View {
    func glassCard(padding: CGFloat = 14) -> some View {
        modifier(GlassCard(padding: padding))
    }
}

struct ContentView: View {
    @EnvironmentObject var monitor: Monitor
    @State private var input = ""
    @State private var error: String?
    @State private var showSettings = false
    @AppStorage("newKind") private var newKind = CheckKind.ping.rawValue

    private var kind: CheckKind { CheckKind(rawValue: newKind) ?? .ping }

    private static let windows: [(label: String, seconds: Int)] = [
        ("5 Minuten", 300), ("15 Minuten", 900), ("1 Stunde", 3600), ("Alles", 0),
    ]

    var body: some View {
        VStack(spacing: 12) {
            toolbar
            if monitor.hosts.isEmpty {
                Text("Noch keine Hosts. Wähle oben Ping oder Web und trage eine Adresse ein.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VSplitView {
                    hostTable
                        .glassCard(padding: 6)
                        .frame(minHeight: 150)
                        .padding(.bottom, 6)
                    HostDetail(hostID: monitor.selectedHostID)
                        .frame(minHeight: 540)
                        .padding(.top, 6)
                }
            }
        }
        .padding(14)
        .frame(minWidth: 940, minHeight: 820)
        .background {
            LinearGradient(colors: [.blue.opacity(0.22), .teal.opacity(0.10), .clear],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        VStack(alignment: .leading, spacing: 6) {
            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    Picker("Art der Prüfung", selection: $newKind) {
                        Label("Ping", systemImage: "dot.radiowaves.left.and.right").tag(CheckKind.ping.rawValue)
                        Label("Web", systemImage: "globe").tag(CheckKind.web.rawValue)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    .help("Ping prüft die Erreichbarkeit, Web lädt die Seite per HTTP/HTTPS und prüft auf Status 200")

                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill").foregroundStyle(.secondary)
                        TextField(kind == .web ? LocalizedStringKey("Web-Adresse, z. B. https://www.example.com")
                                               : LocalizedStringKey("IP oder Hostname, z. B. 192.168.1.1 oder example.com"),
                                  text: $input)
                            .textFieldStyle(.plain)
                            .onSubmit(add)
                            .textInputSuggestions {
                                ForEach(monitor.inputHistory.suggestions(for: input, kind: kind), id: \.self) { entry in
                                    Text(entry).textInputCompletion(entry)
                                }
                            }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .glassEffect(.regular, in: .capsule)

                    Button("Hinzufügen", action: add)
                        .buttonStyle(.glassProminent)
                        .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty)

                    Menu {
                        ForEach(Array(monitor.inputHistory.items.enumerated()), id: \.offset) { _, item in
                            Button {
                                newKind = item.kind.rawValue
                                input = item.text
                            } label: {
                                Label(item.text, systemImage: item.kind == .web ? "globe" : "dot.radiowaves.left.and.right")
                            }
                        }
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                    .menuStyle(.button)
                    .menuIndicator(.hidden)
                    .buttonStyle(.glass)
                    .disabled(monitor.inputHistory.items.isEmpty)
                    .help("Zuletzt eingegebene Hosts und Web-Adressen (die letzten 50)")

                    HStack(spacing: 6) {
                        Image(systemName: "clock").foregroundStyle(.secondary)
                        Picker("Zeitraum", selection: $monitor.windowSeconds) {
                            ForEach(Self.windows, id: \.seconds) { Text(LocalizedStringKey($0.label)).tag($0.seconds) }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .glassEffect(.regular, in: .capsule)

                    Toggle("Aktiv", isOn: $monitor.running)
                        .toggleStyle(.switch)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .glassEffect(.regular, in: .capsule)

                    Button { monitor.muted.toggle() } label: {
                        Image(systemName: monitor.muted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .foregroundStyle(monitor.muted ? Color.red : Color.primary)
                            .frame(width: 18)
                    }
                    .buttonStyle(.glass)
                    .keyboardShortcut("m", modifiers: [.command, .shift])
                    .help(monitor.muted ? LocalizedStringKey("Alarmtöne sind stumm – klicken zum Einschalten (⇧⌘M)")
                                        : LocalizedStringKey("Alarmtöne stumm schalten (⇧⌘M)"))

                    Button { showSettings.toggle() } label: { Image(systemName: "gearshape") }
                        .buttonStyle(.glass)
                        .help("Einstellungen")
                        .popover(isPresented: $showSettings, arrowEdge: .bottom) {
                            SettingsView().environmentObject(monitor)
                        }
                }
            }
            if let error {
                Text(error).font(.caption).foregroundStyle(.red).padding(.leading, 14)
            }
        }
    }

    private func add() {
        let rejected = monitor.add(input, kind: kind)
        error = rejected.isEmpty ? nil : String(localized: "Ungültig: \(rejected.joined(separator: ", "))")
        input = rejected.joined(separator: " ")
    }

    // MARK: - Host table

    private var hostTable: some View {
        Table(monitor.hosts, selection: $monitor.selection) {
            TableColumn("Host") { host in
                HStack(spacing: 8) {
                    Circle().fill(color(for: host)).frame(width: 10, height: 10)
                    Image(systemName: host.kind == .web ? "globe" : "dot.radiowaves.left.and.right")
                        .foregroundStyle(.secondary)
                        .help(host.kind == .web ? LocalizedStringKey("Web-Prüfung (HTTP/HTTPS)") : LocalizedStringKey("Ping"))
                    Text(host.name).font(.system(.body, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                }
            }
            .width(min: 180, ideal: 260)
            TableColumn("HTTP") { host in
                StatusCodeText(host: host, status: monitor.status[host.id])
            }
            .width(46)
            TableColumn("Aktuell") { host in
                Text(formatMs(monitor.stats(for: host.id).last)).monospacedDigit()
            }
            .width(68)
            TableColumn("Ø") { host in
                Text(formatMs(monitor.stats(for: host.id).avg)).monospacedDigit()
            }
            .width(68)
            TableColumn("Min") { host in
                Text(formatMs(monitor.stats(for: host.id).min)).monospacedDigit()
            }
            .width(68)
            TableColumn("Max") { host in
                Text(formatMs(monitor.stats(for: host.id).max)).monospacedDigit()
            }
            .width(68)
            TableColumn("Verlust") { host in
                LossText(percent: monitor.stats(for: host.id).lossPercent)
            }
            .width(66)
            TableColumn("Verlauf") { host in
                LatencyBars(samples: monitor.samples(for: host.id), window: monitor.windowSeconds)
                    .frame(height: 24)
            }
            TableColumn("Intervall") { host in
                intervalPicker(host)
            }
            .width(120)
            TableColumn("") { host in
                HStack(spacing: 8) {
                    Toggle("", isOn: enabledBinding(host)).labelsHidden().help("Pausieren / fortsetzen")
                    Button(role: .destructive) { monitor.remove(host.id) } label: { Image(systemName: "trash") }
                        .buttonStyle(.borderless)
                        .help("Entfernen")
                }
            }
            .width(70)
        }
        .scrollContentBackground(.hidden)
    }

    /// Seconds between two checks of this host; "Standard" follows the default for Ping or Web in the settings.
    private func intervalPicker(_ host: HostEntry) -> some View {
        let presets = [1, 2, 3, 5, 10, 15, 30, 60, 120, 300, 600]
        let options = Set(presets + [host.interval].compactMap { $0 }).sorted()
        let selection = Binding<Int>(
            get: { host.interval ?? 0 },
            set: { value in
                if let i = monitor.hosts.firstIndex(where: { $0.id == host.id }) {
                    monitor.hosts[i].interval = value == 0 ? nil : value
                }
            }
        )
        return Picker("", selection: selection) {
            Text("Standard (\(durationLabel(monitor.defaultInterval(for: host.kind))))").tag(0)
            ForEach(options, id: \.self) { Text(durationLabel($0)).tag($0) }
        }
        .labelsHidden()
        .controlSize(.small)
        .help("Abstand zwischen zwei Prüfungen dieses Hosts")
    }

    private func durationLabel(_ seconds: Int) -> String {
        seconds >= 60 && seconds % 60 == 0 ? "\(seconds / 60) min" : "\(seconds) s"
    }

    private func enabledBinding(_ host: HostEntry) -> Binding<Bool> {
        Binding(
            get: { host.enabled },
            set: { value in
                if let i = monitor.hosts.firstIndex(where: { $0.id == host.id }) { monitor.hosts[i].enabled = value }
            }
        )
    }

    private func color(for host: HostEntry) -> Color {
        guard host.enabled, monitor.running else { return .gray.opacity(0.4) }
        switch monitor.status[host.id]?.state ?? .unknown {
        case .up: return .green
        case .down: return .red
        case .unknown: return .gray
        }
    }
}

/// The HTTP status of the last web check: green for 2xx, red otherwise ("ERR" if there was no response).
struct StatusCodeText: View {
    let host: HostEntry
    let status: HostStatus?

    var body: some View {
        if host.kind == .ping {
            Text("–").foregroundStyle(.secondary)
        } else if let code = status?.statusCode {
            Text("\(code)").monospacedDigit().foregroundStyle((200..<300).contains(code) ? .green : .red)
        } else if status?.detail != nil {
            Text("ERR").foregroundStyle(.red)
        } else {
            Text("").foregroundStyle(.secondary)
        }
    }
}

struct LossText: View {
    let percent: Double

    var body: some View {
        Text(String(format: "%.1f %%", percent))
            .monospacedDigit()
            .foregroundStyle(percent > 0 ? .red : .primary)
    }
}

// MARK: - Detail

struct HostDetail: View {
    @EnvironmentObject var monitor: Monitor
    let hostID: UUID?
    /// The hop whose timeline is shown; nil is the target itself (round trip).
    @State private var selectedHop: Int?
    @AppStorage("timelineHeight") private var timelineHeight = 250.0
    @AppStorage("timelineCollapsed") private var timelineCollapsed = false
    @State private var dragStartHeight: CGFloat?

    private static let minTraceHeight: CGFloat = 160
    private static let handleHeight: CGFloat = 16
    private static let collapsedHeight: CGFloat = 50
    private static let minTimelineHeight: CGFloat = 120

    var body: some View {
        if let id = hostID, let host = monitor.hosts.first(where: { $0.id == id }) {
            let hop = selectedHop.flatMap { monitor.hop($0, for: id) }
            GeometryReader { proxy in
                let room = max(proxy.size.height - Self.minTraceHeight - Self.handleHeight, Self.collapsedHeight)
                let timelineSize = timelineCollapsed ? Self.collapsedHeight : min(CGFloat(timelineHeight), room)
                VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(host.name).font(.system(.title2, design: .monospaced))
                        if let address = monitor.resolved[host.hostName], address != host.hostName {
                            Text("→ \(address)").font(.system(.body, design: .monospaced)).foregroundStyle(.secondary)
                        }
                        stateBadge(for: host)
                        if host.kind == .web, host.enabled, monitor.running, let detail = monitor.status[host.id]?.detail {
                            webBadge(detail: detail, code: monitor.status[host.id]?.statusCode)
                        }
                        Spacer()
                        legend
                    }
                    TraceGraph(hostID: id, selectedHop: $selectedHop,
                               roundTripLabel: host.kind == .web ? String(localized: "HTTP-Ladezeit (ms)") : String(localized: "Round Trip (ms)"))
                }
                .glassCard()
                .frame(maxHeight: .infinity)

                resizeHandle(room: room)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Button { timelineCollapsed.toggle() } label: {
                            Image(systemName: timelineCollapsed ? "chevron.right" : "chevron.down")
                                .frame(width: 14)
                        }
                        .buttonStyle(.borderless)
                        .help(timelineCollapsed ? LocalizedStringKey("Timeline einblenden") : LocalizedStringKey("Timeline ausblenden"))
                        Text(timelineTitle(host: host, hop: hop)).font(.headline)
                        Spacer()
                        Text(windowLabel).font(.caption).foregroundStyle(.secondary)
                    }
                    if !timelineCollapsed {
                        TimelineGraph(samples: hop?.samples ?? monitor.samples(for: id), window: monitor.windowSeconds)
                    }
                }
                .glassCard()
                .frame(height: timelineSize)
                }
            }
            .onChange(of: id) { _, _ in selectedHop = nil }
        } else {
            Text("Wähle einen Host aus.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Grab bar between the trace graph and the timeline: drag to resize, double-click to collapse.
    private func resizeHandle(room: CGFloat) -> some View {
        Capsule()
            .fill(.secondary.opacity(0.55))
            .frame(width: 44, height: 5)
            .frame(maxWidth: .infinity)
            .frame(height: Self.handleHeight)
            .contentShape(Rectangle())
            .pointerStyle(.rowResize)
            .help("Ziehen: Timeline größer oder kleiner · Doppelklick: ein-/ausklappen")
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        let start = dragStartHeight ?? (timelineCollapsed ? Self.collapsedHeight : min(CGFloat(timelineHeight), room))
                        dragStartHeight = start
                        timelineCollapsed = false
                        timelineHeight = Double(min(max(start - value.translation.height, Self.minTimelineHeight), room))
                    }
                    .onEnded { _ in dragStartHeight = nil }
            )
            .onTapGesture(count: 2) { timelineCollapsed.toggle() }
    }

    private func timelineTitle(host: HostEntry, hop: HopInfo?) -> String {
        guard let hop else {
            return host.kind == .web ? String(localized: "Timeline · Ladezeit von \(host.name)")
                                     : String(localized: "Timeline · \(host.name) (Round Trip)")
        }
        return String(localized: "Timeline · Hop \(hop.hop) · \(hop.address ?? String(localized: "keine Antwort"))")
    }

    private var windowLabel: String {
        switch monitor.windowSeconds {
        case 0: return String(localized: "alle Daten")
        case 3600: return String(localized: "letzte Stunde")
        case let seconds: return String(localized: "letzte \(seconds / 60) Minuten")
        }
    }

    private func stateBadge(for host: HostEntry) -> some View {
        let (text, color) = badge(for: host)
        return Text(LocalizedStringKey(text))
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .glassEffect(.regular.tint(color.opacity(0.4)), in: .capsule)
    }

    /// "HTTP 200 OK" in green, anything else (other status, timeout, TLS error …) in red.
    private func webBadge(detail: String, code: Int?) -> some View {
        let healthy = code.map { (200..<300).contains($0) } ?? false
        return Text(detail)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .glassEffect(.regular.tint((healthy ? Color.green : Color.red).opacity(0.4)), in: .capsule)
    }

    private func badge(for host: HostEntry) -> (String, Color) {
        guard host.enabled, monitor.running else { return ("pausiert", .gray) }
        switch monitor.status[host.id]?.state ?? .unknown {
        case .up: return ("erreichbar", .green)
        case .down: return ("nicht erreichbar", .red)
        case .unknown: return ("wird geprüft …", .gray)
        }
    }

    private var legend: some View {
        HStack(spacing: 12) {
            ForEach([("unter 100 ms", Color.green), ("100–200 ms", .yellow), ("über 200 ms", .red)],
                    id: \.0) { label, color in
                HStack(spacing: 4) {
                    Circle().fill(color).frame(width: 8, height: 8)
                    Text(LocalizedStringKey(label))
                }
            }
            HStack(spacing: 4) {
                Rectangle().fill(.red.opacity(0.6)).frame(width: 8, height: 8)
                Text("Verlust")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

// MARK: - Settings

struct SettingsView: View {
    @EnvironmentObject var monitor: Monitor

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
            GridRow {
                Text("Standard-Abstand Ping")
                Stepper("\(monitor.pingInterval) s", value: $monitor.pingInterval, in: 1...3600)
            }
            GridRow {
                Text("Standard-Abstand Web")
                Stepper("\(monitor.webInterval) s", value: $monitor.webInterval, in: 1...3600)
            }
            GridRow {
                Text("PING (erreichbar)")
                HStack {
                    soundPicker($monitor.pingSound)
                    Stepper("\(monitor.pingCount)×", value: $monitor.pingCount, in: 1...20)
                    Button("Testen", action: monitor.testPing).buttonStyle(.glass)
                }
            }
            GridRow {
                Text("DOWN (nicht erreichbar)")
                HStack {
                    soundPicker($monitor.downSound)
                    Stepper("\(monitor.downCount)×", value: $monitor.downCount, in: 1...20)
                    Button("Testen", action: monitor.testDown).buttonStyle(.glass)
                }
            }
            GridRow {
                Text("DOWN nach Fehlversuchen")
                Stepper("\(monitor.downAfter)", value: $monitor.downAfter, in: 1...10)
            }
            GridRow {
                Text("Systembanner")
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Bei Wechsel von erreichbar/nicht erreichbar und bei geändertem HTTP-Status",
                           isOn: $monitor.banners)
                    if monitor.banners, monitor.bannersDenied {
                        Text("Mitteilungen sind für PingWatch in den Systemeinstellungen ausgeschaltet.")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
        }
        .padding(16)
    }

    private func soundPicker(_ selection: Binding<String>) -> some View {
        Picker("", selection: selection) {
            ForEach(Monitor.availableSounds, id: \.self) { Text($0).tag($0) }
        }
        .onChange(of: selection.wrappedValue) { _, sound in monitor.preview(sound) }
        .labelsHidden()
        .frame(width: 130)
    }
}
