// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DriveSync",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "DriveSync",
            resources: [.process("Resources")],
            linkerSettings: [.linkedFramework("DiskArbitration")]
        )
    ]
)
