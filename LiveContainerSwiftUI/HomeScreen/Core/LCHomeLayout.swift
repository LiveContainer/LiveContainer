import Foundation

/// Desktop placement uses the registry's version-specific identifiers, never display names.
struct LCHomeLayout: Codable, Equatable {
    var version = 1
    var order: [String] = []
    var dock: [String] = []

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
