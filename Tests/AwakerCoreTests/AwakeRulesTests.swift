import Foundation
import Testing
@testable import AwakerCore

@Suite struct AwakeSessionTests {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    @Test func totalCountsARunningSessionUntilNow() {
        let sessions = [
            AwakeSession(start: start, end: start.addingTimeInterval(3_600), trigger: .manual),
            AwakeSession(start: start.addingTimeInterval(7_200), trigger: .auto),
        ]
        #expect(sessions.totalAwakeTime(now: start.addingTimeInterval(9_000)) == 3_600 + 1_800)
    }

    @Test func anInterruptedSessionEndsWhereItWasLastSeen() {
        let lastSeen = start.addingTimeInterval(600)
        let closed = AwakeSession(start: start, trigger: .manual, lastSeen: lastSeen).closedAfterInterruption()

        #expect(closed.end == lastSeen)
        #expect(closed.endReason == .crash)
        #expect(AwakeSession(start: start, trigger: .manual).closedAfterInterruption().end == start)
    }

    @Test func sessionsSavedByEarlierVersionsStillLoad() throws {
        let json = """
        [{"id": "7F1C4E0A-6A1B-4C0E-9B5E-2B6C8D0F1A22", "start": 1000, "end": 4600, "trigger": "claude", "endReason": "claudeIdle"}]
        """
        let sessions = try JSONDecoder().decode([AwakeSession].self, from: Data(json.utf8))

        #expect(sessions.first?.trigger == .auto)
        #expect(sessions.first?.endReason == .agentsIdle)
    }
}

@Suite struct PowerPolicyTests {
    private let onBattery = BatteryInfo(percent: 12, onAC: false, charging: false)
    private let pluggedIn = BatteryInfo(percent: 12, onAC: true, charging: true)

    private func policy(acOnly: Bool = false, batteryGuard: Bool = true, thermalGuard: Bool = true) -> PowerPolicy {
        PowerPolicy(acOnly: acOnly, batteryGuard: batteryGuard, batteryThreshold: 15, thermalGuard: thermalGuard)
    }

    @Test func lowBatteryBlocksOnlyOnBattery() {
        #expect(policy().blocker(battery: onBattery, isThermalCritical: false) == .battery)
        #expect(policy().blocker(battery: pluggedIn, isThermalCritical: false) == nil)
        #expect(policy(batteryGuard: false).blocker(battery: onBattery, isThermalCritical: false) == nil)
    }

    @Test func acOnlyBlocksAsSoonAsUnplugged() {
        let charged = BatteryInfo(percent: 90, onAC: false, charging: false)
        #expect(policy(acOnly: true).blocker(battery: charged, isThermalCritical: false) == .unplugged)
        #expect(policy(acOnly: true).blocker(battery: pluggedIn, isThermalCritical: false) == nil)
    }

    @Test func overheatingBlocksWhenTheGuardIsOn() {
        #expect(policy().blocker(battery: pluggedIn, isThermalCritical: true) == .thermal)
        #expect(policy(thermalGuard: false).blocker(battery: pluggedIn, isThermalCritical: true) == nil)
        // A Mac without a battery is only subject to the thermal guard.
        #expect(policy(acOnly: true).blocker(battery: nil, isThermalCritical: false) == nil)
    }
}

@Suite struct AutoModeTests {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    private func at(_ seconds: TimeInterval) -> Date { t0.addingTimeInterval(seconds) }

    @Test func startsWhenAnAgentWorksAndOnlyIfEnabled() {
        var mode = AutoMode()
        #expect(mode.step(now: t0, isEnabled: false, busyAgents: 1, isAwake: false, isAutoSession: false) == .nothing)
        #expect(mode.step(now: t0, isEnabled: true, busyAgents: 0, isAwake: false, isAutoSession: false) == .nothing)
        #expect(mode.step(now: t0, isEnabled: true, busyAgents: 1, isAwake: false, isAutoSession: false) == .start)
    }

    @Test func stopsOnlyAfterAgentsStayIdleForTheGracePeriod() {
        var mode = AutoMode(grace: 180)
        #expect(mode.step(now: t0, isEnabled: true, busyAgents: 1, isAwake: true, isAutoSession: true) == .nothing)
        #expect(mode.step(now: at(30), isEnabled: true, busyAgents: 0, isAwake: true, isAutoSession: true) == .nothing)
        // An agent starts another turn: the countdown starts over.
        #expect(mode.step(now: at(60), isEnabled: true, busyAgents: 1, isAwake: true, isAutoSession: true) == .nothing)
        #expect(mode.step(now: at(90), isEnabled: true, busyAgents: 0, isAwake: true, isAutoSession: true) == .nothing)
        #expect(mode.step(now: at(260), isEnabled: true, busyAgents: 0, isAwake: true, isAutoSession: true) == .nothing)
        #expect(mode.step(now: at(270), isEnabled: true, busyAgents: 0, isAwake: true, isAutoSession: true) == .stop)
    }

    @Test func neverStopsASessionTheUserStarted() {
        var mode = AutoMode(grace: 180)
        _ = mode.step(now: t0, isEnabled: true, busyAgents: 0, isAwake: true, isAutoSession: false)
        #expect(mode.step(now: at(600), isEnabled: true, busyAgents: 0, isAwake: true, isAutoSession: false) == .nothing)
    }

    @Test func aManualStopHoldsUntilAgentsHaveReallyGoneQuiet() {
        var mode = AutoMode(grace: 180)
        mode.userStopped()
        // Agents keep working, with a short gap between two turns: no restart.
        #expect(mode.step(now: t0, isEnabled: true, busyAgents: 1, isAwake: false, isAutoSession: false) == .nothing)
        #expect(mode.step(now: at(30), isEnabled: true, busyAgents: 0, isAwake: false, isAutoSession: false) == .nothing)
        #expect(mode.step(now: at(60), isEnabled: true, busyAgents: 1, isAwake: false, isAutoSession: false) == .nothing)
        // They go quiet for the whole grace period: auto mode is free to start again next time.
        #expect(mode.step(now: at(90), isEnabled: true, busyAgents: 0, isAwake: false, isAutoSession: false) == .nothing)
        #expect(mode.step(now: at(280), isEnabled: true, busyAgents: 0, isAwake: false, isAutoSession: false) == .nothing)
        #expect(mode.step(now: at(310), isEnabled: true, busyAgents: 1, isAwake: false, isAutoSession: false) == .start)
    }

    @Test func startingByHandLiftsTheHold() {
        var mode = AutoMode()
        mode.userStopped()
        mode.userStarted()
        #expect(mode.step(now: t0, isEnabled: true, busyAgents: 1, isAwake: false, isAutoSession: false) == .start)
    }
}

@Suite struct FormatTests {
    @Test func durations() {
        #expect(Format.duration(59) == "0 min")
        #expect(Format.duration(45 * 60) == "45 min")
        #expect(Format.duration(2 * 3_600 + 5 * 60) == "2 h 05")
        #expect(Format.clock(65 * 60) == "1:05")
    }
}

@Suite struct AwakeReasonTests {
    private let end = Date(timeIntervalSince1970: 1_000_000)
    private let time: (Date) -> String = { _ in "14:30" }

    private func sentence(_ trigger: Trigger, endsAt: Date? = nil, busy: [String] = [], autoStopsAt: Date? = nil) -> String {
        AwakeReason(trigger: trigger, endsAt: endsAt, busyAgents: busy, autoStopsAt: autoStopsAt).sentence(time: time)
    }

    @Test func aManualSessionSaysTheUserStartedItAndUntilWhen() {
        #expect(sentence(.manual, endsAt: end) == "Started by you · until 14:30")
        #expect(sentence(.manual) == "Started by you · no time limit")
        // The agents at work are not the reason: stopping them would not let the Mac sleep.
        #expect(sentence(.manual, busy: ["Tests"]) == "Started by you · no time limit")
    }

    @Test func anAutoSessionNamesTheAgentsThatHoldTheMac() {
        #expect(sentence(.auto, busy: ["Tests"]) == "Kept awake by “Tests”")
        #expect(sentence(.auto, busy: ["Tests", "Deploy"]) == "Kept awake by “Tests” and 1 other agent")
        #expect(sentence(.auto, busy: ["Tests", "Deploy", "Docs"]) == "Kept awake by “Tests” and 2 other agents")
    }

    @Test func anAutoSessionWithNoAgentLeftSaysWhenSleepReturns() {
        #expect(sentence(.auto, autoStopsAt: end) == "No agent working · normal sleep at 14:30")
        #expect(sentence(.auto) == "No agent working · normal sleep returns soon")
    }

    @Test func autoModeKnowsWhenItWillStop() {
        var mode = AutoMode(grace: 180)
        _ = mode.step(now: end, isEnabled: true, busyAgents: 1, isAwake: true, isAutoSession: true)
        #expect(mode.stopsAt == nil)
        _ = mode.step(now: end, isEnabled: true, busyAgents: 0, isAwake: true, isAutoSession: true)
        #expect(mode.stopsAt == end.addingTimeInterval(180))
    }
}
