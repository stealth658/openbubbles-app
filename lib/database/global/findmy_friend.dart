import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/models/models.dart' show HandleLookupKey;
import 'package:bluebubbles/services/services.dart';
import 'package:bluebubbles/src/rust/api/api.dart' as api;
import 'package:collection/collection.dart';
import 'package:intl/intl.dart';

enum LocationStatus { legacy, shallow, live }

class FindMyFriend {
  FindMyFriend({
    required this.latitude,
    required this.longitude,
    required this.longAddress,
    required this.shortAddress,
    required this.title,
    required this.subtitle,
    required this.handle,
    required this.handleAddress,
    required this.lastUpdated,
    required this.status,
    required this.locatingInProgress,
    this.id,
  });

  final double? latitude;
  final double? longitude;
  final String? longAddress;
  final String? shortAddress;
  final String? title;
  final String? subtitle;
  final Handle? handle;
  // Raw address from the server — stable even when handle is not in the local DB.
  final String? handleAddress;
  final DateTime? lastUpdated;
  final LocationStatus? status;
  final bool locatingInProgress;
  final String? id;

  /// Contact matched by address when the handle itself has no linked contact
  /// (typical for a friend you share location with but have never messaged
  /// from this app). Filled by [resolveContact].
  ContactV2? contact;

  /// Stable identifier for matching and map marker keys.
  /// Prefers the hydrated handle key; falls back to the raw server address.
  String? get stableId => handle?.uniqueAddressAndService ?? handleAddress;

  /// Address with any tel:/mailto: prefix stripped and emails lower-cased, for
  /// matching against chat participants.
  static String normalizeAddress(String address) {
    var a = address.trim();
    if (a.startsWith("tel:")) a = a.substring(4);
    if (a.startsWith("mailto:")) a = a.substring(7);
    return a.contains("@") ? a.toLowerCase() : a;
  }

  String? get normalizedAddress => handleAddress == null ? null : normalizeAddress(handleAddress!);

  bool get hasLocation => (latitude ?? 0) != 0 && (longitude ?? 0) != 0;

  /// Name to show: the handle's contact, then a contact matched by address,
  /// then the formatted address.
  String get displayName {
    final h = handle;
    if (h != null && h.contactsV2.isNotEmpty) return h.displayName;
    if (contact != null) return contact!.computedDisplayName;
    if (h != null) return h.displayName;
    if (title != null && title!.isNotEmpty) return title!;
    return handleAddress == null ? "Unknown Friend" : formatPhoneNumber(handleAddress);
  }

  /// Short, human place name for headers: "Old Westbury, NY". Falls back to the
  /// first formatted address line when the geocoder gave no locality.
  String? get placeName {
    if (shortAddress != null && shortAddress!.isNotEmpty) return shortAddress;
    final lines = longAddress?.split("\n");
    if (lines != null && lines.length >= 2) return lines[1];
    return lines?.firstOrNull;
  }

  /// Looks the handle up loosely (any service, case-insensitive) so a friend
  /// whose address was stored as "jane@example.com" still matches
  /// "Jane@example.com" from Find My. Falls back to an unsaved Handle.
  static Handle handleFor(String address) {
    final raw = normalizeAddress(address);
    return Handle.findOneLoose(raw) ?? Handle(address: raw);
  }

  /// Builds a friend from a rustpush [api.Follow]. Shared by the Find My page,
  /// the in-chat location bubble and [FindMyFriendsCache] so they agree.
  factory FindMyFriend.fromFollow(api.Follow e, {Handle? handle}) {
    final addr = e.invitationAcceptedHandles.firstOrNull ?? "";
    final loc = e.lastLocation;
    final address = loc?.address;
    String? short;
    if (address != null) {
      final parts = <String>[
        if (address.locality != null && address.locality!.isNotEmpty) address.locality!,
        if ((address.stateCode ?? address.countryCode).isNotEmpty) address.stateCode ?? address.countryCode,
      ];
      short = parts.isEmpty ? null : parts.join(", ");
    }
    return FindMyFriend(
      latitude: loc?.latitude,
      longitude: loc?.longitude,
      longAddress: address?.formattedAddressLines?.join("\n"),
      shortAddress: short,
      title: null,
      subtitle: null,
      handle: handle ?? handleFor(addr),
      handleAddress: addr,
      lastUpdated: loc?.timestamp != null ? DateTime.fromMillisecondsSinceEpoch(loc!.timestamp) : null,
      status: null,
      // Apple leaves locateInProgress set for long stretches; the page never
      // surfaced it before and a permanent spinner would be a regression.
      locatingInProgress: false,
      id: e.id,
    );
  }

  /// Fills [contact] when the handle has no linked contact. Cheap when it does.
  Future<void> resolveContact() async {
    if (contact != null) return;
    final h = handle;
    if (h != null && h.contactsV2.isNotEmpty) return;
    final addr = normalizedAddress;
    if (addr == null || addr.isEmpty) return;
    try {
      contact = await ContactsSvcV2.getContact(addr);
    } catch (_) {}
  }

  factory FindMyFriend.fromJson(Map<String, dynamic> json) => FindMyFriend(
        latitude: json["coordinates"]?[0].toDouble(),
        longitude: json["coordinates"]?[1].toDouble(),
        longAddress: json["long_address"],
        shortAddress: json["short_address"],
        title: json["title"],
        subtitle: json["subtitle"],
        handleAddress: json["handle"] ?? json["title"],
        handle: json["handle"] == null && json["title"] == null
            ? null
            : Handle.findOne(addressAndService: HandleLookupKey(json["handle"] ?? json["title"], "iMessage")),
        lastUpdated:
            (json["last_updated"] ?? 0) == 0 ? null : DateTime.fromMillisecondsSinceEpoch(json["last_updated"]),
        status: LocationStatus.values.firstWhereOrNull((e) => e.name == json["status"]),
        locatingInProgress: json["is_locating_in_progress"] ?? false,
      );

  Map<String, dynamic> toJson() => {
        "coordinates": [latitude, longitude],
        "long_address": longAddress,
        "short_address": shortAddress,
        "title": title,
        "subtitle": subtitle,
        "handle": handle?.toMap(),
        "last_updated": lastUpdated == null ? null : DateFormat("MMMM d, yyyy h:mm:ss a").format(lastUpdated!),
        "status": status?.name,
        "locating_in_progress": locatingInProgress,
      };
}
