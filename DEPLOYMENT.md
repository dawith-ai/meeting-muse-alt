# 배포 가이드

`meeting-muse-alt` 는 macOS 네이티브 앱입니다. 표준 배포 흐름:

```
태그 푸시 (v0.4.0)
  → GitHub Actions 자동 빌드
  → 코드사인 (Developer ID Application)
  → Apple 공증 (notarytool)
  → DMG 생성
  → Sparkle EdDSA 서명
  → GitHub Releases 업로드
  → appcast.xml 자동 갱신
  → 기존 사용자 앱에 자동 업데이트 알림 표시
```

## 1회만 설정 (최초 셋업)

### 1. Apple Developer Program 가입
- https://developer.apple.com/programs/ ($99/yr)
- 가입 후 "Certificates" 에서 **Developer ID Application** 인증서 생성
- 인증서를 macOS 키체인에 export → `.p12` 파일로 저장 + 패스워드 설정

### 2. App-specific password 발급 (Notarization 용)
- https://account.apple.com/account/manage → "앱 암호" → 생성
- 생성된 비밀번호 저장 (예: `abcd-efgh-ijkl-mnop`)

### 3. Sparkle EdDSA 키페어 생성
```bash
brew install --cask sparkle  # 또는 .xz 다운로드 후 bin/generate_keys
./bin/generate_keys
# → 공개키 (Info.plist SUPublicEDKey 에 넣음)
# → 개인키 (GitHub secret SPARKLE_ED_PRIVATE_KEY 로 등록)
```
공개키를 `project.yml` 의 `SUPublicEDKey` 에 채워넣고 다시 `xcodegen generate`.

### 4. GitHub Repository Secrets 등록
`Settings → Secrets and variables → Actions → New repository secret`:

| Secret 이름 | 값 |
|---|---|
| `MAC_APP_DEVELOPER_ID_CERT` | `.p12` 인증서 base64 (`base64 -i cert.p12 \| pbcopy`) |
| `MAC_APP_DEVELOPER_ID_CERT_PASSWORD` | `.p12` export 시 설정한 패스워드 |
| `MAC_DEVELOPER_ID_APPLICATION` | "Developer ID Application: Your Name (TEAM_ID)" 문자열 |
| `APPLE_ID` | Apple 계정 이메일 |
| `APPLE_TEAM_ID` | Developer 페이지 우상단 10자 ID (예: ABCDE12345) |
| `APPLE_APP_PASSWORD` | 2단계의 app-specific password |
| `SPARKLE_ED_PRIVATE_KEY` | 3단계의 private key 문자열 전체 |

## 매번 릴리스 (수정사항 반영)

```bash
# 1) 코드 수정 + 커밋
git add . && git commit -m "feat: ..." && git push

# 2) 버전 태그 푸시 — 이게 트리거
git tag v0.4.0
git push origin v0.4.0

# 3) GitHub Actions 가 자동으로:
#    - xcodegen generate
#    - xcodebuild archive (Developer ID 서명)
#    - notarytool 공증 (Apple 서버 처리 ~10분)
#    - DMG 생성
#    - Sparkle 서명
#    - GitHub Releases 업로드
#    - appcast.xml 자동 갱신 후 main 푸시
```

진행 상황은 `https://github.com/dawith-ai/meeting-muse-alt/actions` 에서 확인.

## 자동 업데이트 동작 흐름

```
사용자 앱 (v0.3 설치됨)
  ↓ 매일 1회 (SUScheduledCheckInterval) 또는 메뉴 "업데이트 확인..." 클릭
  ↓
SUFeedURL 폴링: https://raw.githubusercontent.com/dawith-ai/meeting-muse-alt/main/appcast.xml
  ↓
appcast.xml 의 <item> 중 v0.4.0 발견
  ↓ EdDSA 서명 검증
  ↓ 사용자에게 "업데이트 가능" 다이얼로그 표시
  ↓ 사용자 동의 시 .dmg 다운로드 + 자동 설치 (앱 재시작)
```

## 미서명 빌드 (1회만, 초기 테스트용)

Apple Developer Program 가입 전에 로컬 테스트 빌드를 만들고 싶을 때:
```bash
xcodegen generate
xcodebuild -project MeetingMuseAlt.xcodeproj -scheme MeetingMuseAlt \
  -configuration Release \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  archive -archivePath build/MeetingMuseAlt.xcarchive
```
사용자는 첫 실행 시 **우클릭 → 열기** 로 Gatekeeper 우회. Production 에는 권장 ❌.

## Vercel 랜딩 페이지

`meeting-muse` (Next.js 웹앱) 안의 `/app/download/` 라우트가 GitHub Releases 최신 버전을 표시합니다 (별도 작업 필요 시 추가).

직접 다운로드 링크:
- 최신 릴리스: https://github.com/dawith-ai/meeting-muse-alt/releases/latest
- 직접 다운로드: https://github.com/dawith-ai/meeting-muse-alt/releases/latest/download/MeetingMuseAlt.dmg
  (※ 정확한 파일 이름은 버전이 포함됨 — appcast.xml 의 enclosure URL 사용 권장)
