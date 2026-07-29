import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:zkteco_flutter_client/l10n/app_tr.dart';

/// Bản đồ xem trước vị trí chấm công (mobile / chấm công thô).
class PunchLocationPreview extends StatefulWidget {
  const PunchLocationPreview({
    super.key,
    required this.latitude,
    required this.longitude,
    required this.onTap,
    this.height = 180,
  });

  final double latitude;
  final double longitude;
  final VoidCallback onTap;
  final double height;

  @override
  State<PunchLocationPreview> createState() => _PunchLocationPreviewState();
}

class _PunchLocationPreviewState extends State<PunchLocationPreview> {
  final MapController _mapController = MapController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _centerMap());
  }

  @override
  void didUpdateWidget(covariant PunchLocationPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.latitude != widget.latitude ||
        oldWidget.longitude != widget.longitude) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _centerMap());
    }
  }

  void _centerMap() {
    if (!mounted) return;
    final point = LatLng(widget.latitude, widget.longitude);
    try {
      _mapController.move(point, 16);
    } catch (_) {
      Future.delayed(const Duration(milliseconds: 120), () {
        if (!mounted) return;
        try {
          _mapController.move(point, 16);
        } catch (_) {}
      });
    }
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final point = LatLng(widget.latitude, widget.longitude);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            height: widget.height,
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: point,
                    initialZoom: 16,
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.none,
                    ),
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'vn.sana.sbox',
                    ),
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: point,
                          width: 36,
                          height: 36,
                          child: const Icon(
                            Icons.location_on,
                            color: Color(0xFFDC2626),
                            size: 36,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.touch_app,
                            size: 14, color: Color(0xFF1E3A5F)),
                        SizedBox(width: 4),
                        Text(tr('Chạm để phóng to'),
                            style: TextStyle(
                                fontSize: 11, color: Color(0xFF1E3A5F))),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
