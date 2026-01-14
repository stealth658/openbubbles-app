import 'dart:convert';

import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/objectbox.g.dart';
import 'package:bluebubbles/data/models/native/message.dart';
import 'package:bluebubbles/services/backend/descriptors/attachment_query_descriptor.dart';
import 'package:bluebubbles/services/backend/interfaces/attachment_interface.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:flutter/foundation.dart';
import 'package:mime_type/mime_type.dart';
// (needed when generating objectbox model code)
// ignore: unnecessary_import
import 'package:objectbox/objectbox.dart';
import 'package:universal_io/io.dart';

@Entity()
class Attachment {
  int? id;
  int? originalROWID;

  @Index(type: IndexType.value)
  @Unique()
  String? guid;

  String? uti;
  String? mimeType;
  bool? isOutgoing;
  String? transferName;
  int? totalBytes;
  int? height;
  int? width;
  @Transient()
  Uint8List? bytes;
  String? webUrl;
  bool hasLivePhoto;
  bool isDownloaded;

  final message = ToOne<Message>();

  Map<String, dynamic>? metadata;

  String? get dbMetadata => metadata == null ? null : jsonEncode(metadata);
  set dbMetadata(String? json) => metadata = json == null ? null : jsonDecode(json) as Map<String, dynamic>;

  Attachment({
    this.id,
    this.originalROWID,
    this.guid,
    this.uti,
    this.mimeType,
    this.isOutgoing,
    this.transferName,
    this.totalBytes,
    this.height,
    this.width,
    this.metadata,
    this.bytes,
    this.webUrl,
    this.hasLivePhoto = false,
    this.isDownloaded = false,
  });

  /// Convert JSON to [Attachment]
  factory Attachment.fromMap(Map<String, dynamic> json) {
    String? mimeType = json["mimeType"];
    if (json["uti"] == "com.apple.coreaudio_format" || json['transferName'].toString().endsWith(".caf")) {
      mimeType = "audio/caf";
    }

    // Load the metadata
    var metadata = json["metadata"];
    if (metadata is String && metadata.isNotEmpty) {
      try {
        metadata = jsonDecode(metadata);
      } catch (_) {}
    }

    return Attachment(
      id: json["ROWID"] ?? json["id"],
      originalROWID: json["originalROWID"],
      guid: json["guid"],
      uti: json["uti"],
      mimeType: mimeType ?? mime(json['transferName']),
      isOutgoing: json["isOutgoing"] == true,
      transferName: json['transferName'],
      totalBytes: json['totalBytes'] is int ? json['totalBytes'] : 0,
      height: json["height"] ?? 0,
      width: json["width"] ?? 0,
      metadata: metadata is String ? null : metadata,
      hasLivePhoto: json["hasLivePhoto"] ?? false,
      isDownloaded: json["isDownloaded"] ?? false,
    );
  }

  Future<Attachment> saveAsync(Message? message) async {
    if (kIsWeb) return this;

    final result = await AttachmentInterface.saveAttachmentAsync(
      attachmentData: toMap(),
      messageData: message?.toMap(),
    );

    id = result.id;
    return this;
  }

  static Future<void> bulkSaveAsync(Map<Message, List<Attachment>> map) async {
    // Convert the map to serializable format
    Map<Map<String, dynamic>, List<Map<String, dynamic>>> mapData = {};
    for (var entry in map.entries) {
      mapData[entry.key.toMap()] = entry.value.map((e) => e.toMap()).toList();
    }

    await AttachmentInterface.bulkSaveAttachmentsAsync(mapData: mapData);
  }

  /// replaces a temporary attachment with the new one from the server (async version)
  /// Note: This must be called from the main thread to access cm/cvc services
  static Future<Attachment> replaceAttachmentAsync(String? oldGuid, Attachment newAttachment) async {
    if (kIsWeb) return newAttachment;

    Attachment? existing = await Attachment.findOneAsync(oldGuid!);
    if (existing == null) {
      return Future.error("Old GUID ($oldGuid) does not exist!");
    }

    // Handle cm/cvc services on main thread BEFORE calling isolate
    if (ChatsSvc.activeChat != null) {
      // Image caching is now handled by Flutter's image cache automatically
    }

    // Call the isolate-safe database operations
    final updatedAttachment = await AttachmentInterface.replaceAttachmentAsync(
      oldGuid: oldGuid,
      newAttachmentData: newAttachment.toMap(),
    );

    // Handle file system operations on main thread AFTER isolate call
    String appDocPath = FilesystemSvc.appDocDir.path;
    String pathName = "$appDocPath/attachments/$oldGuid";
    Directory directory = Directory(pathName);

    if (directory.existsSync()) {
      await directory.rename("$appDocPath/attachments/${newAttachment.guid}");
    }

    // Update newAttachment with values from result
    newAttachment.id = updatedAttachment.id;
    newAttachment.width = updatedAttachment.width;
    newAttachment.height = updatedAttachment.height;
    newAttachment.metadata = updatedAttachment.metadata;

    return newAttachment;
  }

  static Future<Attachment?> findOneAsync(String guid) async {
    if (kIsWeb) return null;
    return await AttachmentInterface.findOneAttachmentAsync(guid: guid);
  }

  static Future<List<Attachment>> findAsync({
    AttachmentQueryDescriptor? queryDescriptor,
  }) async {
    if (kIsWeb) return [];
    return await AttachmentInterface.findAttachmentsAsync(queryDescriptor: queryDescriptor);
  }

  static Future<void> deleteAsync(String guid) async {
    if (kIsWeb) return;

    await AttachmentInterface.deleteAttachmentAsync(guid: guid);
  }

  String getFriendlySize({decimals = 2}) {
    return (totalBytes ?? 0.0).toDouble().getFriendlySize();
  }

  bool get hasValidSize => (width ?? 0) > 0 && (height ?? 0) > 0;

  double get aspectRatio =>
      hasValidSize ? (_isPortrait && height! < width! ? (height! / width!).abs() : (width! / height!).abs()) : 0.78;

  String? get mimeStart => mimeType?.split("/").first;

  static String get baseDirectory => "${FilesystemSvc.appDocDir.path}/attachments";

  String get directory => "$baseDirectory/$guid";

  String get path {
    switch (Platform.operatingSystem) {
      case "windows":
        return "$directory/${"$transferName".replaceAll(RegExp(r'[<>:"/\|?*]'), "_")}";
      case "linux":
      case "macos":
        return "$directory/${"$transferName".replaceAll(RegExp(r'/'), "_")}";
      default:
        return "$directory/$transferName";
    }
  }

  String get convertedPath => "$path.png";

  bool get existsOnDisk => File(path).existsSync();

  Future<bool> get existsOnDiskAsync async => await File(path).exists();

  bool get canCompress => mimeStart == "image" && !mimeType!.contains("gif");

  static Attachment merge(Attachment attachment1, Attachment attachment2) {
    attachment1.id ??= attachment2.id;
    attachment1.bytes ??= attachment2.bytes;
    attachment1.guid ??= attachment2.guid;
    attachment1.height ??= attachment2.height;
    attachment1.width ??= attachment2.width;
    attachment1.isOutgoing ??= attachment2.isOutgoing;
    attachment1.mimeType ??= attachment2.mimeType;
    attachment1.totalBytes ??= attachment2.totalBytes;
    attachment1.transferName ??= attachment2.transferName;
    attachment1.uti ??= attachment2.uti;
    attachment1.webUrl ??= attachment2.webUrl;
    attachment1.metadata = mergeTopLevelDicts(attachment1.metadata, attachment2.metadata);
    if (attachment2.hasLivePhoto) {
      attachment1.hasLivePhoto = attachment2.hasLivePhoto;
    }
    // Only overwrite isDownloaded if the new attachment is downloaded
    if (!attachment1.isDownloaded && attachment2.isDownloaded) {
      attachment1.isDownloaded = attachment2.isDownloaded;
    }
    if (!attachment1.message.hasValue) {
      attachment1.message.target = attachment2.message.target;
    }
    return attachment1;
  }

  Map<String, dynamic> toMap() => {
        "ROWID": id,
        "originalROWID": originalROWID,
        "guid": guid,
        "uti": uti,
        "mimeType": mimeType,
        "isOutgoing": isOutgoing!,
        "transferName": transferName,
        "totalBytes": totalBytes,
        "height": height,
        "width": width,
        "metadata": jsonEncode(metadata),
        "hasLivePhoto": hasLivePhoto,
        "isDownloaded": isDownloaded,
      };

  bool get _isPortrait {
    if (metadata?['orientation'] == '1') return true;
    if (metadata?['orientation'] == 1) return true;
    if (metadata?['orientation'] == 'portrait') return true;
    if (metadata?['Image Orientation']?.contains("90") ?? false) return true;
    return false;
  }
}
