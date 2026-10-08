#!/bin/sh

set -eu

if [ "${CI_XCODE_CLOUD:-}" != "TRUE" ]; then
    exit 0
fi

if [ "${CI_XCODEBUILD_ACTION:-}" != "archive" ]; then
    exit 0
fi

if [ "${CI_PRODUCT_PLATFORM:-}" != "macOS" ]; then
    exit 0
fi

if [ -z "${CI_TAG:-}" ]; then
    echo "No CI_TAG is set; leaving app version unchanged."
    exit 0
fi

VERSION="${CI_TAG#v}"
if [ "$VERSION" = "$CI_TAG" ] || ! printf '%s\n' "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    echo "Tag '$CI_TAG' is not a release tag; leaving app version unchanged."
    exit 0
fi

BUILD_NUMBER="${CI_BUILD_NUMBER:-1}"

cd "${CI_PRIMARY_REPOSITORY_PATH:-.}"

echo "Setting release version to $VERSION ($BUILD_NUMBER)."
xcrun agvtool new-marketing-version "$VERSION"
xcrun agvtool new-version -all "$BUILD_NUMBER"
