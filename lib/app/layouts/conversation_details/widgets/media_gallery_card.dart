import 'package:bluebubbles/app/app.dart';
import 'package:bluebubbles/data/database/models.dart';
import 'package:flutter/widgets.dart';

/// Legacy wrapper for BBMediaCard
/// 
/// @Deprecated('Use BBMediaCard from package:bluebubbles/app/app.dart instead')
@Deprecated('Use BBMediaCard from package:bluebubbles/app/app.dart instead')
class MediaGalleryCard extends StatelessWidget {
  const MediaGalleryCard({super.key, required this.attachment});
  final Attachment attachment;

  @override
  Widget build(BuildContext context) {
    return BBMediaCard(attachment: attachment);
  }
}
