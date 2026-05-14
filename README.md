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
