import Foundation
import Testing
@testable import LockInCore

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
private func at(_ minutes: Double) -> Date { t0.addingTimeInterval(minutes * 60) }

struct TimerEngineTests {
    var settings = FocusSettings()

    @Test func fixedCycleOffersLongBreakAfterThirdBlock() {
        var e = TimerEngine()
        var clock = 0.0
        for block in 1...3 {
            e.startFocus(intention: " write spec ", settings: settings, now: at(clock))
            #expect(e.tick(now: at(clock + 49), settings: settings) == nil)
            clock += 50
            guard case .focusEnded(let s) = e.tick(now: at(clock), settings: settings) else {
                Issue.record("focus should end"); return
            }
            #expect(s.completed && s.focusedSeconds == 50 * 60 && s.intention == "write spec")
            #expect(e.phase == .breakReady(block == 3 ? .long : .short))
            #expect(e.pendingBreak == (block == 3 ? 20 : 10) * 60)
            e.startBreak(now: at(clock))
            clock += block == 3 ? 20 : 10
            #expect(e.tick(now: at(clock), settings: settings) == .breakEnded)
            #expect(e.phase == .idle)
        }
        #expect(e.completedInCycle == 0)
    }

    @Test func pauseExcludesPausedTimeAndRewindsToPast() {
        var e = TimerEngine()
        e.startFocus(intention: "", settings: settings, now: at(0))
        e.pause(at: at(10))
        e.resume(now: at(30))
        #expect(e.elapsed(at: at(40)).rounded() == 20 * 60)
        // Idle detection: pause effective 5 minutes before it was noticed.
        e.pause(at: at(35))
        #expect(e.elapsed(at: at(60)).rounded() == 15 * 60)
        #expect(e.isPaused)
    }

    @Test func extendAddsToTarget() {
        var e = TimerEngine()
        e.startFocus(intention: "", settings: settings, now: at(0))
        e.extend(by: 5 * 60)
        #expect(e.tick(now: at(50), settings: settings) == nil)
        #expect(e.remaining(at: at(50))?.rounded() == 300.0)
    }

    @Test func keepGoingLogsOvertimeWithoutCountingABlock() {
        var e = TimerEngine()
        e.startFocus(intention: "x", settings: settings, now: at(0))
        _ = e.tick(now: at(50), settings: settings)
        e.keepGoing(for: 5 * 60, now: at(51))
        guard case .focusEnded(let s) = e.tick(now: at(56), settings: settings) else {
            Issue.record("extension should end"); return
        }
        #expect(!s.completed && s.focusedSeconds == 5 * 60)
        #expect(e.phase == .breakReady(.short))
        #expect(e.completedInCycle == 1)
    }

    @Test func flowtimeBreakScalesWithFocus() {
        var flow = settings
        flow.mode = .flow
        var e = TimerEngine()

        e.startFocus(intention: "", settings: flow, now: at(0))
        #expect(e.remaining(at: at(500)) == nil)
        guard case .focusEnded(let s) = e.stopFocus(now: at(40), settings: flow) else {
            Issue.record("flow should end"); return
        }
        #expect(s.completed && e.phase == .breakReady(.short) && e.pendingBreak == 8 * 60)

        e.skipBreak()
        e.startFocus(intention: "", settings: flow, now: at(100))
        _ = e.stopFocus(now: at(105), settings: flow)
        #expect(e.pendingBreak == 3 * 60)

        e.skipBreak()
        e.startFocus(intention: "", settings: flow, now: at(200))
        guard case .focusEnded(let tiny) = e.stopFocus(now: at(200.5), settings: flow) else { return }
        #expect(!tiny.completed && e.phase == .idle)
    }

    @Test func fixedStopEndsEarlyWithoutBreak() {
        var e = TimerEngine()
        e.startFocus(intention: "", settings: settings, now: at(0))
        guard case .focusEnded(let s) = e.stopFocus(now: at(20), settings: settings) else { return }
        #expect(!s.completed && s.focusedSeconds == 20 * 60 && e.phase == .idle)
    }

    @Test func survivesCodableRoundTrip() throws {
        var e = TimerEngine()
        e.startFocus(intention: "persist me", settings: settings, now: at(0))
        let back = try JSONDecoder().decode(TimerEngine.self, from: JSONEncoder().encode(e))
        #expect(back == e)
        #expect(back.remaining(at: at(10))?.rounded() == 2400.0)
    }
}
