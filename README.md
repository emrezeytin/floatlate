# Floatlate

A menu bar translator for macOS. Click the menu bar icon or press ⌃⌥T to open it. Right-click the icon for settings.

![Floatlate in light mode translating French to English, and in dark mode waiting for input](docs/screenshot.png)

## Install

Download the latest `Floatlate-x.y.z.dmg` from [Releases](https://github.com/emrezeytin/floatlate/releases/latest). Open it and drag Floatlate to Applications. The app is signed and notarized by Apple.

Requires macOS 15 or later.

## Input

- Type or paste text.
- Paste anything with ⇧⌘V: text, an image, or a copied file.
- Drop text, images, PDFs, or documents (.txt, .rtf, .docx, .html) on the menu bar icon.
- Press ⌃⌥S anywhere, then drag over part of the screen. Floatlate reads the text and translates it.
- While Floatlate reads an image, it shows the image. After that, a thumbnail stays above the text. Click it to enlarge it.

## Shortcuts

| Keys | Action |
| --- | --- |
| ⌃⌥T | Open or close Floatlate |
| ⌃⌥S | Capture text from the screen |
| ⇧⌘V | Paste text, image, or file |
| ⌘O | Open a file |
| ⇧⌘C | Copy the translation |
| ⌘K | Clear |
| ⌘. | Stop translating |
| Esc | Close |

## How it works

- Apple's Translation framework translates on the device. No account, no API key.
- Vision reads text from images and scanned PDFs.
- Lines show as soon as each one is translated.
- On macOS 26 or later, translation keeps going after you close Floatlate. Click the stop button or press ⌘. to cancel it.
- If the text is already in your target language, Floatlate translates it into the last language you translated from.

## Speed and quality

Floatlate uses Apple's fast translation model by default.

- The first time you translate between two languages, macOS asks to download that pair. Approve it once.
- Keep the download sheet open until the download ends. If you close it early, wait a moment, then click **Try Again**.
- The fast and high-quality models download separately.
- For better but slower results, right-click the menu bar icon and choose **High-Quality Translation (Slower)**. It takes about 0.7 seconds per line.
- The high-quality option needs macOS 26.4 or later. Older systems use Apple's default model.

## Permissions

- The first ⌃⌥S asks for Screen Recording access. Allow it in System Settings → Privacy & Security → Screen & System Audio Recording.
- If Floatlate is not in that list, click **+** and add it.
- A plain `./build.sh` build is ad-hoc signed. macOS ties the permission to that exact binary, so it asks again after each rebuild.
- Build with `SIGN_IDENTITY="Developer ID Application"` to keep the permission across rebuilds. Release builds keep it too.

## Build

```bash
./build.sh
```

```bash
ditto build/Floatlate.app ~/Applications/Floatlate.app
```

To redraw the app icon after changing `Scripts/make-icon.swift`:

```bash
swift Scripts/make-icon.swift Resources/AppIcon.icns
```

To redraw the README screenshot after a UI change:

```bash
./Scripts/make-screenshots.sh
```

`build.sh` also reads these settings:

| Setting | Effect |
| --- | --- |
| `VERSION=1.2.0` | Sets the app version |
| `UNIVERSAL=1` | Builds for Apple silicon and Intel |
| `SIGN_IDENTITY="Developer ID Application"` | Signs with that certificate and the hardened runtime |

## Release

One-time setup:

1. Create a **Developer ID Application** certificate: Xcode → Settings → Accounts → Manage Certificates → + → Developer ID Application.
2. Create an app-specific password at [account.apple.com](https://account.apple.com) → Sign-In and Security → App-Specific Passwords.
3. Save the notary credentials in your keychain:

```bash
xcrun notarytool store-credentials floatlate --apple-id YOUR_APPLE_ID --team-id 4UT7HVR48K
```

To release, commit and push `main`, then run:

```bash
./Scripts/release.sh 1.0.0
```

The script:

1. Builds a universal app and signs it with the hardened runtime.
2. Notarizes the app with Apple and staples the ticket.
3. Packs the app into a DMG, then signs, notarizes, and staples the DMG.
4. Checks both with Gatekeeper.
5. Tags `v1.0.0` and publishes a GitHub release with the DMG and its SHA-256.

## License

[MIT](LICENSE)
