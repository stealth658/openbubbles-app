import 'package:bluebubbles/services/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:url_launcher/url_launcher.dart';

/// OpenBubbles: selectable basemap for the Find My screen.
///
/// Upstream draws raw OpenStreetMap tiles. Alternatives here are keyless and
/// free for light use with attribution: Esri's World Street Map / World
/// Imagery (ArcGIS Online public tile services) and OpenTopoMap. CARTO's
/// basemaps were tried first and dropped: they now watermark "API KEY
/// REQUIRED" over every tile without a key.
///
/// The Google entries are opt-in and unofficial, at the user's request: Google
/// has no keyless public tile API, these `mt{0-3}.google.com/vt` endpoints are
/// undocumented and outside Google Maps Platform's terms, and they can change
/// or start refusing requests without notice. The supported route is
/// google_maps_flutter with an API key, which is a different map widget. They
/// are never the default and are labelled as unofficial in the picker.
enum FindMyMapStyle {
  esriStreets('Streets (Esri)', 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Street_Map/MapServer/tile/{z}/{y}/{x}',
      attribution: '© Esri, HERE, Garmin, OpenStreetMap contributors', attributionUrl: 'https://www.esri.com/en-us/legal/terms/data-attributions'),
  esriImagery('Satellite (Esri)', 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
      attribution: '© Esri, Maxar, Earthstar Geographics', attributionUrl: 'https://www.esri.com/en-us/legal/terms/data-attributions'),
  osm('OpenStreetMap', 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      attribution: '© OpenStreetMap contributors', attributionUrl: 'https://openstreetmap.org/copyright'),
  openTopo('Topographic', 'https://{s}.tile.opentopomap.org/{z}/{x}/{y}.png',
      subdomains: ['a', 'b', 'c'], attribution: '© OpenStreetMap contributors, SRTM | © OpenTopoMap (CC-BY-SA)', attributionUrl: 'https://opentopomap.org/about'),
  // lyrs: m = roadmap, y = hybrid (satellite + labels). Subdomains mt0-mt3.
  // `{scale}` is filled in by findMyTileLayer from the device pixel ratio.
  google('Google (unofficial)', 'https://mt{s}.google.com/vt/lyrs=m&x={x}&y={y}&z={z}&scale={scale}',
      subdomains: ['0', '1', '2', '3'], attribution: '© Google', attributionUrl: 'https://www.google.com/intl/en_us/help/terms_maps/'),
  googleHybrid('Google satellite (unofficial)', 'https://mt{s}.google.com/vt/lyrs=y&x={x}&y={y}&z={z}&scale={scale}',
      subdomains: ['0', '1', '2', '3'], attribution: '© Google', attributionUrl: 'https://www.google.com/intl/en_us/help/terms_maps/');

  const FindMyMapStyle(this.label, this.urlTemplate,
      {this.subdomains = const [], required this.attribution, required this.attributionUrl});
  final String label;
  final String urlTemplate;
  final List<String> subdomains;
  final String attribution;
  final String attributionUrl;

  static FindMyMapStyle get current =>
      FindMyMapStyle.values.firstWhere((e) => e.name == SettingsSvc.settings.findMyMapStyle.value,
          orElse: () => FindMyMapStyle.esriStreets);
}

TileLayer findMyTileLayer(BuildContext context) {
  final style = FindMyMapStyle.current;
  // A 256px raster tile stretched across ~3 device pixels per logical pixel is
  // what made the map look soft next to the Google Maps app.
  //
  // Google's tile servers honour `scale=2` (512px) and `scale=4` (1024px),
  // rendered for the same 256-point tile box, so the layer stays at the
  // normal 256-point tile size and zoom and simply gets a denser image to
  // paint into it (the same thing flutter_map's `{r}` server-retina mode
  // does). Drawing the 512px tile at 512 points instead, as a first attempt
  // did, doubles the size of every label. The scale is picked from the
  // device pixel ratio so a ~3x phone screen gets the 1024px tile and
  // downsamples slightly rather than upscaling.
  //
  // The other providers have no 2x endpoint, so flutter_map's simulated
  // retina mode fetches the next zoom level and draws it at half size
  // instead: four times the tile requests, but sharp.
  final bool google = style == FindMyMapStyle.google || style == FindMyMapStyle.googleHybrid;
  if (google) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final scale = dpr > 2.5 ? 4 : (dpr > 1.5 ? 2 : 1);
    return TileLayer(
      urlTemplate: style.urlTemplate.replaceAll('{scale}', '$scale'),
      subdomains: style.subdomains,
      tileDimension: 256,
      retinaMode: false,
      userAgentPackageName: 'com.bluebubbles.app',
    );
  }
  return TileLayer(
    urlTemplate: style.urlTemplate,
    subdomains: style.subdomains,
    tileDimension: 256,
    retinaMode: RetinaMode.isHighDensity(context),
    userAgentPackageName: 'com.bluebubbles.app',
  );
}

Widget findMyAttribution(BuildContext context) {
  final style = FindMyMapStyle.current;
  return SimpleAttributionWidget(
    source: Text(style.attribution),
    onTap: () => launchUrl(Uri.parse(style.attributionUrl)),
    backgroundColor: Theme.of(context).colorScheme.surface.withValues(alpha: 0.6),
  );
}

/// Popup menu that switches the basemap and persists the choice.
Widget findMyStyleButton(BuildContext context, VoidCallback onChanged) {
  return PopupMenuButton<FindMyMapStyle>(
    tooltip: 'Map style',
    icon: Icon(Icons.layers_outlined, color: Theme.of(context).colorScheme.onSurface, size: 22),
    onSelected: (style) {
      SettingsSvc.settings.findMyMapStyle.value = style.name;
      SettingsSvc.settings.saveOneAsync('findMyMapStyle');
      onChanged();
    },
    itemBuilder: (context) => FindMyMapStyle.values
        .map((s) => CheckedPopupMenuItem<FindMyMapStyle>(
              value: s,
              checked: s == FindMyMapStyle.current,
              child: Text(s.label),
            ))
        .toList(),
  );
}
