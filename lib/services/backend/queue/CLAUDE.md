# services/backend/queue/ — Message Queues

For the complete inbound flow (socket → queue → DB → state → UI), see `docs/MESSAGE_RECEIVE_FLOW.md`.
For the complete outbound flow (send button → tempGuid → HTTP + socket race → real GUID swap), see `docs/MESSAGE_SEND_FLOW.md`.

## Files
| File | Purpose |
|------|---------|
| `queue_impl.dart` | Abstract `Queue` base class — serial processing, error handling, cancellation |
| `incoming_queue.dart` | `IncomingQueue` — processes messages arriving from the server |
| `outgoing_queue.dart` | `OutgoingQueue` — buffers messages being sent by the user |

## IncomingQueue
Handles server-pushed events sequentially. Accessed via the `inq` top-level getter.

Routes `QueueType` to `MessageHandlerSvc`:
- `QueueType.newMessage` → `MessageHandlerSvc.handleNewMessage()`
- `QueueType.updatedMessage` → `MessageHandlerSvc.handleUpdatedMessage()`

**Usage:**
```dart
inq.queue(IncomingItem(type: QueueType.newMessage, chat: chat, message: message));
```

## OutgoingQueue
Buffers outbound sends so they process serially and surface send progress. Accessed via the `outq` top-level getter.

`prepItem()` is called first (validates/prepares the message), then `handleQueueItem()` performs the actual send.

Routes `QueueType` to `MessageHandlerSvc`:
- `QueueType.sendMessage` → `MessageHandlerSvc.sendMessage()`
- `QueueType.sendMultipart` → `MessageHandlerSvc.sendMultipart()`
- `QueueType.sendAttachment` → `MessageHandlerSvc.sendAttachment()`

**Usage:**
```dart
outq.queue(OutgoingItem(
  type: QueueType.sendMessage,
  chat: chat,
  message: message,
));
```

## Queue Base Class
- Maintains a `List<QueueItem> items`; processes one item at a time (`isProcessing` flag)
- If `cancelQueuedMessages` is enabled in settings, a failed outgoing item cancels all subsequent items for the same chat
- Items can carry a `Completer` for the caller to await completion

## QueueItem Types
Defined in `lib/database/global/queue_items.dart`:
- `IncomingItem` — `chat`, `message`, `tempGuid`
- `OutgoingItem` — `chat`, `message`, `selected` (reply target), `reaction`, `customArgs`
