# kmsg

A CLI tool for KakaoTalk on macOS using Accessibility APIs.

## Features

- Check KakaoTalk status
- Inspect UI hierarchy for debugging
- List chat rooms
- Send messages
- Read messages

## Requirements

- macOS 13.0+
- KakaoTalk for Mac
- Accessibility permission granted

## Installation

```bash
# Clone the repository
git clone https://github.com/channprj/kmsg.git
cd kmsg

# Build
swift build -c release

# Install (optional)
mkdir -p ~/.local/bin
cp .build/release/kmsg ~/.local/bin/
export PATH="$HOME/.local/bin:$PATH"
```

## Usage

### Check Status

```bash
kmsg status
kmsg status --verbose
```

### Inspect UI

```bash
# Inspect main window
kmsg inspect

# Inspect specific window with more depth
kmsg inspect --window 1 --depth 5

# Show all attributes
kmsg inspect --show-attributes
```

### List Chats

```bash
kmsg chats
kmsg chats --verbose
```

### Send Message

```bash
kmsg send "Friend Name" "Hello!"
kmsg send "Chat Room" "Message" --dry-run
```

### Read Messages

```bash
kmsg read "Chat Name"
kmsg read "Chat Name" --limit 50
```

## Permissions

This tool requires Accessibility permission to control KakaoTalk:

1. Open **System Settings** > **Privacy & Security** > **Accessibility**
2. Click the **+** button
3. Navigate to and select the `kmsg` binary
4. Enable the toggle for `kmsg`

## How It Works

kmsg uses macOS Accessibility APIs (`AXUIElement`) to interact with KakaoTalk's user interface. This approach:

- Doesn't require reverse engineering KakaoTalk protocols
- Doesn't violate KakaoTalk's terms of service
- Works with the official KakaoTalk for Mac app
- Is safe and respects user privacy

## License

MIT License - See [LICENSE](LICENSE) for details.
