import 'dart:math';

import 'package:bluebubbles/database/database.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:bluebubbles/services/backend/interfaces/handle_interface.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:dice_bear/dice_bear.dart';
import 'package:faker/faker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart' hide Condition;
// (needed when generating objectbox model code)
// ignore: unnecessary_import
import 'package:objectbox/objectbox.dart';
import 'package:tuple/tuple.dart';

@Entity()
class Handle {
  int? id;
  int? originalROWID;
  @Unique()
  String uniqueAddressAndService;
  String address;
  String? formattedAddress;
  String service;
  String? country;
  String? defaultEmail;
  String? defaultPhone;
  @Transient()
  final String fakeName = "${faker.person.firstName()} ${faker.person.lastName()}";

  final RxnString _color = RxnString();
  String? get color => _color.value;
  set color(String? val) => _color.value = val;

  // N:M Relationship to ContactV2 (new contact service)
  // This is a backlink - ContactV2 owns the relationship
  @Backlink('handles')
  final contactsV2 = ToMany<ContactV2>();

  // Cache the contact display name so it can be accessed outside of transactions
  // This is populated when the handle is fetched within a transaction
  @Transient()
  String? cachedContactName;

  @Transient()
  Widget? _fakeAvatar;

  @Transient()
  Widget get fakeAvatar {
    if (_fakeAvatar != null) return _fakeAvatar!;
    Avatar _avatar = DiceBearBuilder(seed: address).build();
    _fakeAvatar = _avatar.toImage();
    return _fakeAvatar!;
  }

  String get displayName {
    if (SettingsSvc.settings.redactedMode.value) {
      if (SettingsSvc.settings.generateFakeContactNames.value) {
        return fakeName;
      } else if (SettingsSvc.settings.hideContactInfo.value) {
        return "";
      }
    }
    if (address.startsWith("urn:biz")) return "Business";

    // Check cached contact name first (populated within transaction)
    if (cachedContactName != null) {
      return cachedContactName!;
    }

    // Try to access ContactV2 directly (only works if in a transaction)
    if (!kIsWeb && contactsV2.isNotEmpty) {
      return contactsV2.first.computedDisplayName;
    }

    return address.contains("@") ? address : (formattedAddress ?? address);
  }

  String? get initials {
    // Remove any numbers, certain symbols, and non-alphabet characters
    if (address.startsWith("urn:biz")) return null;

    // Check ContactV2 first for initials
    if (!kIsWeb && contactsV2.isNotEmpty) {
      final contactV2Initials = contactsV2.first.initials;
      if (contactV2Initials != null) return contactV2Initials;
    }

    String importantChars = displayName.toUpperCase().replaceAll(RegExp(r'[^a-zA-Z _-]'), "").trim();
    if (importantChars.isEmpty) return null;

    // Split by a space or special character delimiter, take each of the items and
    // reduce it to just the capitalized first letter. Then join the array by an empty char
    List<String> initials =
        importantChars.split(RegExp(r'[ \-_]')).map((e) => e.isEmpty ? '' : e[0].toUpperCase()).toList();

    initials.removeRange(1, max(initials.length - 1, 1));

    return initials.join("").isEmpty ? null : initials.join("");
  }

  Handle({
    this.id,
    this.originalROWID,
    this.address = "",
    this.formattedAddress,
    this.service = 'iMessage',
    this.uniqueAddressAndService = "",
    this.country,
    String? handleColor,
    this.defaultEmail,
    this.defaultPhone,
  }) {
    if (service.isEmpty) {
      service = 'iMessage';
    }
    if (uniqueAddressAndService.isEmpty) {
      uniqueAddressAndService = "$address/$service";
    }
    color = handleColor;
  }

  factory Handle.fromMap(Map<String, dynamic> json) => Handle(
        id: json["ROWID"] ?? json["id"],
        originalROWID: json["originalROWID"],
        address: json["address"],
        formattedAddress: json["formattedAddress"],
        service: json["service"] ?? "iMessage",
        uniqueAddressAndService: json["uniqueAddrAndService"] ?? "${json["address"]}/${json["service"] ?? "iMessage"}",
        country: json["country"],
        handleColor: json["color"],
        defaultPhone: json["defaultPhone"],
        defaultEmail: json["defaultEmail"],
      );

  /// Formats and sets the formattedAddress field if not already set.
  ///
  /// For emails and business chats (urn:biz), uses the address as-is.
  /// For phone numbers, formats them using the formatPhoneNumber helper.
  ///
  /// This should be called in isolate actions before saving handles to the database.
  Future<void> updateFormattedAddress() async {
    if (!isNullOrEmpty(formattedAddress)) return;

    if (address.contains('@') || address.startsWith('urn:biz')) {
      formattedAddress = address;
    } else {
      formattedAddress = await formatPhoneNumber(address);
    }
  }

  /// Save a single handle - prefer [bulkSave] for multiple handles rather
  /// than iterating through them
  Handle save({bool updateColor = false, matchOnOriginalROWID = false}) {
    if (kIsWeb) return this;
    Database.runInTransaction(TxMode.write, () {
      Handle? existing;
      if (matchOnOriginalROWID) {
        existing = Handle.findOne(originalROWID: originalROWID);
      } else {
        existing = Handle.findOne(addressAndService: Tuple2(address, service));
      }

      if (existing != null) {
        id = existing.id;
      }
      // Contact matching is now handled automatically by ContactServiceV2
      if (!updateColor) {
        color = existing?.color ?? color;
      }
      try {
        id = Database.handles.put(this);
      } on UniqueViolationException catch (_) {}
    });
    return this;
  }

  /// Save a single handle asynchronously (non-blocking)
  Future<Handle> saveAsync({bool updateColor = false, matchOnOriginalROWID = false}) async {
    if (kIsWeb) return this;

    final savedHandle = await HandleInterface.saveHandleAsync(
      handleData: toMap(),
      updateColor: updateColor,
      matchOnOriginalROWID: matchOnOriginalROWID,
    );

    // Update this handle with the saved data
    id = savedHandle.id;
    color = savedHandle.color;

    return this;
  }

  /// Save a list of handles
  static List<Handle> bulkSave(List<Handle> handles, {matchOnOriginalROWID = false}) {
    Database.runInTransaction(TxMode.write, () {
      /// Match existing to the handles to save, where possible
      for (Handle h in handles) {
        Handle? existing;
        if (matchOnOriginalROWID) {
          existing = Handle.findOne(originalROWID: h.originalROWID);
        } else {
          existing = Handle.findOne(addressAndService: Tuple2(h.address, h.service));
        }

        if (existing != null) {
          h.id = existing.id;
        }
        // Contact matching is now handled automatically by ContactServiceV2
      }

      List<int> insertedIds = Database.handles.putMany(handles);
      for (int i = 0; i < insertedIds.length; i++) {
        handles[i].id = insertedIds[i];
      }
    });

    return handles;
  }

  /// Save a list of handles asynchronously (non-blocking)
  static Future<List<Handle>> bulkSaveAsync(List<Handle> handles, {matchOnOriginalROWID = false}) async {
    if (kIsWeb) return handles;
    if (handles.isEmpty) return handles;

    final savedHandles = await HandleInterface.bulkSaveHandlesAsync(
      handlesData: handles.map((e) => e.toMap()).toList(),
      matchOnOriginalROWID: matchOnOriginalROWID,
    );

    // Update the handles with saved data
    for (int i = 0; i < handles.length; i++) {
      if (i < savedHandles.length) {
        handles[i].id = savedHandles[i].id;
        handles[i].color = savedHandles[i].color;
      }
    }

    return handles;
  }

  Handle updateColor(String? newColor) {
    color = newColor;
    save();
    return this;
  }

  Handle updateDefaultPhone(String newPhone) {
    defaultPhone = newPhone;
    save();
    return this;
  }

  Handle updateDefaultEmail(String newEmail) {
    defaultEmail = newEmail;
    save();
    return this;
  }

  static Handle? findOne({int? id, int? originalROWID, Tuple2<String, String>? addressAndService}) {
    if (kIsWeb || id == 0) return null;
    if (id != null) {
      final handle = Database.handles.get(id) ?? Handle.findOne(originalROWID: id);
      return handle;
    } else if (originalROWID != null) {
      final query = Database.handles.query(Handle_.originalROWID.equals(originalROWID)).build();
      query.limit = 1;
      final result = query.findFirst();
      query.close();
      return result;
    } else if (addressAndService != null) {
      final query = Database.handles
          .query(Handle_.address.equals(addressAndService.item1) & Handle_.service.equals(addressAndService.item2))
          .build();
      query.limit = 1;
      final result = query.findFirst();
      query.close();
      return result;
    }
    return null;
  }

  static Future<Handle?> findOneAsync({int? id, int? originalROWID, Tuple2<String, String>? addressAndService}) async {
    if (kIsWeb || id == 0) return null;

    return await HandleInterface.findOneHandleAsync(
      id: id,
      originalROWID: originalROWID,
      address: addressAndService?.item1,
      service: addressAndService?.item2,
    );
  }

  static Handle merge(Handle handle1, Handle handle2) {
    handle1.id ??= handle2.id;
    handle1.originalROWID ??= handle2.originalROWID;
    handle1._color.value ??= handle2._color.value;
    handle1.country ??= handle2.country;
    handle1.formattedAddress ??= handle2.formattedAddress;
    if (isNullOrEmpty(handle1.defaultPhone)) {
      handle1.defaultPhone = handle2.defaultPhone;
    }
    if (isNullOrEmpty(handle1.defaultEmail)) {
      handle1.defaultEmail = handle2.defaultEmail;
    }

    return handle1;
  }

  /// Find a list of handles by the specified condition, or return all handles
  /// when no condition is specified
  static List<Handle> find({Condition<Handle>? cond}) {
    final query = Database.handles.query(cond).build();
    return query.find();
  }

  static Future<List<Handle>> findAsync({Condition<Handle>? cond}) async {
    if (kIsWeb) return [];

    // Note: For now, we don't serialize conditions for cross-isolate communication
    // This will return all handles. Future enhancement can add condition serialization.
    return await HandleInterface.findHandlesAsync();
  }

  Map<String, dynamic> toMap() {
    return {
      "ROWID": id,
      "originalROWID": originalROWID,
      "address": address,
      "formattedAddress": formattedAddress,
      "service": service,
      "uniqueAddrAndService": uniqueAddressAndService,
      "country": country,
      "color": color,
      "defaultPhone": defaultPhone,
      "defaultEmail": defaultEmail,
    };
  }
}
