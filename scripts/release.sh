#!/bin/bash
# Developer ID 서명 + Apple 공증 + 배포용 zip 생성
#
# 사전 준비 (1회): 공증 자격증명을 키체인에 등록
#   xcrun notarytool store-credentials inputswitcher \
#     --apple-id <Apple ID 이메일> --team-id 6NQV4LAHSK --password <앱 암호>
set -euo pipefail
cd "$(dirname "$0")/.."

IDENTITY="Developer ID Application: heesung jin (6NQV4LAHSK)"
PROFILE="inputswitcher"
VERSION=$(sed -n 's/.*CFBundleShortVersionString.*<string>\(.*\)<\/string>.*/\1/p' scripts/bundle.sh)

./scripts/bundle.sh
APP=build/InputSwitcher.app

# Developer ID + hardened runtime 재서명 (공증 필수 조건)
codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
codesign --verify --strict "$APP"

ZIP="build/InputSwitcher-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$APP"

# staple 반영본으로 다시 압축 (이게 배포 파일)
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
echo "배포 파일: $ZIP"
spctl -a -vv "$APP"
