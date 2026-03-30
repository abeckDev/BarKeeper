# BarKeeper Release Process

> Related to issue [#6 — Set up CI/CD for automated build, code signing, notarization, and GitHub Releases](https://github.com/abeckDev/BarKeeper/issues/6)

## Overview

BarKeeper uses a GitHub Actions workflow at [`.github/workflows/release.yml`](../.github/workflows/release.yml) to automate the full release pipeline. Pushing a version tag (e.g. `v1.0.0`) triggers the workflow, which runs on `macos-15` runners and handles the following steps automatically:

- **Project generation** — regenerates `BarKeeper.xcodeproj` from `project.yml` using XcodeGen (the `.xcodeproj` is gitignored and never committed)
- **Building** — compiles and archives the app with Xcode
- **Code signing** — signs the app with a Developer ID Application certificate from GitHub Secrets
- **Notarization** — submits the app to Apple's notarization service and staples the ticket
- **Packaging** — creates both a `.dmg` (for drag-and-drop installation) and a `.zip` (for Homebrew Cask)
- **GitHub Release** — creates a draft release with SHA256 checksums and both artifacts attached

---

## Pipeline Steps

### 1. Checkout
Clones the repository at the exact commit the tag points to.

### 2. Xcode Setup
Selects Xcode 16.0 on the runner:

```bash
sudo xcode-select -s /Applications/Xcode_16.0.app
```

### 3. Project Generation
Installs XcodeGen via Homebrew and regenerates `BarKeeper.xcodeproj` from `project.yml`:

```bash
brew install xcodegen
xcodegen generate
```

The `.xcodeproj` is gitignored and is never committed — `project.yml` is the source of truth for the project structure.

### 4. Certificate Import
Decodes the base64-encoded `.p12` certificate from GitHub Secrets, creates a temporary keychain on the runner, imports the certificate, and grants `codesign` access:

```bash
# Create temporary keychain
security create-keychain -p "$KEYCHAIN_PASSWORD" signing.keychain-db

# Decode and import the certificate
echo "$CERTIFICATE_P12" | base64 --decode > certificate.p12
security import certificate.p12 -k signing.keychain-db \
  -P "$CERTIFICATE_PASSWORD" \
  -T /usr/bin/codesign
```

The keychain is deleted in the **Cleanup** step at the end of the run.

### 5. Build & Archive
Runs `xcodebuild archive` with manual signing using the Developer ID Application identity, your Team ID, and the temporary keychain:

```bash
xcodebuild archive \
  -project BarKeeper.xcodeproj \
  -scheme BarKeeper \
  -configuration Release \
  -archivePath BarKeeper.xcarchive \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="Developer ID Application" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  OTHER_CODE_SIGN_FLAGS="--keychain signing.keychain-db"
```

### 6. Export
Exports the `.xcarchive` using an `ExportOptions.plist` configured for the `developer-id` distribution method:

```xml
<key>method</key>
<string>developer-id</string>
```

### 7. Notarization
Zips the exported `.app`, submits it to Apple via `xcrun notarytool`, waits for approval, then staples the notarization ticket to the app:

```bash
# Submit and wait for notarization
xcrun notarytool submit BarKeeper-notarize.zip \
  --apple-id "$APPLE_ID" \
  --password "$APPLE_APP_PASSWORD" \
  --team-id "$TEAM_ID" \
  --wait

# Staple the ticket
xcrun stapler staple BarKeeper.app
```

### 8. Packaging
Creates both a `.dmg` (using `hdiutil`) and a `.zip` (using `ditto`) from the notarized app, and computes SHA256 checksums for both:

```bash
# Create DMG
hdiutil create -volname "BarKeeper" -srcfolder BarKeeper.app \
  -ov -format UDZO BarKeeper.dmg

# Create ZIP
ditto -c -k --keepParent BarKeeper.app BarKeeper.zip

# Compute checksums
shasum -a 256 BarKeeper.dmg
shasum -a 256 BarKeeper.zip
```

### 9. GitHub Release
Uses [`softprops/action-gh-release@v2`](https://github.com/softprops/action-gh-release) to create a **draft** release with auto-generated release notes, the SHA256 checksums in the body, and both `.dmg` and `.zip` attached as assets.

The release is created as a **draft** so you can review and edit it before publishing.

### 10. Cleanup
Always runs (even if previous steps failed) and deletes the temporary keychain:

```bash
security delete-keychain signing.keychain-db || true
```

---

## Required GitHub Secrets

Add all six secrets at: **Repository → Settings → Secrets and variables → Actions → New repository secret**

| Secret | Description | How to obtain |
|--------|-------------|---------------|
| `CERTIFICATE_P12` | Base64-encoded `.p12` export of your **Developer ID Application** certificate | In Keychain Access on your Mac: find the certificate → right-click → Export → save as `.p12` with a password. Then run `base64 -i certificate.p12 \| pbcopy` to copy the base64 string |
| `CERTIFICATE_PASSWORD` | The password you set when exporting the `.p12` file | You chose this during the export step above |
| `KEYCHAIN_PASSWORD` | Any strong random password used for the temporary CI keychain | Generate a random string, e.g. `openssl rand -base64 32` — this is only used during the CI run |
| `TEAM_ID` | Your 10-character Apple Developer Team ID | Find it at [developer.apple.com/account](https://developer.apple.com/account) → Membership details |
| `APPLE_ID` | The Apple ID email address used for notarization | Your Apple Developer account email |
| `APPLE_APP_PASSWORD` | An App-Specific Password for notarization | Generate at [appleid.apple.com](https://appleid.apple.com) → Sign-In and Security → App-Specific Passwords |

---

## How to Trigger a Release

The workflow triggers automatically on any tag matching `v*`. To release version `1.0.0`:

```bash
git tag v1.0.0
git push origin v1.0.0
```

> **Important:** The tag must point to a commit that already contains `.github/workflows/release.yml`. If the workflow file is not present in the tagged commit, GitHub Actions will not trigger the workflow.

Once the workflow completes successfully, go to the repository's **Releases** page, review the draft release, and click **Publish release**.

---

## How to Re-tag / Fix a Failed Tag

If you need to move or retag a release (e.g. to fix a workflow error or point to a different commit):

```bash
# Delete the tag locally and remotely
git tag -d v1.0.0
git push origin :refs/tags/v1.0.0

# Re-create and push the tag
git tag v1.0.0
git push origin v1.0.0
```

---

## Artifacts Produced

Each successful release produces the following artifacts, all attached to the GitHub Release:

| Artifact | Description |
|----------|-------------|
| `BarKeeper.dmg` | Disk image for drag-and-drop installation |
| `BarKeeper.zip` | ZIP archive (useful for [Homebrew Cask](https://github.com/abeckDev/BarKeeper/issues/5) distribution) |

SHA256 checksums for both files are included in the release notes body.

---

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| "No Team Found in Archive" | Team not set in `project.yml`, or `CODE_SIGN_IDENTITY` is still `"-"` (ad-hoc) | Ensure `project.yml` has `CODE_SIGN_IDENTITY: "Apple Development"` and `ENABLE_HARDENED_RUNTIME: true` |
| Workflow not triggering after `git push origin v1.0.0` | Tag points to a commit that does not contain the workflow file, or the tag does not start with `v` | Ensure the workflow file is committed before tagging, and the tag starts with `v` |
| Notarization fails | Incorrect Apple ID, wrong app-specific password, or hardened runtime not enabled | Double-check `APPLE_ID` and `APPLE_APP_PASSWORD` secrets; verify `ENABLE_HARDENED_RUNTIME: true` is in `project.yml` |
| Certificate import fails | Incorrect base64 encoding of the `.p12`, or the password doesn't match | Re-encode: `base64 -i certificate.p12 \| pbcopy`, then update `CERTIFICATE_P12` and `CERTIFICATE_PASSWORD` secrets |
| Actions tab shows no workflows | GitHub Actions may be disabled for the repository | Go to **Repository → Settings → Actions → General** and enable Actions |

---

## Security Notes

- **Secrets are never logged** — GitHub Actions automatically redacts secret values from workflow logs.
- **Temporary keychain** — the signing keychain is created at the start of the CI run and deleted in the cleanup step, even if the run fails.
- **Certificate file** — the `.p12` is decoded to a temp file on the runner's ephemeral disk, which is discarded when the runner is recycled.
- **App-Specific Password** — it is recommended to rotate the `APPLE_APP_PASSWORD` periodically at [appleid.apple.com](https://appleid.apple.com).
