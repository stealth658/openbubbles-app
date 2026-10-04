# OpenBubbles

## About this fork: branch `merge-bb`

This branch is OpenBubbles `rustpush` (at `eed1b6332`) with BlueBubbles
`master` (at `78ab8fc3b`, about 1,100 upstream commits) merged in, followed by
a series of fixes and features developed while using the result daily on an
Android phone. The fixes depend on the merged tree and do not apply to
`rustpush` on their own.

Everything here is Apache 2.0, the same as both upstreams. Nothing proprietary
was added.

The merge and the changes on top of it were written with Claude (Anthropic's
AI model) doing the implementation under direction and daily testing on a
real device. Treat the code with the same scrutiny you would give any
contribution; the notes below say what was verified and what was not.

### How it was built and tested

- Flutter 3.44 / Dart 3.x, `flutter build apk --release --flavor alpha
  --target-platform android-arm64`. Only the Android arm64 build has been
  exercised. Desktop, iOS and web were brought through `flutter analyze` but
  not run.
- The Rust side (`rustpush` submodule pinned at `a7fab47`) was not rebuilt.
  Test devices ran the prebuilt `librust_lib_bluebubbles.so` from the official
  OpenBubbles release. The Dart/Kotlin changes are therefore verified against
  that library's API surface, not against a fresh Rust build.
- No ObjectBox schema changes. Existing databases open as they are.

### Changes on top of the merge

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
- Running on rustpush with no BlueBubbles server: the merged socket code
  showed a permanent red connection bar and Connection & Server / Private
  API tiles, and routed external downloads (emoji font, sounds, GIFs) through
  the server API guard, so they failed instantly. Both restored to the
  no-server behaviour.
- Gradle tuned for memory-capped CI containers.

Upstream BlueBubbles cherry-picks taken after the merge point: restore
previous chat filters when toggling the other-chats chip; derive contact
accounts from the contacts provider rather than AccountManager; stop gallery
saves crashing on Android 16.

Features and fixes:

- Android Auto: templated messaging conversation list (CarAppService).
  Known open item: binding to the car session is not reliable yet.
- iOS-style tapback menu as an opt-in on Material and Samsung (Theming & Styles,
  under App Skin).
- Find My: selectable basemaps, map controls, friend/device zoom on tap, a
  visible refresh button (long-press for diagnostics), plain map credit.
- Find My in chats: friends matched to contacts by any address on the
  contact (email or phone), case-insensitive handle lookup, city line under
  the name in the 1:1 chat header, a Location card in conversation details,
  throttled background refresh via `FindMyFriendsCache`.
- Conversation details: redesigned page on all skins (header with the
  action row, participants, location, media, links, documents); the chat's
  settings moved unchanged to a "Conversation Settings" page behind a gear in
  the app bar; tapping the name in the chat header opens details. iOS keeps
  its profile poster.
- Tracking numbers open the carrier's own tracking page.
- "Read on another device" clears the notification and the unread dot.
- Backup and restore: local backups are written through MediaStore and land
  in Downloads; messages restore works on a fresh install (handles, chats,
  messages and attachments re-created with fresh IDs); Reset App deregisters
  the device first.
- Short codes shown as-is instead of "+1 62438".
- Reply suggestions moved into the composer (sparkle plus compact pills,
  hidden while typing); optional ghost-text suggestion inside the text field.
- On-device AI via ML Kit GenAI (Gemini Nano), off by default: compose
  assistant, summarise recent messages, reply suggestions when the Prompt API
  is available.
- Conversation list search on all skins: the header turns into a search bar
  (Material 3 bar on Material and Samsung, rounded field with Cancel on iOS),
  results update as you type, grouped into Conversations and Messages,
  filters in a bottom sheet.
- Log export includes the rustpush log.
- "Edited" shown on the receipt line ("Delivered • Edited") on all skins;
  Undo Send and Edit lead the long-press menu while still possible, Remind
  Later moves under More.
- Samsung skin: chat list blocks inset with One UI's 26dp radius (the custom
  sliver decoration was not painting the long block); details page under a
  bare toolbar with round labelled action buttons.
- Contact photos keep their aspect ratio (the avatar decode squashed
  non-square photos into a square).

### Building

Tested with Flutter 3.44 (Dart 3.12), Java 21, Android SDK 36, NDK
28.2.13676358, a stable Rust toolchain and `protoc`. Clone with submodules;
`telephony_plus` has a nested one, so `--recursive` matters:

```
git clone --recursive -b merge-bb https://github.com/stealth658/openbubbles-app.git
cd openbubbles-app
flutter pub get
flutter build apk --release --flavor alpha --target-platform android-arm64
```

The Rust side needs Apple FairPlay certificates in `rustpush/certs/fairplay/`
to sign device activation. Those are private to the OpenBubbles maintainer
and are not in any repository. Without them the build still compiles if you
copy the placeholder pair from `rustpush/certs/legacy-fairplay/` under the
names upstream's CI uses (see the "Set up fake Fairplay keys" step in
OpenBubbles' `.github/workflows/build.yml`), but the resulting app cannot
register with Apple. A working install therefore needs the Rust library
(`lib/arm64-v8a/librust_lib_bluebubbles.so`) from an official OpenBubbles
release in place of the one you built; the Dart and Kotlin code in this
branch runs unchanged against it.

The build is memory-hungry: `android/gradle.properties` is tuned down for a
capped container (small heap, one worker, no daemon). On a normal machine
you can raise those values again.

### Known limitations

- Find My friends: on the tested device, friend positions never advance past
  what Apple's server already holds. The Rust log shows no Find My IDS
  messages arriving, so locate requests never complete. This predates the
  branch and looks like a registration capability issue in the prebuilt
  library rather than something in the Dart code; the Dart side has been left
  on the foreground identity only.
- Android Auto car binding, see above.
- Only Android arm64 tested.

---

OpenBubbles is an open-source and cross-platform ecosystem of apps aimed to bring Apple platform services to Android and Windows! With OpenBubbles, you'll be able to send messages, media, and much more to your friends and family.

**Please note that OpenBubbles requires access to a Mac and an Apple ID to function!

Key Features:

- Send/receive emoji reactions 
- Send formatted messages (bold, italic, etc)
- Edit messages
- Unsend messages 
- Call your friends on FaceTime
- Answer calls from your friends on FaceTime
- See friends' locations on FindMy
- Join and Sync iCloud Shared Albums
- See typing indicators
- Receive stickers
- Create and manage group chats
- Add an icon to personalize your group chat 
- Send images and videos
- Forward SMS and MMS to/from connected Macs or other devices with OpenBubbles 

If you need help setting up the app, have any issues or feature requests, or just want to come hang out, feel free to join our Discord, linked below! We hope you enjoy using the app!

## Useful links

* Our Website: [here](https://openbubbles.app)
* Discord: [here](https://discord.gg/98fWS4AQqN)!
    - We highly encourage users to join to get in direct communication with the developers and community
* GitHub: [here](https://github.com/OpenBubbles)
    - Please submit any issues with the app here so we can properly track them! Remember to search before opening a ticket :)

## Getting Started

[Quickstart](https://openbubbles.app/quickstart.html)
