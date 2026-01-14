import 'package:bluebubbles/app/app.dart';
import 'package:bluebubbles/app/layouts/conversation_view/widgets/message/interactive/url_preview.dart';
import 'package:bluebubbles/data/database/models.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:flutter/cupertino.dart';
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
        const SliverToBoxAdapter(
          child: BBSectionHeader(text: "LOCATIONS"),
        ),
        if (isLoading)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(
                vertical: BBSpacing.lg,
                horizontal: BBSpacing.lg,
              ),
              child: Center(
                child: BBLoadingIndicator(size: 24),
              ),
            ),
          )
        else if (locations.isEmpty)
          SliverToBoxAdapter(
            child: BBEmptyState(
              message: "No locations",
              icon: SettingsSvc.settings.skin.value == Skins.iOS ? CupertinoIcons.location : Icons.location_on,
            ),
          )
        else
          SliverPadding(
            padding: BBMediaGrid.getGridPadding(SettingsSvc.settings.skin.value),
            sliver: SliverToBoxAdapter(
              child: MasonryGridView.count(
                crossAxisCount: BBMediaGrid.calculateCrossAxisCount(context),
                mainAxisSpacing: BBMediaGrid.mainAxisSpacing,
                crossAxisSpacing: BBMediaGrid.crossAxisSpacing,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemBuilder: (context, index) {
                  if (AttachmentsSvc.getContent(locations[index]) is! PlatformFile) {
                    return const Text("Failed to load location!");
                  }
                  final skin = SettingsSvc.settings.skin.value;
                  return Material(
                    color: context.theme.colorScheme.properSurface,
                    borderRadius: BBRadius.largeBR(skin),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      borderRadius: BBRadius.largeBR(skin),
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
                          message: locations[index].message.target!,
                          file: AttachmentsSvc.getContent(locations[index]),
                        ),
                      ),
                    ),
                  );
                },
                itemCount: locations.length,
              ),
            ),
          ),
      ],
    );
  }
}
