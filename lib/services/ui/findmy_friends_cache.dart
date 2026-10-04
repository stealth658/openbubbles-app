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
/// this cache and asks for a cheap refresh through the daemon-side Find My
/// client (`fmfd`), the same path the in-chat location bubble already uses.
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

  static bool get available {
    try {
      return backend.supportsFindMy() && pushService.state?.icloudServices?.fmfd != null;
    } catch (_) {
      return false;
    }
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
      final fmfd = pushService.state!.icloudServices!.fmfd!;
      List<api.Follow> follows;
      // Cached data first so the UI has something immediately, then a network
      // refresh for current positions.
      if (byAddress.isEmpty) {
        follows = await api.getBackgroundFollowing(fmfd: fmfd);
        await _ingest(follows);
      }
      follows = await api.refreshBackgroundFollowing(state: fmfd, config: pushService.state!.osConfig);
      await _ingest(follows);
      _lastRefresh = DateTime.now();
    } catch (e, s) {
      Logger.warn("FindMyFriendsCache refresh failed: $e", trace: s);
    }
  }

  static Future<void> _ingest(List<api.Follow> follows) async {
    final friends = follows.where((f) => f.invitationAcceptedHandles.isNotEmpty).map(FindMyFriend.fromFollow).toList();
    await Future.wait(friends.map((f) => f.resolveContact()));
    for (final f in friends) {
      _index(f);
    }
  }
}
