# lib/app/state/ — Reactive State Wrappers

Two files. These are the bridge between ObjectBox DB entities and the UI.

## Files
- `chat_state.dart` — `ChatState`: reactive wrapper for a `Chat` entity
- `message_state.dart` — `MessageState`: reactive wrapper for a `Message` entity

## Purpose
ObjectBox entities are heavy (lazy-loaded relations, DB context required). Re-querying the DB on every UI event would be expensive. Instead, `ChatState`/`MessageState` mirror the UI-relevant fields as `Rx*` observables so widgets can rebuild only the sub-tree that cares about a specific field.

## Key Rules
- **Never write to a state object from UI code.** Only `*Internal()` methods may mutate observables.
- `*Internal()` methods are called exclusively by `ChatsService` (for `ChatState`) and `MessagesService` (for `MessageState`) after a confirmed DB write.
- Each `Rx*` field is independent — a badge update does not trigger a title rebuild.

## ChatState Observable Fields
| Field | Type | Driven by |
|-------|------|-----------|
| `isPinned` | `RxBool` | pin/unpin |
| `hasUnreadMessage` | `RxBool` | mark read/unread |
| `isArchived` | `RxBool` | archive |
| `muteType` / `muteArgs` | `RxnString` | mute settings |
| `title` / `displayName` / `subtitle` | `RxnString` | contact name changes |
| `latestMessage` | `Rxn<Message>` | new message received |
| `textFieldText` / `textFieldAttachments` | reactive | draft persistence |
| `isActive` / `isAlive` | `RxBool` | lifecycle (conversation open) |

## MessageState Observable Fields
Key observables: `guid`, `text`, `dateDelivered`, `dateRead`, `dateEdited`, `error`, `hasReactions`, `associatedMessages`, `isSending`, `isSent`, `hasError`, `isReaction`.

## Updating State (correct pattern)
```dart
// In ChatsService, after DB write:
chatState.updateHasUnreadInternal(true);

// In MessagesService, after DB write:
messageState.updateDateReadInternal(DateTime.now());
```

## Bulk Update
`updateFromChat(Chat)` and `updateFromMessage(Message)` update all fields at once from a freshly fetched DB object.

## Redaction
Both state classes support `redactFields()` / `unredactFields()` for redacted mode — called by the service layer when the setting changes.

## Where ChatState lives
`ChatsService` owns a `Map<String, ChatState>` keyed by chat GUID. Access via `ChatsSvc.getChatState(guid)`.

## Where MessageState lives
`MessagesService` owns a `Map<String, MessageState>` keyed by message GUID.
