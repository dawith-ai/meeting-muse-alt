# ROADMAP — Meeting Muse Alt

Alt 앱과 기능 동등성을 달성하기 위한 단계별 로드맵.

## 현재 상태 요약 (2026-05-12)

| Alt 기능 | 상태 | 구현 위치 |
|---|---|---|
| 마이크 녹음 (시간제한 없음) | ✅ 동작 | `Audio/AudioRecorder.swift` |
| 시스템 오디오 캡처 (Zoom/Meet/Teams) | 🟡 부분 | `Audio/SystemAudioTap.swift` — CATapDescription + AudioHardwareCreateProcessTap 실제 호출, IO proc 버퍼 스트리밍은 후속 PR |
| Whisper 온디바이스 전사 | ✅ 동작 | `Transcription/WhisperKitEngine.swift` — WhisperKit SPM 통합, 첫 사용 시 모델 자동 다운로드 |
| Pyannote 화자분리 | 🟡 부분 | `Diarization/PyannoteEngine.swift` — 모델 룩업/매핑 OK, segmentation 추론은 후속 PR. `scripts/convert_pyannote.py` 로 모델 변환 |
| 회의 앱 자동 감지 | ✅ 동작 | `Detection/MeetingAppDetector.swift` |
| 실시간 요약 (로컬 LLM) | 🟡 부분 | `Storage/SummarizationService.swift` — OpenAI 원격 ✅, 로컬 llama.cpp 후속 PR |
| 다국어 번역 | 🟡 부분 | `Storage/TranslationService.swift` — OpenAI 원격 ✅, 로컬 NLLB 후속 PR |
| PDF 강의자료 동기화 | ✅ 동작 | `App/PdfSyncPanel.swift` + `Storage/PdfSyncStore.swift` (PDFKit) |
| 회의 영구 저장 | ✅ 동작 | `Storage/MeetingRecord.swift` + `MeetingPersistence.swift` + `MeetingRepository.swift` (JSON 파일) |
| 공유 링크 (HTML 익스포트) | ✅ 동작 | `Storage/MeetingExporter.swift` (HTML/Markdown/plainText, XSS escape) |
| 검색 (전사본 전문 검색) | ✅ 동작 | `Storage/MeetingSearchEngine.swift` + `App/MeetingSearchView.swift` |
| 메뉴바 앱 모드 | ✅ 동작 | `App/MenuBarScene.swift` (MenuBarExtra) |
| 다크모드 / i18n | ✅ 동작 | `App/AppSettings.swift` + `Resources/Localizable.xcstrings` (ko/en) |
| 인터넷 없이도 동작 | 🟡 부분 | Whisper/PDF/검색/익스포트/저장 OFFLINE OK. 요약/번역은 로컬 엔진 도착까지 OPT-IN 원격 |

**범례**: ✅ 동작, 🟡 부분 (인터페이스 + 일부 동작, 후속 PR 대기), 🔌 stub, ⏸️ 미착수

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

## 🟡 후속 PR (외부 자산/실기기 테스트 필요)

1. **whisper.cpp 직접 통합** (WhisperKit 의존 회피용) — 로컬 fork 또는 xcframework binaryTarget
2. **Pyannote CoreML 추론** — `scripts/convert_pyannote.py` 실행 후 segmentation → clustering 파이프라인
3. **Core Audio IO proc** — `AudioDeviceCreateIOProcID` + 링 버퍼, 권한 흐름, 실제 macOS 14.4+ 디바이스 테스트
4. **llama.cpp Swift binding** — LLMFarm / llama.cpp.swift 평가 후 통합
5. **NLLB CoreML 변환** — Python `coremltools` 스크립트 + Swift 로더
6. **AudioRecorder ↔ SystemAudioTap 와이어링** — `attach(to:pid:)` 호출부 활성화
7. **UI 통합** — `ContentView` 에 새 패널들 (PdfSyncPanel, MeetingSearchView, MeetingExporter dialog) 마운트

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
