import 'dart:math';

import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/interactive/url_preview.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

/// Widget that handles locations section display
class LocationsSection extends StatelessWidget {
  final List<Attachment> locations;
  final bool isLoading;

  const LocationsSection({
    super.key,
    required this.locations,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    return SliverMainAxisGroup(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.only(top: 20, bottom: 5, left: 20),
          sliver: SliverToBoxAdapter(
            child: Text(
              "LOCATIONS",
              style: context.theme.textTheme.bodyMedium!.copyWith(
                color: context.theme.colorScheme.outline,
              ),
            ),
          ),
        ),
        if (isLoading)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 20.0, horizontal: 20.0),
              child: Center(
                child: buildProgressIndicator(context, size: 24),
              ),
            ),
          )
        else if (locations.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 20.0, horizontal: 20.0),
              child: Center(
                child: Text(
                  "No locations",
                  style: context.theme.textTheme.bodyMedium!.copyWith(
                    color: context.theme.colorScheme.outline,
                  ),
                ),
              ),
            ),
          )
        else
          Obx(() => SliverPadding(
                padding: EdgeInsets.only(
                  left: SettingsSvc.settings.skin.value == Skins.iOS ? 20 : 10,
                  right: SettingsSvc.settings.skin.value == Skins.iOS ? 20 : 10,
                  top: 10,
                  bottom: 10,
                ),
                sliver: SliverToBoxAdapter(
                  child: MasonryGridView.count(
                    crossAxisCount: max(2, NavigationSvc.width(context) ~/ 200),
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemBuilder: (context, index) {
                      if (AttachmentsSvc.getContent(locations[index]) is! PlatformFile) {
                        return const Text("Failed to load location!");
                      }
                      return Material(
                        color: context.theme.colorScheme.properSurface,
                        borderRadius: BorderRadius.circular(20),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: () async {
                            final attachment = locations[index];
                            if (attachment.mimeType?.contains("location") ?? false) {
                              // Launch the location in maps
                              final location = attachment.transferName;
                              if (location != null) {
                                final uri = Uri.parse("https://maps.google.com/?q=$location");
                                await launchUrl(uri, mode: LaunchMode.externalApplication);
                              }
                            }
                          },
                          child: Center(
                            child: UrlPreview(
                              data: UrlPreviewData(
                                title:
                                    "Location from ${DateFormat.yMd().format(locations[index].message.target!.dateCreated!)}",
                                siteName: "Tap to open",
                              ),
                              file: AttachmentsSvc.getContent(locations[index]),
                            ),
                          ),
                        ),
                      );
                    },
                    itemCount: locations.length,
                  ),
                ),
              )),
      ],
    );
  }
}
