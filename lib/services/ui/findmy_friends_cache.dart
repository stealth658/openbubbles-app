import 'dart:async';

import 'package:bluebubbles/database/global/findmy_friend.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/services/network/backend_service.dart';
import 'package:bluebubbles/services/rustpush/rustpush_service.dart';
import 'package:bluebubbles/src/rust/api/api.dart' as api;
import 'package:bluebubbles/utils/logger/logger.dart';
import 'package:get/get.dart';

/// App-wide view of "people who share their location with me".
///
/// The Find My page owns its own client and refresh loop and is left alone; it
/// publishes what it loads here through [publish]. Everywhere else (the chat
/// header's city line, the location card in conversation details) reads from
/// this cache and asks for a throttled refresh, which opens a short-lived
/// foreground client the same way the page does.
class FindMyFriendsCache {
  FindMyFriendsCache._();

  /// Keyed by [matchKey] of the friend's own address and of every address on
  /// the contact matched to them, so a friend who shares location from their
  /// Apple ID email still shows up in the chat you have with their phone number.
  static final RxMap<String, FindMyFriend> byAddress = <String, FindMyFriend>{}.obs;

  /// "e:<lower email>" or "p:<last ten digits>" (shorter numbers kept whole),
  /// so "+1 555-010-4242" in Contacts and "+15550104242" on a handle agree.
  static String matchKey(String address) {
    final a = FindMyFriend.normalizeAddress(address);
    if (a.contains("@")) return "e:$a";
    final digits = a.replaceAll(RegExp(r'\D'), "");
    return "p:${digits.length > 10 ? digits.substring(digits.length - 10) : digits}";
  }

  static Iterable<String> _keysFor(FindMyFriend f) sync* {
    if (f.handleAddress != null && f.handleAddress!.isNotEmpty) yield matchKey(f.handleAddress!);
    final contact = f.contact ?? f.handle?.contactsV2.firstOrNull;
    if (contact == null) return;
    for (final a in contact.addresses) {
      if (a.trim().isNotEmpty) yield matchKey(a);
    }
    for (final e in contact.emailAddresses) {
      if (e.address.trim().isNotEmpty) yield matchKey(e.address);
    }
    for (final ph in contact.phoneNumbers) {
      if (ph.number.trim().isNotEmpty) yield matchKey(ph.number);
    }
  }

  static void _index(FindMyFriend f) {
    for (final k in _keysFor(f).toSet()) {
      byAddress[k] = f;
    }
  }

  static DateTime? _lastRefresh;
  static Future<void>? _inflight;
  static const Duration _staleAfter = Duration(minutes: 2);
  static const Duration _backgroundEvery = Duration(minutes: 15);
  static Timer? _backgroundTimer;

  static bool get available {
    try {
      return backend.supportsFindMy() && pushService.state?.icloudServices != null;
    } catch (_) {
      return false;
    }
  }

  /// Diagnostics: how many follows came back and how fresh the newest
  /// location is, so a log export shows whether Apple is returning new data.
  static void logFollows(String source, List<api.Follow> follows) {
    Logger.info("FindMy follows ($source): ${summarizeFollows(follows)}", tag: "FindMy");
  }

  /// One line: counts plus per-friend ages, locate flags and capabilities.
  static String summarizeFollows(List<api.Follow> follows) {
    int? newest;
    int located = 0;
    int locating = 0;
    final per = <String>[];
    for (final f in follows) {
      final t = f.lastLocation?.timestamp;
      if (f.locateInProgress) locating++;
      String age = "none";
      if (t != null) {
        located++;
        if (newest == null || t > newest) newest = t;
        age = "${DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(t)).inMinutes}m";
      }
      final who = f.invitationAcceptedHandles.firstOrNull ?? f.id;
      final short = who.contains("@") ? who.split("@").first : who.length > 4 ? who.substring(who.length - 4) : who;
      per.add("$short:$age${f.locateInProgress ? "*" : ""}${f.secureLocationsCapable ? "S" : ""}${f.shallowOrLiveSecureLocationsCapable ? "L" : ""}/${f.source}");
    }
    final age = newest == null ? "n/a" : "${DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(newest)).inMinutes} min";
    return "${follows.length} total, $located located, $locating locating, newest $age; ${per.join(" ")}";
  }

  /// Foreground identity only.
  ///
  /// History, so nobody re-adds the daemon call: the daemon ("fmfd") identity
  /// was tried for friends in v30/31 and v37/38. Each time it spoke to Apple,
  /// the positions this device received stopped advancing, and in v37 even
  /// the cached ones disappeared ("0 located, 9 locating" from both
  /// identities). The Rust log shows no Find My IDS message ever reaching
  /// this device, so the only positions we can show are the ones Apple's
  /// server already holds, and the daemon identity appears to make the server
  /// withhold those. The daemon stays reserved for the in-chat location
  /// bubble, which is upstream behaviour.
  static Future<List<api.Follow>> fetchMerged({
    api.FindMyFriendsClientDefaultAnisetteProvider? foreground,
    bool refreshForeground = true,
    String source = "merge",
  }) async {
    final config = pushService.state!.osConfig;
    if (foreground == null) return const [];
    final fg = refreshForeground
        ? await api.refreshFollowing(config: config, client: foreground)
        : await api.getFollowing(client: foreground);
    logFollows("$source foreground", fg);
    return fg;
  }

  /// Per friend id, the record whose location is newer; the other side's
  /// locate flag is kept if either reports one.
  static List<api.Follow> mergeFollows(List<api.Follow> a, List<api.Follow> b) {
    if (a.isEmpty) return b;
    if (b.isEmpty) return a;
    final byId = <String, api.Follow>{for (final f in a) f.id: f};
    for (final f in b) {
      final cur = byId[f.id];
      if (cur == null) {
        byId[f.id] = f;
        continue;
      }
      final tCur = cur.lastLocation?.timestamp ?? 0;
      final tNew = f.lastLocation?.timestamp ?? 0;
      final best = tNew > tCur ? f : cur;
      final other = identical(best, f) ? cur : f;
      byId[f.id] = api.Follow(
        createTimestamp: best.createTimestamp,
        expires: best.expires,
        id: best.id,
        invitationAcceptedHandles: best.invitationAcceptedHandles,
        invitationFromHandles: best.invitationFromHandles,
        isFromMessages: best.isFromMessages,
        offerId: best.offerId,
        onlyInEvent: best.onlyInEvent,
        personIdHash: best.personIdHash,
        secureLocationsCapable: best.secureLocationsCapable,
        shallowOrLiveSecureLocationsCapable: best.shallowOrLiveSecureLocationsCapable,
        source: best.source,
        tkPermission: best.tkPermission,
        updateTimestamp: best.updateTimestamp,
        fallbackToLegacyAllowed: best.fallbackToLegacyAllowed,
        optedNotToShare: best.optedNotToShare,
        lastLocation: best.lastLocation ?? other.lastLocation,
        locateInProgress: best.locateInProgress || other.locateInProgress,
      );
    }
    return byId.values.toList();
  }

  /// Periodic refresh while the app process is alive (the rustpush foreground
  /// service keeps it alive), so positions are reasonably current when a chat
  /// is opened. A few light HTTPS calls per interval.
  static void startBackgroundRefresh() {
    _backgroundTimer?.cancel();
    _backgroundTimer = Timer.periodic(_backgroundEvery, (_) {
      if (available) refresh(force: true);
    });
  }

  static FindMyFriend? forAddress(String? address) {
    if (address == null || address.isEmpty) return null;
    return byAddress[matchKey(address)];
  }

  /// By the handle's own address first, then by any address of its contact
  /// (the chat may be on a phone number while Find My knows the email).
  static FindMyFriend? forHandle(Handle? handle) {
    if (handle == null) return null;
    final direct = forAddress(handle.address);
    if (direct != null) return direct;
    final contact = handle.contactsV2.firstOrNull;
    if (contact == null) return null;
    for (final a in contact.addresses) {
      final f = forAddress(a);
      if (f != null) return f;
    }
    for (final e in contact.emailAddresses) {
      final f = forAddress(e.address);
      if (f != null) return f;
    }
    for (final ph in contact.phoneNumbers) {
      final f = forAddress(ph.number);
      if (f != null) return f;
    }
    return null;
  }

  /// The friend record for a 1:1 chat's other party, or null for groups and
  /// people who do not share with you.
  static FindMyFriend? forChat(Chat chat) {
    if (chat.isGroup) return null;
    final participant = chat.participants.firstOrNull;
    return forHandle(participant);
  }

  /// Called by the Find My page with whatever it just loaded, so the two views
  /// never disagree. Keeps records for friends the page did not return.
  static void publish(Iterable<FindMyFriend> friends) {
    for (final f in friends) {
      _index(f);
    }
    _lastRefresh = DateTime.now();
  }

  /// Fetches followers through the daemon client. Throttled; concurrent callers
  /// share one request. Safe to call from build-time hooks (fire and forget).
  static Future<void> refresh({bool force = false}) {
    if (!available) return Future.value();
    if (_inflight != null) return _inflight!;
    if (!force && _lastRefresh != null && DateTime.now().difference(_lastRefresh!) < _staleAfter) {
      return Future.value();
    }
    _inflight = _doRefresh().whenComplete(() => _inflight = null);
    return _inflight!;
  }

  static Future<void> _doRefresh() async {
    try {
      // A fresh client each time: its first/initClient is what the Find My
      // page does on open, and that is the only path that has produced fresh
      // positions so far. One refreshClient on top for good measure, then the
      // client is dropped.
      final c = await api.makeFindMyFriends(
        path: pushService.statePath,
        config: pushService.state!.osConfig,
        aps: pushService.state!.conn,
        anisette: pushService.state!.anisette,
        provider: pushService.state!.icloudServices!.tokenProvider,
      );
      try {
        await _ingest(await fetchMerged(foreground: c, source: "cache"));
      } finally {
        c.dispose();
      }
      _lastRefresh = DateTime.now();
    } catch (e, s) {
      Logger.warn("FindMyFriendsCache refresh failed: $e", trace: s);
    }
  }

  static Future<void> _ingest(List<api.Follow> follows) async {
    final friends = follows.where((f) => f.invitationAcceptedHandles.isNotEmpty).map(FindMyFriend.fromFollow).toList();
    FindMyFriend.resolveContacts(friends);
    for (final f in friends) {
      _index(f);
    }
  }
}
