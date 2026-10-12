import AppKit
import SwiftUI

/// First-run walkthrough: permission, find the monitor, pair, pick the output, choose a mode.
struct SetupView: View {
    @ObservedObject var coordinator: AppCoordinator

    private enum Step: Int, CaseIterable {
        case accessibility, find, pair, output, mode

        var symbol: String {
            switch self {
            case .accessibility: return "hand.raised"
            case .find: return "display"
            case .pair: return "link"
            case .output: return "speaker.wave.3"
            case .mode: return "menubar.rectangle"
            }
        }

        var title: String {
            switch self {
            case .accessibility: return "Allow Volume Keys"
            case .find: return "Find Your Monitor"
            case .pair: return "Pair With the Monitor"
            case .output: return "Choose the Sound Output"
            case .mode: return "Where Should SmartVolume Live?"
            }
        }

        var subtitle: String {
            switch self {
            case .accessibility:
                return "SmartVolume needs \(KeyPermission.settingsName) permission to use the volume keys. It only acts on them while your monitor is the sound output."
            case .find:
                return "Your Mac and your Samsung monitor need to be on the same network."
            case .pair:
                return "The monitor asks once whether to allow SmartVolume."
            case .output:
                return "Select your monitor as the sound output in Control Center or System Settings › Sound."
            case .mode:
                return "You can change this any time in Settings."
            }
        }
    }

    private struct FoundMonitor: Identifiable, Equatable {
        let host: String
        let info: DeviceInfo
        var id: String { info.id }
    }

    @State private var step: Step = .accessibility
    @State private var found: [FoundMonitor] = []
    @State private var selected: FoundMonitor?
    @State private var searching = false
    @State private var connecting = false
    @State private var manualHost = ""
    @State private var errorText: String?
    @State private var mode: PresenceMode = .menuBar

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            VStack(spacing: 14) {
                Image(systemName: step.symbol)
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(.secondary)
                    .frame(height: 52)
                Text(step.title).font(.title2.weight(.semibold))
                Text(step.subtitle)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 400)
                content
                    .frame(maxWidth: 400)
                    .padding(.top, 6)
            }
            .padding(.horizontal, 32)
            .padding(.top, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            Divider()
            footer
        }
        .task { await searchIfNeeded() }
    }

    // MARK: Chrome

    private var header: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 32, height: 32)
                Text("Set Up SmartVolume").font(.headline)
                Spacer()
                Text("Step \(step.rawValue + 1) of \(Step.allCases.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: Double(step.rawValue + 1), total: Double(Step.allCases.count))
                .progressViewStyle(.linear)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var footer: some View {
        HStack {
            if step != .accessibility {
                Button("Back") { go(to: Step(rawValue: step.rawValue - 1)!) }
            }
            Spacer()
            primaryButton
        }
        .padding(16)
    }

    @ViewBuilder
    private var primaryButton: some View {
        switch step {
        case .accessibility:
            Button("Continue") { go(to: .find) }
                .keyboardShortcut(.defaultAction)
                .disabled(!coordinator.accessibilityGranted)
        case .find:
            Button(connecting ? "Connecting…" : "Connect") { Task { await connect() } }
                .keyboardShortcut(.defaultAction)
                .disabled(connecting || (selected == nil && trimmedHost.isEmpty))
        case .pair:
            Button("Continue") { go(to: .output) }
                .keyboardShortcut(.defaultAction)
                .disabled(coordinator.linkState != .connected)
        case .output:
            Button("Continue") { go(to: .mode) }
                .keyboardShortcut(.defaultAction)
                .disabled(!coordinator.monitorIsOutput)
        case .mode:
            Button("Finish") { try? coordinator.completeSetup(mode: mode) }
                .keyboardShortcut(.defaultAction)
        }
    }

    // MARK: Step content

    @ViewBuilder
    private var content: some View {
        switch step {
        case .accessibility: accessibilityContent
        case .find: findContent
        case .pair: pairContent
        case .output: outputContent
        case .mode: modeContent
        }
    }

    private var accessibilityContent: some View {
        VStack(spacing: 10) {
            if coordinator.accessibilityGranted {
                StatusLabel(text: "Permission granted", color: .green)
            } else {
                Button("Open \(KeyPermission.settingsName) Settings") { KeyPermission.prompt() }
                Button("Check Again") { coordinator.refreshAccessibility() }
                    .buttonStyle(.link)
            }
        }
    }

    private var findContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Monitors on this network").font(.subheadline.weight(.medium))
                Spacer()
                if searching {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Search Again") { Task { await search() } }.buttonStyle(.link)
                }
            }
            VStack(spacing: 0) {
                if found.isEmpty {
                    Text(searching ? "Searching…" : "No monitors found")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                } else {
                    ForEach(found) { monitor in
                        Button { selected = monitor; manualHost = "" } label: {
                            HStack {
                                Image(systemName: "display")
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(monitor.info.name)
                                    Text(monitor.host).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if selected == monitor { Image(systemName: "checkmark").foregroundStyle(.tint) }
                            }
                            .contentShape(Rectangle())
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                        if monitor != found.last { Divider() }
                    }
                }
            }
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(nsColor: .separatorColor)))

            HStack {
                Text("Or enter its IP address:").foregroundStyle(.secondary)
                TextField("192.168.1.20", text: $manualHost)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: manualHost) { _, value in if !value.isEmpty { selected = nil } }
            }
            .font(.callout)
            if let errorText { StatusLabel(text: errorText, color: .orange) }
        }
    }

    private var pairContent: some View {
        VStack(spacing: 10) {
            switch coordinator.linkState {
            case .connecting:
                ProgressView().controlSize(.small)
                Text("Press Allow on your monitor's screen.").font(.callout)
            case .connected:
                StatusLabel(text: "Paired with \(coordinator.pairedMonitor?.displayName ?? "your monitor")", color: .green)
            case .unpaired:
                StatusLabel(text: "The monitor didn't allow the connection.", color: .orange)
                Button("Try Again") { coordinator.retryPairing() }
            case .unreachable:
                StatusLabel(text: "Can't reach the monitor. Check that it's on.", color: .orange)
                Button("Try Again") { coordinator.retryPairing() }
            }
        }
    }

    private var outputContent: some View {
        VStack(spacing: 10) {
            if coordinator.monitorIsOutput {
                StatusLabel(text: "Ready. Press a volume key to try it.", color: .green)
            } else if let output = coordinator.currentOutput {
                Text("Current output: \(output.name)").font(.callout).foregroundStyle(.secondary)
                if output.transport == .displayPort || output.transport == .hdmi {
                    Button("Use \(output.name)") { coordinator.useCurrentOutputAsMonitor() }
                }
            }
        }
    }

    private var modeContent: some View {
        VStack(spacing: 8) {
            ForEach(PresenceRules.allowedModes(paired: coordinator.pairedMonitor != nil), id: \.self) { option in
                ModeRow(mode: option, isSelected: mode == option) { mode = option }
            }
        }
    }

    // MARK: Actions

    private var trimmedHost: String { manualHost.trimmingCharacters(in: .whitespaces) }

    private func go(to newStep: Step) {
        errorText = nil
        withAnimation(.easeInOut(duration: 0.15)) { step = newStep }
        if newStep == .find { Task { await searchIfNeeded() } }
    }

    @MainActor
    private func searchIfNeeded() async {
        if step == .find && found.isEmpty && !searching { await search() }
    }

    @MainActor
    private func search() async {
        searching = true
        errorText = nil
        var results: [FoundMonitor] = []
        for host in await SSDPDiscovery().discover() {
            if let info = try? await DeviceInfoClient().fetch(host: host) {
                results.append(FoundMonitor(host: host, info: info))
            }
        }
        found = results
        if selected == nil, results.count == 1 { selected = results.first }
        searching = false
    }

    @MainActor
    private func connect() async {
        if let selected {
            choose(host: selected.host, info: selected.info)
            return
        }
        connecting = true
        defer { connecting = false }
        do {
            let info = try await DeviceInfoClient().fetch(host: trimmedHost)
            choose(host: trimmedHost, info: info)
        } catch {
            errorText = "No Samsung monitor answered at \(trimmedHost)."
        }
    }

    private func choose(host: String, info: DeviceInfo) {
        coordinator.pair(with: PairedMonitor(deviceID: info.id, host: host, name: info.name))
        go(to: .pair)
    }
}

/// A small coloured dot with a line of text.
struct StatusLabel: View {
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text).font(.callout)
        }
    }
}

private struct ModeRow: View {
    let mode: PresenceMode
    let isSelected: Bool
    let action: () -> Void

    private var symbol: String {
        switch mode {
        case .dock: return "dock.rectangle"
        case .menuBar: return "menubar.rectangle"
        case .background: return "eye.slash"
        }
    }

    private var detail: String {
        switch mode {
        case .dock: return "Shows an icon in the Dock."
        case .menuBar: return "A small speaker in the menu bar."
        case .background: return "No icon. Open SmartVolume again to see Settings."
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol).frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.title)
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: isSelected ? 1.5 : 1)
            )
        }
        .buttonStyle(.plain)
    }
}
