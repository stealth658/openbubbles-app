# Message Receive Flow

End-to-end flow for an inbound message: from the server socket through the database to the reactive UI state.

For the outgoing half (user sends a message), see `docs/MESSAGE_SEND_FLOW.md`.

---

## High-Level Overview

```
Server WebSocket event: "new-message" / "updated-message"
  → SocketService
  → MessageHandlerSvc.handleEvent()  (action_handler.dart)
  → IncomingQueue  (serial FIFO)
  → MessageHandlerSvc.handleNewMessage() or handleUpdatedMessage()
  → chat.addMessage() → ChatInterface → GlobalIsolate → ChatActions (ObjectBox write)
  → hydrate ID → Message object
  → ChatsSvc.updateChat()       → ChatState.*Internal()     → Obx() rebuild
  → MessagesSvc.updateMessage() → MessageState.*Internal()  → Obx() rebuild
```

---

## Step-by-Step Detail

### Step 1 — Socket Receives Event (`socket_service.dart`)

The WebSocket connection maintained by `SocketService` registers listeners at startup:
```dart
socket?.on("new-message",     (data) => MessageHandlerSvc.handleEvent("new-message",     data, 'DartSocket'));
socket?.on("updated-message", (data) => MessageHandlerSvc.handleEvent("updated-message", data, 'DartSocket'));
```

No parsing or routing logic lives here — raw JSON is passed directly to `MessageHandlerSvc`. Firebase push and the Android method channel use the same `handleEvent()` entry point with a different `source` string.

**Key file:** `lib/services/network/socket_service.dart`

---

### Step 2 — Event Dispatch (`action_handler.dart`)

`MessageHandlerSvc` is a GetIt singleton alias for `ActionHandler`. All incoming event routing lives here.

**`handleEvent(eventName, data, source)`** parses the raw payload into a typed `ServerPayload`, extracts the `Chat` and `Message`, and creates an `IncomingItem`. It then routes to the queue:
- **Normal path:** `inq.queue(item)` — ensures serial ordering
- **Fast path** (used by some Firebase/push codepaths): calls `handleNewMessage()` / `handleUpdatedMessage()` directly without queuing

For `"new-message"` events on messages sent by this device, the handler checks whether a `tempGuid` field is present in the payload. If it is, the server is echoing back a message we sent — see `docs/MESSAGE_SEND_FLOW.md` for how the tempGuid → realGuid swap is resolved.

**Key file:** `lib/services/backend/action_handler.dart`

---

### Step 3 — IncomingQueue (`incoming_queue.dart`)

`IncomingQueue` is a serial FIFO queue (backed by the abstract `Queue` base class in `queue_impl.dart`). It processes one `QueueItem` at a time — the next item only starts after the previous one fully completes. This prevents race conditions on `Chat.latestMessage` and the unread badge when two messages arrive nearly simultaneously.

Routing by `QueueType`:
- `QueueType.newMessage` → `MessageHandlerSvc.handleNewMessage(chat, message, tempGuid)`
- `QueueType.updatedMessage` → `MessageHandlerSvc.handleUpdatedMessage(chat, message, tempGuid)`

**Key file:** `lib/services/backend/queue/incoming_queue.dart`

---

### Step 4 — Handle New Message (`action_handler.dart`)

**`handleNewMessage(Chat, Message, tempGuid?)`:**

1. **Deduplication** — checks `handledNewMessages` (a rolling list of the last 100 GUIDs). If the GUID was already processed (e.g. delivered by both socket and Firebase), the method returns early.

2. **Ensure Chat exists** — looks up the chat in ObjectBox by GUID. If not found, bulk-syncs it via `ChatInterface.bulkSyncChats()`. This ensures the message has a valid parent chat before insertion.

3. **Save message to DB** — calls `chat.addMessage(message)`. This is the DB write entry point (see Step 5).

4. **Post-save** — plays notification sound, creates a local notification via `NotificationsService` if appropriate, and clears the notification badge for messages from this device.

5. **Update chat list** — calls `ChatsSvc.updateChat(chat, override: true)` to push the new `latestMessage` and unread state into `ChatState` (see Step 7).

**`handleUpdatedMessage(Chat, Message, tempGuid?)`:**

1. **Resolve temp → real GUID** — if `tempGuid` is set, this is a sent-message confirmation. Calls `matchMessageWithExisting(chat, tempGuid, realMessage)` to swap the record (see `docs/MESSAGE_SEND_FLOW.md` Step 7).

2. **Update attachments** — for each attachment on the updated message, `matchAttachmentWithExisting()` resolves the attachment GUID.

3. **Update message state** — calls `MessagesSvc(chat.guid).updateMessage(message, oldGuid: tempGuid)` to push changes into `MessageState` (see Step 8).

---

### Step 5 — Database Write (via Interface + GlobalIsolate)

**Entry point:** `chat.addMessage(message)` in `lib/database/io/chat.dart`

**`ChatInterface.addMessageToChat()`** (`lib/services/backend/interfaces/chat_interface.dart`):

- Packs arguments into a `Map<String, dynamic>` (all values must be primitive — no ObjectBox entities cross the isolate boundary)
- **If already inside an isolate** (`isIsolate == true`): calls `ChatActions.addMessageToChat(data)` directly
- **If on the main thread:** dispatches to `GlobalIsolate.send(IsolateRequestType.addMessageToChat, data)` and awaits the response
- After the isolate returns `{ messageId: int, isNewer: bool }`, hydrates the result: `Database.messages.get(messageId)` → full `Message` object (O(1) lookup)

**`ChatActions.addMessageToChat()`** (`lib/services/backend/actions/chat_actions.dart`) runs inside the isolate:
- Upserts the `Message` record into ObjectBox
- Updates `Chat.latestMessage` pointer if the new message is newer
- Returns a plain map — never ObjectBox entities

For a temp → real GUID swap, `MessageInterface.replaceMessage()` → `MessageActions.replaceMessage()` follows the same isolate routing pattern and atomically updates the GUID on the existing record.

**Key files:**
- `lib/database/io/chat.dart` — `addMessage()`
- `lib/services/backend/interfaces/chat_interface.dart` — `addMessageToChat()`
- `lib/services/backend/actions/chat_actions.dart` — `addMessageToChat()` (runs in isolate)

---

### Step 6 — Unread / Archive State Update

Inside `chat.addMessage()`, after the DB write, the chat's unread and archive state is updated:
- If the message is **from someone else** and is newer: `chat.toggleHasUnreadAsync(true)` — marks the chat as having an unread message
- If the message is **from this device**: `chat.toggleHasUnreadAsync(false)` — clears the unread badge
- If the chat was **archived** and receives a message from someone else: `chat.toggleArchivedAsync(false)` — unarchives it automatically

These also go through `ChatInterface` → ObjectBox in the isolate.

---

### Step 7 — Chat Service State Update (`chats_service.dart`)

**`ChatsSvc.updateChat(Chat updated)`:**

1. Finds the `ChatState` for this chat (keyed by GUID in `chatStates` map)
2. Calls `state.updateFromChat(updated)` — updates every changed `Rx*` field via `*Internal()` methods. Each `Obx()` widget watching a field rebuilds independently — a `latestMessage` change does not force the chat title to rebuild.
3. If `latestMessage` or `pinIndex` changed (sort-order-relevant), calls `_repositionChat()` to re-sort the chat list

**Key file:** `lib/services/ui/chat/chats_service.dart`

---

### Step 8 — Message Service State Update (`messages_service.dart`)

**`MessagesSvc(chatGuid).updateMessage(Message updated, {String? oldGuid})`:**

1. Finds the existing `Message` in the in-memory `MessageStruct` by `oldGuid` (if swapping) or by `updated.guid`
2. Merges the updated message with the existing one (`updated.mergeWith(existing)`)
3. Finds or creates the `MessageState` for this message
4. Calls `messageState.updateFromMessage(updated)` — pushes new values into all `Rx*` fields
5. **If `oldGuid != null`** (tempGuid → realGuid swap): removes `messageStates[oldGuid]` and inserts `messageStates[realGuid]` pointing to the same state object
6. Increments `messageUpdateTrigger[realGuid]` — widgets that observe the trigger rather than individual fields are notified to rebuild

**Key file:** `lib/services/ui/message/messages_service.dart`

---

### Step 9 — UI Reactivity (`lib/app/state/`)

`ChatState` and `MessageState` are never written to directly by UI code. The only write path is `*Internal()` methods called by the service layer.

**ChatState observables** that drive UI rebuilds: `isPinned`, `hasUnreadMessage`, `isArchived`, `muteType`, `title`, `displayName`, `subtitle`, `latestMessage`, `textFieldText`, `isActive`, `isAlive`, and others. Each is a separate `Rx*` field.

**MessageState observables**: `guid`, `text`, `dateDelivered`, `dateRead`, `dateEdited`, `error`, `hasReactions`, `associatedMessages`, `isSending`, `isSent`, `hasError`, `isReaction`, and others.

Because each field is its own observable, `Obx()` rebuilds only the widget that reads that specific field. An unread badge update does not re-render the chat title. A delivery timestamp update does not re-render the message bubble text.

---

## Key Files at a Glance

| Step | File | Key Method |
|------|------|-----------|
| Socket | `lib/services/network/socket_service.dart` | `socket.on("new-message", ...)` |
| Event dispatch | `lib/services/backend/action_handler.dart` | `handleEvent()`, `handleNewMessage()`, `handleUpdatedMessage()` |
| Queue | `lib/services/backend/queue/incoming_queue.dart` | `handleQueueItem()` |
| Chat DB entry | `lib/database/io/chat.dart` | `addMessage()` |
| Interface (chat) | `lib/services/backend/interfaces/chat_interface.dart` | `addMessageToChat()` |
| Interface (message) | `lib/services/backend/interfaces/message_interface.dart` | `replaceMessage()` |
| Isolate actions | `lib/services/backend/actions/chat_actions.dart` | `addMessageToChat()` (runs in isolate) |
| Chat state update | `lib/services/ui/chat/chats_service.dart` | `updateChat()` |
| Message state update | `lib/services/ui/message/messages_service.dart` | `updateMessage()` |
| Reactive state | `lib/app/state/chat_state.dart` | `updateFromChat()`, `update*Internal()` |
| Reactive state | `lib/app/state/message_state.dart` | `updateFromMessage()`, `update*Internal()` |
