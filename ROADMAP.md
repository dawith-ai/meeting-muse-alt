# ROADMAP — Meeting Muse Alt

Alt 앱과 기능 동등성을 달성하기 위한 3단계 로드맵.

---

## M1 — 스카폴드 & 마이크 녹음 (현재)

**목표**: 빌드 가능한 SwiftUI 앱 + 모든 핵심 컴포넌트의 인터페이스 + 마이크 녹음 동작.

- [x] SwiftPM `executableTarget` macOS 14+
- [x] SwiftUI App/Scene 구조 (`MeetingMuseAltApp`)
- [x] 메인 화면 (사이드바 + 전사본 리스트 + 컨트롤 바)
- [x] `RecordingViewModel` MVVM
- [x] `AudioRecorder` — AVAudioEngine 마이크 캡처 + 파일 저장
- [x] `TranscriptionService` 프로토콜
- [x] `WhisperEngine` stub (UI 흐름 검증용 더미 결과)
- [x] `PyannoteEngine` 스켈레톤
- [x] `SystemAudioTap` 인터페이스 (stub)
- [x] `MeetingAppDetector` (Zoom/Teams/Meet/Slack/Discord/브라우저 감지)
- [x] 기본 단위 테스트

**검증**: `swift build` 성공, `swift test` 5/5 통과.

---

## M2 — 실제 모델 통합 & 시스템 오디오

**목표**: Alt와 동등한 핵심 기능. 인터넷 없이 동작.

### 2.1 Whisper.cpp + CoreML 인코더

- [ ] `Package.swift`에 whisper.cpp 의존성 추가:
  ```swift
  .package(url: "https://github.com/ggerganov/whisper.cpp", branch: "master")
  ```
- [ ] `WhisperEngine.transcribe(audioURL:)` 구현
  - `whisper_init_from_file_with_params` 로 모델 로드
  - 16kHz mono PCM으로 리샘플링
  - CoreML 인코더 자동 사용 (Apple Silicon)
- [ ] `liveTranscriptionStream` 구현 — 30초 윈도우, 5초 hop
- [ ] 모델 자동 다운로드 헬퍼 (`ModelInstaller.swift`)

### 2.2 Pyannote 화자분리 (CoreML)

- [ ] `pyannote/segmentation-3.0` 모델을 coremltools로 `.mlpackage` 변환
- [ ] WeSpeaker 또는 Resemblyzer 임베딩 모델도 동일하게 변환
- [ ] `PyannoteEngine.segment(audioURL:)` — segmentation 추론 → 발화 구간
- [ ] Agglomerative clustering으로 임베딩 → speaker label
- [ ] Whisper 발화와 시간 겹침 기반 매핑

### 2.3 Core Audio Process Tap

- [ ] `SystemAudioTap.captureProcess(pid:)` 구현 (macOS 14.4+)
  - `CATapDescription` 생성
  - `AudioHardwareCreateProcessTap` 호출
  - Aggregate device로 마이크 + 시스템 오디오 믹스
- [ ] 권한 요청 흐름 (Screen & System Audio Recording)
- [ ] Zoom/Meet/Teams 감지 시 자동 탭 부착 옵션

### 2.4 Xcode App Target 전환

- [ ] xcodegen `project.yml` 또는 직접 `.xcodeproj` 작성
- [ ] Info.plist (마이크/오디오 권한 메시지)
- [ ] App Sandbox + Hardened Runtime + Notarization 준비
- [ ] Universal Binary (arm64 + x86_64)

---

## M3 — Alt 동등 기능 완성

**목표**: Alt 앱의 모든 기능을 1:1 클론.

- [ ] **실시간 요약**: llama.cpp Swift 바인딩 + Phi-3-mini 또는 Llama-3.2-3B (로컬)
- [ ] **PDF 강의자료 동기화**: PDFKit + 페이지↔타임스탬프 마킹 + 자동 동기 재생
- [ ] **다국어 번역**: 로컬 NLLB-distilled, 실패 시 OpenAI fallback
- [ ] **회의 영구 저장**: SwiftData 또는 GRDB로 회의 라이브러리
- [ ] **공유 링크**: 회의록 → HTML 익스포트 → 로컬 서버 또는 iCloud 공유
- [ ] **검색**: 전사본 전문 검색 + 화자별 필터
- [ ] **메뉴바 앱 모드**: 항상 떠 있는 status bar 아이콘
- [ ] **다크모드 / 한국어 / 영어 로컬라이제이션**

---

## 비기능 요구사항

- 🔒 **프라이버시**: 모든 처리는 로컬, 외부 송신 0 (옵트인 fallback만 예외)
- ⚡ **성능 목표**: Whisper base 모델 기준 실시간 ≥1×, Pyannote ≥30×
- 🧪 **테스트 커버리지**: 80%+ (현재 도메인 모델만 커버)
- 📦 **배포**: GitHub Releases + Sparkle 자동 업데이트 (M3)

---

## 참고 자료

- whisper.cpp: https://github.com/ggerganov/whisper.cpp
- Pyannote: https://github.com/pyannote/pyannote-audio
- CoreML Tools: https://apple.github.io/coremltools/
- Core Audio Process Tap (macOS 14.4): https://developer.apple.com/documentation/coreaudio/audio_object_property
- Whisper SwiftUI 예제: https://github.com/ggerganov/whisper.cpp/tree/master/examples/whisper.swiftui
