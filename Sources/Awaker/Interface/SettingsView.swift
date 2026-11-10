import AwakerCore
import SwiftUI

/// A native grouped form in a glass panel as tall as its content. Changes apply immediately.
struct SettingsView: View {
    @Environment(AwakeController.self) private var awake
    @Environment(AppSettings.self) private var settings
    @Environment(Updater.self) private var updater


    var body: some View {
        // The form doesn't scroll itself: it takes its natural height, and the page scrolls around it.
        ScrollView {
            form
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)
                .scrollDisabled(true)
                .fixedSize(horizontal: false, vertical: true)
                .glassEffect(in: .rect(cornerRadius: PanelMetrics.radius))
                .frame(maxWidth: PanelMetrics.maxWidth)
                .padding()
        }
        .scrollIndicators(.never)
    }

    private var form: some View {
        @Bindable var settings = settings
        return Form {
            Section {
                LabeledContent {
                    if awake.isAuthorized {
                        Button("Remove", role: .destructive) { awake.removeAuthorization() }
                    } else {
                        Button("Install…") { awake.installAuthorization() }
                    }
                } label: {
                    Label(awake.isAuthorized ? "Authorization installed" : "Authorization needed",
                          systemImage: awake.isAuthorized ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .symbolRenderingMode(.multicolor)
                    Text("Keeping the Mac awake with the lid closed goes through pmset, which needs administrator rights. The authorization covers that command only.")
                }
            }

            Section("Session") {
                Picker("Default duration", selection: $settings.defaultMinutes) {
                    ForEach(AppSettings.durationChoices, id: \.minutes) { Text($0.label).tag($0.minutes) }
                }
                Toggle(isOn: $settings.autoMode) {
                    Text("Auto mode")
                    Text("Keeps the Mac awake while an agent is working or one of its commands is running, and lets it sleep 3 minutes later. A session that is merely open doesn't count.")
                }
            }

            Section("Protections") {
                Toggle(isOn: $settings.batteryGuard) {
                    Text("Stop when the battery is low")
                    Text("On battery only. Plugged in, the Mac stays awake.")
                }
                Picker("Battery threshold", selection: $settings.batteryThreshold) {
                    ForEach(AppSettings.thresholdChoices, id: \.self) { Text("\($0)%").tag($0) }
                }
                .disabled(!settings.batteryGuard)
                Toggle(isOn: $settings.acOnly) {
                    Text("Only when plugged in")
                    Text("Stops as soon as the charger is unplugged.")
                }
                Toggle(isOn: $settings.thermalGuard) {
                    Text("Stop when the Mac overheats")
                    Text("With the lid closed, heat escapes less easily.")
                }
            }

            Section("System") {
                Toggle("Show duration in the menu bar", isOn: $settings.showElapsedInMenuBar)
                Toggle(isOn: $settings.notifications) {
                    Text("Session notifications")
                    Text("When auto mode starts a session, or a protection stops one.")
                }
                Toggle(isOn: $settings.agentNotifications) {
                    Text("Agent notifications")
                    Text("When an agent finishes or needs you, and a recap when you come back to the Mac.")
                }
                Toggle("Open at login",
                       isOn: Binding(get: { awake.launchesAtLogin }, set: { awake.setLaunchesAtLogin($0) }))
            }

            Section("Updates") {
                LabeledContent {
                    updateControl
                } label: {
                    Text("Awaker \(updater.currentVersion)")
                    Text(updateStatus)
                }
            }

            if let error = awake.lastError {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .symbolRenderingMode(.multicolor)
                }
            }
        }
    }

    @ViewBuilder private var updateControl: some View {
        switch updater.status {
        case .available(let release):
            Button("Install \(release.version)") { Task { await updater.install(release) } }
                .buttonStyle(.glassProminent)
        case .checking, .downloading:
            ProgressView().controlSize(.small)
        case .idle, .upToDate, .failed:
            Button("Check Now") { Task { await updater.check() } }
        }
    }

    private var updateStatus: String {
        switch updater.status {
        case .idle: "Checked automatically once a day."
        case .checking: "Checking for a new version…"
        case .upToDate: "You have the latest version."
        case .available(let release): "Version \(release.version) is available. Installing relaunches Awaker and stops the running session."
        case .downloading(let release): "Downloading version \(release.version)…"
        case .failed(let message): message
        }
    }
}
