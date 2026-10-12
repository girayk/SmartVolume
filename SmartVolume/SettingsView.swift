import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var coordinator: AppCoordinator

    var body: some View {
        Form {
            Section {
                HStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 48, height: 48)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(coordinator.pairedMonitor?.displayName ?? "No monitor").font(.headline)
                        StatusLabel(text: status.text, color: status.color)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(.vertical, 4)

                if !coordinator.accessibilityGranted {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("After an update, macOS can show SmartVolume as allowed while ignoring it. If so, remove it from the \(KeyPermission.settingsName) list with the minus button, then add it again.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Open \(KeyPermission.settingsName) Settings") { KeyPermission.prompt() }
                    }
                }
            }

            Section("Monitor") {
                LabeledContent("Address", value: coordinator.pairedMonitor?.host ?? "None")
                HStack {
                    Button("Re-pair") { coordinator.retryPairing() }
                    Spacer()
                    Button("Forget Monitor", role: .destructive) { coordinator.forgetMonitor() }
                }
            }

            Section("General") {
                Picker("Show in", selection: Binding(
                    get: { coordinator.presenceMode },
                    set: { try? coordinator.setPresence($0) }
                )) {
                    ForEach(PresenceRules.allowedModes(paired: coordinator.pairedMonitor != nil), id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                if coordinator.presenceMode == .background {
                    Text("To come back here, open SmartVolume again from Applications or Spotlight.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Toggle("Start at login", isOn: Binding(
                    get: { coordinator.startAtLogin },
                    set: { coordinator.setStartAtLogin($0) }
                ))
            }

            Section {
                HStack {
                    Text("Version \(SmartVolumeInfo.version)").foregroundStyle(.secondary)
                    Spacer()
                    Link("GitHub", destination: URL(string: SmartVolumeInfo.repositoryURL)!)
                    Button("Quit") { NSApp.terminate(nil) }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var status: (text: String, color: Color) {
        if !coordinator.accessibilityGranted {
            return ("Needs \(KeyPermission.settingsName) permission", .orange)
        }
        switch coordinator.linkState {
        case .unpaired: return ("Not paired", .gray)
        case .connecting: return ("Connecting…", .yellow)
        case .unreachable: return ("Can't reach the monitor, using Mac volume", .orange)
        case .connected:
            return coordinator.monitorIsOutput
                ? ("Volume keys control this monitor", .green)
                : ("Connected. Select it as the sound output to use it", .gray)
        }
    }
}
