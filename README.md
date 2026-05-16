# Assistant

Native macOS second-brain assistant. See `docs/superpowers/specs/` for design specs.

## Dev setup

Requirements: macOS 13+, Xcode 15+, `brew install xcodegen`.

```bash
# Generate Xcode project
xcodegen generate

# Build both targets
xcodebuild -project Assistant.xcodeproj -scheme AssistantUI build
xcodebuild -project Assistant.xcodeproj -scheme AssistantCoreHelper build

# Install the dev LaunchAgent (loads the daemon)
./Scripts/install-dev-agent.sh

# Launch the UI app
open ~/Library/Developer/Xcode/DerivedData/Assistant-*/Build/Products/Debug/AssistantUI.app
```

Click the menu-bar brain icon → "Ping daemon". Expected reply: "pong".

To remove the daemon: `./Scripts/uninstall-dev-agent.sh`.

## Running unit tests

```bash
swift test
```

## Installation (end-user)

Launch Assistant for the first time. The onboarding wizard walks you through:
1. Enter your Claude API key
2. Connect Google Calendar (paste an OAuth Client ID + complete consent flow)
3. Pick a summon hotkey
4. Approve the background daemon registration in System Settings

That's it.

## Installation (developer, unsigned builds)

If SMAppService refuses to register an unsigned Debug build, fall back to:

    ./Scripts/install-dev-agent.sh

To remove:

    ./Scripts/uninstall-dev-agent.sh
