import 'dart:async';
import 'dart:convert';

import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/database/database.dart';
import 'package:bluebubbles/helpers/types/helpers/misc_helpers.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:bluebubbles/utils/logger/logger.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

/// OpenBubbles: on-device generative AI through Gemini Nano (ML Kit GenAI).
///
/// Everything here runs on the phone via Android's AICore service; there is no
/// API key and no network call for inference. The Kotlin side is
/// services/genai/GenAiHandler.kt. Features and their models are independent:
/// each reports its own status and downloads separately, so a device can have
/// proofreading ready while the Prompt API is still unavailable.
class GenAi {
  GenAi._();

  static const features = ['summarize', 'proofread', 'rewrite', 'prompt'];

  /// Last known per-feature status: available | downloadable | downloading | unavailable.
  static final RxMap<String, String> status = <String, String>{}.obs;

  static bool get supported => !kIsWeb && !kIsDesktop && defaultTargetPlatform == TargetPlatform.android;

  static bool get enabled => supported && SettingsSvc.settings.onDeviceAi.value;

  static bool available(String feature) => status[feature] == 'available';

  /// Refreshes [status]. Safe to call often; it is a cheap local query.
  static Future<Map<String, String>> refreshStatus() async {
    if (!supported) return {};
    try {
      final s = await MethodChannelSvc.actions.genAiStatus().timeout(const Duration(seconds: 10));
      status.assignAll(s);
      return s;
    } catch (e) {
      Logger.warn("GenAI status check failed: $e", tag: 'GenAI');
      status.assignAll({for (final f in features) f: 'unavailable'});
      return status;
    }
  }

  /// Downloads a feature's model. Resolves when it is usable, throws otherwise.
  static Future<void> download(String feature) async {
    await MethodChannelSvc.actions.genAiDownload(feature).timeout(const Duration(minutes: 10));
    await refreshStatus();
  }

  /// Makes sure [feature] is usable, downloading if the device offers it.
  /// Returns false when the feature cannot be made available on this device.
  static Future<bool> ensure(String feature) async {
    if (!enabled) return false;
    if (status.isEmpty) await refreshStatus();
    switch (status[feature]) {
      case 'available':
        return true;
      case 'downloadable':
      case 'downloading':
        try {
          await download(feature);
          return available(feature);
        } catch (e) {
          Logger.warn("GenAI download of $feature failed: $e", tag: 'GenAI');
          return false;
        }
      default:
        return false;
    }
  }

  static String _describe(Object e) =>
      e is PlatformException ? (e.message ?? e.code) : e.toString();

  static Future<String> proofread(String text) async {
    try {
      return await MethodChannelSvc.actions.genAiProofread(text).timeout(const Duration(seconds: 45));
    } catch (e) {
      throw Exception("Proofreading failed: ${_describe(e)}");
    }
  }

  /// style: elaborate | emojify | shorten | friendly | professional | rephrase
  static Future<List<String>> rewrite(String text, String style) async {
    try {
      final out = await MethodChannelSvc.actions.genAiRewrite(text, style).timeout(const Duration(seconds: 45));
      return out.where((s) => s.trim().isNotEmpty).toList();
    } catch (e) {
      throw Exception("Rewrite failed: ${_describe(e)}");
    }
  }

  static Future<String> summarize(String conversationText, {int bullets = 3}) async {
    try {
      return await MethodChannelSvc.actions
          .genAiSummarize(conversationText, bullets: bullets)
          .timeout(const Duration(seconds: 90));
    } catch (e) {
      throw Exception("Summary failed: ${_describe(e)}");
    }
  }

  static Future<String> prompt(String prompt) async {
    try {
      return await MethodChannelSvc.actions.genAiPrompt(prompt).timeout(const Duration(seconds: 60));
    } catch (e) {
      throw Exception("Gemini Nano failed: ${_describe(e)}");
    }
  }

  // ---------------------------------------------------------------------------
  // Conversation helpers
  // ---------------------------------------------------------------------------

  /// Renders recent messages of [chat] as "Name: text" lines, oldest first,
  /// skipping reactions, group events and empty attachment-only messages.
  static List<String> transcriptLines(Chat chat, {int limit = 40, DateTime? after}) {
    final q = (Database.messages.query(Message_.dateDeleted.isNull()
            .and(Message_.itemType.equals(0))
            .and(Message_.associatedMessageGuid.isNull()))
          ..order(Message_.dateCreated, flags: Order.descending)
          ..link(Message_.chat, Chat_.id.equals(chat.id!)))
        .build();
    q.limit = limit;
    final recent = q.find().reversed.toList();
    q.close();

    final lines = <String>[];
    for (final m in recent) {
      if (after != null && (m.dateCreated?.isBefore(after) ?? false)) continue;
      final text = m.fullText.trim();
      if (text.isEmpty) continue;
      final who = (m.isFromMe ?? false) ? "Me" : (m.handle?.displayName ?? chat.getTitle() ?? "Them");
      lines.add("$who: $text");
    }
    return lines;
  }

  /// Three short reply suggestions for the current state of [chat], generated
  /// by Gemini Nano from the last few messages. Returns an empty list when the
  /// model declines or the output cannot be parsed; callers fall back to ML
  /// Kit's smart reply.
  static Future<List<String>> suggestReplies(Chat chat) async {
    if (!await ensure('prompt')) return [];
    final lines = transcriptLines(chat, limit: 8);
    if (lines.isEmpty || lines.last.startsWith("Me:")) return [];
    final p = StringBuffer()
      ..writeln("You are helping someone reply to a text message conversation.")
      ..writeln("Lines starting with \"Me:\" were sent by the person you are helping; other lines are from the other side.")
      ..writeln("Suggest three short, natural replies they could send next, each under 12 words, in the same tone as the conversation.")
      ..writeln("Respond with only a JSON array of three strings and nothing else.")
      ..writeln()
      ..writeln(lines.join("\n"));
    final raw = await prompt(p.toString());
    return _parseList(raw);
  }

  /// Summarises the recent conversation in [chat] as bullets.
  static Future<String> summarizeChat(Chat chat, {int limit = 40, DateTime? after}) async {
    if (!await ensure('summarize')) {
      throw Exception("Summaries aren't available on this device yet.");
    }
    final lines = transcriptLines(chat, limit: limit, after: after);
    if (lines.length < 2) throw Exception("Not enough recent messages to summarise.");
    return summarize(lines.join("\n"));
  }

  static List<String> _parseList(String raw) {
    var s = raw.trim();
    final start = s.indexOf('[');
    final end = s.lastIndexOf(']');
    if (start >= 0 && end > start) s = s.substring(start, end + 1);
    try {
      final decoded = jsonDecode(s);
      if (decoded is List) {
        return decoded.whereType<String>().map((e) => e.trim()).where((e) => e.isNotEmpty).take(3).toList();
      }
    } catch (_) {}
    // Fall back to one suggestion per line.
    return raw
        .split('\n')
        .map((l) => l.replaceFirst(RegExp(r'^\s*[-*\d.)]+\s*'), '').replaceAll(RegExp(r'^"|"$'), '').trim())
        .where((l) => l.isNotEmpty && l.length < 80)
        .take(3)
        .toList();
  }
}
