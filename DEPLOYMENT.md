# 설치 & 업데이트 (개인용)

이 레포는 사용자 본인만 쓰는 macOS 앱입니다. 공식 배포(Apple Developer Program, 공증, 자동 업데이트 Sparkle)는 사용하지 않습니다.

## 첫 설치

```bash
git clone https://github.com/dawith-ai/meeting-muse-alt.git
cd meeting-muse-alt
./scripts/install.sh
```

스크립트가 하는 일:
1. `swift build -c release --product MeetingMuseAlt` (최초 ~3분, 이후 ~30초)
2. 결과 바이너리를 `.app` 번들 구조로 포장
3. `~/Applications/MeetingMuseAlt.app` 에 설치
4. Spotlight 색인 갱신

설치 후:
- Finder → `~/Applications` → `Meeting Muse Alt` 더블 클릭
- 또는 Spotlight (⌘Space) 에서 "Meeting Muse Alt" 검색
- 또는 `open ~/Applications/MeetingMuseAlt.app`

## 권한 (첫 실행 시)

시스템 설정 → 개인정보 보호:
- ✅ **마이크** (필수, 녹음용)
- ✅ **화면 녹화** (시스템 오디오 캡처 시, Zoom/Meet/Teams 오디오)
- ✅ **자동화** (회의 앱 자동 감지 시)
- ✅ **Apple Intelligence** (로컬 LLM 요약/번역/Ask AI 사용 시, macOS 26+)

## 업데이트

```bash
cd /Users/dawith/개발/meeting-muse-alt
git pull
./scripts/install.sh
```

스크립트가 기존 `.app` 을 덮어씁니다. 안의 사용자 데이터 (회의 라이브러리, 메모, 설정) 는 `~/Library/Application Support/MeetingMuseAlt/` 에 있어 영향 없음.

## 데이터 위치

| 무엇 | 경로 |
|---|---|
| 회의 라이브러리 (JSON) | `~/Library/Application Support/MeetingMuseAlt/meetings.json` |
| 메모 (JSON) | `~/Library/Application Support/MeetingMuseAlt/notes.json` |
| WhisperKit 모델 캐시 | `~/Documents/huggingface/` |
| Pyannote 모델 (사용 시) | `~/Library/Application Support/MeetingMuseAlt/Models/` |
| 녹음 파일 (.caf) | `~/Library/Application Support/MeetingMuseAlt/` |
| 앱 설정 | UserDefaults `kr.dawith.meetingmuse.alt` |

## 완전 제거

```bash
rm -rf ~/Applications/MeetingMuseAlt.app
rm -rf ~/Library/Application\ Support/MeetingMuseAlt
defaults delete kr.dawith.meetingmuse.alt 2>/dev/null
```

## (참고) 공개 배포가 필요해진다면

공식 .dmg 배포 + 자동 업데이트 + Apple 공증이 필요해지면 다음을 추가해야 합니다:

1. **Apple Developer Program** 가입 ($99/yr)
2. **Sparkle** SPM 의존성 복원 + `UpdaterController` 본체 (`SPUStandardUpdaterController` 사용)
3. **GitHub Actions** release workflow (xcodegen → xcodebuild → notarytool → DMG → appcast.xml → Releases 업로드)
4. **Vercel 랜딩 페이지** — `meeting-muse/src/app/download/page.tsx` 이미 작성됨, GitHub Releases API ISR

이 모든 것의 자세한 YAML/Secret/키 생성 절차는 git history `feat/deploy-pipeline` 브랜치 (`c1cfbba` 커밋) 에 보존되어 있습니다.
