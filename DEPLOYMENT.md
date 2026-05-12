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

```yaml
name: Release

on:
  push:
    tags:
      - "v[0-9]+.[0-9]+.[0-9]+*"
  workflow_dispatch:
    inputs:
      version:
        description: "Version (e.g. 0.4.0)"
        required: true

permissions:
  contents: write

jobs:
  build-and-release:
    runs-on: macos-15
    timeout-minutes: 60

    steps:
      - uses: actions/checkout@v5

      - name: Resolve version
        id: ver
        run: |
          if [[ "${{ github.event_name }}" == "workflow_dispatch" ]]; then
            VERSION="${{ inputs.version }}"
          else
            VERSION="${GITHUB_REF_NAME#v}"
          fi
          echo "version=$VERSION" >> $GITHUB_OUTPUT

      - name: Install xcodegen
        run: brew install xcodegen

      - name: Generate Xcode project
        run: |
          sed -i '' "s/MARKETING_VERSION: \"[^\"]*\"/MARKETING_VERSION: \"${{ steps.ver.outputs.version }}\"/" project.yml
          xcodegen generate

      - name: Import code signing certificate
        if: ${{ secrets.MAC_APP_DEVELOPER_ID_CERT != '' }}
        env:
          MAC_APP_DEVELOPER_ID_CERT: ${{ secrets.MAC_APP_DEVELOPER_ID_CERT }}
          MAC_APP_DEVELOPER_ID_CERT_PASSWORD: ${{ secrets.MAC_APP_DEVELOPER_ID_CERT_PASSWORD }}
        run: |
          KEYCHAIN_PATH=$RUNNER_TEMP/build.keychain
          KEYCHAIN_PASSWORD=$(uuidgen)
          security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
          security set-keychain-settings -lut 21600 "$KEYCHAIN_PATH"
          security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"
          echo "$MAC_APP_DEVELOPER_ID_CERT" | base64 -d > "$RUNNER_TEMP/cert.p12"
          security import "$RUNNER_TEMP/cert.p12" -k "$KEYCHAIN_PATH" \
            -P "$MAC_APP_DEVELOPER_ID_CERT_PASSWORD" -A -t cert -f pkcs12
          security list-keychain -d user -s "$KEYCHAIN_PATH" $(security list-keychain -d user | tr -d \")
          security set-key-partition-list -S apple-tool:,apple: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN_PATH"

      - name: Build & archive (.app)
        env:
          DEVELOPER_ID: ${{ secrets.MAC_DEVELOPER_ID_APPLICATION }}
        run: |
          mkdir -p build
          if [[ -n "$DEVELOPER_ID" ]]; then
            CODE_SIGN_FLAGS="CODE_SIGN_IDENTITY=\"$DEVELOPER_ID\" CODE_SIGN_STYLE=Manual"
          else
            CODE_SIGN_FLAGS="CODE_SIGN_IDENTITY=\"\" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO"
          fi
          eval xcodebuild -project MeetingMuseAlt.xcodeproj -scheme MeetingMuseAlt \
            -configuration Release -derivedDataPath build/derived \
            -destination "platform=macOS" $CODE_SIGN_FLAGS \
            archive -archivePath build/MeetingMuseAlt.xcarchive

      - name: Notarize
        if: ${{ secrets.APPLE_ID != '' }}
        env:
          APPLE_ID: ${{ secrets.APPLE_ID }}
          APPLE_TEAM_ID: ${{ secrets.APPLE_TEAM_ID }}
          APPLE_APP_PASSWORD: ${{ secrets.APPLE_APP_PASSWORD }}
        run: |
          APP_PATH="build/MeetingMuseAlt.xcarchive/Products/Applications/MeetingMuseAlt.app"
          ZIP_PATH="build/MeetingMuseAlt.zip"
          ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"
          xcrun notarytool submit "$ZIP_PATH" \
            --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" \
            --password "$APPLE_APP_PASSWORD" --wait
          xcrun stapler staple "$APP_PATH"

      - name: Create DMG
        run: |
          APP_PATH="build/MeetingMuseAlt.xcarchive/Products/Applications/MeetingMuseAlt.app"
          DMG_PATH="build/MeetingMuseAlt-${{ steps.ver.outputs.version }}.dmg"
          mkdir -p build/dmg-staging
          cp -R "$APP_PATH" build/dmg-staging/
          ln -s /Applications build/dmg-staging/Applications
          hdiutil create -volname "Meeting Muse Alt" -srcfolder build/dmg-staging \
            -ov -format UDZO "$DMG_PATH"

      - name: Sign DMG (Sparkle EdDSA)
        if: ${{ secrets.SPARKLE_ED_PRIVATE_KEY != '' }}
        id: edsign
        env:
          SPARKLE_ED_PRIVATE_KEY: ${{ secrets.SPARKLE_ED_PRIVATE_KEY }}
        run: |
          curl -L -o sparkle.tar.xz https://github.com/sparkle-project/Sparkle/releases/download/2.9.1/Sparkle-2.9.1.tar.xz
          tar -xf sparkle.tar.xz
          DMG_PATH="build/MeetingMuseAlt-${{ steps.ver.outputs.version }}.dmg"
          echo "$SPARKLE_ED_PRIVATE_KEY" > /tmp/ed_private_key
          SIG=$(./bin/sign_update -f /tmp/ed_private_key "$DMG_PATH")
          rm /tmp/ed_private_key
          echo "signature=$SIG" >> $GITHUB_OUTPUT

      - name: Update appcast.xml
        run: |
          DMG_NAME="MeetingMuseAlt-${{ steps.ver.outputs.version }}.dmg"
          DMG_PATH="build/$DMG_NAME"
          DMG_SIZE=$(stat -f%z "$DMG_PATH")
          PUB_DATE=$(date -R)
          SIG_ATTR="${{ steps.edsign.outputs.signature }}"
          cat > build/appcast-entry.xml <<EOF
          <item>
            <title>Version ${{ steps.ver.outputs.version }}</title>
            <pubDate>$PUB_DATE</pubDate>
            <sparkle:version>${{ steps.ver.outputs.version }}</sparkle:version>
            <sparkle:shortVersionString>${{ steps.ver.outputs.version }}</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
            <enclosure
              url="https://github.com/${{ github.repository }}/releases/download/v${{ steps.ver.outputs.version }}/$DMG_NAME"
              length="$DMG_SIZE"
              type="application/octet-stream"
              $SIG_ATTR />
          </item>
          EOF
          awk -v entry_file=build/appcast-entry.xml '
            /<channel>/ {
              print
              while ((getline line < entry_file) > 0) print "    " line
              close(entry_file)
              next
            }
            { print }
          ' appcast.xml > appcast.xml.new
          mv appcast.xml.new appcast.xml
          git config user.name "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"
          git add appcast.xml
          git commit -m "chore(release): appcast.xml 갱신 — v${{ steps.ver.outputs.version }}" || echo "no changes"
          git push origin HEAD:main || echo "push skipped"

      - name: Upload to GitHub Release
        uses: softprops/action-gh-release@v2
        with:
          tag_name: v${{ steps.ver.outputs.version }}
          name: "Meeting Muse Alt v${{ steps.ver.outputs.version }}"
          files: build/MeetingMuseAlt-${{ steps.ver.outputs.version }}.dmg
          body: |
            ## Meeting Muse Alt v${{ steps.ver.outputs.version }}

            macOS 14+ 회의 녹음/전사/요약 네이티브 앱.

            ### 설치
            1. `.dmg` 다운로드 → `MeetingMuseAlt.app` 을 Applications 로 드래그
            2. 첫 실행 시 시스템 설정 → 개인정보 보호:
               - 마이크 (필수)
               - 화면 녹화 (시스템 오디오 캡처 시)
               - Apple Intelligence 활성화 (로컬 LLM 사용 시)

            ### 자동 업데이트
            v0.3 이상은 메뉴 → "업데이트 확인..." 또는 매일 자동 폴링.
```

추가 방법 (둘 중 하나):

**옵션 A: 로컬에서 `gh auth refresh`** (인터랙티브 2FA):
```bash
gh auth refresh -s workflow
cd /Users/dawith/개발/meeting-muse-alt
mkdir -p .github/workflows
# 위 YAML 두 개를 ci.yml / release.yml 로 저장 후
git add .github
git commit -m "ci: 워크플로우 추가"
git push origin main
```

**옵션 B: GitHub 웹 UI** (가장 간단):
1. https://github.com/dawith-ai/meeting-muse-alt/actions/new
2. "set up a workflow yourself" 클릭 → 위 CI YAML 붙여넣기 → `ci.yml` 로 저장 → commit
3. 같은 절차로 `release.yml` 추가
