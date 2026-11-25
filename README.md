# Psst

Little messengers for your Mac notifications.

Psst turns Claude and Codex desktop notifications into animated companions and speech bubbles. Claude gets a warm sunburst; Codex gets a terminal robot and a blue bubble. All eight entrances rotate in a shuffled order, starting at random points along the screen edges.

## Download and install

Get **Psst-0.7.0-universal.dmg** from [Releases](https://github.com/Sickaada/psst/releases). Apple Silicon and Intel are included in one app. macOS 14 or newer is required. Notification compatibility depends on the macOS and source-app versions; this first release has not been tested on every supported Mac.

1. Open the disk image and drag **Psst** into **Applications**. Eject the disk image.
2. Open Psst from Applications. This personal/community build is locally signed, **not Apple-notarized**. If macOS blocks it, review [Apple’s instructions for opening an app from an unidentified developer](https://support.apple.com/en-us/102445). Only proceed if you trust this download. Do not disable Gatekeeper globally or install a signing certificate.
3. Click **Connect**, then enable Psst in **System Settings → Privacy & Security → Accessibility**. Quit and reopen Psst if the connection does not refresh.
4. Keep notifications and banners enabled for Claude/Codex in macOS settings. Focus modes may suppress banners, which Psst cannot capture.
5. Use **Preview** to check the characters, then trigger a real notification while Claude/Codex is in the background.
6. Optional: add **Psst** under **System Settings → General → Login Items → Open at Login**. The sparkle menu provides settings and Quit.

A ZIP version is also available if you prefer to unzip and move `Psst.app` into Applications. No Python, Node, Xcode, API key, or subscription is required to use the downloaded app.

## What it does

- Eight styles: running, chasing, parkour, delivery, portal, peekaboo, celebration, floating.
- Every style appears before the shuffle refills; no immediate repeats at cycle boundaries.
- Random entrance points on all four edges of the main display’s visible area. The message stays in your chosen corner.
- Hover pauses dismissal. Close dismisses the card and its companion.
- **Open chat** invokes the original notification’s Open action when it remains available. If the notification expired or macOS does not expose that action, Psst opens the app instead. Chat routing depends on the source app; it is not guaranteed for every notification.
- Reduce Motion uses a stationary character and fade.
- Optional message-text hiding and experimental original-banner suppression.

## Privacy and limitations

Psst reads visible Notification Center banners through Accessibility. It does not record your screen, read your chat history, request notification APIs from Claude/Codex, or send data to a server. Notification text stays in memory and is not written to diagnostics. Preferences stay on your Mac.

Diagnostics contain event names, counters, source-app names, timing and runtime status in `~/Library/Logs/Psst/`. Notification Center’s Accessibility structure is not a stable public integration contract, so macOS updates can affect capture. Standard macOS banners must stay enabled. Reply buttons and other original notification actions are not reproduced.

This is an independent community app, not affiliated with Anthropic or OpenAI. The bundle identifier remains `local.alienping.mac` to retain existing users’ preferences and Accessibility identity after the rename.

## Build from source

Requires Xcode Command Line Tools / Swift 5.9+ and Python 3. No third-party Swift packages.

```sh
swift run --package-path . AlienCoreTests
python3 scripts/test_pipeline.py
python3 scripts/test_signing.py
python3 scripts/validate_sprites.py
```

To make your own persistent local signing identity (one-time, macOS Keychain may ask for approval):

```sh
python3 scripts/setup_signing.py
./build.sh
```

The output defaults to `../Psst.app`; set `APP_OUTPUT` to choose another path. The private signing key stays in your Keychain; never commit/export it to this repository. `scripts/sign_app.py` pins the certificate and bundle identifier and fails if no valid signing configuration exists. It does not silently fall back to ad-hoc signing. Our release signing identity is not included. Your own builds require your own initial Accessibility approval.

`./pipeline.sh update --preview` is the legacy developer checkout updater. It uses `../AlienPing.app`, takes a backup, verifies signatures, checks a fresh runtime heartbeat, and sends synthetic notifications. It does not overwrite `/Applications/Psst.app`. `./pipeline.sh rollback` restores its previous local build and re-signs it with the configured identity.

For a distributable release, run `python3 scripts/package_release.py /path/to/Psst.app /path/to/output`. Apple Developer ID signing and notarization are required for normal trusted public distribution; this repository does not claim notarization.

## License

MIT for code and original procedural companion artwork. The bundled legacy arrival-effect atlas is CC0; see [asset attribution](Resources/Mascots/LICENSES.txt).
