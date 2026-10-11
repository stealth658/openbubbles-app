import 'dart:math';
import 'dart:async';
import 'package:bluebubbles/database/models.dart' hide Entity;
import 'package:bluebubbles/utils/logger/logger.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:google_mlkit_entity_extraction/google_mlkit_entity_extraction.dart';
import 'package:maps_launcher/maps_launcher.dart';
import 'package:tuple/tuple.dart';
import 'package:url_launcher/url_launcher.dart';

/// Applies the fork's rich-text [Annotation] styling (bold / italic /
/// strikethrough / underline / big / small text effects) on top of [base].
TextStyle _styleForAnnotation(TextStyle base, Annotation annotation) {
  var style = base;
  if (annotation.bold ?? false) style = style.apply(fontWeightDelta: 2);
  if (annotation.italic ?? false) style = style.apply(fontStyle: FontStyle.italic);
  style = style.apply(
      decoration: TextDecoration.combine([
    if (annotation.strikethrough ?? false) TextDecoration.lineThrough,
    if (annotation.underline ?? false) TextDecoration.underline,
  ]));
  if (annotation.textEffect == Attributes.BIG) style = style.apply(fontSizeDelta: 4);
  if (annotation.textEffect == Attributes.SMALL) style = style.apply(fontSizeDelta: -2);
  return style;
}

/// Opens the contact form for a mentioned address, using the platform contact
/// sheet when the handle maps to a native contact.
Future<void> _openMention(String? mentionedAddress) async {
  if (kIsDesktop || kIsWeb) return;
  final handle = ChatsSvc.activeChat!.chat.handles.firstWhereOrNull((h) => h.address == mentionedAddress);
  if (handle?.contactsV2.isNotEmpty == true && handle!.contactsV2.first.isNative) {
    try {
      await MethodChannelSvc.actions.viewContactForm(
        nativeContactId: handle.contactsV2.first.nativeContactId,
      );
    } catch (_) {
      showSnackbar("Error", "Failed to find contact on device!");
    }
  } else if (handle != null) {
    await MethodChannelSvc.actions.openContactForm(
      address: handle.address,
      isEmail: handle.address.isEmail,
    );
  }
}

List<InlineSpan> buildMessageSpans(BuildContext context, MessagePart part, Message message,
    {Color? colorOverride, bool hideBodyText = false}) {
  final textSpans = <InlineSpan>[];
  final bubbleColors = context.theme.extensions[BubbleColors] as BubbleColors?;
  final textStyle = (context.theme.extensions[BubbleText] as BubbleText).bubbleText.apply(
        color: colorOverride ??
            (message.isFromMe!
                ? context.theme.colorScheme.onBubble(context, message.chat.target?.isIMessage ?? true)
                : bubbleColors?.onReceivedBubbleColor ?? context.theme.colorScheme.onSurfaceVariant),
        fontSizeFactor: message.isBigEmoji ? 3 : 1,
      );

  if (!isNullOrEmpty(part.subject)) {
    textSpans.addAll(MessageHelper.buildEmojiText(
      "${part.displaySubject}${!hideBodyText ? "\n" : ""}",
      textStyle.apply(fontWeightDelta: 2),
    ));
  }
  if (part.annotations.isNotEmpty) {
    part.annotations.forEachIndexed((i, e) {
      final range = part.annotations[i].range;
      final style = _styleForAnnotation(textStyle, e);
      if (e.mentionedAddress != null) {
        textSpans.addAll(MessageHelper.buildEmojiText(
          part.displayText!.substring(range.first, range.last),
          style.apply(fontWeightDelta: 2),
          recognizer: TapGestureRecognizer()..onTap = () => _openMention(part.annotations[i].mentionedAddress),
        ));
      } else {
        textSpans.addAll(MessageHelper.buildEmojiText(
          part.displayText!.substring(range.first, range.last),
          style,
        ));
      }
    });
  } else if (!isNullOrEmpty(part.displayText)) {
    textSpans.addAll(MessageHelper.buildEmojiText(
      part.displayText!,
      textStyle,
    ));
  }

  return textSpans;
}

/// One ML Kit entity extractor for the whole app.
///
/// Each `EntityExtractor()` gets its own id, and the plugin creates and keeps
/// a native ML Kit client per id until `close()` is called. This used to be
/// constructed per message part and never closed, so every message with text
/// that scrolled past left a native extractor (and its model state) behind --
/// unbounded native memory growth, a far likelier cause of the native crashes
/// that led upstream to cap message length than the text itself.
EntityExtractor? _sharedExtractor;
Future<void> _extractorQueue = Future.value();

/// ML Kit entity extraction over the whole of [text]. Long text is fed in
/// chunks of at most 500 code units, split at paragraph, line, sentence or
/// word boundaries (never inside a surrogate pair), and the results are
/// shifted back to offsets in [text]. Calls are serialised on the shared
/// extractor.
Future<List<EntityAnnotation>> annotateEntities(String text) {
  final completer = Completer<List<EntityAnnotation>>();
  _extractorQueue = _extractorQueue.then((_) async {
    try {
      _sharedExtractor ??= EntityExtractor(language: EntityExtractorLanguage.english);
      final results = <EntityAnnotation>[];
      const chunkSize = 500;
      var start = 0;
      while (start < text.length) {
        var end = min(start + chunkSize, text.length);
        if (end < text.length) {
          final window = text.substring(start, end);
          for (final sep in const ["\n\n", "\n", ". ", " "]) {
            final i = window.lastIndexOf(sep);
            if (i > chunkSize ~/ 4) {
              end = start + i + sep.length;
              break;
            }
          }
          final last = text.codeUnitAt(end - 1);
          if (last >= 0xD800 && last <= 0xDBFF) end--;
        }
        final chunk = sanitizeForMlKit(text.substring(start, end));
        final found = await _sharedExtractor!.annotateText(chunk);
        for (final a in found) {
          results.add(EntityAnnotation(start: a.start + start, end: a.end + start, text: a.text, entities: a.entities));
        }
        start = end;
      }
      completer.complete(results);
    } catch (e, s) {
      completer.completeError(e, s);
    }
  });
  return completer.future;
}

Future<List<InlineSpan>> buildEnrichedMessageSpans(BuildContext context, MessagePart part, Message message,
    {Color? colorOverride, bool hideBodyText = false}) async {
  final textSpans = <InlineSpan>[];
  final bubbleColors = context.theme.extensions[BubbleColors] as BubbleColors?;
  final textStyle = (context.theme.extensions[BubbleText] as BubbleText).bubbleText.apply(
        color: colorOverride ??
            (message.isFromMe!
                ? context.theme.colorScheme.onBubble(context, message.chat.target?.isIMessage ?? true)
                : bubbleColors?.onReceivedBubbleColor ?? context.theme.colorScheme.onSurfaceVariant),
        fontSizeFactor: message.isBigEmoji ? 3 : 1,
      );

  // extract rich content
  final urlRegex = RegExp(
      r'((https?://)|(www\.))[-a-zA-Z0-9@:%._+~#=]{1,256}\.[a-zA-Z0-9()]{1,6}([-a-zA-Z0-9/()@:%_.~#?&=*\[\]]*)\b');

  // The fork renders from the attributed-body [Annotation] list rather than a
  // flat list of entity matches, so that text effects/styles survive alongside
  // ML Kit's link, phone, address, date, tracking and flight detection. Each
  // detected entity is "marked" onto the annotations it overlaps, splitting
  // annotations at the entity boundaries where necessary.
  List<Annotation> annotations = part.annotations.map((a) => a.copy()).toList();
  void markRange(Tuple3<String, List<int>, List?> annotation) {
    var range = annotation.item2;
    List<Annotation> extras = [];
    // split em up correctly
    for (var a in annotations) {
      if (a.range[0] < range[0] && a.range[1] > range[0]) {
        var dup = a.copy();
        dup.range[1] = range[0];
        extras.add(dup);

        // end this range at the start of my new range
        a.range[0] = range[0];
      }

      if (a.range[0] < range[1] && a.range[1] > range[1]) {
        var dup = a.copy();
        dup.range[0] = range[1];
        extras.add(dup);

        // end this range at the start of my new range
        a.range[1] = range[1];
      }
    }
    annotations.addAll(extras);

    for (var a in annotations) {
      if (a.range[0] >= range[0] && a.range[1] <= range[1]) {
        a.renderExtras.add(annotation);
      }
    }
  }

  final controller = cvc(message.chat.target ?? ChatsSvc.activeChat!.chat);
  if (!isNullOrEmpty(part.text)) {
    if (!kIsWeb && !kIsDesktop && SettingsSvc.settings.smartReply.value) {
      if (controller.mlKitParsedText["${message.guid!}-${part.part}"] == null) {
        try {
          controller.mlKitParsedText["${message.guid!}-${part.part}"] = await annotateEntities(part.text!);
        } catch (ex, stack) {
          Logger.warn('Failed to extract entities using mlkit!', error: ex, trace: stack);
        }
      }
      final entities = controller.mlKitParsedText["${message.guid!}-${part.part}"] ?? [];
      for (EntityAnnotation element in entities) {
        if (element.entities.first is AddressEntity) {
          markRange(Tuple3("map", [element.start, element.end], null));
        } else if (element.entities.first is PhoneEntity) {
          markRange(Tuple3("phone", [element.start, element.end], null));
        } else if (element.entities.first is EmailEntity) {
          markRange(Tuple3("email", [element.start, element.end], null));
        } else if (element.entities.first is UrlEntity) {
          markRange(Tuple3("link", [element.start, element.end], null));
        } else if (element.entities.first is DateTimeEntity) {
          final ent = (element.entities.first as DateTimeEntity);
          if (part.text?.substring(element.start, element.end).toLowerCase() == "now") {
            continue;
          }
          markRange(Tuple3("date", [element.start, element.end], [ent.timestamp]));
        } else if (element.entities.first is TrackingNumberEntity) {
          final ent = (element.entities.first as TrackingNumberEntity);
          markRange(Tuple3("tracking", [element.start, element.end], [ent.carrier, ent.number]));
        } else if (element.entities.first is FlightNumberEntity) {
          final ent = (element.entities.first as FlightNumberEntity);
          markRange(Tuple3("flight", [element.start, element.end], [ent.airlineCode, ent.flightNumber]));
        }
      }
      // Belt and braces: mark any URL the regex finds that ML Kit did not
      // already cover (ML Kit occasionally misses bare short-link domains).
      final covered = entities.where((e) => e.entities.first is UrlEntity).map((e) => [e.start, e.end]).toList();
      for (final match in urlRegex.allMatches(part.text!)) {
        final overlaps = covered.any((r) => match.start < r[1] && match.end > r[0]);
        if (!overlaps) markRange(Tuple3("link", [match.start, match.end], null));
      }
    } else {
      List<RegExpMatch> matches = urlRegex.allMatches(part.text!).toList();
      for (RegExpMatch match in matches) {
        markRange(Tuple3("link", [match.start, match.end], null));
      }
    }
  }

  annotations.sort((a, b) => a.range[0].compareTo(b.range[0]));

  // render subject
  if (!isNullOrEmpty(part.subject)) {
    textSpans.addAll(MessageHelper.buildEmojiText(
      "${part.displaySubject}${!hideBodyText ? "\n" : ""}",
      textStyle.apply(fontWeightDelta: 2),
    ));
  }
  // render rich content if needed
  if (annotations.isNotEmpty) {
    annotations.forEachIndexed((i, e) {
      final item = e.renderExtras.firstOrNull;

      final type = item?.item1;
      final range = e.range;
      final data = item?.item3;
      final text = part.displayText!.substring(range.first, range.last);

      final style = _styleForAnnotation(textStyle, e);
      // Only a run that *is* a link is styled (and opens) as one. Testing for
      // a URL anywhere in the run underlined whole paragraphs whenever a link
      // in them had not been split out as its own run.
      final isUrlRun = type == "link" ||
          (type == null && text.trim().isNotEmpty && urlRegex.stringMatch(text) == text.trim());

      if (e.mentionedAddress != null) {
        textSpans.addAll(MessageHelper.buildEmojiText(
          text,
          style.apply(fontWeightDelta: 2),
          recognizer: TapGestureRecognizer()..onTap = () => _openMention(e.mentionedAddress),
        ));
      } else if (isUrlRun ||
          type == "map" ||
          text.isPhoneNumber ||
          text.isEmail ||
          type == "date" ||
          type == "tracking" ||
          type == "flight") {
        textSpans.add(
          TextSpan(
            text: text,
            recognizer: TapGestureRecognizer()
              ..onTap = () async {
                if (isUrlRun) {
                  String url = text.trim();
                  if (!url.startsWith("http://") && !url.startsWith("https://")) {
                    url = "http://$url";
                  }
                  await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                } else if (type == "map") {
                  await MapsLauncher.launchQuery(text);
                } else if (type == "phone") {
                  await launchUrl(Uri(scheme: "tel", path: text));
                } else if (type == "email") {
                  await launchUrl(Uri(scheme: "mailto", path: text));
                } else if (type == "date") {
                  await MethodChannelSvc.actions.openCalendar(dateEpochMillis: data!.first as int);
                } else if (type == "tracking") {
                  final TrackingCarrier c = data!.first;
                  final String number = data.last;
                  Clipboard.setData(ClipboardData(text: number));
                  await launchUrl(trackingUrl(c, number), mode: LaunchMode.externalApplication);
                } else if (type == "flight") {
                  final String c = data!.first;
                  final String number = data.last;
                  await launchUrl(Uri.parse("https://www.google.com/search?q=flight $c$number"),
                      mode: LaunchMode.externalApplication);
                }
              },
            style: style.apply(decoration: TextDecoration.underline),
          ),
        );
      } else {
        textSpans.addAll(MessageHelper.buildEmojiText(
          text,
          style,
        ));
      }
    });
  } else if (!isNullOrEmpty(part.displayText)) {
    textSpans.addAll(MessageHelper.buildEmojiText(
      part.displayText!,
      textStyle,
    ));
  }

  return textSpans;
}


/// OpenBubbles: the carrier's own tracking page for a detected tracking number.
///
/// ML Kit already identifies the carrier, so send the user straight to the
/// shipment instead of a web search for "FEDEX 1234…". Carriers without a
/// known URL fall back to that search. The number is also copied to the
/// clipboard by the caller, so a carrier page that ignores the query parameter
/// still only costs a paste.
Uri trackingUrl(TrackingCarrier carrier, String number) {
  final n = Uri.encodeComponent(number);
  switch (carrier) {
    case TrackingCarrier.fedex:
      return Uri.parse("https://www.fedex.com/fedextrack/?trknbr=$n");
    case TrackingCarrier.ups:
      return Uri.parse("https://www.ups.com/track?tracknum=$n");
    case TrackingCarrier.usps:
      return Uri.parse("https://tools.usps.com/go/TrackConfirmAction?tLabels=$n");
    case TrackingCarrier.dhl:
      return Uri.parse("https://www.dhl.com/us-en/home/tracking.html?tracking-id=$n");
    case TrackingCarrier.ontrac:
      return Uri.parse("https://www.ontrac.com/tracking/?number=$n");
    case TrackingCarrier.lasership:
      return Uri.parse("https://www.lasership.com/track/$n");
    case TrackingCarrier.amazon:
      return Uri.parse("https://track.amazon.com/tracking/$n");
    case TrackingCarrier.israelPost:
      return Uri.parse("https://mypost.israelpost.co.il/itemtrace?itemcode=$n");
    case TrackingCarrier.swissPost:
      return Uri.parse("https://service.post.ch/ekp-web/ui/entry/search/$n");
    case TrackingCarrier.iParcel:
      return Uri.parse("https://tracking.i-parcel.com/?trackingnumber=$n");
    case TrackingCarrier.mcs:
    case TrackingCarrier.unknown:
      return Uri.parse("https://www.google.com/search?q=${Uri.encodeComponent("track package $number")}");
  }
}
