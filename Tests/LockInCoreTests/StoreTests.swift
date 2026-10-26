import Foundation
import Testing
@testable import LockInCore

private func tempFile(_ name: String) -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("lockin-tests-\(UUID().uuidString)")
        .appendingPathComponent(name)
}

struct StatsStoreTests {
    @Test func aggregatesTodayAndPersists() throws {
        let url = tempFile("sessions.jsonl")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let now = Date()
        let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: now)!

        let store = StatsStore(url: url, now: now)
        store.append(Session(start: now, end: now, focusedSeconds: 3000, intention: "a", completed: true))
        store.append(Session(start: now, end: now, focusedSeconds: 600, intention: "b", completed: false))
        store.append(Session(start: yesterday, end: yesterday, focusedSeconds: 1500, intention: "c", completed: true))

        let reloaded = StatsStore(url: url, now: now)
        #expect(reloaded.sessions.count == 3)
        #expect(reloaded.focusedSeconds(on: now) == 3600)
        #expect(reloaded.completedBlocks(on: now) == 1)
        let week = reloaded.dailyTotals(days: 7, endingOn: now)
        #expect(week.count == 7)
        #expect(week.map(\.seconds).suffix(2) == [1500, 3600])
    }
}

struct BlocklistTests {
    @Test func matchesAppsByNameOrBundleID() {
        let apps = ["Slack", "discord", "com.apple.mail"]
        #expect(Blocklist.isBlocked(appName: "Discord", bundleID: "com.hnc.Discord", list: apps))
        #expect(Blocklist.isBlocked(appName: "Mail", bundleID: "com.apple.mail", list: apps))
        #expect(!Blocklist.isBlocked(appName: "Xcode", bundleID: "com.apple.dt.Xcode", list: apps))
    }

    @Test func parsesFileSkippingComments() {
        #expect(BlocklistFile.parse("# hi\n Slack \n\n# Mail\nDiscord\n") == ["Slack", "Discord"])
        #expect(BlocklistFile.parse(BlocklistFile.defaultText).contains("Slack"))
    }
}

struct ParkingLotTests {
    @Test func appendsAndCountsOpenItems() throws {
        let url = tempFile("parking-lot.md")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let lot = ParkingLot(url: url)
        try lot.append("email Sam about invoice")
        try lot.append("   ")
        try lot.append("look up SMAppService docs")
        #expect(lot.openCount() == 2)
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.hasPrefix("# Parking lot"))
        #expect(text.contains("email Sam about invoice"))
    }

    @Test func ensureExistsCreatesEmptyLot() throws {
        let url = tempFile("parking-lot.md")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let lot = ParkingLot(url: url)
        _ = lot.ensureExists()
        #expect(lot.openCount() == 0)
        try lot.append("first thought")
        #expect(lot.openCount() == 1)
    }
}

struct SettingsTests {
    @Test func decodesOldPayloadWithDefaults() throws {
        let s = try JSONDecoder().decode(FocusSettings.self, from: Data(#"{"focusMinutes": 25, "mode": "flow"}"#.utf8))
        #expect(s.focusMinutes == 25 && s.mode == .flow && s.shortBreakMinutes == 10 && s.secondsPerMinute == 60)
    }
}
