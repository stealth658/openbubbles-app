# Message Send Flow

End-to-end flow for an outbound message: from the user tapping Send through the API call, the race between the socket response and the HTTP response, and the tempGuid → realGuid swap that merges them.

For the inbound half of this flow (after the server echoes the message back), see `docs/MESSAGE_RECEIVE_FLOW.md`.

---

## High-Level Overview

```
UI (send button tap)
  → build Message with tempGuid
  → OutgoingQueue (serial, one at a time)
      → prepMessage: save to DB with tempGuid (appears in UI as "sending")
      → sendMessage: fire HTTP POST; register send progress tracker
          ↓ (concurrent)
    ┌─────────────────────┬──────────────────────────┐
    │ Path A              │ Path B                   │
    │ Socket/Firebase     │ HTTP response             │
    │ fires first         │ arrives first             │
    └─────────────────────┴──────────────────────────┘
          ↓ (both paths converge here)
      matchMessageWithExisting(tempGuid, realMessage)
        → delete temp record, upsert real record
        → MessagesService.updateMessage(real, oldGuid: temp)
          → MessageState: isSending → false, isSent → true
          → UI rebuilds (bubble stops animating)
```

---

## Step-by-Step Detail

### Step 1 — User Taps Send (`send_button.dart`)

The Send button calls the `sendMessage` callback passed down from `ConversationTextField`. Validation runs (non-empty content, setup complete, etc.), then delegates to `controller.send()` (`conversation_view_controller.dart`), which calls the `sendFunc` registered by `SendAnimation`.

**Key file:** `lib/app/layouts/conversation_view/widgets/text_field/send_button.dart`

---

### Step 2 — Build Message Objects with tempGuid (`send_animation.dart`)

`SendAnimation.send()` constructs one `Message` per attachment and one for the text body (if non-empty).

**For each message:**
```dart
message.generateTempGuid();  // sets guid = "temp-XXXXXXXX" (8 random chars)
```

The tempGuid format is always `temp-` followed by 8 random alphanumeric characters (e.g. `temp-a7d3k9m2`). This prefix is how the app detects "sending" state: `message.isSending == guid.startsWith("temp")`.

Each message is then wrapped in an `OutgoingItem` and pushed to the `OutgoingQueue`:
```dart
outq.queue(OutgoingItem(
  type: QueueType.sendMessage,   // or sendMultipart, sendAttachment
  chat: controller.chat,
  message: message,              // has tempGuid at this point
));
```

**Key file:** `lib/app/layouts/conversation_view/widgets/message/send_animation.dart`

---

### Step 3 — OutgoingQueue: Prepare (`outgoing_queue.dart` → `action_handler.dart`)

`OutgoingQueue.prepItem()` calls `MessageHandlerSvc.prepMessage()` (for text) or `prepAttachment()` (for files).

**`prepMessage()`** saves the message to ObjectBox **with its tempGuid** via `chat.addMessage(message)`. This is intentional — the message appears in the UI immediately in a "sending" state before the server has confirmed anything. After this call, the message exists in the DB and in `MessagesService` state with `isSending == true`.

For attachments, `prepAttachment()` additionally copies the file from its source path to the app's attachment directory and loads image metadata (dimensions, etc.) before the upload.

---

### Step 4 — OutgoingQueue: Send (`action_handler.dart`)

`OutgoingQueue.handleQueueItem()` calls `MessageHandlerSvc.sendMessage()` (or `sendMultipart` / `sendAttachment`).

**`sendMessage()` does two things before the HTTP call:**

1. **Registers a send progress tracker** keyed by tempGuid:
   ```dart
   registerSendProgressTracker(m.guid!, chat, completer);
   ```
   This is the mechanism that handles the race condition (see Step 5).

2. **Fires the HTTP POST** (non-blocking — uses `.then()` / `.catchError()`):
   ```dart
   HttpSvc.sendMessage(chat.guid, m.guid!, m.text!, ...)
   ```
   The tempGuid is passed to the server as the `tempGuid` field in the request body. The server echoes it back in the "new-message" socket event so the client can correlate the two.

The method returns a `Future` backed by a `Completer` that resolves when either the HTTP response or the socket event completes it — whichever comes first.

**Key file:** `lib/services/backend/action_handler.dart`

---

### Step 5 — HTTP POST to Server (`http_service.dart`)

`HttpSvc.sendMessage()` makes the actual network request via `dio`:
```dart
await dio.post("$apiRoot/message/text", data: {
  "chatGuid": chatGuid,
  "tempGuid": tempGuid,   // so server can echo it in the socket event
  "message": text,
  "method": "private-api" | "apple-script",
  // + effectId, subject, selectedMessageGuid if applicable
});
```

For attachments, `sendAttachment()` uses `FormData` and `MultipartFile` with upload progress callbacks. For multipart (rich text with mentions), `sendMultipart()` sends a `parts` array.

All three use `runApiGuarded()` for consistent error handling.

The request is fire-and-forget from the queue's perspective — the `.then()` and `.catchError()` callbacks handle the result asynchronously.

**Key file:** `lib/services/network/http_service.dart`

---

### Step 6 — The Race: Two Paths to Confirmation

After the POST fires, two things can happen concurrently. Whichever arrives first wins and hands off to the other.

---

#### Path A — Socket/Firebase/Method Channel fires BEFORE the HTTP response

The server sends a "new-message" socket event (or Firebase push on Android) with the real GUID and the original `tempGuid` in the payload.

`SocketService` routes this to `MessageHandlerSvc.handleEvent("new-message", data)`. The handler checks the payload for `tempGuid`:

- **If `tempGuid` is present:** The real GUID and the tempGuid are known. `completeSendProgressIfExists(tempGuid)` is called, which:
  - Removes the progress tracker from `_sendProgressTrackers`
  - Completes the send progress animation (`chat.sendProgress.value = 1`)
  - Completes the `Completer`, unblocking the outgoing queue's `handleSend()`
  - The `IncomingItem` is queued to `IncomingQueue` with `tempGuid` set, so `handleNewMessage()` knows to swap

- **If `tempGuid` is null** (out-of-order event — the server sent the real GUID before the client registered the tracker): The real GUID is added to `outOfOrderTempGuids`. The handler waits 500ms, then checks again. If the tracker arrived in the meantime, the swap proceeds normally; if not, the event is treated as a regular new message.

When `IncomingQueue` processes the item, `handleNewMessage()` calls `matchMessageWithExisting(tempGuid, realMessage)`.

---

#### Path B — HTTP response arrives BEFORE the socket event

The `.then()` callback in `sendMessage()` fires with the server's response body, which contains the real `Message`:
```dart
final newMessage = Message.fromMap(response.data['data']);
completeSendProgressIfExists(m.guid!);   // removes tracker, finishes progress
await matchMessageWithExisting(chat, m.guid!, newMessage, existing: m);
```

`matchMessageWithExisting()` is called directly from the HTTP callback. If the socket event has not yet arrived with the real GUID, the temp message is swapped for the real one here. If the socket event then arrives, `matchMessageWithExisting()` sees that a message with the real GUID already exists and skips the swap.

---

### Step 7 — `matchMessageWithExisting()`: The tempGuid → realGuid Swap

This method handles both paths. It is safe to call from either.

**Logic:**
1. Look up a message with the **real GUID** in the DB.
   - **If found:** The socket event already completed the swap. If the HTTP response's message is newer (e.g. has a `dateDelivered`), replace it. Then if the tempGuid record still exists, delete it.
   - **If not found:** The temp message is still the only record. Call `Message.replaceMessage(tempGuid, realMessage)` → `MessageInterface.replaceMessage()` → `MessageActions.replaceMessage()` in the GlobalIsolate → ObjectBox atomically renames the record's GUID.
2. Call `MessagesSvc(chat.guid).updateMessage(realMessage, oldGuid: tempGuid)`.

**Key file:** `lib/services/backend/action_handler.dart`, `matchMessageWithExisting()` method

---

### Step 8 — State Update and UI Rebuild

`MessagesService.updateMessage(realMessage, oldGuid: tempGuid)`:
1. Finds the `MessageState` keyed by `tempGuid`
2. Calls `messageState.updateFromMessage(realMessage)`:
   - `updateGuidInternal(realGuid)` — sets the GUID, auto-updates `isSending = false`, `isSent = true`
   - All other changed fields (`dateDelivered`, `error`, etc.) updated via their `*Internal()` methods
3. Re-keys the `messageStates` map: `messageStates.remove(tempGuid)` → `messageStates[realGuid] = state`
4. Increments `messageUpdateTrigger[realGuid]` — widgets watching this rebuild

The `Obx()` wrapper around `isSending` in the message bubble widget rebuilds and removes the "sending" animation. The `Obx()` wrapper around `dateDelivered` rebuilds to show the delivery timestamp when it arrives.

**Key files:**
- `lib/services/ui/message/messages_service.dart` — `updateMessage()`
- `lib/app/state/message_state.dart` — `updateGuidInternal()`, `updateFromMessage()`

---

### Step 9 — Error Path

If the HTTP call fails (`.catchError()`):
1. `completeSendProgressIfExists(tempGuid)` runs (clears the tracker)
2. `handleSendError(error, message)` sets `message.guid = guid.replace("temp", "error-...")` and `message.error = BAD_REQUEST`
3. `Message.replaceMessage(tempGuid, errorMessage)` persists the error state
4. If the app is backgrounded or the conversation is not active, a "Failed to send" local notification is created
5. The `Completer` completes with an error, which `OutgoingQueue.handleSend()` catches — if `cancelQueuedMessages` is enabled, all subsequent outgoing items for the same chat are cancelled

---

## Key Files at a Glance

| Step | File | Key Method |
|------|------|-----------|
| Send button | `lib/app/layouts/conversation_view/widgets/text_field/send_button.dart` | `onPressed` callback |
| Build message + tempGuid | `lib/app/layouts/conversation_view/widgets/message/send_animation.dart` | `send()`, `message.generateTempGuid()` |
| tempGuid generation | `lib/database/io/message.dart` | `generateTempGuid()` → `"temp-XXXXXXXX"` |
| Queue | `lib/services/backend/queue/outgoing_queue.dart` | `prepItem()`, `handleQueueItem()` |
| Save to DB (temp) | `lib/services/backend/action_handler.dart` | `prepMessage()` → `chat.addMessage()` |
| HTTP POST | `lib/services/network/http_service.dart` | `sendMessage()`, `sendMultipart()`, `sendAttachment()` |
| Progress tracker | `lib/services/backend/action_handler.dart` | `registerSendProgressTracker()`, `completeSendProgressIfExists()` |
| Out-of-order handling | `lib/services/backend/action_handler.dart` | `outOfOrderTempGuids`, 500ms grace period |
| tempGuid → realGuid swap | `lib/services/backend/action_handler.dart` | `matchMessageWithExisting()` |
| DB swap | `lib/database/io/message.dart` + interfaces | `replaceMessage()` → `MessageInterface.replaceMessage()` |
| State update | `lib/services/ui/message/messages_service.dart` | `updateMessage(real, oldGuid: temp)` |
| UI rebuild | `lib/app/state/message_state.dart` | `updateGuidInternal()` → `isSending = false` |

---

## Deduplication Guarantees

- **`handledNewMessages`** — a rolling list of the last 100 GUIDs seen by `handleEvent()`. Prevents the same socket event from being processed twice (e.g. if Firebase and socket both deliver it).
- **`matchMessageWithExisting()` real-GUID-first check** — before swapping, always checks whether a message with the real GUID already exists. If it does, the swap is a no-op (or a metadata update only). This makes both Path A and Path B safe to call.
- **`_sendProgressTrackers` removal** — `completeSendProgressIfExists()` removes the tracker on first call. The second arrival (socket after HTTP, or HTTP after socket) finds no tracker and does nothing extra.
- **`outOfOrderTempGuids` with 500ms delay** — handles the edge case where the server emits "new-message" with a null `tempGuid` before the client has registered its tracker.
