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
                        Button("Retirer", role: .destructive) { awake.removeAuthorization() }
                    } else {
                        Button("Installer…") { awake.installAuthorization() }
                    }
                } label: {
                    Label(awake.isAuthorized ? "Autorisation installée" : "Autorisation requise",
                          systemImage: awake.isAuthorized ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .symbolRenderingMode(.multicolor)
                    Text("Garder le Mac éveillé capot fermé passe par pmset, qui demande les droits administrateur. L'autorisation ne couvre que cette commande.")
                }
            }

            Section("Session") {
                Picker("Durée par défaut", selection: $settings.defaultMinutes) {
                    ForEach(AppSettings.durationChoices, id: \.minutes) { Text($0.label).tag($0.minutes) }
                }
                Toggle(isOn: $settings.autoMode) {
                    Text("Mode auto")
                    Text("Garde le Mac éveillé tant qu'un agent travaille ou qu'une de ses commandes tourne, et rend la main 3 minutes après. Une session simplement ouverte ne compte pas.")
                }
            }

            Section("Protections") {
                Toggle(isOn: $settings.batteryGuard) {
                    Text("Arrêter quand la batterie est faible")
                    Text("Sur batterie uniquement. Branché, le Mac reste éveillé.")
                }
                Picker("Seuil de batterie", selection: $settings.batteryThreshold) {
                    ForEach(AppSettings.thresholdChoices, id: \.self) { Text("\($0) %").tag($0) }
                }
                .disabled(!settings.batteryGuard)
                Toggle(isOn: $settings.acOnly) {
                    Text("Seulement sur secteur")
                    Text("S'arrête dès que le chargeur est débranché.")
                }
                Toggle(isOn: $settings.thermalGuard) {
                    Text("Arrêter en cas de surchauffe")
                    Text("Capot fermé, la chaleur s'évacue moins bien.")
                }
            }

            Section("Système") {
                Toggle("Durée dans la barre des menus", isOn: $settings.showElapsedInMenuBar)
                Toggle(isOn: $settings.notifications) {
                    Text("Notifications des sessions")
                    Text("Quand le mode auto lance une session, ou qu'une protection l'arrête.")
                }
                Toggle(isOn: $settings.agentNotifications) {
                    Text("Notifications des agents")
                    Text("Quand un agent termine ou a besoin de toi, et un récapitulatif à ton retour devant le Mac.")
                }
                Toggle("Lancer à l'ouverture de session",
                       isOn: Binding(get: { awake.launchesAtLogin }, set: { awake.setLaunchesAtLogin($0) }))
            }

            Section("Mises à jour") {
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
            Button("Installer \(release.version)") { Task { await updater.install(release) } }
                .buttonStyle(.glassProminent)
        case .checking, .downloading:
            ProgressView().controlSize(.small)
        case .idle, .upToDate, .failed:
            Button("Rechercher") { Task { await updater.check() } }
        }
    }

    private var updateStatus: String {
        switch updater.status {
        case .idle: "Vérification automatique une fois par jour."
        case .checking: "Recherche d'une nouvelle version…"
        case .upToDate: "Tu as la dernière version."
        case .available(let release): "La version \(release.version) est disponible. L'installation relance Awaker et arrête la session en cours."
        case .downloading(let release): "Téléchargement de la version \(release.version)…"
        case .failed(let message): message
        }
    }
}
