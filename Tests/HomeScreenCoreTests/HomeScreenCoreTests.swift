import Foundation
import XCTest
@testable import HomeScreenCore

final class HomeScreenCoreTests: XCTestCase {
    func testInventoryReconcilesWithoutDuplicatesOrStaleIcons() {
        let layout = LCHomeLayout(order: ["old", "b", "b", "a"], dock: ["old", "b", "b", "c"])
        XCTAssertEqual(layout.ordered(["a", "b", "c", "d"]), ["b", "a", "c", "d"])
        XCTAssertEqual(layout.pinned(["a", "b", "c", "d"], capacity: 4), ["b", "c"])
        XCTAssertEqual(layout.pinned(["a", "b", "c", "d"], capacity: 1), ["b"])
    }
    func testReorderingSurvivesEncodingAndNewInstall() throws {
        var layout = LCHomeLayout()
        layout.move("c", before: "a", available: ["a", "b", "c"])
        let restored = try JSONDecoder().decode(LCHomeLayout.self, from: JSONEncoder().encode(layout))
        XCTAssertEqual(restored.ordered(["a", "b", "c", "new"]), ["c", "a", "b", "new"])
    }
    func testDockCapacityAndUnpinDoNotLoseApps() {
        var layout = LCHomeLayout()
        layout.toggleDock("a", available: ["a", "b"], capacity: 1)
        layout.toggleDock("b", available: ["a", "b"], capacity: 1)
        XCTAssertEqual(layout.dock, ["a"])
        layout.toggleDock("a", available: ["a", "b"], capacity: 1)
        XCTAssertTrue(layout.dock.isEmpty)
        XCTAssertEqual(layout.ordered(["a", "b"]), ["a", "b"])
    }
    func testDuplicateVersionsKeepIndependentPlacement() {
        var layout = LCHomeLayout()
        let versions = ["com.example.app:first.app", "com.example.app:second.app"]
        layout.toggleDock(versions[1], available: versions, capacity: 4)
        XCTAssertEqual(layout.pinned(versions, capacity: 4), [versions[1]])
        XCTAssertEqual(layout.ordered(versions), versions)
    }
    func testUnknownDragCannotEnterLayout() {
        var layout = LCHomeLayout()
        layout.move("outside", before: "a", available: ["a", "b"])
        layout.toggleDock("outside", available: ["a", "b"], capacity: 4)
        XCTAssertEqual(layout, LCHomeLayout())
    }
}
