import 'package:bluebubbles/database/models.dart';
import 'package:dice_bear/dice_bear.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:objectbox/objectbox.dart';

/// ContactV2 - New contact entity designed for N:M relationship with Handles
/// This entity follows the architecture outlined in FR-1.md
@Entity()
class ContactV2 {
  ContactV2({
    this.id = 0,
    required this.displayName,
    required this.nativeContactId,
    this.avatarPath,
    this.addresses = const [],
  });

  @Id()
  int id;

  /// Display name of the contact
  String displayName;

  /// Native contact ID from the device's contact database
  /// Essential for tracking updates/changes
  @Index()
  @Unique()
  String nativeContactId;

  /// Local file path to the avatar image (if any)
  String? avatarPath;

  /// Normalized list of phone numbers and emails
  /// Phone numbers should be stripped of non-digits
  /// Emails should be lowercased
  List<String> addresses;

  /// N:M Relationship to Handles
  /// This establishes the many-to-many relationship between contacts and handles
  final handles = ToMany<Handle>();

  @Transient()
  Widget? _fakeAvatar;

  @Transient()
  Widget get fakeAvatar {
    if (_fakeAvatar != null) return _fakeAvatar!;
    Avatar _avatar = DiceBearBuilder(seed: displayName).build();
    _fakeAvatar = _avatar.toImage();
    return _fakeAvatar!;
  }

  /// Get the initials from the display name
  String? get initials {
    final parts = displayName.trim().split(' ');
    if (parts.isEmpty || displayName.isEmpty) return null;

    if (parts.length == 1) {
      return parts[0].isNotEmpty ? parts[0][0].toUpperCase() : null;
    }

    final first = parts.first.isNotEmpty ? parts.first[0] : '';
    final last = parts.last.isNotEmpty ? parts.last[0] : '';

    return (first + last).isEmpty ? null : (first + last).toUpperCase();
  }

  /// Normalize a phone number by removing all non-digit characters
  static String normalizePhoneNumber(String phone) {
    return phone.replaceAll(RegExp(r'[^\d+]'), '');
  }

  /// Normalize an email by converting to lowercase and trimming
  static String normalizeEmail(String email) {
    return email.toLowerCase().trim();
  }

  /// Check if an address matches any of this contact's addresses
  bool hasMatchingAddress(String address) {
    final normalized = address.contains('@') ? normalizeEmail(address) : normalizePhoneNumber(address);

    return addresses.any((contactAddress) {
      final contactNormalized =
          contactAddress.contains('@') ? normalizeEmail(contactAddress) : normalizePhoneNumber(contactAddress);
      return contactNormalized == normalized;
    });
  }

  /// Convert to map for serialization
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'displayName': displayName,
      'nativeContactId': nativeContactId,
      'avatarPath': avatarPath,
      'addresses': addresses,
    };
  }

  /// Create from map
  static ContactV2 fromMap(Map<String, dynamic> map) {
    return ContactV2(
      id: map['id'] ?? 0,
      displayName: map['displayName'] ?? '',
      nativeContactId: map['nativeContactId'] ?? '',
      avatarPath: map['avatarPath'],
      addresses: List<String>.from(map['addresses'] ?? []),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ContactV2 &&
          runtimeType == other.runtimeType &&
          nativeContactId == other.nativeContactId &&
          displayName == other.displayName &&
          listEquals(addresses, other.addresses) &&
          avatarPath == other.avatarPath);

  @override
  int get hashCode => Object.hash(
        nativeContactId,
        displayName,
        Object.hashAll(addresses),
        avatarPath,
      );
}
