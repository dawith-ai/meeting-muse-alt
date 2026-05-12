#!/usr/bin/env bash
# Meeting Muse Alt — 개인용 로컬 설치 스크립트.
#
# 사용:
#   ./scripts/install.sh
#
# 동작:
#   1. swift build -c release --product MeetingMuseAlt
#   2. .build/release/MeetingMuseAlt 바이너리를 .app 번들로 포장
#   3. ~/Applications/MeetingMuseAlt.app 에 설치 (관리자 권한 불필요)
#   4. dock 에서 바로 실행 가능
#
# 업데이트는 그냥 다시 실행하면 됨 — git pull && ./scripts/install.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

APP_NAME="MeetingMuseAlt"
BUNDLE_ID="kr.dawith.meetingmuse.alt"
DISPLAY_NAME="Meeting Muse Alt"
VERSION="0.4.0"
TARGET_DIR="${HOME}/Applications"
APP_BUNDLE="${TARGET_DIR}/${APP_NAME}.app"

echo "→ 빌드 중 (~3분, 최초 1회만 오래 걸림)..."
swift build -c release --product "${APP_NAME}"
BIN_PATH=$(swift build -c release --show-bin-path)
EXE="${BIN_PATH}/${APP_NAME}"
RESOURCE_BUNDLE="${BIN_PATH}/${APP_NAME}_${APP_NAME}.bundle"

if [[ ! -x "${EXE}" ]]; then
  echo "✗ 빌드 결과를 찾을 수 없습니다: ${EXE}"
  exit 1
fi

echo "→ .app 번들 생성: ${APP_BUNDLE}"
mkdir -p "${TARGET_DIR}"

# 기존 설치 제거
if [[ -d "${APP_BUNDLE}" ]]; then
  rm -rf "${APP_BUNDLE}"
fi

mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

# 바이너리 복사
cp "${EXE}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
chmod +x "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"

# 리소스 번들 (Localizable.xcstrings 등) 복사
if [[ -d "${RESOURCE_BUNDLE}" ]]; then
  cp -R "${RESOURCE_BUNDLE}" "${APP_BUNDLE}/Contents/Resources/"
fi

# Info.plist 작성
cat > "${APP_BUNDLE}/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>ko</string>
    <key>CFBundleDisplayName</key>
    <string>${DISPLAY_NAME}</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.productivity</string>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026 Dawith. Personal use only.</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>회의 녹음을 위해 마이크가 필요합니다.</string>
    <key>NSScreenCaptureUsageDescription</key>
    <string>Zoom/Meet/Teams 등의 시스템 오디오를 캡처하기 위해 화면 녹화 권한이 필요합니다.</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>실행 중인 회의 앱을 자동 감지하기 위해 권한이 필요합니다.</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
    <key>LSUIElement</key>
    <false/>
</dict>
</plist>
EOF

# Gatekeeper 메타데이터 제거 (다운로드한 게 아니라 로컬 빌드므로 quarantine 없어도 됨)
xattr -cr "${APP_BUNDLE}" 2>/dev/null || true

echo ""
echo "✓ 설치 완료: ${APP_BUNDLE}"
echo ""
echo "실행 방법:"
echo "  Finder → ~/Applications → ${DISPLAY_NAME} 더블 클릭"
echo "  또는 터미널: open \"${APP_BUNDLE}\""
echo ""
echo "Spotlight 색인 갱신:"
mdimport "${APP_BUNDLE}" 2>/dev/null || true
echo "  (몇 초 후 Spotlight 에서 \"Meeting Muse Alt\" 검색 가능)"
echo ""
echo "업데이트:"
echo "  git pull && ./scripts/install.sh"
