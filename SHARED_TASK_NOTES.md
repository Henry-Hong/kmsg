# SHARED_TASK_NOTES

## Current State

Basic Swift package structure is complete and compiles:
- `KakaoTalkAccessibility` library - wraps macOS Accessibility APIs
- `kmsg` CLI executable - uses swift-argument-parser

## Available Commands

- `kmsg status` - checks accessibility permissions and KakaoTalk running state
- `kmsg hierarchy` - prints the KakaoTalk UI element tree (for debugging)

## Next Steps (Priority Order)

1. **Analyze KakaoTalk UI structure** - Run `kmsg hierarchy` with KakaoTalk open to understand the element tree. This is essential before implementing the commands below.

2. **Implement `friends` command** - List friends from the friend list tab
   - Need to navigate to friend list tab
   - Parse the list items

3. **Implement `chats` command** - List chat rooms from the chat tab
   - Need to navigate to chat tab
   - Parse the chat room list

4. **Implement `messages` command** - Read messages from a specific chat
   - Need to open/find a specific chat room
   - Parse message bubbles

5. **Implement `send` command** - Send a message to a chat
   - Find the text input field
   - Enter text and press send

## Technical Notes

- KakaoTalk macOS bundle identifier: `com.kakao.KakaoTalkMac`
- Uses `ApplicationServices` framework for AXUIElement APIs
- User must grant accessibility permission in System Settings

## Files Structure

```
Sources/
  KakaoTalkAccessibility/
    AccessibilityError.swift    # Error types
    AccessibilityHelper.swift   # Low-level AX API helpers
    KakaoTalkApp.swift          # High-level KakaoTalk wrapper
    KakaoTalkAccessibility.swift # Module exports
  kmsg/
    Kmsg.swift                  # Main entry point
    Commands/
      StatusCommand.swift       # status subcommand
      HierarchyCommand.swift    # hierarchy subcommand
```

## Running the Tool

```bash
swift build
.build/debug/kmsg status
.build/debug/kmsg hierarchy --depth 8
```
