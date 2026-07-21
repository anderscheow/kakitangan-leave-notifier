---
name: release-tagging
description: Prepare and publish Kakitangan Leave Notifier releases by pushing a `vX.Y.Z` Git tag, which triggers the GitHub Actions release workflow to sign, notarize, publish a GitHub Release, and regenerate the Sparkle appcast so the in-app updater picks up the new version. Use when asked to cut, tag, publish, or release a version, or to fix an incorrect release tag.
---

# Release Tagging

Kakitangan Leave Notifier is a macOS app distributed as a signed `.pkg` and updated in place by **Sparkle**. Releases are automated by `.github/workflows/release.yml`, which runs on any pushed `v*` tag. The "Software updates and release automation" section of `README.md` is the source of truth; this skill is the operational checklist. Git commands assume the RTK hook rewrites `git` transparently — write plain `git`.

## What a pushed tag does

Pushing a `vX.Y.Z` tag triggers **Release macOS app** (`.github/workflows/release.yml`), which:

1. Derives the version from the tag (`vX.Y.Z` → `X.Y.Z`) and **fails unless it matches `MAJOR.MINOR.PATCH`**. The build number is the workflow run number.
2. Archives a Release build signed with the Developer ID Application certificate (hardened runtime), injecting `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` from the tag — **do not bump the version in `project.pbxproj`; the tag drives it.**
3. Notarizes and staples the app, then builds a signed + notarized `.pkg` and a Sparkle `.zip`.
4. Publishes a GitHub Release `Kakitangan Leave Notifier X.Y.Z` with the `.zip` and `.pkg` attached (`--generate-notes` fills notes from commits).
5. Regenerates the Sparkle **appcast** (EdDSA-signed with `SPARKLE_EDDSA_PRIVATE_KEY`, keeping the newest 3 versions) and deploys it to GitHub Pages at the `SUFeedURL`.

Step 5 is what makes the **updater** work: existing installs poll
`https://anderscheow.github.io/kakitangan-leave-notifier/appcast.xml`, verify the
EdDSA signature against `SUPublicEDKey` in `Info.plist`, and offer the update. A
release is not done until that appcast is live and shows the new version.

## Pre-flight checks (stop on any failure)

1. `git fetch origin --tags --prune`.
2. `git status --short` is empty; `HEAD` is on `main` and level with `origin/main`.
3. The **Verify macOS build** workflow (`verify.yml`) is green on the target commit.
4. Tag `vX.Y.Z` does not already exist locally or on `origin` (`git ls-remote --tags origin "refs/tags/vX.Y.Z"`). **Never reuse a published version** — Sparkle clients cache what they have seen; cut the next patch instead.
5. Confirm the required GitHub Actions secrets exist (Settings → Secrets and variables → Actions). Any missing secret fails the run:
   - Signing: `APPLE_TEAM_ID`, `DEVELOPER_ID_APPLICATION_P12_BASE64`, `DEVELOPER_ID_INSTALLER_P12_BASE64`, `SIGNING_CERTIFICATE_PASSWORD`, `DEVELOPER_ID_APPLICATION_IDENTITY`, `DEVELOPER_ID_INSTALLER_IDENTITY`
   - Notarization: `APP_STORE_CONNECT_API_KEY_ID`, `APP_STORE_CONNECT_ISSUER_ID`, `APP_STORE_CONNECT_API_KEY_P8`
   - Updater: `SPARKLE_EDDSA_PRIVATE_KEY` — **must match `SUPublicEDKey` in `Info.plist`**, or clients reject the update
   - Optional: `DEVELOPER_ID_PROVISIONING_PROFILE_BASE64`, `DEVELOPER_ID_PROVISIONING_PROFILE_NAME`
6. **GitHub Pages** source is set to **GitHub Actions** (Settings → Pages). Otherwise the appcast deploy fails and the updater never sees the release.
7. When the version is ambiguous, ask the user to confirm it. Inspect the range since the last tag with `git log <previous-tag>..HEAD --no-merges` and `git diff --stat <previous-tag>..HEAD` (use full history for the first release, and say so).

## Choose the version

Semantic versioning: **MAJOR** for breaking or behaviour changes users must know about, **MINOR** for backward-compatible features, **PATCH** for fixes only. The first public release is `v1.0.0`.

## Tag and publish

State the consequence and get explicit approval before pushing: **pushing the tag immediately starts signing, notarization, a public GitHub Release, and an appcast deploy that offers the update to every existing install.**

The GitHub Release notes come from `--generate-notes`, so the tag message is optional:

```bash
git tag -a "vX.Y.Z" -m "Kakitangan Leave Notifier X.Y.Z"
git push origin "vX.Y.Z"
```

## Verify after pushing (do not claim success early)

- Watch the run: `gh run watch "$(gh run list --workflow 'Release macOS app' --limit 1 --json databaseId -q '.[0].databaseId')"`.
- Release exists with both artifacts: `gh release view "vX.Y.Z"`.
- Appcast updated: `curl -s https://anderscheow.github.io/kakitangan-leave-notifier/appcast.xml | grep -E 'sparkle:(version|shortVersionString)'` shows `X.Y.Z`.
- Optionally confirm the updater end-to-end from an older install via **Check for Updates…**.
- Report success only once the workflow finished green and the appcast shows the new version.

## Fix an incorrect tag

Before the workflow publishes the Release/appcast, delete and recreate:

```bash
git push origin :refs/tags/vX.Y.Z   # delete remote tag
git tag -d vX.Y.Z                     # delete local tag
```

Once a version is published to the appcast, **do not reuse it** — cut the next patch version instead, because Sparkle clients cache the versions they have already seen.
