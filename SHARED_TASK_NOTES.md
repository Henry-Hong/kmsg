# kmsg - KakaoTalk CLI Tool

## Current Status

Basic project structure is complete with working CLI commands:

- `kmsg status` - Check accessibility and KakaoTalk status ✓
- `kmsg inspect` - Inspect UI hierarchy ✓
- `kmsg chats` - List chats (basic implementation)
- `kmsg send` - Send message (basic implementation)
- `kmsg read` - Read messages (basic implementation)

Build: `swift build`
Run: `.build/debug/kmsg`

## KakaoTalk UI Structure (discovered via inspect)

Main window (`id: Main Window`):

- Navigation buttons: `id: friends`, `id: chatrooms`, `id: more`
- Unread count: `AXStaticText` with value like "999+"
- Content area: `AXScrollArea > AXTable > AXRow > AXCell`

Chat window (e.g., `title: "홍길동"`):

- Messages: `AXScrollArea > AXTable > AXRow` structure
- Input: Look for `AXTextArea` or `AXTextField`

## Next Steps

1. **Improve chat list parsing** - Extract chat names from AXCell children
2. **Add friends command** - List friends from friends tab
3. **Improve message reading** - Parse actual message content from rows
4. **Test send command** - Verify keyboard input works for Korean text
5. **Add open command** - Open a specific chat by name/search
6. **Error handling** - Better feedback when elements not found

## Technical Notes

- Uses macOS Accessibility APIs (AXUIElement)
- Requires Accessibility permission in System Settings
- KakaoTalk bundle ID: `com.kakao.KakaoTalkMac`
- Keyboard input uses CGEvent for Korean text support

## Testing

```bash
# Check status
.build/debug/kmsg status --verbose

# Inspect UI (very useful for debugging)
.build/debug/kmsg inspect --depth 5 --window 1

# With attributes
.build/debug/kmsg inspect --depth 3 --show-attributes
```
