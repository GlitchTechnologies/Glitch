import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/l10n.dart';
import '../theme/app_theme.dart';
import 'glitch_pressable.dart' show ClickableCursor;

(double lat, double lon) parseGeoString(String geo) {
  final parts = geo.split(',');
  final lat = double.tryParse(parts[0].trim()) ?? 0;
  final lon = double.tryParse(parts.length > 1 ? parts[1].trim() : '0') ?? 0;
  return (lat, lon);
}

Future<void> openInMaps(double lat, double lon) async {
  final yandex = Uri.parse('yandexmaps://maps.yandex.ru/?pt=$lon,$lat&z=16');
  final geo    = Uri.parse('geo:$lat,$lon?q=$lat,$lon');
  if (await canLaunchUrl(yandex)) {
    await launchUrl(yandex);
  } else if (await canLaunchUrl(geo)) {
    await launchUrl(geo);
  } else {
    final web = Uri.parse('https://maps.yandex.ru/?pt=$lon,$lat&z=16');
    await launchUrl(web, mode: LaunchMode.externalApplication);
  }
}

class GeoMapWidget extends StatelessWidget {
  final String geo;
  final BorderRadius borderRadius;

  const GeoMapWidget({
    super.key,
    required this.geo,
    required this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final (lat, lon) = parseGeoString(geo);

    final mapUrl = 'https://static-maps.yandex.ru/1.x/'
        '?ll=${lon.toStringAsFixed(6)},${lat.toStringAsFixed(6)}'
        '&z=14&size=400,200&l=map'
        '&pt=${lon.toStringAsFixed(6)},${lat.toStringAsFixed(6)},pm2rdl'
        '&lang=ru_RU';

    return ClickableCursor(
      child: GestureDetector(
      onTap: () => openInMaps(lat, lon),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: Stack(
          children: [
            CachedNetworkImage(
              imageUrl: mapUrl,
              width: double.infinity,
              height: 160,
              fit: BoxFit.cover,
              placeholder: (_, __) => Container(
                height: 160,
                color: const Color(0xFF1e2a1e),
                child: Center(
                  child: CircularProgressIndicator(strokeWidth: 2, color: GlitchColors.accentBlue),
                ),
              ),
              errorWidget: (_, __, ___) => Container(
                height: 160,
                color: const Color(0xFF1a2218),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.location_on_rounded, color: Color(0xFF4caf50), size: 36),
                  const SizedBox(height: 6),
                  Text(
                    '${lat.toStringAsFixed(4)}, ${lon.toStringAsFixed(4)}',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ]),
              ),
            ),

            Positioned(
              right: 8, bottom: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.55),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.open_in_new_rounded, color: Colors.white, size: 13),
                  const SizedBox(width: 4),
                  Text(context.s.geoOpen,
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500)),
                ]),
              ),
            ),
          ],
        ),
      ),
    ),
    );
  }
}
