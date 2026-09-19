import XCTest
@testable import SwitchingCore
final class SwitchingSessionTests: XCTestCase {
    func testNaturalRing() {
        var session = SwitchingSession(windowCounts: [1, 3, 1, 2])!
        var actual: [String] = []
        for _ in 0..<8 { actual.append("\(session.app):\(session.window)"); session.advance() }
        XCTAssertEqual(actual, ["1:0", "1:1", "1:2", "2:0", "3:0", "3:1", "0:0", "1:0"])
    }
    func testWindowlessAppsAndSingleApp() {
        var session = SwitchingSession(windowCounts: [0, 0])!
        XCTAssertEqual(session.app, 1); session.advance(); XCTAssertEqual(session.app, 0)
        var single = SwitchingSession(windowCounts: [3])!
        XCTAssertEqual(single.window, 1)
        single.advance(); XCTAssertEqual(single.window, 2)
        single.advance(); XCTAssertEqual(single.window, 0)
    }
    func testInvalidAndForegroundIndex() {
        XCTAssertNil(SwitchingSession(windowCounts: []))
        XCTAssertNil(SwitchingSession(windowCounts: [-1]))
        XCTAssertNil(SwitchingSession(windowCounts: [1], currentApp: 2))
        XCTAssertEqual(SwitchingSession(windowCounts: [1, 2, 3], currentApp: 1)?.app, 1)
    }
}

extension SwitchingSessionTests {
    func testEveryEntryVisitedExactlyOnceAcrossVaryingCounts() {
        for counts in [[0], [1], [7], [0, 3, 0, 2], [8, 1, 4, 0, 2]] {
            for foreground in counts.indices {
                var session = SwitchingSession(windowCounts: counts, currentApp: foreground)!
                let initial = session
                var visited = Set<String>()
                for _ in 0..<counts.reduce(0, { $0 + max(1, $1) }) {
                    XCTAssertTrue(visited.insert("\(session.app):\(session.window)").inserted)
                    XCTAssertTrue(counts.indices.contains(session.app))
                    XCTAssertLessThan(session.window, max(1, counts[session.app]))
                    session.advance()
                }
                XCTAssertEqual(session, initial)
            }
        }
    }
    func testSessionDoesNotChangeWhenDiscoveryChanges() {
        var counts = [1, 3, 2]
        var session = SwitchingSession(windowCounts: counts)!
        counts[1] = 0
        session.advance(); session.advance()
        XCTAssertEqual(session.app, 1)
        XCTAssertEqual(session.window, 2)
        XCTAssertEqual(session.counts, [1, 3, 2])
    }
}


extension SwitchingSessionTests {
    func testCurrentAppWindowsComeBeforeNextApp() {
        var session = SwitchingSession(windowCounts: [3, 2, 1])!
        var visits: [String] = []
        for _ in 0..<7 { visits.append("\(session.app):\(session.window)"); session.advance() }
        XCTAssertEqual(visits, ["0:1", "0:2", "1:0", "1:1", "2:0", "0:0", "0:1"])
    }
    func testCurrentAppAtEndFinishesWindowsBeforeWrapping() {
        var session = SwitchingSession(windowCounts: [1, 1, 3], currentApp: 2)!
        XCTAssertEqual(session.app, 2); XCTAssertEqual(session.window, 1)
        session.advance(); XCTAssertEqual(session.app, 2); XCTAssertEqual(session.window, 2)
        session.advance(); XCTAssertEqual(session.app, 0); XCTAssertEqual(session.window, 0)
    }
    func testOnlyPlainCommandTabIsOwned() {
        // Includes Command+grave (50), Escape (53), all arrows, app shortcuts,
        // and combinations such as Shift+Command+Tab and Control+Tab.
        for key in Int64(0)...127 {
            for modifiers in 0..<16 {
                XCTAssertEqual(ShortcutPolicy.handles(keyCode: key, command: modifiers & 1 != 0,
                    shift: modifiers & 2 != 0, control: modifiers & 4 != 0, option: modifiers & 8 != 0),
                    key == 48 && modifiers == 1, "key \(key), modifiers \(modifiers)")
            }
        }
    }
}
