import AwakerCore
import SwiftUI

/// A native grouped form in a glass panel as tall as its content. Changes apply immediately.
struct SettingsView: View {
    @Environment(AwakeController.self) private var awake
    @Environment(AppSettings.self) private var settings
    @Environment(Updater.self) private var updater
    @Environment(AgentMonitor.self) private var monitor
    /// Switches the window to the Home screen, where a recap shows.
    var showHome: () -> Void = {}

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

            Section("Background") {
                // Four to a row: eight thumbnails side by side would be too small to tell apart.
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 12) {
                    ForEach(Backdrop.scenes) { scene in
                        let isOn = Backdrop.scene(settings.backdrop) == scene
                        Button {
                            settings.backdrop = scene.id
                        } label: {
                            VStack(spacing: 6) {
                                Color.clear
                                    .aspectRatio(16 / 9, contentMode: .fit)
                                    .overlay {
                                        if let thumbnail = Backdrop.thumbnail(of: scene) {
                                            Image(decorative: thumbnail, scale: 1)
                                                .resizable()
                                                .aspectRatio(contentMode: .fill)
                                        }
                                    }
                                    .clipShape(.rect(cornerRadius: 10))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 10)
                                            .strokeBorder(isOn ? AnyShapeStyle(.tint) : AnyShapeStyle(.separator), lineWidth: isOn ? 3 : 1)
                                    }
                                Text(scene.title)
                                    .font(.callout)
                                    .foregroundStyle(isOn ? .primary : .secondary)
                            }
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(isOn ? .isSelected : [])
                    }
                }
                .padding(.vertical, 4)
                Toggle(isOn: $settings.animatedBackdrop) {
                    Text("Animated background")
                    Text("Off, the picture stays still and the window uses much less processor.")
                }
            }

            Section {
                Toggle(isOn: $settings.showsAgents) {
                    Text("Show agents on Home")
                    Text("Off, the Home screen keeps only the count. The menu bar still lists the agents that need you.")
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 52), spacing: 8)], spacing: 8) {
                    ForEach(AvatarSkin.all) { skin in
                        let isOn = !settings.hiddenSkins.contains(skin.name)
                        Button {
                            if isOn { settings.hiddenSkins.insert(skin.name) } else { settings.hiddenSkins.remove(skin.name) }
                        } label: {
                            AgentAvatar(pose: .standing, fixedSkin: skin)
                                .opacity(isOn ? 1 : 0.3)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .background(.quaternary.opacity(isOn ? 1 : 0.4), in: .rect(cornerRadius: 10))
                                .overlay(alignment: .bottomTrailing) {
                                    Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                                        .font(.caption)
                                        .foregroundStyle(isOn ? AnyShapeStyle(.green) : AnyShapeStyle(.tertiary))
                                        .padding(3)
                                }
                                .contentShape(.rect(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                        .help(skin.name)
                        .accessibilityLabel(skin.name)
                        .accessibilityAddTraits(isOn ? .isSelected : [])
                    }
                }
                .padding(.vertical, 4)
            } header: {
                HStack {
                    Text("Avatars")
                    Spacer()
                    Button("All") { settings.hiddenSkins = [] }
                    Button("None") { settings.hiddenSkins = Set(AvatarSkin.all.map(\.name)) }
                }
                .controlSize(.small)
            } footer: {
                // Counted from the bundled skins: a hidden name may be a skin a later version no longer has.
                let selected = AvatarSkin.all.count { !settings.hiddenSkins.contains($0.name) }
                Text("Each agent wears one of the selected avatars. \(selected) of \(AvatarSkin.all.count) selected.")
            }

            Section("System") {
                Toggle(isOn: $settings.notifications) {
                    Text("Session notifications")
                    Text("When auto mode starts a session, or a protection stops one.")
                }
                Toggle(isOn: $settings.agentNotifications) {
                    Text("Agent notifications")
                    Text("When an agent finishes or needs you, and a recap when you come back to the Mac.")
                }
                Toggle(isOn: $settings.writtenRecap) {
                    Text("Recap written by Claude Code")
                    Text("When you come back, your own Claude Code sums up every session in a few lines. Uses a little of your Claude usage each time.")
                }
                LabeledContent {
                    Button("Write a recap now") {
                        monitor.writeRecapNow()
                        showHome()
                    }
                } label: {
                    Text("Try it")
                    Text("Sums up the last 8 hours on the Home screen.")
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
