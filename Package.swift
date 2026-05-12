// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MeetingMuseAlt",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "MeetingMuseAlt", targets: ["MeetingMuseAlt"]),
        .executable(name: "WhisperKitProbe", targets: ["WhisperKitProbe"]),
        .executable(name: "LLMProbe", targets: ["LLMProbe"])
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
        // 자동 업데이트 — Sparkle 2.x (EdDSA 서명, macOS 10.13+).
        // GitHub Releases 에 올라간 .dmg + appcast.xml 을 폴링해 사용자에게
        // "업데이트 가능" 다이얼로그 표시.
        .package(url: "https://github.com/sparkle-project/Sparkle.git", from: "2.6.0"),
        // M3.1: 로컬 LLM 은 Apple `FoundationModels` (macOS 15.1+ Apple Intelligence)
        //   를 사용합니다. 외부 SPM 패키지 의존성 없이 시스템 모델로 추론하므로
        //   빌드 안정성/의존성 충돌이 없습니다.
        //
        //   ※ 평가 후 보류한 대안:
        //     - `mlx-swift-examples` 2.0.0 — `Libraries/MLXLLM/SwitchLayers.swift:128`
        //       optional 미언랩핑으로 Swift 6.3 빌드 실패.
        //     - `mlx-swift-examples` main — `MLXLLM` product 제거됨 (MNIST/StableDiffusion 만 노출).
        //     - `LLM.swift` (eastriverlee) — 레포 부재 (404).
        //     - `whisperkit` main + `mlx-swift-examples` main — `swift-transformers` 충돌.
        // Pyannote diarization is wired via Apple's coremltools-exported model
        // (loaded directly with CoreML) so it requires no SPM dependency.
    ],
    targets: [
        .executableTarget(
            name: "MeetingMuseAlt",
            dependencies: [
                .product(name: "WhisperKit", package: "WhisperKit"),
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Sources/MeetingMuseAlt",
            exclude: [
                // xcodegen 이 자동 생성하는 Info.plist 는 Xcode 빌드 전용으로,
                // SPM 리소스 번들에 포함하면 top-level Info.plist 충돌이 발생한다.
                "Resources/Info.plist",
                // entitlements 도 Xcode 빌드 전용 — SPM 빌드는 코드사인 안 함.
                "Resources/MeetingMuseAlt.entitlements",
            ],
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
        .executableTarget(
            name: "LLMProbe",
            dependencies: [],
            path: "Sources/LLMProbe",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        ),
        .executableTarget(
            name: "WhisperKitProbe",
            dependencies: [
                .product(name: "WhisperKit", package: "WhisperKit"),
            ],
            path: "Sources/WhisperKitProbe",
            swiftSettings: [
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
