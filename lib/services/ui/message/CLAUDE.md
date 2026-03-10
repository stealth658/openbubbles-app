# services/ui/message/ — Message State & Widget Controllers

## Files
| File | Purpose |
|------|---------|
| `messages_service.dart` | Per-chat message cache, `MessageState` map, update triggers |
| `message_widget_controller.dart` | Per-message controller for parts, edits, and audio |

---

## MessagesService (`messages_service.dart`)

One instance per chat GUID. Accessed via `MessagesSvc(chatGuid)`.

**What it owns:**
- `messageStates` — `Map<String, MessageState>` keyed by message GUID
- `messageUpdateTrigger` — `RxMap<String, int>` timestamps; widgets watch a message's entry here to know when to rebuild
- `struct` — in-memory `MessageStruct` for ordered access and range queries
- Per-message `MessageWidgetController` map

**Key methods:**
- `updateMessage(Message, {String? oldGuid})` — the main write path; merges changes into `MessageState` and handles tempGuid → realGuid remapping
- `addMessages(List<Message>)` — bulk-inserts into the struct and creates `MessageState` entries
- `getMessage(String guid)` → `Message?` — fast in-memory lookup
- `getOrCreateController(Message)` → `MessageWidgetController` — lazily creates a per-message controller

**Convenience getters:**
- `mostRecentSent` — the most recently sent outgoing message
- `mostRecent` — the most recent message in the thread
- `mostRecentReceived` — the most recent incoming message

**Rules:**
- Never write `MessageState` fields directly from UI — always go through `MessagesService.updateMessage()`
- Widgets should observe `messageUpdateTrigger[guid]` in an `Obx()` to know when to re-query state
- For bulk initial load, use `addMessages()` which skips per-field update overhead

**For the full update flow**, see `docs/MESSAGE_RECEIVE_FLOW.md`.

---

## MessageWidgetController (`message_widget_controller.dart`)

One instance per visible message. Obtained via `MessagesSvc(chatGuid).getOrCreateController(message)`.

**What it owns:**
- Parsed `List<MessagePart>` — the message content split into typed parts (text, attachment, etc.)
- Edit history display state
- Audio playback tracking

**Lifecycle:** Created lazily when a message widget first renders; cached in `MessagesService` so the same controller is returned on re-renders. Cleared when the message is removed from the visible list.

**Access pattern in widgets:**
```dart
final controller = MessagesSvc(chat.guid).getOrCreateController(message);
final parts = controller.parts;  // pre-parsed, cached
```
