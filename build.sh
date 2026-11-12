#!/bin/bash
# Build Glassmates (target EverythingInOne) thành build/Glassmates.app.
# Ký app: dùng SIGN_IDENTITY nếu có; không thì dùng chứng chỉ "Apple Development" nếu máy có
# (ký ổn định để macOS nhớ quyền giữa các lần build); không có nữa thì ký ad-hoc ("-").
#   SIGN_IDENTITY=- ./build.sh      # ép ký ad-hoc (dùng cho bản phát hành công khai)
set -euo pipefail
cd "$(dirname "$0")"

if [ -n "${SIGN_IDENTITY:-}" ]; then
  IDENTITY="$SIGN_IDENTITY"
elif security find-identity -v -p codesigning 2>/dev/null | grep -q "Apple Development"; then
  IDENTITY="Apple Development"
else
  IDENTITY="-"
fi
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
echo "Ký bằng: $IDENTITY"
echo "Đã build: $(pwd)/$APP"
