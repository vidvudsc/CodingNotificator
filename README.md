# Coding Notificator

A small macOS menu bar app for keeping an eye on coding agents without babysitting the terminal.

Coding Notificator watches local OpenCode/Codex activity, shows compact notch-style status updates, plays lightweight sounds for important state changes, and exposes a clean AI usage popover from the menu bar.

![Coding Notificator usage popover](docs/images/usage-popover.png)

## What It Does

- Shows Codex and OpenCode usage in a compact menu bar popover.
- Displays Codex 5h and weekly reset timing from local Codex session data.
- Tracks OpenCode 5h, weekly, and monthly usage from the local OpenCode database.
- Shows notch-style overlays for finished, failed, and input-required agent states.
- Uses separate sounds for completion, required input, and failure.
- Keeps running/busy events silent so repeated OpenCode status updates do not become noisy.

![Coding Notificator notch notification](docs/images/notch-notification.png)

## Usage Panel

The menu bar panel keeps the app intentionally small:

- **OpenCode**: `5h`, `Weekly`, and `Monthly` usage percentages.
- **Codex**: `5h left` and `Weekly left`, with reset countdowns when Codex exposes them.
- Progress bars shift from healthy green to warning amber to critical red.

## Agent Notifications

The app listens for local event files written by OpenCode/Codex helper workflows and turns them into native macOS feedback:

- `done` / `session.idle`: completion overlay and sound.
- `requires_input` / `permission.asked`: input-required overlay and sound.
- `failed` / `session.error`: failure overlay and sound.
- `running` / `busy`: state update only, no sound.

## Building

Open the Xcode project and build the `CodingNotificator` scheme, or build from the terminal:

```bash
xcodebuild -project CodingNotificator.xcodeproj -scheme CodingNotificator -configuration Debug build
```

To install the current debug build into your user Applications folder:

```bash
APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData -path '*/Build/Products/Debug/CodingNotificator.app' -type d | head -1)
ditto "$APP_PATH" ~/Applications/CodingNotificator.app
open ~/Applications/CodingNotificator.app
```

## Notes

This is a local utility. Usage values come from local OpenCode and Codex files, so OpenCode numbers can differ slightly from the OpenCode web dashboard when the server has usage that has not landed in the local database.
