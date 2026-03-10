# conversation_view/ — Message Thread UI

## Structure
- `pages/conversation_view.dart` — main chat screen
- `pages/messages_view.dart` — scrollable message list
- `widgets/message/` — all message rendering → `CLAUDE.md` inside
- `widgets/header/` — chat header bar and info → `CLAUDE.md` inside
- `widgets/text_field/` — message composer
  - `buttons/` — attachment, emoji, send buttons
  - `helpers/` — input field helpers
- `widgets/media_picker/` — file/image selection UI
- `mixins/messages_service_mixin.dart` — message loading logic

## Controller
`ConversationViewController` → `lib/services/ui/chat/conversation_view_controller.dart`
