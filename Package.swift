// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "BatteryLens",
    platforms: [.macOS(.v11)],
    products: [
        .library(name: "BatteryDomain", targets: ["BatteryDomain"]),
        .library(name: "BatteryPersistence", targets: ["BatteryPersistence"]),
        .library(name: "BatteryDiscovery", targets: ["BatteryDiscovery"]),
        .library(name: "BatteryAlerts", targets: ["BatteryAlerts"]),
        .library(name: "BatteryPeers", targets: ["BatteryPeers"]),
    ],
    targets: [
        .target(name: "BatteryDomain", path: "Packages/BatteryCore/Sources/BatteryDomain"),
        .target(
            name: "BatteryPersistence",
            dependencies: ["BatteryDomain"],
            path: "Packages/BatteryCore/Sources/BatteryPersistence",
            linkerSettings: [.linkedLibrary("sqlite3"), .linkedFramework("Security")]
        ),
        .target(
            name: "BatteryDiscovery",
            dependencies: ["BatteryDomain", "BatteryPersistence"],
            path: "Packages/BatteryCore/Sources/BatteryDiscovery",
            linkerSettings: [
                .linkedFramework("CoreBluetooth"),
                .linkedFramework("IOKit"),
            ]
        ),
        .target(
            name: "BatteryAlerts",
            dependencies: ["BatteryDomain"],
            path: "Packages/BatteryCore/Sources/BatteryAlerts"
        ),
        .target(
            name: "BatteryPeers",
            dependencies: ["BatteryDomain"],
            path: "Packages/BatteryCore/Sources/BatteryPeers",
            linkerSettings: [
                .linkedFramework("CryptoKit"),
                .linkedFramework("MultipeerConnectivity"),
            ]
        ),
        .testTarget(
            name: "BatteryDomainTests",
            dependencies: ["BatteryDomain", "BatteryDiscovery"],
            path: "Packages/BatteryCore/Tests/BatteryDomainTests"
        ),
        .testTarget(
            name: "BatteryAlertsTests",
            dependencies: ["BatteryAlerts", "BatteryDomain"],
            path: "Packages/BatteryCore/Tests/BatteryAlertsTests"
        ),
        .testTarget(
            name: "BatteryPeersTests",
            dependencies: ["BatteryPeers", "BatteryDomain"],
            path: "Packages/BatteryCore/Tests/BatteryPeersTests"
        ),
        .testTarget(
            name: "BatteryPersistenceTests",
            dependencies: ["BatteryPersistence", "BatteryDomain"],
            path: "Packages/BatteryCore/Tests/BatteryPersistenceTests"
        ),
    ]
)
