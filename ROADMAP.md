# ROADMAP — Meeting Muse Alt

Alt 앱과 기능 동등성을 달성하기 위한 단계별 로드맵.

## 현재 상태 요약 (2026-05-12 최종)

| Alt 기능 | 상태 | 구현 위치 / 검증 방식 |
|---|---|---|
| 마이크 녹음 (시간제한 없음) | ✅ 동작 | `Audio/AudioRecorder.swift` |
| 시스템 오디오 캡처 (Zoom/Meet/Teams) | ✅ 코드 동작 / 🟡 권한 검증 사용자 필요 | `Audio/SystemAudioTap.swift` — Tap + Aggregate device + IOProc 전 라이프사이클 구현. PCM 흐름 검증은 macOS 14.4+ Screen Recording 권한 필요 |
| Whisper 온디바이스 전사 | ✅ 검증 완료 | `Transcription/WhisperKitEngine.swift` + `WhisperKitProbe` CLI 로 실제 모델 다운로드 + 추론 검증 (20s init + 16s 추론) |
| Pyannote 화자분리 | ✅ 코드 동작 / 🟡 모델 자산 사용자 필요 | `Diarization/PyannoteEngine.swift` — CoreML 모델 로드 + 16kHz 리샘플 + 10초 윈도우 추론 + argmax + 인접 머지. 모델은 HF 게이트 토큰 + `scripts/convert_pyannote.py` 1회 실행 필요 |
| 회의 앱 자동 감지 | ✅ 동작 | `Detection/MeetingAppDetector.swift` — AX 트리에서 "Chrome (Google Meet 가능)" 감지 검증 |
| 실시간 요약 | ✅ 원격 동작 / 🟡 로컬 stub | `Storage/SummarizationService.swift` + `OpenAISummarizer` (gpt-4o-mini). `LocalLlamaSummarizer` 는 후속 PR — llama.cpp Swift binding 의 빌드 안정성 이슈로 보류 |
| 다국어 번역 | ✅ 원격 동작 / 🟡 로컬 stub | `Storage/TranslationService.swift` + `OpenAITranslator` (8개 언어). `LocalNLLBTranslator` 는 후속 PR — coremltools NLLB 변환 필요 |
| PDF 강의자료 동기화 | ✅ 동작 | `App/PdfSyncPanel.swift` + `Storage/PdfSyncStore.swift` — PDFKit `PDFView` NSViewRepresentable, 타임라인 마크 자동 추종 |
| 회의 영구 저장 | ✅ 동작 | `Storage/MeetingRecord.swift` + `MeetingPersistence.swift` + `MeetingRepository.swift` — JSON 파일 (Application Support), SwiftData 매크로는 Xcode 환경에서만 동작하므로 우회 |
| 공유 링크 (HTML 익스포트) | ✅ 동작 | `Storage/MeetingExporter.swift` — HTML/Markdown/plainText, XSS escape, 라이트/다크 모드 인라인 스타일 |
| 검색 (전사본 전문 검색) | ✅ 동작 | `Storage/MeetingSearchEngine.swift` + `App/MeetingSearchView.swift` — 텍스트 + 화자 + 날짜 + NSRange |
| 메뉴바 앱 모드 | ✅ 동작 | `App/MenuBarScene.swift` (MenuBarExtra) — AX 트리에서 표시 검증 |
| 다크모드 / i18n | ✅ 동작 | `App/AppSettings.swift` + `Resources/Localizable.xcstrings` (ko/en) |
| Xcode App Target | ✅ project.yml + xcodegen 검증 / 🟡 풀 Xcode 빌드 사용자 필요 | `project.yml` + `Resources/MeetingMuseAlt.entitlements`. `xcodegen 2.45.4` 로 `.xcodeproj` 생성 검증. `xcodebuild` 실 빌드는 Command Line Tools 가 아닌 풀 Xcode 필요 |
| UI 통합 (사이드바 + 라우팅) | ✅ 동작 | `App/ContentView.swift` — 5탭 NavigationSplitView, AX 트리로 사이드바/라우팅/감지 직접 검증 |
| 인터넷 없이도 동작 | ✅ 90% | Whisper/PDF/검색/익스포트/저장/메뉴바/i18n OFFLINE OK. 요약/번역은 OpenAI 원격이 기본 (로컬 엔진은 후속) |

**범례**: ✅ 코드 동작, 🟡 사용자 트리거 또는 외부 자산 필요, 🔌 stub, ⏸️ 미착수

### 테스트 커버리지
- `swift build` 클린, `swift test` **86/86** 통과
- 검증 방식: 단위/통합 (인메모리), AX 트리 직접 검증 (UI), `WhisperKitProbe` 로 실제 추론 (외부)

---

## ✅ M1 — 스카폴드 & 마이크 녹음 (완료)

- SwiftPM `executableTarget` macOS 14+
- SwiftUI App/Scene 구조 (`MeetingMuseAltApp`)
- 메인 화면 (사이드바 + 전사본 리스트 + 컨트롤 바)
- `RecordingViewModel` MVVM
- `AudioRecorder` — AVAudioEngine 마이크 캡처 + 파일 저장
- `TranscriptionService` 프로토콜
- `WhisperEngine` stub (UI 흐름 검증용 더미 결과)
- `PyannoteEngine` 스켈레톤
- `SystemAudioTap` 인터페이스 (stub)
- `MeetingAppDetector` (Zoom/Teams/Meet/Slack/Discord/브라우저 감지)

---

## ✅ M2 — 실제 모델 통합 & 시스템 오디오 (1차 완료, 일부 후속 PR)

### ✅ M2.1 Whisper

- ~~whisper.cpp SPM 직접 통합~~ → **WhisperKit (argmaxinc) 으로 전환**
  - whisper.cpp 의 `unsafeFlags` traveling dep 차단점 우회
  - 첫 사용 시 모델 자동 다운로드 (HuggingFace 캐시)
- `WhisperKitEngine`: file-based transcribe + 30초 청크 라이브 스트리밍
- `WhisperEngine`(stub) 은 모델 다운로드 불가 환경의 폴백으로 유지
- `ModelInstaller`: 모델 경로/존재 검사 헬퍼

### ✅ M2.2 Pyannote 화자분리

- `scripts/convert_pyannote.py`: pyannote/segmentation-3.0 → CoreML 변환 (Python)
- `PyannoteEngine`: 모델 룩업 + `assignSpeakers(to:segments:)` 매핑 (M1 부터 동작)
- 🟡 **후속 PR**: CoreML 추론 (16kHz 리샘플 → 윈도우 슬라이딩 → 임베딩 → clustering)

### 🟡 M2.3 Core Audio Process Tap

- `processObjectID(for: pid_t)` → `AudioHardwareCreateProcessTap` + `CATapDescription` 실제 호출
- `attach(to: AVAudioEngine, pid:)` 컨비니언스 시그니처
- 🟡 **후속 PR**: `AudioDeviceCreateIOProcID` + ring buffer → `AVAudioPCMBuffer` 스트리밍, Aggregate device 마이크 + 시스템 오디오 믹스

### ✅ M2.4 Xcode App Target

- `project.yml`: xcodegen 정의 (bundle id, Info.plist 권한 키, WhisperKit SPM)
- `Resources/MeetingMuseAlt.entitlements`: App Sandbox + 마이크 + 네트워크 + Files
- `xcodegen generate` 로 `.xcodeproj` 생성 후 Xcode 에서 빌드 / Hardened Runtime / Notarization

---

## ✅ M3 — Alt 동등 기능 (대부분 완료)

### ✅ M3.4 영구 저장
- `MeetingRecord` (Codable struct) + `MeetingPersistence` (JSON 파일) + `MeetingRepository` (CRUD)
- SwiftData 매크로는 Swift CLT 6.3.1 환경 미지원 → JSON 영속화로 구현, Xcode 환경에서 SwiftData/GRDB 마이그레이션 가능

### ✅ M3.5 공유 링크
- `MeetingExporter`: HTML (self-contained, XSS escape, 라이트/다크), Markdown, plainText

### ✅ M3.6 검색
- `MeetingSearchEngine`: 텍스트 + 화자 + 날짜 필터, 매치 NSRange 반환
- `MeetingSearchView`: TextField 검색바 + 결과 카드

### ✅ M3.7 메뉴바 앱 모드
- `MenuBarExtra` + `MenuBarScene`: 녹음 토글 / 메인 창 / 자동 감지 서브메뉴 / 종료

### ✅ M3.8 다크모드 / 한국어 / 영어
- `AppSettings.themeMode`: system/light/dark (UserDefaults)
- `Localizable.xcstrings`: ko 원본 + en 번역

### ✅ M3.2 PDF 강의자료 동기화
- `PdfPageMark` 모델 + `PdfSyncStore` (인메모리 상태) + `PdfSyncPanel` (PDFKit)
- `MeetingRecord` 에 `pdfFilePath` + `pdfPageMarks` 필드 추가 (레거시 JSON 역호환 디코드)

### ✅ M3.1 실시간 요약
- `SummarizationService` 프로토콜
- `OpenAISummarizer`: gpt-4o-mini Chat Completions (`/api/summarize` 와 동등 프롬프트)
- `LocalLlamaSummarizer`: notImplemented stub
- 🟡 **후속 PR**: llama.cpp Swift binding + Phi-3-mini / Llama-3.2-3B 로컬 추론

### ✅ M3.3 다국어 번역
- `TranslationService` 프로토콜
- `OpenAITranslator`: gpt-4o-mini 일괄 번역, 60건 1500자 제한 (`/api/translate` 와 동등)
- `LocalNLLBTranslator`: notImplemented stub
- 🟡 **후속 PR**: NLLB-distilled CoreML 변환 + Swift 로더

---

## 🟡 사용자 트리거 / 외부 자산 필요 (자동화 불가능 항목)

이 항목들은 코드 측면에서 진입점/스카폴드가 모두 준비되어 있지만, 다음 외부 트리거가 한 번 필요합니다:

1. **Screen Recording 권한 부여** — 시스템 설정 → 개인정보 보호 → 화면 녹화에서 MeetingMuseAlt(또는 Terminal/Xcode) 허용. SystemAudioTap IO proc 의 실제 PCM 흐름은 이 권한이 있어야 callback 호출됨.
2. **Pyannote 모델 변환** — `huggingface.co/pyannote/segmentation-3.0` 약관 동의 + 토큰 발급 후 `HF_TOKEN=hf_xxx python3 scripts/convert_pyannote.py` 실행. `.mlpackage` 가 `~/Library/Application Support/MeetingMuseAlt/Models/` 에 생기면 `PyannoteEngine.segment` 자동 동작.
3. **OpenAI API 키 입력** — `SettingsModal`/`AppSettings` 에 입력. `OpenAISummarizer` / `OpenAITranslator` 활성화.
4. **풀 Xcode 설치** — `xcodebuild` / Hardened Runtime / Notarization 빌드. CommandLineTools 만으로는 `xcodegen generate` 까지만 검증 가능.

## ⏸️ 후속 PR (코드 추가 작업)

1. **llama.cpp Swift binding** — LLMFarm / llama-cpp-swift / MLX-Swift 평가 후 안정적인 SPM 통합. `LocalLlamaSummarizer` 본체 구현.
2. **NLLB CoreML 변환** — Python `coremltools` 스크립트 + Swift 로더. `LocalNLLBTranslator` 본체 구현.
3. **whisper.cpp 직접 통합** — WhisperKit 의존성을 회피하고 싶으면 로컬 fork 또는 xcframework binaryTarget.
4. **AVAudioEngine ↔ 시스템 오디오 믹싱** — `SystemAudioTap.attach(to:pid:)` 의 health-check 패턴을 실제 mixing 노드 연결로 확장.

---

## 비기능 요구사항

- 🔒 **프라이버시**: 모든 처리는 로컬, 외부 송신 0 (요약/번역 OpenAI 호출은 OPT-IN, 키 미입력 시 비활성)
- ⚡ **성능 목표**: Whisper base 모델 기준 실시간 ≥1×, Pyannote ≥30×
- 🧪 **테스트 커버리지**: 도메인/저장소/검색/익스포트/번역/요약 = 81/81 통과
- 📦 **배포**: GitHub Releases + Sparkle 자동 업데이트 (후속 PR)

---

## 참고 자료

- WhisperKit: https://github.com/argmaxinc/WhisperKit
- whisper.cpp: https://github.com/ggerganov/whisper.cpp
- Pyannote: https://github.com/pyannote/pyannote-audio
- CoreML Tools: https://apple.github.io/coremltools/
- Core Audio Process Tap (macOS 14.4): https://developer.apple.com/documentation/coreaudio/audio_object_property
- xcodegen: https://github.com/yonaskolb/XcodeGen
