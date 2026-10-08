#!/bin/sh

set -eu

APP_NAME="Kakitangan Leave Notifier"
APPCAST_URL="https://github.com/anderscheow/kakitangan-leave-notifier/releases/latest/download/appcast.xml"
SPARKLE_ACCOUNT="com.kakitangan.leave-notifier"
REPOSITORY_SLUG="${GITHUB_REPOSITORY:-anderscheow/kakitangan-leave-notifier}"

require_env() {
    if [ -z "$(eval "printf '%s' \"\${$1:-}\"")" ]; then
        echo "Missing required Xcode Cloud environment variable: $1" >&2
        exit 1
    fi
}

if [ -z "${CI_TAG:-}" ]; then
    echo "No CI_TAG is set; skipping GitHub release."
    exit 0
fi

VERSION="${CI_TAG#v}"
if [ "$VERSION" = "$CI_TAG" ] || ! printf '%s\n' "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
    echo "Tag '$CI_TAG' is not vMAJOR.MINOR.PATCH; skipping GitHub release."
    exit 0
fi

require_env APP_STORE_CONNECT_API_KEY_ID
require_env APP_STORE_CONNECT_ISSUER_ID
require_env APP_STORE_CONNECT_API_KEY_P8
require_env DEVELOPER_ID_INSTALLER_IDENTITY
require_env GITHUB_TOKEN
require_env SPARKLE_EDDSA_PRIVATE_KEY

WORK_DIRECTORY="$(mktemp -d "${TMPDIR:-/tmp}/kakitangan-release.XXXXXX")"
RELEASE_DIRECTORY="$WORK_DIRECTORY/release"
UPDATE_DIRECTORY="$WORK_DIRECTORY/updates"
UPDATE_ARCHIVE="$RELEASE_DIRECTORY/KakitanganLeaveNotifier-$VERSION.zip"
INSTALLER_PACKAGE="$RELEASE_DIRECTORY/KakitanganLeaveNotifier-$VERSION.pkg"
API_KEY_PATH="$WORK_DIRECTORY/AuthKey.p8"
NOTARY_RESPONSE="$WORK_DIRECTORY/notary-response.json"

cleanup() {
    rm -rf "$WORK_DIRECTORY"
}
trap cleanup EXIT

mkdir -p "$RELEASE_DIRECTORY" "$UPDATE_DIRECTORY"
printf '%s' "$APP_STORE_CONNECT_API_KEY_P8" > "$API_KEY_PATH"

find_app_path() {
    if [ -n "${CI_DEVELOPER_ID_SIGNED_APP_PATH:-}" ]; then
        if [ -d "$CI_DEVELOPER_ID_SIGNED_APP_PATH" ] && [ "${CI_DEVELOPER_ID_SIGNED_APP_PATH##*.}" = "app" ]; then
            printf '%s\n' "$CI_DEVELOPER_ID_SIGNED_APP_PATH"
            return 0
        fi

        app_path="$(find "$CI_DEVELOPER_ID_SIGNED_APP_PATH" -maxdepth 4 -type d -name "$APP_NAME.app" -print -quit)"
        if [ -n "$app_path" ]; then
            printf '%s\n' "$app_path"
            return 0
        fi
    fi

    if [ -n "${CI_ARCHIVE_PATH:-}" ]; then
        find "$CI_ARCHIVE_PATH/Products/Applications" -maxdepth 1 -type d -name "$APP_NAME.app" -print -quit
        return 0
    fi
}

find_generate_appcast() {
    if [ -n "${CI_DERIVED_DATA_PATH:-}" ]; then
        find "$CI_DERIVED_DATA_PATH" -type f -name generate_appcast -path '*/Sparkle/bin/generate_appcast' -print -quit 2>/dev/null
    fi
}

notarize() {
    artifact="$1"
    xcrun notarytool submit "$artifact" \
        --key "$API_KEY_PATH" \
        --key-id "$APP_STORE_CONNECT_API_KEY_ID" \
        --issuer "$APP_STORE_CONNECT_ISSUER_ID" \
        --wait \
        --output-format json > "$NOTARY_RESPONSE"

    submission_id="$(plutil -extract id raw -o - "$NOTARY_RESPONSE")"
    status="$(plutil -extract status raw -o - "$NOTARY_RESPONSE")"
    echo "Notarization for $(basename "$artifact"): submission $submission_id -> $status"

    if [ "$status" != "Accepted" ]; then
        xcrun notarytool log "$submission_id" \
            --key "$API_KEY_PATH" \
            --key-id "$APP_STORE_CONNECT_API_KEY_ID" \
            --issuer "$APP_STORE_CONNECT_ISSUER_ID" || true
        echo "Notarization failed for $(basename "$artifact") (status: $status)" >&2
        exit 1
    fi
}

verify_signature() {
    target="$1"
    codesign --verify --strict --verbose=2 "$target"
    signature="$(codesign -dvv "$target" 2>&1)"
    printf '%s\n' "$signature" | grep -q 'Authority=Developer ID Application'
    printf '%s\n' "$signature" | grep -q '^Timestamp='
}

upload_asset() {
    upload_base="$1"
    artifact="$2"
    asset_name="$3"

    curl --fail --silent --show-error \
        --request POST \
        --header "Authorization: Bearer $GITHUB_TOKEN" \
        --header "Accept: application/vnd.github+json" \
        --header "Content-Type: application/octet-stream" \
        --data-binary "@$artifact" \
        "$upload_base?name=$asset_name" > /dev/null
}

APP_PATH="$(find_app_path)"
if [ -z "$APP_PATH" ] || [ ! -d "$APP_PATH" ]; then
    echo "Could not locate the Developer ID signed app exported by Xcode Cloud." >&2
    exit 1
fi

APP_VERSION="$(plutil -extract CFBundleShortVersionString raw -o - "$APP_PATH/Contents/Info.plist")"
APP_BUILD="$(plutil -extract CFBundleVersion raw -o - "$APP_PATH/Contents/Info.plist")"
if [ "$APP_VERSION" != "$VERSION" ]; then
    echo "Archived app version '$APP_VERSION' does not match release tag '$VERSION'." >&2
    exit 1
fi

echo "Packaging $APP_NAME $APP_VERSION ($APP_BUILD)."
verify_signature "$APP_PATH"

ditto -c -k --keepParent "$APP_PATH" "$UPDATE_ARCHIVE"
notarize "$UPDATE_ARCHIVE"
xcrun stapler staple "$APP_PATH"
spctl -a -vv -t exec "$APP_PATH"

rm "$UPDATE_ARCHIVE"
ditto -c -k --keepParent "$APP_PATH" "$UPDATE_ARCHIVE"
productbuild \
    --sign "$DEVELOPER_ID_INSTALLER_IDENTITY" \
    --component "$APP_PATH" /Applications \
    "$INSTALLER_PACKAGE"
notarize "$INSTALLER_PACKAGE"
xcrun stapler staple "$INSTALLER_PACKAGE"
spctl -a -vv -t install "$INSTALLER_PACKAGE"

SPARKLE_GENERATE_APPCAST="$(find_generate_appcast)"
if [ -z "$SPARKLE_GENERATE_APPCAST" ] || [ ! -x "$SPARKLE_GENERATE_APPCAST" ]; then
    echo "Could not locate Sparkle's generate_appcast tool in DerivedData." >&2
    exit 1
fi

curl --fail --location "$APPCAST_URL" --output "$UPDATE_DIRECTORY/appcast.xml" || rm -f "$UPDATE_DIRECTORY/appcast.xml"
cp "$UPDATE_ARCHIVE" "$UPDATE_DIRECTORY/"
printf '%s' "$SPARKLE_EDDSA_PRIVATE_KEY" | "$SPARKLE_GENERATE_APPCAST" \
    --account "$SPARKLE_ACCOUNT" \
    --ed-key-file - \
    --download-url-prefix "https://github.com/$REPOSITORY_SLUG/releases/download/$CI_TAG/" \
    --maximum-versions 3 \
    --maximum-deltas 0 \
    --versions "$APP_BUILD" \
    -o "$UPDATE_DIRECTORY/appcast.xml" \
    "$UPDATE_DIRECTORY"

CREATE_RELEASE_RESPONSE="$WORK_DIRECTORY/github-release.json"
curl --fail --silent --show-error \
    --request POST \
    --header "Authorization: Bearer $GITHUB_TOKEN" \
    --header "Accept: application/vnd.github+json" \
    --data "{\"tag_name\":\"$CI_TAG\",\"name\":\"$APP_NAME $VERSION\",\"generate_release_notes\":true}" \
    "https://api.github.com/repos/$REPOSITORY_SLUG/releases" > "$CREATE_RELEASE_RESPONSE"

UPLOAD_URL="$(plutil -extract upload_url raw -o - "$CREATE_RELEASE_RESPONSE")"
UPLOAD_BASE="${UPLOAD_URL%%\{*}"

upload_asset "$UPLOAD_BASE" "$UPDATE_ARCHIVE" "KakitanganLeaveNotifier-$VERSION.zip"
upload_asset "$UPLOAD_BASE" "$INSTALLER_PACKAGE" "KakitanganLeaveNotifier-$VERSION.pkg"
upload_asset "$UPLOAD_BASE" "$UPDATE_DIRECTORY/appcast.xml" "appcast.xml"

echo "Published GitHub release $CI_TAG."
