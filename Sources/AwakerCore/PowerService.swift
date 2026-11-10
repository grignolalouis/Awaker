import Foundation
import IOKit.ps

/// System calls: pmset through a narrow sudoers rule, and battery state.
///
/// Keeping the Mac awake with the lid closed requires `pmset -a disablesleep 1`, which needs root.
/// `installAuthorization()` adds a sudoers rule limited to exactly two commands (on / off).
public enum PowerService {
    public static let sudoersPath = "/etc/sudoers.d/awaker"
    /// Rule installed by versions named LidAwake. Still valid; removed together with the current one.
    private static let legacySudoersPath = "/etc/sudoers.d/lidawake"
    private static let pmset = "/usr/bin/pmset"
    private static let sudo = "/usr/bin/sudo"

    // MARK: Sleep

    @discardableResult
    public static func setSleepDisabled(_ disabled: Bool) -> Bool {
        Shell.run(sudo, ["-n", pmset, "-a", "disablesleep", disabled ? "1" : "0"]).succeeded
    }

    public static var isSleepDisabled: Bool {
        Shell.run(pmset, ["-g"]).output
            .split(separator: "\n")
            .first { $0.contains("SleepDisabled") }?
            .split(whereSeparator: \.isWhitespace)
            .last == "1"
    }

    /// True when sudo lets this user run the pmset command without a password. No side effect.
    public static var isAuthorized: Bool {
        Shell.run(sudo, ["-n", "-l", pmset, "-a", "disablesleep", "0"]).succeeded
    }

    // MARK: Authorization

    /// Shows the native admin prompt and installs the sudoers rule. Returns an error message, or nil.
    public static func installAuthorization() -> String? {
        let user = NSUserName()
        guard user.allSatisfy({ $0.isLetter || $0.isNumber || "_-.".contains($0) }) else {
            return "Nom d'utilisateur inattendu."
        }
        let rule = "\(user) ALL=(root) NOPASSWD: \(pmset) -a disablesleep 0, \(pmset) -a disablesleep 1"
        let script = """
        f=$(/usr/bin/mktemp) && \
        printf '%s\\n' '\(rule)' > "$f" && \
        /usr/sbin/visudo -cf "$f" && \
        /usr/sbin/chown root:wheel "$f" && \
        /bin/chmod 0440 "$f" && \
        /bin/mv "$f" \(sudoersPath)
        """
        return Shell.runAsAdministrator(script)
    }

    public static func removeAuthorization() -> String? {
        Shell.runAsAdministrator("/bin/rm -f \(sudoersPath) \(legacySudoersPath)")
    }

    // MARK: Battery

    /// Nil on a Mac without a battery.
    public static func battery() -> BatteryInfo? {
        let info = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(info).takeRetainedValue() as [CFTypeRef]
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
            let current = description[kIOPSCurrentCapacityKey] as? Int ?? 0
            let capacity = max(description[kIOPSMaxCapacityKey] as? Int ?? 100, 1)
            return BatteryInfo(
                percent: current * 100 / capacity,
                onAC: description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue,
                charging: description[kIOPSIsChargingKey] as? Bool ?? false
            )
        }
        return nil
    }
}
