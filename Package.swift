// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "LiveContainerPackageCore",
    platforms: [.macOS(.v12), .iOS(.v15)],
    products: [.library(name: "PackageCore", targets: ["PackageCore"])],
    targets: [
        .target(name: "LCArchiveBridge", path: "LiveContainerSwiftUI/PackageManager/ArchiveBridge",
                publicHeadersPath: ".", linkerSettings: [.linkedLibrary("archive")]),
        .target(name: "PackageCore", dependencies: ["LCArchiveBridge"],
                path: "LiveContainerSwiftUI/PackageManager/Core"),
        .testTarget(name: "PackageCoreTests", dependencies: ["PackageCore"], path: "Tests/PackageCoreTests",
                    resources: [.copy("Fixtures")]),
        .target(name: "HomeScreenCore", path: "LiveContainerSwiftUI/HomeScreen/Core"),
        .testTarget(name: "HomeScreenCoreTests", dependencies: ["HomeScreenCore"], path: "Tests/HomeScreenCoreTests")
    ])
