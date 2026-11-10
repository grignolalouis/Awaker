import AwakerCore
import Foundation
import ServiceManagement

/// Everything the app does to the machine, behind one value: sleep, authorization, login item.
/// Snapshots and previews get `.inert`, which touches nothing, so no call can reach pmset or sudo by accident.
struct SystemControl {
    var isAuthorized: () -> Bool
    /// Returns nil on success, or what went wrong.
    var installAuthorization: () -> String?
    var removeAuthorization: () -> String?
    /// Returns false when the system refused.
    var setSleepDisabled: (Bool) -> Bool
    var isSleepDisabled: () -> Bool
    var battery: () -> BatteryInfo?
    var launchesAtLogin: () -> Bool
    var setLaunchesAtLogin: (Bool) throws -> Void

    static let live = SystemControl(
        isAuthorized: { PowerService.isAuthorized },
        installAuthorization: PowerService.installAuthorization,
        removeAuthorization: PowerService.removeAuthorization,
        setSleepDisabled: PowerService.setSleepDisabled,
        isSleepDisabled: { PowerService.isSleepDisabled },
        battery: PowerService.battery,
        launchesAtLogin: { SMAppService.mainApp.status == .enabled },
        setLaunchesAtLogin: { enabled in
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        }
    )

    /// Looks set up and does nothing. Reading the battery is harmless, so it stays real.
    static let inert = SystemControl(
        isAuthorized: { true },
        installAuthorization: { nil },
        removeAuthorization: { nil },
        setSleepDisabled: { _ in true },
        isSleepDisabled: { false },
        battery: PowerService.battery,
        launchesAtLogin: { false },
        setLaunchesAtLogin: { _ in }
    )
}
