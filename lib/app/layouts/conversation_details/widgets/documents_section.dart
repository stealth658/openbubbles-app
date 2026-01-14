import 'package:bluebubbles/app/app.dart';
import 'package:bluebubbles/app/layouts/conversation_details/widgets/media_gallery_card.dart';
import 'package:bluebubbles/data/database/models.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Widget that handles documents/files section display
class DocumentsSection extends StatelessWidget {
  final List<Attachment> docs;
  final bool isLoading;

  const DocumentsSection({
    super.key,
    required this.docs,
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
          child: BBSectionHeader(text: "OTHER FILES"),
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
        else if (docs.isEmpty)
          SliverToBoxAdapter(
            child: BBEmptyState(
              message: "No files",
              icon: SettingsSvc.settings.skin.value == Skins.iOS ? CupertinoIcons.doc : Icons.description,
            ),
          )
        else
          SliverPadding(
            padding: BBMediaGrid.getGridPadding(SettingsSvc.settings.skin.value),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: BBMediaGrid.calculateCrossAxisCount(context),
                mainAxisSpacing: BBMediaGrid.mainAxisSpacing,
                crossAxisSpacing: BBMediaGrid.crossAxisSpacing,
                childAspectRatio: 1.75,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, int index) {
                  return MediaGalleryCard(
                    attachment: docs[index],
                  );
                },
                childCount: docs.length,
              ),
            ),
          ),
      ],
    );
  }
}
