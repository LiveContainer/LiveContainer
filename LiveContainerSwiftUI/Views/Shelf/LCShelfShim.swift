//  LCShelfShim.swift
//  ShellUI (copied unchanged from S2Arm's shell/Sources/ShellUI) was written as a Swift package and reads its font,
//  art and strings through `Bundle.module`. LiveContainerSwiftUI is a framework target and has no such accessor,
//  so this points it at the framework's own bundle, where Shelf/Resources ends up.
import Foundation

private final class LCShelfBundleToken {}

extension Bundle {
    static var module: Bundle { Bundle(for: LCShelfBundleToken.self) }
}
