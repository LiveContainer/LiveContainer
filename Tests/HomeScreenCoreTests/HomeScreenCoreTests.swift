import Foundation
import XCTest
@testable import HomeScreenCore

final class HomeScreenCoreTests: XCTestCase {
    func testV1MigrationReturnsDockedAppsToGrid() throws {
        let old = Data(#"{"version":1,"order":["b","a"],"dock":["c"]}"#.utf8)
        let migrated = try JSONDecoder().decode(LCHomeLayout.self, from: old).reconciled(["a", "b", "c"])
        XCTAssertEqual(migrated.version, 2)
        XCTAssertEqual(migrated.order, ["b", "a", "c"])
        XCTAssertTrue(migrated.dock.isEmpty)
    }
    func testFolderCreationRoundTripAndRename() throws {
        var layout = LCHomeLayout(order: ["a", "b", "c"])
        let id = try XCTUnwrap(layout.combine("a", with: "b", name: "Utilities", available: ["a", "b", "c"]))
        layout.renameFolder(id, name: "  Tools  ")
        let restored = try JSONDecoder().decode(LCHomeLayout.self, from: JSONEncoder().encode(layout))
        XCTAssertEqual(restored.folders.first?.apps, ["b", "a"])
        XCTAssertEqual(restored.folders.first?.name, "Tools")
        XCTAssertEqual(restored.rootItems(["a", "b", "c"]), [id, "c"])
    }
    func testFolderRemainsUntilItsLastAppIsMovedOut() throws {
        var layout = LCHomeLayout()
        let id = try XCTUnwrap(layout.combine("a", with: "b", name: "Folder", available: ["a", "b", "c"]))
        layout.moveItem("c", before: nil, in: id, available: ["a", "b", "c"])
        layout.moveItem("a", before: nil, available: ["a", "b", "c"])
        XCTAssertEqual(layout.folders.first?.apps, ["b", "c"])
        layout.moveItem("b", before: "a", available: ["a", "b", "c"])
        XCTAssertEqual(layout.folders.first?.apps, ["c"])
        XCTAssertTrue(layout.rootItems(["a", "b", "c"]).contains(id))
        layout.moveItem("c", before: nil, available: ["a", "b", "c"])
        XCTAssertTrue(layout.folders.isEmpty)
        XCTAssertEqual(Set(layout.rootItems(["a", "b", "c"])), Set(["a", "b", "c"]))
    }
    func testUninstallAndDuplicateFolderMembershipAreReconciled() {
        let layout = LCHomeLayout(folders: [.init(id: "folder:one", name: "One", apps: ["a", "b", "b", "removed"]),
                                          .init(id: "folder:two", name: "Two", apps: ["a", "c"])])
        let result = layout.reconciled(["a", "b", "c"])
        XCTAssertEqual(result.folders.count, 2)
        XCTAssertEqual(result.folders[0].apps, ["a", "b"])
        XCTAssertEqual(result.folders[1].apps, ["c"])
        XCTAssertEqual(result.rootItems(["a", "b", "c"]), ["folder:one", "folder:two"])
    }
    func testCannotNestFolderOrMoveToMissingTarget() throws {
        var layout = LCHomeLayout()
        let id = try XCTUnwrap(layout.combine("a", with: "b", name: "Folder", available: ["a", "b", "c"]))
        let saved = layout
        layout.moveItem("c", before: "missing", in: id, available: ["a", "b", "c"])
        layout.moveItem(id, before: nil, in: id, available: ["a", "b", "c"])
        XCTAssertEqual(layout, saved)
    }
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
    func testDragAdvancesIntoAdjacentSlotInBothDirections() {
        var layout = LCHomeLayout(order: ["a", "b", "c"])
        layout.moveItem("a", toSlotOf: "b", available: ["a", "b", "c"])
        XCTAssertEqual(layout.order, ["b", "a", "c"])
        layout.moveItem("c", toSlotOf: "a", available: ["a", "b", "c"])
        XCTAssertEqual(layout.order, ["b", "c", "a"])
    }
    func testDirectFolderToFolderDragAndSnapshotRestore() throws {
        let available = ["a", "b", "c", "d", "e"]
        let original = LCHomeLayout(order: ["folder:one", "folder:two"], folders: [
            .init(id: "folder:one", name: "One", apps: ["a", "b", "e"]),
            .init(id: "folder:two", name: "Two", apps: ["c", "d"])])
        var moved = original
        moved.moveItem("a", toSlotOf: "d", in: "folder:two", available: available)
        XCTAssertEqual(moved.folders[0].apps, ["b", "e"])
        XCTAssertEqual(moved.folders[1].apps, ["c", "a", "d"])
        let restored = try JSONDecoder().decode(LCHomeLayout.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(restored.reconciled(available), original)
    }
    func testDragFromFolderCanCreateNewFolderWithoutIntermediateDrop() throws {
        let available = ["a", "b", "c", "d"]
        var layout = LCHomeLayout(order: ["folder:one", "d"], folders: [
            .init(id: "folder:one", name: "One", apps: ["a", "b", "c"])])
        let newID = try XCTUnwrap(layout.combine("a", with: "d", name: "New", available: available))
        XCTAssertEqual(layout.folders.first { $0.id == newID }?.apps, ["d", "a"])
        XCTAssertEqual(layout.folders.first { $0.id == "folder:one" }?.apps, ["b", "c"])
        XCTAssertEqual(layout.folders.flatMap(\.apps).sorted(), available.sorted())
    }
}
