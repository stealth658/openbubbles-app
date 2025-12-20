import 'dart:io';

import 'package:bluebubbles/database/database.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/utils/logger/logger.dart';
import 'package:crypto/crypto.dart';
import 'package:fast_contacts/fast_contacts.dart' hide Contact, StructuredName;
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// ContactV2Actions - Isolate-side logic for the new contact service
/// All operations here run in the GlobalIsolate to prevent UI jank
/// This follows the architecture outlined in FR-1.md
class ContactV2Actions {
  /// Fetch all contacts from device and match them to existing handles
  /// This is the main operation described in Section II.A of FR-1.md
  static Future<List<int>> fetchAndMatchContacts(dynamic data) async {
    final startTime = DateTime.now().millisecondsSinceEpoch;
    final affectedHandleIds = <int>[];

    try {
      // Step 1: Fetch contacts using FastContacts
      Logger.info('[ContactV2] Starting contact fetch...');
      final rawContacts = await FastContacts.getAllContacts(
        fields: List<ContactField>.from(ContactField.values)
          ..removeWhere((e) => [
                ContactField.company,
                ContactField.department,
                ContactField.jobDescription,
                ContactField.emailLabels,
                ContactField.phoneLabels
              ].contains(e)),
      );

      Logger.info('[ContactV2] Fetched ${rawContacts.length} contacts from device');

      // Step 1.5: Pre-fetch and save all contact avatars (async operations must be done BEFORE transaction)
      final avatarPaths = <String, String?>{};
      for (final rawContact in rawContacts) {
        try {
          final avatarData = await FastContacts.getContactImage(
            rawContact.id,
            size: ContactImageSize.fullSize,
          );
          if (avatarData != null && avatarData.isNotEmpty) {
            avatarPaths[rawContact.id] = await _saveContactAvatar(rawContact.id, avatarData);
          }
        } catch (e) {
          // Avatar fetch failed, continue without it
        }
      }

      // Step 2: Process and normalize contacts within a transaction (synchronous only!)
      Database.runInTransaction(TxMode.write, () {
        final contactsBox = Database.contactsV2;
        final handlesBox = Database.handles;

        for (final rawContact in rawContacts) {
          // Normalize addresses
          final normalizedAddresses = <String>[];
          
          // Add normalized phone numbers
          for (final phone in rawContact.phones) {
            final normalized = ContactV2.normalizePhoneNumber(phone.number);
            if (normalized.isNotEmpty) {
              normalizedAddresses.add(normalized);
            }
          }

          // Add normalized emails
          for (final email in rawContact.emails) {
            final normalized = ContactV2.normalizeEmail(email.address);
            if (normalized.isNotEmpty) {
              normalizedAddresses.add(normalized);
            }
          }

          if (normalizedAddresses.isEmpty) continue;

          // Get pre-fetched avatar path
          final avatarPath = avatarPaths[rawContact.id];

          // Check if contact already exists
          final existingQuery = contactsBox
              .query(ContactV2_.nativeContactId.equals(rawContact.id))
              .build();
          final existingContact = existingQuery.findFirst();
          existingQuery.close();

          ContactV2 contact;
          if (existingContact != null) {
            // Update existing contact
            contact = existingContact;
            final nameChanged = contact.displayName != rawContact.displayName;
            contact.displayName = rawContact.displayName;
            contact.addresses = normalizedAddresses;
            contact.avatarPath = avatarPath;
            
            if (nameChanged) {
              // Mark all existing handles for this contact as affected
              for (final existingHandle in contact.handles) {
                if (existingHandle.id != null && !affectedHandleIds.contains(existingHandle.id!)) {
                  affectedHandleIds.add(existingHandle.id!);
                }
              }
            }
          } else {
            // Create new contact
            contact = ContactV2(
              displayName: rawContact.displayName,
              nativeContactId: rawContact.id,
              avatarPath: avatarPath,
              addresses: normalizedAddresses,
            );
          }

          // Step 3: Match contact to handles
          final matchedHandles = <Handle>[];
          
          // Get all handles - we'll filter by normalization since handles might not be normalized in DB
          final allHandles = handlesBox.getAll();
          
          for (final address in normalizedAddresses) {
            final isContactEmail = address.contains('@');
            
            for (final handle in allHandles) {
              // Check if address matches when normalized
              // Use appropriate normalization based on whether it's an email or phone number
              final isHandleEmail = handle.address.contains('@');
              
              // Skip if types don't match (email vs phone)
              if (isContactEmail != isHandleEmail) continue;
              
              final handleAddress = isHandleEmail 
                  ? ContactV2.normalizeEmail(handle.address)
                  : ContactV2.normalizePhoneNumber(handle.address);
              final handleFormatted = handle.formattedAddress != null 
                  ? (isHandleEmail 
                      ? ContactV2.normalizeEmail(handle.formattedAddress!)
                      : ContactV2.normalizePhoneNumber(handle.formattedAddress!))
                  : null;

              if (handleAddress == address || handleFormatted == address) {
                if (!matchedHandles.contains(handle)) {
                  matchedHandles.add(handle);
                  if (handle.id != null && !affectedHandleIds.contains(handle.id!)) {
                    affectedHandleIds.add(handle.id!);
                  }
                }
              }
            }
          }

          // Clear existing handle relationships and add new ones
          contact.handles.clear();
          contact.handles.addAll(matchedHandles);

          // Save the contact with its relationships
          try {
            contactsBox.put(contact);
          } on UniqueViolationException catch (e) {
            Logger.warn('[ContactV2] Unique violation for contact ${contact.nativeContactId}: $e');
          }
        }
      });

      final endTime = DateTime.now().millisecondsSinceEpoch;
      Logger.info('[ContactV2] Contact fetch and match completed in ${endTime - startTime}ms');
      Logger.info('[ContactV2] Affected ${affectedHandleIds.length} handles');

      return affectedHandleIds;
    } catch (e, stack) {
      Logger.error('[ContactV2] Error fetching and matching contacts', error: e, trace: stack);
      return [];
    }
  }

  /// Check for contact database changes by comparing native contact IDs
  /// This is used by the periodic background task (Section II.B of FR-1.md)
  static Future<bool> checkContactChanges(dynamic data) async {
    try {
      Logger.info('[ContactV2] Checking for contact changes...');

      // Get current device contact IDs (only fetch minimal data)
      final currentContacts = await FastContacts.getAllContacts(
        fields: [ContactField.displayName], // Minimal fetch for ID comparison
      );
      final currentIds = currentContacts.map((c) => c.id).toSet();

      // Get stored contact IDs
      final storedIds = Database.runInTransaction(TxMode.read, () {
        final contactsBox = Database.contactsV2;
        final allContacts = contactsBox.getAll();
        return allContacts.map((c) => c.nativeContactId).toSet();
      });

      // Check for differences
      final hasChanges = currentIds.length != storedIds.length ||
          !currentIds.containsAll(storedIds) ||
          !storedIds.containsAll(currentIds);

      if (hasChanges) {
        Logger.info('[ContactV2] Contact changes detected, triggering refresh');
        await fetchAndMatchContacts(<String, dynamic>{});
        return true;
      }

      Logger.info('[ContactV2] No contact changes detected');
      return false;
    } catch (e, stack) {
      Logger.error('[ContactV2] Error checking contact changes', error: e, trace: stack);
      return false;
    }
  }

  /// Get all stored ContactV2 IDs for comparison
  static Future<List<String>> getStoredContactIds(dynamic data) async {
    return await Database.runInTransaction(TxMode.read, () {
      final contactsBox = Database.contactsV2;
      final allContacts = contactsBox.getAll();
      return allContacts.map((c) => c.nativeContactId).toList();
    });
  }

  /// Find a single ContactV2 by native contact ID
  static Future<Map<String, dynamic>?> findOneContactV2(dynamic data) async {
    final dataMap = data as Map<dynamic, dynamic>;
    final nativeContactId = dataMap['nativeContactId'] as String;

    return await Database.runInTransaction(TxMode.read, () {
      final contactsBox = Database.contactsV2;
      final query = contactsBox
          .query(ContactV2_.nativeContactId.equals(nativeContactId))
          .build();
      query.limit = 1;
      final contact = query.findFirst();
      query.close();

      return contact?.toMap();
    });
  }

    /// Get ContactV2 entities for a list of Handle IDs
  static Future<List<Map<String, dynamic>>> getContactsForHandles(dynamic data) async {
    final dataMap = data as Map<dynamic, dynamic>;
    final handleIds = (dataMap['handleIds'] as List).cast<int>();

    return await Database.runInTransaction(TxMode.read, () {
      final handlesBox = Database.handles;
      final contacts = <ContactV2>[];

      for (final handleId in handleIds) {
        final handle = handlesBox.get(handleId);
        if (handle != null && handle.contactsV2.isNotEmpty) {
          // Get the first contact (should typically only be one)
          contacts.addAll(handle.contactsV2);
        }
      }

      // Remove duplicates based on nativeContactId
      final uniqueContacts = <String, ContactV2>{};
      for (final contact in contacts) {
        uniqueContacts[contact.nativeContactId] = contact;
      }

      return uniqueContacts.values.map((c) => c.toMap()).toList();
    });
  }

  /// Manually trigger a contact refresh
  static Future<List<int>> refreshContacts(dynamic data) async {
    return await fetchAndMatchContacts(data);
  }

  /// Save a contact avatar to disk and return the file path
  /// 
  /// Optimizations:
  /// - Only writes if avatar doesn't exist or has changed
  /// - Uses file size comparison first (fast)
  /// - Falls back to hash comparison if sizes match
  static Future<String?> _saveContactAvatar(String contactId, Uint8List avatarData) async {
    try {
      // Get the app's documents directory
      final appDocDir = Directory(Database.appDocPath);
      final avatarsDir = Directory(p.join(appDocDir.path, 'contact_avatars'));
      
      // Create the directory if it doesn't exist
      if (!await avatarsDir.exists()) {
        await avatarsDir.create(recursive: true);
      }

      // Save the avatar with the contact ID as filename
      final avatarFile = File(p.join(avatarsDir.path, '$contactId.jpg'));
      
      // Check if avatar already exists and compare it to avoid unnecessary writes
      if (await avatarFile.exists()) {
        final existingData = await avatarFile.readAsBytes();
        
        // Quick size check first
        if (existingData.length == avatarData.length) {
          // If sizes match, do a hash comparison to be sure
          final existingHash = sha256.convert(existingData);
          final newHash = sha256.convert(avatarData);
          
          if (existingHash == newHash) {
            // Avatar hasn't changed, return existing path without writing
            return avatarFile.path;
          }
        }
      }
      
      // Avatar is new or has changed, write it to disk
      await avatarFile.writeAsBytes(avatarData);

      return avatarFile.path;
    } catch (e, stack) {
      Logger.error('[ContactV2] Error saving avatar for contact $contactId', error: e, trace: stack);
      return null;
    }
  }

  /// Get a contact by address (email or phone number)
  static Future<Map<String, dynamic>?> getContactByAddress(dynamic data) async {
    final dataMap = data as Map<dynamic, dynamic>;
    final address = dataMap['address'] as String;

    return await Database.runInTransaction(TxMode.read, () {
      final contactsBox = Database.contactsV2;
      
      // Normalize the search address
      final normalized = address.contains('@') 
          ? ContactV2.normalizeEmail(address)
          : ContactV2.normalizePhoneNumber(address);

      // Search through all contacts for a match
      final allContacts = contactsBox.getAll();
      
      for (final contact in allContacts) {
        if (contact.hasMatchingAddress(normalized)) {
          return contact.toMap();
        }
      }

      return null;
    });
  }

  /// Get all contacts from the database
  static Future<List<Map<String, dynamic>>> getAllContacts(dynamic data) async {
    return await Database.runInTransaction(TxMode.read, () {
      final contactsBox = Database.contactsV2;
      final allContacts = contactsBox.getAll();
      return allContacts.map((c) => c.toMap()).toList();
    });
  }

  /// Fetch network contacts for web/desktop (from server)
  static Future<List<Map<String, dynamic>>> fetchNetworkContacts(dynamic data) async {
    // This will be implemented when web/desktop support is added
    // For now, return empty list
    Logger.warn('[ContactV2] fetchNetworkContacts not yet implemented for web/desktop');
    return [];
  }

  /// Get avatar data for a contact by native contact ID
  static Future<Uint8List?> getContactAvatar(dynamic data) async {
    final dataMap = data as Map<dynamic, dynamic>;
    final nativeContactId = dataMap['nativeContactId'] as String;

    try {
      // First try to get from disk (if we've already saved it)
      final appDocDir = Directory(Database.appDocPath);
      final avatarsDir = Directory(p.join(appDocDir.path, 'contact_avatars'));
      final avatarFile = File(p.join(avatarsDir.path, '$nativeContactId.jpg'));

      if (await avatarFile.exists()) {
        return await avatarFile.readAsBytes();
      }

      // If not on disk, try to fetch it fresh
      if (!kIsWeb && !kIsDesktop) {
        Uint8List? avatar;
        
        try {
          avatar = await FastContacts.getContactImage(nativeContactId, size: ContactImageSize.fullSize);
        } catch (e) {
          Logger.warn('[ContactV2] Failed to get full size avatar for ID $nativeContactId: $e');
        }

        if (avatar == null) {
          try {
            avatar = await FastContacts.getContactImage(nativeContactId);
          } catch (e) {
            Logger.warn('[ContactV2] Failed to get small size avatar for ID $nativeContactId: $e');
          }
        }

        // Save it to disk for future use
        if (avatar != null) {
          await _saveContactAvatar(nativeContactId, avatar);
        }

        return avatar;
      }

      return null;
    } catch (e, stack) {
      Logger.error('[ContactV2] Error getting contact avatar for $nativeContactId', error: e, trace: stack);
      return null;
    }
  }
}
