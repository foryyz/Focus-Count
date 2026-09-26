import XCTest
@testable import FocusCountCore

final class GoalSnapshotTests: XCTestCase {
    func testGoalMergeDeletionAndLegacyFiles() throws {
        let a = GoalSnapshot(name: "考试", date: Date(timeIntervalSince1970: 2000), updatedAt: Date(timeIntervalSince1970: 100))
        let b = GoalSnapshot(name: "", date: a.date, deleted: true, updatedAt: Date(timeIntervalSince1970: 101))
        XCTAssertEqual(GoalSnapshot.merge(a, b), b)
        XCTAssertEqual(GoalSnapshot.merge(b, a), b)
        XCTAssertEqual(GoalSnapshot.merge(b, b), b)
        XCTAssertEqual(GoalSnapshot.merge(a, nil), a)
        XCTAssertEqual(try RecordExchange.decode(RecordExchange.encode(Database(goal: b))).goal, b)
        XCTAssertNil(try RecordExchange.decode(RecordExchange.encode(Database())).goal)
        let bad = GoalSnapshot(name: "  ", date: Date())
        XCTAssertThrowsError(try RecordExchange.decode(RecordExchange.encode(Database(goal: bad))))
    }
    func testEqualTimestampMergeHasStableWinner() {
        let a = GoalSnapshot(name: "A", date: Date(timeIntervalSince1970: 2000), updatedAt: Date(timeIntervalSince1970: 100))
        var b = a; b.name = "B"
        XCTAssertEqual(GoalSnapshot.merge(a, b), GoalSnapshot.merge(b, a))
    }
}
