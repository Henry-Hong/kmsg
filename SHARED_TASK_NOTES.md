# SHARED_TASK_NOTES

## Current State

Swift package is functional with core chat and friend functionality implemented:
- `KakaoTalkAccessibility` library - wraps macOS Accessibility APIs
- `kmsg` CLI executable - uses swift-argument-parser

## Available Commands

- `kmsg status` - checks accessibility permissions and KakaoTalk running state
- `kmsg hierarchy [--depth N]` - prints the KakaoTalk UI element tree (for debugging)
- `kmsg friends [--limit N] [--verbose]` - lists friends from KakaoTalk
- `kmsg chats [--limit N] [--verbose]` - lists chat rooms from KakaoTalk
- `kmsg send "message" [--chat NAME] [--dry-run]` - sends a message

## Next Steps (Priority Order)

1. **Test with real KakaoTalk** - The chat list, friend list, and send functionality need real-world testing. KakaoTalk's UI structure may vary.

2. **Implement `read` command** - Read messages from a specific chat
   - Find message elements in the chat window
   - Parse message content, sender, timestamps

3. **Improve detection heuristics** - After testing with real KakaoTalk, refine `findChatListRows()` and `findFriendListRows()` logic.

4. **Add error recovery** - Retry logic for transient accessibility failures

## Technical Notes

- KakaoTalk macOS bundle identifier: `com.kakao.KakaoTalkMac`
- Uses `ApplicationServices` framework for AXUIElement APIs
- User must grant accessibility permission in System Settings
- Send functionality tries `kAXConfirmAction` (Enter) by default, `--use-send-button` for click
- Tests require Xcode (not just Command Line Tools) due to XCTest

## File Structure

```
Sources/
  KakaoTalkAccessibility/
    AccessibilityError.swift    # Error types
    AccessibilityHelper.swift   # Low-level AX API helpers
    KakaoTalkApp.swift          # High-level KakaoTalk wrapper (ChatRoom, Friend)
    KakaoTalkAccessibility.swift # Module exports
  kmsg/
    Kmsg.swift                  # Main entry point
    Commands/
      StatusCommand.swift       # status subcommand
      HierarchyCommand.swift    # hierarchy subcommand
      FriendsCommand.swift      # friends subcommand
      ChatsCommand.swift        # chats subcommand
      SendCommand.swift         # send subcommand
```

## Running the Tool

```bash
swift build
.build/debug/kmsg status
.build/debug/kmsg hierarchy --depth 8
.build/debug/kmsg friends --limit 20 --verbose
.build/debug/kmsg chats --limit 10 --verbose
.build/debug/kmsg send "Hello!" --chat "Friend Name" --dry-run
```

## Known Limitations

- Chat/friend list detection is heuristic-based and may need adjustment after testing
- Send via Enter key (`kAXConfirmAction`) may not work in all cases
- No message history reading yet
