# services/backend/queue/ — Message Queues

For the complete inbound flow (socket → handler → DB → state → UI), see `docs/MESSAGE_RECEIVE_FLOW.md`.
For the complete outbound flow (send button → tempGuid → HTTP + socket race → real GUID swap), see `docs/MESSAGE_SEND_FLOW.md`.

## Files
| File | Purpose |
|------|---------|
| `queue_impl.dart` | Abstract `Queue` base class — serial processing, error handling, cancellation |
| `outgoing_queue.dart` | `OutgoingQueue` — buffers messages being sent by the user |

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
- `OutgoingItem` — `chat`, `message`, `selected` (reply target), `reaction`, `customArgs`

## Inbound Message Handling
Incoming messages from the server are **not** processed through this queue. They go through `IncomingMessageHandler` (`lib/services/backend/incoming_message_handler.dart`), which owns its own FIFO queue with configurable concurrency and per-GUID serialization.
