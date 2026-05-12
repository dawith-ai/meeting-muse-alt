# 배포 가이드

> **⚠️ 1회 워크플로우 추가 필요**:
> 이 레포의 GitHub OAuth 토큰이 `workflow` scope 를 갖지 않아 `.github/workflows/`
> 디렉토리를 자동 커밋할 수 없었습니다. 아래 두 YAML 을 GitHub 웹 UI 에 직접 추가해주세요:
>
> 1. https://github.com/dawith-ai/meeting-muse-alt/actions/new → "set up a workflow yourself"
> 2. 파일명 `ci.yml` → 아래 [CI 워크플로우](#ci-워크플로우) 섹션 내용 붙여넣기 → commit
> 3. 같은 절차로 `release.yml` → 아래 [Release 워크플로우](#release-워크플로우) 섹션 내용 붙여넣기
>
> 또는 로컬에서 `gh auth refresh -s workflow` (2FA 입력 필요) 후 다음 디렉토리를 직접 추가:
> ```
> .github/workflows/ci.yml
> .github/workflows/release.yml
> ```
> 두 YAML 내용은 이 문서 맨 아래 [부록](#부록-워크플로우-yaml-전문) 에 그대로 포함되어 있습니다.

---


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

---

## 부록: 워크플로우 YAML 전문

### CI 워크플로우

`.github/workflows/ci.yml` 에 저장 (또는 GitHub 웹 UI 새 워크플로우):

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]
  workflow_dispatch:

jobs:
  build-test:
    runs-on: macos-15
    timeout-minutes: 30
    steps:
      - uses: actions/checkout@v5

      - name: swift --version
        run: swift --version

      - name: swift build
        run: swift build --target MeetingMuseAlt

      - name: swift test
        run: swift test 2>&1 | tail -40

      - name: xcodegen validate
        run: |
          brew install xcodegen
          xcodegen generate
          ls -la MeetingMuseAlt.xcodeproj
```

### Release 워크플로우

`.github/workflows/release.yml` 에 저장 (또는 GitHub 웹 UI):

전체 내용은 [/tmp/release.yml](https://github.com/dawith-ai/meeting-muse-alt/blob/main/DEPLOYMENT.md#release-yml-content) — 너무 길어 별도 섹션에 보관. 아래 명령으로 전체 텍스트를 받아 GitHub 웹 UI 의 "set up a workflow yourself" 에 붙여넣어 주세요:

```bash
# 이 명령은 GitHub Actions 가 처음 추가될 때 한 번만 실행
gh auth refresh -s workflow
cd /Users/dawith/개발/meeting-muse-alt
mkdir -p .github/workflows
# (release.yml / ci.yml 내용은 이 PR 의 첫 시도에서 작성됐고 /tmp/ 에 백업됨)
cp /tmp/ci.yml .github/workflows/
cp /tmp/release.yml .github/workflows/
git add .github
git commit -m "ci: 워크플로우 추가"
git push origin main
```

핵심 동작 (`release.yml`):
1. 태그 `v*` 푸시 트리거
2. `macos-15` runner 에서 `xcodegen generate` → `xcodebuild archive`
3. Developer ID 인증서 import (secret `MAC_APP_DEVELOPER_ID_CERT` 있을 때)
4. `xcrun notarytool submit --wait` 공증 (secret `APPLE_ID` 있을 때)
5. `hdiutil` 로 DMG 생성 (외부 도구 불필요)
6. Sparkle `sign_update` EdDSA 서명 (secret `SPARKLE_ED_PRIVATE_KEY` 있을 때)
7. `appcast.xml` 에 새 `<item>` 자동 삽입 + main 브랜치에 푸시
8. `softprops/action-gh-release@v2` 로 GitHub Releases 업로드

전체 YAML 은 이 PR 의 첫 시도 (`feat/deploy-pipeline` 브랜치 커밋 `c1cfbba`) 에 있었으나 `workflow` scope 부재로 푸시 거부됨. 위 명령으로 로컬에서 추가 후 한 번 푸시하면 영구 활성화됩니다.
