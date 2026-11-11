// swift-tools-version: 6.0
import PackageDescription

let macOnly: [Platform] = [.macOS]
let linuxOnly: [Platform] = [.linux]

let package = Package(
    name: "CarbonMirror",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "CarbonMirror", targets: ["CarbonMirrorApp"]),
    ],
    targets: [
        .systemLibrary(name: "CarbonCoreC", path: "rust/include"),
        .target(
            name: "CMCoreBridge",
            dependencies: ["CarbonCoreC"],
            linkerSettings: [
                // Full path to the static archive: with `-l`, the linker would pick the cdylib (.dylib/.so) built beside it.
                .unsafeFlags(["rust/target/aarch64-apple-darwin/release/libcarbon_core.a"], .when(platforms: macOnly)),
                .unsafeFlags(["rust/target/release/libcarbon_core.a"], .when(platforms: linuxOnly)),
                .linkedFramework("Security", .when(platforms: macOnly)),
                .linkedLibrary("gcc_s", .when(platforms: linuxOnly)),
                .linkedLibrary("util", .when(platforms: linuxOnly)),
                .linkedLibrary("rt", .when(platforms: linuxOnly)),
                .linkedLibrary("pthread", .when(platforms: linuxOnly)),
                .linkedLibrary("m", .when(platforms: linuxOnly)),
                .linkedLibrary("dl", .when(platforms: linuxOnly)),
            ]
        ),
        .target(name: "CMCore", dependencies: ["CMCoreBridge"]),
        .target(name: "CMSecurity", dependencies: ["CMCore", "CMCoreBridge"]),
        .target(name: "CMTransport", dependencies: ["CMCore", "CMCoreBridge", "CMSecurity"]),
        .target(name: "CMMedia", dependencies: ["CMCore"]),
        .target(name: "CMInput", dependencies: ["CMCore"]),
        .target(name: "CMUI", dependencies: ["CMCore", "CMCoreBridge", "CMTransport", "CMMedia", "CMInput", "CMSecurity"]),
        .executableTarget(name: "CarbonMirrorApp", dependencies: ["CMUI", "CMCore", "CMTransport"]),
        .testTarget(
            name: "CMTests",
            dependencies: ["CMCore", "CMCoreBridge", "CMTransport"],
            exclude: ["Fixtures"]
        ),
    ]
)
