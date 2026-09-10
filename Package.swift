// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "MacBookDuo", platforms: [.macOS(.v14)], targets: [
.executableTarget(name: "MacBookDuo", swiftSettings: [.defaultIsolation(MainActor.self), .enableUpcomingFeature("NonisolatedNonsendingByDefault")])
])
