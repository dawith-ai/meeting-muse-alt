# Meeting Muse — Alt

Alt 앱(오프라인 AI 음성 비서) 컨셉을 macOS 네이티브로 클론한 오픈소스 회의 비서.
**`meeting-muse`** (Next.js 웹앱) 의 자매 프로젝트로, 웹 브라우저로는 불가능한
**시스템 오디오 캡처 · 완전 오프라인 처리 · CoreML 가속 화자분리**를 목표로 합니다.

## 기능 매트릭스 (Alt 대비)

| Alt 기능 | Meeting Muse — Alt | M1 | M2 | M3 |
|---|---|:---:|:---:|:---:|
| 마이크 녹음 (시간제한 없음) | AVFoundation 기반 | ✅ | ✅ | ✅ |
| 시스템 오디오 캡처 (Zoom/Meet/Teams) | Core Audio Process Tap | 🔌 stub | ✅ | ✅ |
| Whisper 온디바이스 전사 | whisper.cpp + CoreML 인코더 | 🔌 stub | ✅ | ✅ |
| Pyannote 화자분리 (39× 실시간) | CoreML 변환 모델 | 🔌 stub | ✅ | ✅ |
| 회의 앱 자동 감지 | NSWorkspace 폴링 | ✅ | ✅ | ✅ |
| 실시간 요약 | 로컬 LLM (llama.cpp) | ⏸️ | ⏸️ | ✅ |
| PDF 강의자료 동기화 | PDFKit + bookmark | ⏸️ | ⏸️ | ✅ |
| 다국어 번역 | 로컬 NLLB / 원격 fallback | ⏸️ | ⏸️ | ✅ |
| 인터넷 없이도 동작 | 모델·앱 모두 로컬 | ✅ | ✅ | ✅ |

범례: ✅ 동작, 🔌 인터페이스만 (stub), ⏸️ 계획 단계

## 빠르게 실행

> 요구사항: **macOS 14 (Sonoma) 이상, Xcode 15+ 또는 Swift 5.9+**

```bash
cd meeting-muse-alt
swift build
swift run MeetingMuseAlt
```

Xcode에서 열려면:

```bash
open Package.swift
```

첫 실행 시 마이크 권한을 요청합니다 (시스템 설정 → 개인정보 보호).

## 디렉토리 구조

```
meeting-muse-alt/
├── Package.swift
├── Sources/MeetingMuseAlt/
│   ├── App/                  # SwiftUI entry + 메인 화면
│   ├── Audio/                # 마이크 녹음 + 시스템 오디오 탭
│   ├── Transcription/        # Whisper.cpp + CoreML 인코더
│   ├── Diarization/          # Pyannote CoreML 변환 모델
│   ├── Detection/            # 회의 앱 자동 감지 (Zoom 등)
│   ├── Models/               # Utterance, Speaker 등 도메인 모델
│   ├── ViewModel/            # RecordingViewModel (MVVM)
│   ├── Storage/              # 회의 영구 저장 (M2)
│   └── Resources/Models/     # CoreML / GGML 모델 파일 (gitignored)
└── Tests/MeetingMuseAltTests/
```

## 모델 설치 (M2 이후 활성화)

`Sources/MeetingMuseAlt/Resources/Models/` 디렉토리에 다음 파일이 필요합니다:

```bash
# Whisper.cpp (M2)
curl -L -o Sources/MeetingMuseAlt/Resources/Models/ggml-base.bin \
    https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin

# CoreML 인코더 (Apple Silicon 가속, M2)
# https://github.com/ggerganov/whisper.cpp/tree/master/models 참고

# Pyannote 화자분리 (M2)
# pyannote/segmentation-3.0을 coremltools로 .mlpackage 변환
```

모델 파일은 `.gitignore`에 등록되어 있어 레포에 커밋되지 않습니다.

## 권한 (Info.plist / Entitlements)

| 권한 | 키 | 용도 |
|---|---|---|
| 마이크 | `NSMicrophoneUsageDescription` | 회의 녹음 |
| 오디오 캡처 | `NSAudioCaptureUsageDescription` | 시스템 오디오 (M2) |
| 파일 접근 | App Sandbox + User Selected File | 회의록 저장 |

> SwiftPM executable로는 Info.plist를 자동 생성하지 않습니다. M2에서 Xcode app target으로
> 마이그레이션하거나 xcodegen으로 생성합니다 ([ROADMAP.md](./ROADMAP.md) 참조).

## 자매 프로젝트

- 🌐 **[meeting-muse](../meeting-muse)** — Next.js 웹앱.
  AssemblyAI + OpenAI를 사용하며, PDF 강의자료 동기화·다국어 번역·PWA 오프라인 지원.

## 라이선스

MIT.
