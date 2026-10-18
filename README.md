# OpenBubbles

## About this fork: branch `merge-bb`

This branch is OpenBubbles `rustpush` (at `eed1b6332`) with BlueBubbles
`master` (at `78ab8fc3b`, about 1,100 upstream commits) merged in, followed by
a series of fixes and features developed while using the result daily on an
Android phone. The fixes depend on the merged tree and do not apply to
`rustpush` on their own.

Everything here is Apache 2.0, the same as both upstreams. Nothing proprietary
was added.

The merge and the changes on top of it were written with Claude.

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
- Incoming edits and unsends were dropped by the merged incoming-message
  handler as duplicates (they carry the original's guid); dispatched as
  updates now.
- Gradle tuned for memory-capped CI containers.

Upstream BlueBubbles cherry-picks taken after the merge point: restore
previous chat filters when toggling the other-chats chip; derive contact
accounts from the contacts provider rather than AccountManager; stop gallery
saves crashing on Android 16.

Features and fixes:

- Android Auto: templated messaging conversation list (`CarAppService`,
  `ConversationItem`, Car API level 7+). Complete and working on the
  development head unit; see Known limitations for real cars.
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
- iMessage read on another of your devices clears the notification and the
  unread dot (rustpush's Read notice, command 102). Forwarded SMS is not
  covered; see Known limitations.
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
- Reply quote (Material) drawn as a small faded quote without a repeated
  author name; reply thread opens in place under the chat header with an X and
  a Reply bar, and uses the thread's own neighbours for time headers and
  sender names.
- Contact photos keep their aspect ratio (the avatar decode squashed
  non-square photos into a square).
- Material skin after Google Messages (October 2026): tailless bubbles with
  20dp/4dp corners by run, nested reply cards with a small avatar, sender row
  with avatar, one-pill composer with a round voice/send button and a grid
  attachment tray, emoji panel in place of the keyboard, reaction pills in
  iPhone colours, several pictures in one message tiled as a collage, Material
  3 long-press menu cut to the iPhone's first page (More selects), settings
  as grouped cards with 56dp rows, details page with separate cards for
  photos and videos, links, files and locations.
- Text size: follows the system text size or an in-app slider (Theming);
  RichText honours the scale too.
- App Font setting (Theming): bundled Google Sans Flex (SIL OFL) plus custom
  font files; see Building for SF Pro.
- Cache service: purge on background and on Android memory trim, cache
  tuning page under developer settings, group photos and chat backgrounds
  decoded at display size.
- Upstream BlueBubbles cherry-picks: snackbar rewrite, copy buttons for
  addresses, image and video previews on pinned conversations, reverse
  geocoded Find My locations, trackpad fix in the image gallery.
- Sending: pictures and videos picked together go as one message; sends keep
  trying for two minutes on a dropped connection before showing as failed;
  Forward sends each selected message separately.
- iCloud sync: walks to the end of the attachment feed, yields to the main
  thread between items, uploads sent text-only messages, skips failed sends.
- Relayed texts: the iPhone's Read receipt is applied to RCS messages you
  sent.
- Diagnostics: main thread watchdog and Android's ANR records in the log
  export; failed typing indicators and read receipts are logged instead of
  thrown.
- Fixes: emoji tapback notifications name the emoji again; the FaceTime
  target check waits for rustpush when a chat opens at start-up; the update
  check no longer parses a desktop release tag as a build code.

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

The "SF Pro" App Font option expects Apple's SF Pro Text files, which are
not redistributable and are not in this repository. Without them the option
falls back to the default font. See the note in `pubspec.yaml` to add them
from your own copy.

The build is memory-hungry: `android/gradle.properties` is tuned down for a
capped container (small heap, one worker, no daemon). On a normal machine
you can raise those values again.

### Known limitations

- Forwarded SMS read on another device (iPhone, iPad, Mac) stays unread here.
  Apple sends that notice on the SMS forwarding service as command 147 with
  the message GUID and read time (`{"g": <guid>, "e": <date>}`). rustpush only
  sends 147 and has no decoder for it on receipt (true of both the pinned
  `a7fab47` and upstream `cb2361c`), so it is dropped before reaching the app.
  A fix needs rustpush to turn an incoming 147 into a Read for message `g`,
  and the Dart handler in `rustpush_service.dart` to accept SMS chats as well
  as iMessage ones.

- Find My friends: on the tested device, friend positions never advance past
  what Apple's server already holds. The Rust log shows no Find My IDS
  messages arriving, so locate requests never complete. This predates the
  branch and looks like a registration capability issue in the prebuilt
  library rather than something in the Dart code; the Dart side has been left
  on the foreground identity only.
- Android Auto, templated messaging in a real car. The implementation is
  finished: on the development head unit (head unit server on the phone) the
  host binds, validates, creates the session and renders the conversation
  list within a fraction of a second. In a real car the same host never binds
  to the service at all (the service logs the instant it is created; a full
  day of car sessions logged nothing), and Android Auto falls back to the
  notification-based messaging screen. With "Unknown sources" on, the app
  does appear in the car and messages and notifications work there; only the
  templated conversation list is withheld. Google documents templated
  messaging as a beta available to apps on Play internal or closed testing
  tracks and early-access partners, with production rollout "at a later
  date", so this looks like that distribution gate rather than anything in
  the code. A Play-distributed build, or the end of the beta, should light
  it up without changes.
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
