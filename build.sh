#!/bin/bash
# Build Glassmates (target EverythingInOne) thành .app và ký bằng chứng chỉ Apple Development
# (ký ổn định để macOS nhớ quyền Screen Recording giữa các lần build).
set -euo pipefail
cd "$(dirname "$0")"

IDENTITY="${SIGN_IDENTITY:-Apple Development}"
APP="build/Glassmates.app"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/EverythingInOne"

rm -rf "$APP" build/EverythingInOne.app   # bản cũ trước khi đổi tên
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/EverythingInOne"
cp Info.plist "$APP/Contents/Info.plist"
mkdir -p "$APP/Contents/Resources"
cp Design/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp -R Resources/*.lproj "$APP/Contents/Resources/"   # ngôn ngữ: en (mặc định), vi

codesign --force --sign "$IDENTITY" "$APP"
echo "Đã build: $(pwd)/$APP"
