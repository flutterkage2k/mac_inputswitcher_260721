#!/bin/bash
# Developer ID 서명 + Apple 공증 + GitHub Release 게시 (버전은 bundle.sh가 단일 출처)
#
# 사전 준비 (1회): 공증 자격증명을 키체인에 등록
#   xcrun notarytool store-credentials inputswitcher \
#     --apple-id <Apple ID 이메일> --team-id 6NQV4LAHSK --password <앱 암호>
set -euo pipefail
cd "$(dirname "$0")/.."

IDENTITY="Developer ID Application: heesung jin (6NQV4LAHSK)"
PROFILE="inputswitcher"
REPO="flutterkage2k/mac_inputswitcher_260721"
VERSION=$(sed -n 's/.*CFBundleShortVersionString.*<string>\(.*\)<\/string>.*/\1/p' scripts/bundle.sh)

# 버전 올리는 것을 잊고 재릴리스하는 실수 방지
if gh release view "v$VERSION" --repo "$REPO" >/dev/null 2>&1; then
    echo "오류: v$VERSION 은 이미 릴리스되어 있습니다. scripts/bundle.sh의 버전을 올리세요."
    exit 1
fi

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
spctl -a -vv "$APP"

# 태그가 번들 버전에서 자동 생성되므로 어긋날 수 없다.
# 릴리스 노트는 커밋 로그 기반 자동 생성 (웹에서 수정 가능).
gh release create "v$VERSION" "$ZIP" --repo "$REPO" \
    --title "InputSwitcher v$VERSION" --generate-notes
echo "릴리스 완료: https://github.com/$REPO/releases/tag/v$VERSION"
