# Kakitangan Leave Notifier for macOS

Native macOS 12+ app that securely checks Kakitangan leave, sends Time Sensitive
notifications, and runs at the selected times every weekday.

## First run

1. Open `KakitanganLeaveNotifier.xcodeproj` in Xcode and run the app.
2. On the setup screen, click **Allow notifications**. The macOS permission prompt is shown only after this action.
3. Enter the Kakitangan account email, password, and employee emails to monitor. Add one or more weekday check times, then click **Save setup**.
4. Leave **Check at sign-in** enabled if you want a hidden leave check after signing in to this Mac.
5. From the read-only dashboard, click **Enable schedule**.
6. Optionally enable **Open app at login** to add the app to **System Settings → General → Login Items → Open at Login** (macOS 13+).
7. Choose where the app appears: **Menu Bar & Dock**, **Menu Bar only**, or **Dock only**.
8. In **System Settings → Notifications → Kakitangan Leave Notifier**, enable
   **Allow time sensitive alerts** and choose **Persistent** alert style.

On later launches, a completed setup opens directly to the dashboard. Click
**Edit setup** whenever the account, watch list, or look-ahead window needs to change.

## Weekday times

The notifier checks once for every selected time, Monday through Friday. Add and delete
times in **Edit setup**. Deleting every time and saving disables the weekday schedule;
manual checks remain available from the dashboard. Existing configurations migrate to a
single 09:00 time.

## Sign-in check

**Check at sign-in** creates a per-user background LaunchAgent with `RunAtLoad`. It runs
after you sign in, when the macOS Keychain and notification session are available. For an
existing schedule, click **Update schedule** once to apply this setting.

## Open at Login

**Open app at login** uses the native macOS Login Items service, so the app is visible in
the **Open at Login** list in System Settings. It opens the app window after sign-in;
it does not replace the hidden **Check at sign-in** leave check.

## App visibility

The **App visibility** setting is available in setup and Edit setup. **Menu Bar only**
keeps a compact icon with Open Leave Watch, Check now, and Quit actions while hiding the
Dock icon. **Dock only** removes the menu-bar icon. The setting takes effect immediately
and is kept after restart when you save the setup configuration.

The password is stored in macOS Keychain. The app stores only the account email,
monitored emails, and look-ahead window in UserDefaults.

## Software updates and release automation

The app uses [Sparkle 2](https://sparkle-project.org/) for secure in-app updates.
Users install a signed `.pkg` once; later updates download a Developer ID-signed,
notarized, Sparkle-signed `.zip` archive without re-running the installer.

The appcast is published at:

```
https://github.com/anderscheow/kakitangan-leave-notifier-updates/releases/latest/download/appcast.xml
```

Sparkle checks this feed daily and users can choose **Check for Updates…** from
the app menu or the menu-bar icon. The update feed retains the three most recent
releases. The public Sparkle EdDSA key is committed in `Info.plist`; its matching
private key must never be committed or placed in a release artifact.

### One-time GitHub setup

1. Push this repository to `git@github.com:anderscheow/kakitangan-leave-notifier.git`.
2. Create the public `anderscheow/kakitangan-leave-notifier-updates` repository.
   It stores only signed Sparkle update archives and `appcast.xml`.
3. Create a fine-grained personal access token scoped only to that repository
   with **Contents: Read and write**, and add it to this repository's Actions
   secrets as `UPDATES_REPOSITORY_TOKEN`.
4. Create a Developer ID Application certificate and a Developer ID Installer
   certificate in Xcode. Export each as password-protected `.p12` files.
5. Create an App Store Connect API key with notarization access. Keep its `.p8`
   private key private.
6. Export the Sparkle private key from this Mac without committing it:

   ```zsh
   /tmp/kakitangan-leave-notifier-spm/artifacts/sparkle/Sparkle/bin/generate_keys \
     --account com.kakitangan.leave-notifier \
     -x "$HOME/Desktop/kakitangan-sparkle-private-key.txt"
   ```

   Add the file contents to GitHub Secrets, then securely delete the temporary
   export from the Desktop.

### GitHub Secrets

Add these repository secrets before creating the first release:

| Secret | Value |
| --- | --- |
| `APPLE_TEAM_ID` | Apple Developer Team ID. |
| `DEVELOPER_ID_APPLICATION_P12_BASE64` | Base64 of the Developer ID Application `.p12`. |
| `DEVELOPER_ID_INSTALLER_P12_BASE64` | Base64 of the Developer ID Installer `.p12`. |
| `SIGNING_CERTIFICATE_PASSWORD` | Password used for both exported `.p12` files. |
| `DEVELOPER_ID_APPLICATION_IDENTITY` | Full certificate name, such as `Developer ID Application: Company (TEAMID)`. |
| `DEVELOPER_ID_INSTALLER_IDENTITY` | Full installer certificate name, such as `Developer ID Installer: Company (TEAMID)`. |
| `APP_STORE_CONNECT_API_KEY_ID` | App Store Connect API key ID. |
| `APP_STORE_CONNECT_ISSUER_ID` | App Store Connect issuer ID. |
| `APP_STORE_CONNECT_API_KEY_P8` | Full contents of the App Store Connect `.p8` key. |
| `SPARKLE_EDDSA_PRIVATE_KEY` | Contents of the exported Sparkle private-key file. |

If Xcode requires a Developer ID provisioning profile for the Time Sensitive
Notifications capability, also add `DEVELOPER_ID_PROVISIONING_PROFILE_BASE64`
and `DEVELOPER_ID_PROVISIONING_PROFILE_NAME`.

Create the two base64 values without printing the source certificate contents:

```zsh
base64 -i developer-id-application.p12 | pbcopy
base64 -i developer-id-installer.p12 | pbcopy
```

### Release a version

1. Ensure the `Verify macOS build` workflow is green on `main`.
2. Create and push a semantic version tag, for example:

   ```zsh
   git tag v1.0.1
   git push origin v1.0.1
   ```

3. The `Release macOS app` workflow archives the app, signs it with Developer
   ID, notarizes and staples the app and installer, publishes the `.zip` and
   `.pkg` to this repository's GitHub Release, then publishes the signed
   Sparkle `.zip` and `appcast.xml` to the public updates repository.
4. Download the published `.pkg` on a separate Mac or macOS user account to
   test the initial install. Then install the previous version and use **Check
   for Updates…** to validate the in-app upgrade path.
