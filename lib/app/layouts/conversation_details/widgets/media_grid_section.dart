import 'package:bluebubbles/app/app.dart';
import 'package:bluebubbles/app/layouts/conversation_details/widgets/media_gallery_card.dart';
import 'package:bluebubbles/app/wrappers/stateful_boilerplate.dart';
import 'package:bluebubbles/data/database/models.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Widget that handles media grid display with selection functionality
class MediaGridSection extends StatefulWidget {
  final List<Attachment> media;
  final RxList<String> selected;
  final bool isLoading;

  const MediaGridSection({
    super.key,
    required this.media,
    required this.selected,
    required this.isLoading,
  });

  @override
  State<MediaGridSection> createState() => _MediaGridSectionState();
}

class _MediaGridSectionState extends OptimizedState<MediaGridSection> {
  @override
  void didUpdateWidget(MediaGridSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Rebuild when isLoading changes
    if (oldWidget.isLoading != widget.isLoading) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }

    return SliverMainAxisGroup(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.only(
            top: BBSpacing.lg,
            bottom: BBSpacing.xs,
            left: BBSpacing.lg,
          ),
          sliver: SliverToBoxAdapter(
            child: Text(
              "IMAGES & VIDEOS",
              style: context.theme.textTheme.bodyMedium!.copyWith(
                color: context.theme.colorScheme.outline,
              ),
            ),
          ),
        ),
        if (widget.isLoading)
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
        else if (widget.media.isEmpty)
          SliverToBoxAdapter(
            child: BBEmptyState(
              message: "No images or videos",
              icon: iOS ? CupertinoIcons.photo : Icons.photo,
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
              ),
              delegate: SliverChildBuilderDelegate(
                (context, int index) {
                  final skin = SettingsSvc.settings.skin.value;
                  return Obx(() => AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        margin: EdgeInsets.all(
                          widget.selected.contains(widget.media[index].guid) ? BBSpacing.sm : 0,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BBRadius.largeBR(skin),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: GestureDetector(
                          onTap: widget.selected.isNotEmpty
                              ? () {
                                  if (widget.selected.contains(widget.media[index].guid)) {
                                    widget.selected.remove(widget.media[index].guid!);
                                  } else {
                                    widget.selected.add(widget.media[index].guid!);
                                  }
                                }
                              : null,
                          onLongPress: () {
                            if (widget.selected.contains(widget.media[index].guid)) {
                              widget.selected.remove(widget.media[index].guid!);
                            } else {
                              widget.selected.add(widget.media[index].guid!);
                            }
                          },
                          child: AbsorbPointer(
                            absorbing: widget.selected.isNotEmpty,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                MediaGalleryCard(
                                  attachment: widget.media[index],
                                ),
                                if (widget.selected.contains(widget.media[index].guid))
                                  Container(
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: context.theme.colorScheme.primary,
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.all(5.0),
                                      child: Icon(
                                        iOS ? CupertinoIcons.check_mark : Icons.check,
                                        color: context.theme.colorScheme.onPrimary,
                                        size: 18,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ));
                },
                childCount: widget.media.length,
              ),
            ),
          ),
      ],
    );
  }
}
