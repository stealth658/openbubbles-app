# chat_creator/ — New Chat Creation

## Main
`chat_creator.dart` — modal/page entry; uses `ChatCreatorController`

## Widgets (`widgets/`)
- `chat_creator_tile.dart` — contact/chat row in the picker list
- `selected_contact_chip.dart` — removable chip for each selected contact
- `chat_list_section.dart` — existing chats list (for resuming a conversation)
- `message_type_toggle.dart` — SMS vs iMessage toggle

## Flow
1. User searches/selects contacts → chips appear at top
2. Toggle SMS vs iMessage
3. If matching chat already exists → continue that chat
4. If new → `ChatInterface.createChat()` → navigate to new `ConversationView`
