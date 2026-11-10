import Foundation

/// The user's protections: the conditions under which the Mac must not be kept awake.
/// One rule, used to refuse a start, to stop a running session and to tell the user why.
public struct PowerPolicy: Equatable, Sendable {
    public var acOnly: Bool
    public var batteryGuard: Bool
    public var batteryThreshold: Int
    public var thermalGuard: Bool

    public init(acOnly: Bool, batteryGuard: Bool, batteryThreshold: Int, thermalGuard: Bool) {
        self.acOnly = acOnly
        self.batteryGuard = batteryGuard
        self.batteryThreshold = batteryThreshold
        self.thermalGuard = thermalGuard
    }

    /// Why the Mac may not stay awake right now, or nil when nothing stands in the way.
    /// `battery` is nil on a Mac without one.
    public func blocker(battery: BatteryInfo?, isThermalCritical: Bool) -> EndReason? {
        if let battery, !battery.onAC {
            if acOnly { return .unplugged }
            if batteryGuard && battery.percent <= batteryThreshold { return .battery }
        }
        if thermalGuard && isThermalCritical { return .thermal }
        return nil
    }
}
