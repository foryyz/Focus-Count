import XCTest
@testable import FocusCountCore

final class TimerTransferTests: XCTestCase {
    let start = Date(timeIntervalSince1970: 1000)
    func sample(running: Bool = true, pending: Bool = false) -> TimerTransfer {
        TimerTransfer(capturedAt: start.addingTimeInterval(100), startedAt: start, accumulated: 60,
                      isRunning: running, pendingEnd: pending ? start.addingTimeInterval(90) : nil, activity: "阅读")
    }
    func testRunningTransferAndRepeatDoNotDoubleCount() throws {
        let transfer = sample()
        let arrival = start.addingTimeInterval(130)
        let phone = transfer.mobileClock(at: arrival)
        XCTAssertEqual(phone.seconds(at: arrival.addingTimeInterval(10)), 100)
        let mac = transfer.timerState(at: arrival, now: 500)
        XCTAssertEqual(mac.seconds(now: 510), 100)
        XCTAssertEqual(transfer.timerState(at: arrival.addingTimeInterval(10), now: 510).seconds(now: 510), 100)
        let decoded = try RecordExchange.decode(RecordExchange.encode(Database(timerTransfer: transfer)))
        XCTAssertTrue(decoded.timerTransfer!.isRunning)
        XCTAssertEqual(decoded.timerTransfer!.activity, "阅读")
    }
    func testPausedPendingAndIdleStayStopped() {
        let arrival = start.addingTimeInterval(300)
        for transfer in [sample(running: false), sample(running: false, pending: true)] {
            XCTAssertTrue(transfer.isValid)
            XCTAssertEqual(transfer.mobileClock(at: arrival).seconds(at: arrival.addingTimeInterval(60)), 60)
            XCTAssertFalse(transfer.timerState(at: arrival).isRunning)
            XCTAssertEqual(transfer.mobileClock(at: arrival).pendingEnd, transfer.pendingEnd)
        }
        let idle = TimerTransfer(startedAt: nil, accumulated: 0, isRunning: false, pendingEnd: nil, activity: nil)
        XCTAssertTrue(idle.isValid)
        XCTAssertNil(idle.mobileClock().startedAt)
    }
    func testInvalidSnapshotsRejectWholeImportAndLegacyStillLoads() throws {
        var bad = sample()
        bad.accumulated = -1
        XCTAssertThrowsError(try RecordExchange.decode(RecordExchange.encode(Database(timerTransfer: bad))))
        bad = sample(); bad.pendingEnd = start.addingTimeInterval(90)
        XCTAssertFalse(bad.isValid)
        bad = sample(); bad.accumulated = 200
        XCTAssertFalse(bad.isValid)
        bad = sample(); bad.startedAt = nil
        XCTAssertFalse(bad.isValid)
        XCTAssertNil(try RecordExchange.decode(RecordExchange.encode(Database())).timerTransfer)
    }
}
