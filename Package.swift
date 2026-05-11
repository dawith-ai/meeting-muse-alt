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
        //
        // 통합 보류 사유 (M2.1 조사 결과):
        //   - whisper.cpp 의 upstream Package.swift 는 GGML 백엔드 빌드 시
        //     cSettings(.define("GGML_USE_ACCELERATE"), .unsafeFlags(...)) 및
        //     linkerSettings(.linkedFramework("Accelerate"), .linkedFramework("CoreML")) 가
        //     필요합니다. SPM `unsafeFlags` 는 traveling dependency 로 사용 불가하므로,
        //     로컬 fork 또는 binaryTarget(.xcframework) 래퍼가 선행돼야 합니다.
        //   - CoreML 인코더(`ggml-base-encoder.mlmodelc`) 는 coremltools 로 별도 생성 후
        //     Application Support/MeetingMuseAlt/Models/ 에 사용자 단위로 배치합니다.
        //   - 후속 PR (M2.2) 에서 위 두 항목을 해결한 뒤 의존성 활성화 + FFI bridge 연결.
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
