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

  /// Keyed by [FindMyFriend.normalizeAddress] of the friend's address.
  static final RxMap<String, FindMyFriend> byAddress = <String, FindMyFriend>{}.obs;

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
    return byAddress[FindMyFriend.normalizeAddress(address)];
  }

  static FindMyFriend? forHandle(Handle? handle) => handle == null ? null : forAddress(handle.address);

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
      final key = f.normalizedAddress;
      if (key == null || key.isEmpty) continue;
      byAddress[key] = f;
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
      final key = f.normalizedAddress;
      if (key == null || key.isEmpty) continue;
      byAddress[key] = f;
    }
  }
}
