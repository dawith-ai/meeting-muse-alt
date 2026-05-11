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
        // M2.1: WhisperKit — argmaxinc 의 pure-Swift wrapper.
        //   whisper.cpp + CoreML 인코더를 SPM 친화적인 형태로 패키징했고,
        //   모델 다운로드/캐시까지 처리한다. macOS 13+ / iOS 16+ 지원.
        //   기본 모델은 첫 사용 시 Hugging Face 에서 자동 다운로드되며
        //   `~/Documents/huggingface/` 에 캐시된다.
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.9.0"),
        // Pyannote diarization is wired via Apple's coremltools-exported model
        // (loaded directly with CoreML) so it requires no SPM dependency.
    ],
    targets: [
        .executableTarget(
            name: "MeetingMuseAlt",
            dependencies: [
                .product(name: "WhisperKit", package: "WhisperKit"),
            ],
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
