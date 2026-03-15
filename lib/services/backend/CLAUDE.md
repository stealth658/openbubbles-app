# services/backend/ — Server Interaction

## Request Pattern
Each resource has an interface and a concrete action file → `interfaces/CLAUDE.md` + `actions/CLAUDE.md`
- `interfaces/chat_interface.dart` → `actions/chat_actions.dart`
- `interfaces/message_interface.dart` → `actions/message_actions.dart`
- (same for: attachment, contact, contact_v2, handle, image, prefs, server, sync, test)

## Sync System (`sync/`) → `sync/CLAUDE.md`
- `sync_service.dart` — coordinator
- `full_sync_manager.dart` — initial full data sync
- `incremental_sync_manager.dart` — delta updates
- `handle_sync_manager.dart` — contact handle sync

## Message Queues (`queue/`) → `queue/CLAUDE.md`
- `outgoing_queue.dart` — buffers outbound messages for reliability

## Incoming Message Handler
- `incoming_message_handler.dart` — `IncomingMessageHandler` / `IncomingMsgHandler` GetIt getter
- Owns the inbound message pipeline: FIFO queue, configurable concurrency, per-GUID serialization, deduplication, chat hydration, DB write, notification dispatch, and UI reactivity

## Other Key Files
- `settings/` — `SettingsService` + `SharedPreferencesService` → `settings/CLAUDE.md`
- `notifications/notifications_service.dart` — local notification dispatch
- `java_dart_interop/` — Android method channel bridge → `java_dart_interop/CLAUDE.md`
- `lifecycle_service.dart` — foreground/background lifecycle
- `filesystem_service.dart` — file I/O operations
