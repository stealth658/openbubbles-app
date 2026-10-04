import 'package:bluebubbles/app/components/avatars/contact_avatar_widget.dart';
import 'package:bluebubbles/app/components/m3e/m3e.dart';
import 'package:bluebubbles/app/layouts/findmy/findmy_page.dart';
import 'package:bluebubbles/app/layouts/findmy/findmy_tiles.dart';
import 'package:bluebubbles/app/wrappers/theme_switcher.dart';
import 'package:bluebubbles/database/global/findmy_friend.dart';
import 'package:bluebubbles/database/models.dart';
import 'package:bluebubbles/helpers/helpers.dart';
import 'package:bluebubbles/services/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:get/get.dart';
import 'package:latlong2/latlong.dart';
import 'package:maps_launcher/maps_launcher.dart';

/// "Location" section for 1:1 conversation details: a small static map with the
/// contact's avatar on it, the address, and when it was last updated. Only
/// appears for people who share their location with you. Tap opens Find My on
/// that friend; the directions button opens the maps app.
class FindMyLocationCard extends StatefulWidget {
  const FindMyLocationCard({super.key, required this.chat, required this.tileColor});

  final Chat chat;
  final Color tileColor;

  @override
  State<FindMyLocationCard> createState() => _FindMyLocationCardState();
}

class _FindMyLocationCardState extends State<FindMyLocationCard> {
  @override
  void initState() {
    super.initState();
    if (FindMyFriendsCache.available) FindMyFriendsCache.refresh();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.chat.isGroup) return const SliverToBoxAdapter(child: SizedBox.shrink());
    return SliverToBoxAdapter(
      child: Obx(() {
        final friend = FindMyFriendsCache.forChat(widget.chat);
        if (friend == null || !friend.hasLocation || SettingsSvc.settings.redactedMode.value) {
          return const SizedBox.shrink();
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const M3ESectionHeader(label: "Location"),
            M3ESection(
              backgroundColor: widget.tileColor,
              children: [
                _LocationTile(chat: widget.chat, friend: friend),
              ],
            ),
          ],
        );
      }),
    );
  }
}

class _LocationTile extends StatelessWidget {
  const _LocationTile({required this.chat, required this.friend});

  final Chat chat;
  final FindMyFriend friend;

  @override
  Widget build(BuildContext context) {
    final scheme = context.theme.colorScheme;
    final point = LatLng(friend.latitude!, friend.longitude!);
    final lines = (friend.longAddress ?? friend.placeName ?? "").split("\n").where((l) => l.trim().isNotEmpty).toList();
    final updated = friend.lastUpdated == null ? null : buildDate(friend.lastUpdated);

    return InkWell(
      onTap: () => Navigator.of(context).push(
        ThemeSwitcher.buildPageRoute(builder: (_) => FindMyPage(defaultFriend: friend.id)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 150,
            child: IgnorePointer(
              child: FlutterMap(
                options: MapOptions(
                  initialCenter: point,
                  initialZoom: 13,
                  interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
                ),
                children: [
                  findMyTileLayer(context),
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: point,
                        width: 36,
                        height: 36,
                        alignment: Alignment.topCenter,
                        child: Container(
                          decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                          padding: const EdgeInsets.all(2),
                          child: ContactAvatarWidget(
                            handle: friend.handle,
                            contact: friend.contact,
                            editable: false,
                            scaleSize: false,
                            size: 32,
                          ),
                        ),
                      ),
                    ],
                  ),
                  findMyAttribution(context),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        lines.isNotEmpty ? lines.first : "Shared location",
                        style: context.theme.textTheme.bodyLarge!.copyWith(color: scheme.onSurface),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (lines.length > 1)
                        Text(
                          lines.skip(1).join(", "),
                          style: context.theme.textTheme.bodyMedium!.copyWith(color: scheme.onSurfaceVariant),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      if (updated != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            "Updated $updated",
                            style: context.theme.textTheme.bodySmall!.copyWith(color: scheme.outline),
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: "Directions",
                  style: IconButton.styleFrom(backgroundColor: scheme.primaryContainer),
                  onPressed: () => MapsLauncher.launchCoordinates(friend.latitude!, friend.longitude!),
                  icon: Icon(Icons.directions, color: scheme.onPrimaryContainer),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
