# merge-bb: OpenBubbles on current BlueBubbles, plus fixes

This branch is OpenBubbles `rustpush` (at `eed1b6332`) with BlueBubbles
`master` (at `78ab8fc3b`, about 1,100 upstream commits) merged in, followed by
a series of fixes and features developed while using the result daily on an
Android phone. It is offered as a reference for the OpenBubbles maintainers:
the fixes depend on the merged tree and do not apply to `rustpush` on their
own.

Everything here is Apache 2.0, the same as both upstreams. Nothing proprietary
was added.

## How it was built and tested

- Flutter 3.44 / Dart 3.x, `flutter build apk --release --flavor alpha
  --target-platform android-arm64`. Only the Android arm64 build has been
  exercised. Desktop, iOS and web were brought through `flutter analyze` but
  not run.
- The Rust side (`rustpush` submodule pinned at `a7fab47`) was not rebuilt.
  Test devices ran the prebuilt `librust_lib_bluebubbles.so` from the official
  OpenBubbles release. The Dart/Kotlin changes are therefore verified against
  that library's API surface, not against a fresh Rust build.
- No ObjectBox schema changes. Existing databases open as they are.

## Changes on top of the merge

Merge integrity (regressions found after the merge):

- `markAsHandledAfter` deadlock on message receipt.
- Init could hang in `is_in_clique` / `sync_trust` keychain reads; bounded.
- Attachments: rustpush carries attachments on the Message, not the
  attachment payload; persistence restored.
- SMS/MMS: forwarded MMS participant lists arrive as bare digits; normalised,
  so conversations no longer split.
- Settings: `lastLocation` serialised by value; settings sync bounded to 10 s.
- Dialogs stranded by `Get.back()` closing a snackbar instead of popping;
  `popRoute()` helper swept over the non-setup dismissals.
- Logger: Dart's `FileMode.append` is not `O_APPEND`; re-seek before every
  write and after rotation, prune NUL-filled shells at startup.
- Gradle tuned for memory-capped CI containers.

Upstream BlueBubbles cherry-picks taken after the merge point: restore
previous chat filters when toggling the other-chats chip; derive contact
accounts from the contacts provider rather than AccountManager; stop gallery
saves crashing on Android 16.

Features and fixes:

- Android Auto: templated messaging conversation list (CarAppService).
  Known open item: binding to the car session is not reliable yet.
- iOS-style tapback menu as an opt-in on Material.
- Find My: selectable basemaps, map controls, friend/device zoom on tap, a
  visible refresh button (long-press for diagnostics), plain map credit.
- Find My in chats: friends matched to contacts by any address on the
  contact (email or phone), case-insensitive handle lookup, city line under
  the name in the 1:1 chat header, a Location card in conversation details,
  throttled background refresh via `FindMyFriendsCache`.
- Conversation details (Material): redesigned 1:1 page (expressive header,
  participants, location, media, links, documents, then options); tapping the
  name in the chat header opens it.
- Tracking numbers open the carrier's own tracking page.
- "Read on another device" clears the notification and the unread dot.
- Backup and restore: local backups are written through MediaStore and land
  in Downloads; messages restore works on a fresh install (handles, chats,
  messages and attachments re-created with fresh IDs); Reset App deregisters
  the device first.
- No-server mode: no red connection bar and no Connection & Server / Private
  API tiles when running on rustpush without a BlueBubbles server; external
  downloads (emoji font, sounds, GIFs) no longer go through the server API
  guard.
- Short codes shown as-is instead of "+1 62438".
- Reply suggestions moved into the composer (sparkle plus compact pills,
  hidden while typing); optional ghost-text suggestion inside the text field.
- On-device AI via ML Kit GenAI (Gemini Nano), off by default: compose
  assistant, summarise recent messages, reply suggestions when the Prompt API
  is available.
- Conversation list search (Material): the header expands into a Material 3
  search bar, results update as you type, grouped into Conversations and
  Messages, filters in a bottom sheet.
- Log export includes the rustpush log.

## Known limitations

- Find My friends: on the tested device, friend positions never advance past
  what Apple's server already holds. The Rust log shows no Find My IDS
  messages arriving, so locate requests never complete. This predates the
  branch and looks like a registration capability issue in the prebuilt
  library rather than something in the Dart code; the Dart side has been left
  on the foreground identity only.
- Android Auto car binding, see above.
- Only Android arm64 tested.
