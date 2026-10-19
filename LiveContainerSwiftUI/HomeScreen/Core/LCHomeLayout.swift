import Foundation

/// Desktop placement uses the registry's version-specific identifiers, never display names.
struct LCHomeLayout: Codable, Equatable {
    struct Folder: Codable, Equatable, Identifiable {
        var id: String
        var name: String
        var apps: [String]
    }
    var version = 2
    var order: [String] = []
    // Read v1 placements without losing formerly docked apps when switching to the grid.
    var dock: [String] = []
    var folders: [Folder] = []

    init(order: [String] = [], dock: [String] = [], folders: [Folder] = []) {
        self.order = order; self.dock = dock; self.folders = folders
    }

    private enum CodingKeys: String, CodingKey { case version, order, dock, folders }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decodeIfPresent(Int.self, forKey: .version) ?? 1
        order = try values.decodeIfPresent([String].self, forKey: .order) ?? []
        dock = try values.decodeIfPresent([String].self, forKey: .dock) ?? []
        folders = try values.decodeIfPresent([Folder].self, forKey: .folders) ?? []
    }

    func reconciled(_ available: [String]) -> LCHomeLayout {
        var result = self
        result.version = 2; result.dock = []
        let allowed = Set(available)
        var assigned = Set<String>(), folderIDs = Set<String>()
        result.folders = folders.compactMap { folder in
            guard folder.id.hasPrefix("folder:"), !allowed.contains(folder.id), folderIDs.insert(folder.id).inserted else { return nil }
            let members = folder.apps.filter { allowed.contains($0) && assigned.insert($0).inserted }
            return members.isEmpty ? nil : Folder(id: folder.id, name: folder.name, apps: members)
        }
        let folderMap = Dictionary(uniqueKeysWithValues: result.folders.map { ($0.id, $0) })
        var seen = Set<String>()
        result.order = (order + result.folders.map(\.id) + available).filter { id in
            (folderMap[id] != nil || (allowed.contains(id) && !assigned.contains(id))) && seen.insert(id).inserted
        }
        // Like SpringBoard, moving the last-but-one app out dissolves the folder.
        for folder in result.folders where folder.apps.count == 1 {
            result.order = result.order.map { $0 == folder.id ? folder.apps[0] : $0 }
        }
        result.folders.removeAll { $0.apps.count < 2 }
        return result
    }

    func rootItems(_ available: [String]) -> [String] { reconciled(available).order }

    mutating func moveItem(_ id: String, before destination: String?, in folderID: String? = nil, available: [String]) {
        self = reconciled(available)
        guard available.contains(id) || folders.contains(where: { $0.id == id }) else { return }
        if let folderID {
            guard available.contains(id), let index = folders.firstIndex(where: { $0.id == folderID }) else { return }
            // Validate the destination before removing the app from its current container.
            if let destination, destination != id, !folders[index].apps.contains(destination) { return }
        } else if let destination, destination != id, !order.contains(destination) { return }
        guard id != destination else { return }
        order.removeAll { $0 == id }
        for index in folders.indices { folders[index].apps.removeAll { $0 == id } }
        if let folderID, let index = folders.firstIndex(where: { $0.id == folderID }) {
            let position = destination.flatMap { folders[index].apps.firstIndex(of: $0) } ?? folders[index].apps.count
            folders[index].apps.insert(id, at: position)
        } else {
            order.insert(id, at: destination.flatMap { order.firstIndex(of: $0) } ?? order.count)
        }
        self = reconciled(available)
    }

    @discardableResult
    mutating func combine(_ source: String, with target: String, name: String, available: [String]) -> String? {
        self = reconciled(available)
        guard source != target, available.contains(source) else { return nil }
        if folders.contains(where: { $0.id == target }) {
            moveItem(source, before: nil, in: target, available: available)
            return target
        }
        guard available.contains(target), order.contains(target) else { return nil }
        // A drag may arrive directly from an open folder without an intermediate root drop.
        if !order.contains(source) { moveItem(source, before: target, available: available) }
        let id = "folder:" + UUID().uuidString
        let position = order.firstIndex(of: target)!
        order[position] = id
        order.removeAll { $0 == source }
        folders.append(Folder(id: id, name: name, apps: [target, source]))
        return id
    }

    mutating func moveItem(_ source: String, toSlotOf target: String, in folderID: String? = nil, available: [String]) {
        let current = reconciled(available)
        let items = folderID.flatMap { id in current.folders.first { $0.id == id }?.apps } ?? current.order
        guard let targetIndex = items.firstIndex(of: target), source != target else { return }
        let sourceIndex = items.firstIndex(of: source)
        let destination = sourceIndex.map { $0 < targetIndex } == true
            ? (targetIndex + 1 < items.count ? items[targetIndex + 1] : nil) : target
        moveItem(source, before: destination, in: folderID, available: available)
    }

    mutating func renameFolder(_ id: String, name: String) {
        let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))
        guard !trimmed.isEmpty, let index = folders.firstIndex(where: { $0.id == id }) else { return }
        folders[index].name = trimmed
    }

    func ordered(_ available: [String]) -> [String] {
        let allowed = Set(available)
        var seen = Set<String>()
        return (order + available).filter { allowed.contains($0) && seen.insert($0).inserted }
    }

    func pinned(_ available: [String], capacity: Int) -> [String] {
        let allowed = Set(available)
        var seen = Set<String>()
        return Array(dock.filter { allowed.contains($0) && seen.insert($0).inserted }.prefix(max(0, capacity)))
    }

    mutating func move(_ id: String, before destination: String, available: [String]) {
        guard id != destination, available.contains(id), available.contains(destination) else { return }
        order = ordered(available).filter { $0 != id }
        if let index = order.firstIndex(of: destination) { order.insert(id, at: index) }
    }

    mutating func toggleDock(_ id: String, available: [String], capacity: Int) {
        guard available.contains(id) else { return }
        if dock.contains(id) { dock.removeAll { $0 == id } }
        else {
            dock = pinned(available, capacity: capacity)
            if dock.count < capacity { dock.append(id) }
        }
    }
}
