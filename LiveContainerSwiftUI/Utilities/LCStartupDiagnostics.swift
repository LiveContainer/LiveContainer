import Foundation

// Synchronous by design: measure the original operation without changing its
// actor, order, or caching behavior while investigating startup hangs.
func LCStartupMeasure<T>(_ label: String, _ operation: () throws -> T) rethrows -> T {
    let span = LCStartupBegin(label)
    defer { LCStartupEnd(span) }
    return try operation()
}
