// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MeetingMuseAlt",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "MeetingMuseAlt", targets: ["MeetingMuseAlt"])
    ],
    dependencies: [
        // Swift Testing — Xcode 16+ provides this in toolchain, but plain
        // swift CLI installs sometimes lack it. Pin explicitly for portability.
        .package(url: "https://github.com/swiftlang/swift-testing.git", from: "0.10.0"),
        // M2: Whisper.cpp + CoreML
        //   .package(url: "https://github.com/ggerganov/whisper.cpp", branch: "master")
        // Pyannote diarization is wired via Apple's coremltools-exported model
        // (loaded directly with CoreML) so it requires no SPM dependency.
    ],
    targets: [
        .executableTarget(
            name: "MeetingMuseAlt",
            path: "Sources/MeetingMuseAlt",
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                // Swift 6 strict concurrency is incompatible with the
                // non-Sendable AVAudioPCMBuffer streaming pattern we use.
                // Revisit in M2 alongside the real whisper.cpp bridge.
                .swiftLanguageMode(.v5)
            ]
        ),
        .testTarget(
            name: "MeetingMuseAltTests",
            dependencies: [
                "MeetingMuseAlt",
                .product(name: "Testing", package: "swift-testing")
            ],
            path: "Tests/MeetingMuseAltTests",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
