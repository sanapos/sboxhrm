import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../utils/platform_geolocation.dart';
import 'notification_overlay.dart';

/// A dialog widget that lets the user pick a location on an OpenStreetMap.
/// Returns the selected [LatLng] or null if cancelled.
class MapLocationPicker extends StatefulWidget {
  final double initialLatitude;
  final double initialLongitude;
  final double initialZoom;
  final double? radius;
  final String? title;
  final bool readOnly;

  const MapLocationPicker({
    super.key,
    this.initialLatitude = 10.7769,
    this.initialLongitude = 106.7009,
    this.initialZoom = 15,
    this.radius,
    this.title,
    this.readOnly = false,
  });

  @override
  State<MapLocationPicker> createState() => _MapLocationPickerState();
}

class _MapLocationPickerState extends State<MapLocationPicker> {
  late LatLng _selectedLocation;
  late final MapController _mapController;
  late double _currentZoom;
  bool _locating = false;
  double? _gpsAccuracyMeters; // accuracy radius from browser geolocation

  @override
  void initState() {
    super.initState();
    _selectedLocation = LatLng(widget.initialLatitude, widget.initialLongitude);
    _mapController = MapController();
    _currentZoom = widget.initialZoom;
  }

  /// Calculate appropriate zoom level based on accuracy radius in meters
  double _zoomForAccuracy(double accuracyMeters) {
    // Rough mapping: at zoom 16 ~380m visible, zoom 14 ~1.5km, zoom 12 ~6km, zoom 10 ~24km
    if (accuracyMeters <= 50) return 17;
    if (accuracyMeters <= 200) return 16;
    if (accuracyMeters <= 500) return 15;
    if (accuracyMeters <= 1500) return 14;
    if (accuracyMeters <= 5000) return 13;
    if (accuracyMeters <= 10000) return 12;
    return 11;
  }

  /// Use platform geolocation API to get current position
  void _getCurrentLocation() async {
    setState(() => _locating = true);

    try {
      final position = await getCurrentPosition(
        enableHighAccuracy: true,
        timeout: 30000,
      );
      final lat = position.latitude;
      final lng = position.longitude;
      final accuracy = position.accuracy;
      final loc = LatLng(lat, lng);
      if (mounted) {
        final zoom = _zoomForAccuracy(accuracy);
        setState(() {
          _selectedLocation = loc;
          _gpsAccuracyMeters = accuracy;
          _locating = false;
        });
        _mapController.move(loc, zoom);

        // Show accuracy info
        final accText = accuracy >= 1000
            ? '${(accuracy / 1000).toStringAsFixed(1)} km'
            : '${accuracy.round()} m';
        if (accuracy > 1000) {
          NotificationOverlayManager().showWarning(title: 'Độ chính xác thấp', message: 'Độ chính xác: ~$accText\nNhấn vào bản đồ để chỉnh lại vị trí chính xác');
        } else {
          NotificationOverlayManager().showSuccess(title: 'Vị trí', message: 'Độ chính xác: ~$accText');
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _locating = false);
        String msg;
        if (e is GeoError) {
          switch (e.code) {
            case 1:
              msg = 'Bạn đã từ chối quyền truy cập vị trí.\nVui lòng cho phép trong cài đặt trình duyệt.';
              break;
            case 2:
              msg = 'Không thể xác định vị trí.\nVui lòng thử lại.';
              break;
            case 3:
              msg = 'Hết thời gian chờ xác định vị trí.\nVui lòng thử lại.';
              break;
            default:
              msg = 'Lỗi: ${e.message}';
          }
        } else {
          msg = 'Lỗi: $e';
        }
        NotificationOverlayManager().showError(title: 'Lỗi vị trí', message: msg);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    final hasValidLocation =
        widget.initialLatitude != 0 || widget.initialLongitude != 0;

    final mapWidget = Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: hasValidLocation
                ? _selectedLocation
                : const LatLng(10.7769, 106.7009), // Default: Ho Chi Minh City
            initialZoom: hasValidLocation ? widget.initialZoom : 12,
            onTap: widget.readOnly
                ? null
                : (tapPosition, point) {
                    setState(() {
                      _selectedLocation = point;
                      _gpsAccuracyMeters = null; // clear accuracy circle on manual tap
                    });
                  },
            onPositionChanged: (pos, _) {
              _currentZoom = pos.zoom;
            },
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.sbox.hrm',
            ),
            // Radius circle (attendance radius)
            if (widget.radius != null && widget.radius! > 0)
              CircleLayer(
                circles: [
                  CircleMarker(
                    point: _selectedLocation,
                    radius: widget.radius!,
                    useRadiusInMeter: true,
                    color: const Color(0xFF1E3A5F).withValues(alpha: 0.15),
                    borderColor: const Color(0xFF1E3A5F).withValues(alpha: 0.6),
                    borderStrokeWidth: 2,
                  ),
                ],
              ),
            // GPS accuracy circle
            if (_gpsAccuracyMeters != null && _gpsAccuracyMeters! > 0)
              CircleLayer(
                circles: [
                  CircleMarker(
                    point: _selectedLocation,
                    radius: _gpsAccuracyMeters!,
                    useRadiusInMeter: true,
                    color: const Color(0xFF3B82F6).withValues(alpha: 0.08),
                    borderColor: const Color(0xFF3B82F6).withValues(alpha: 0.4),
                    borderStrokeWidth: 1.5,
                  ),
                ],
              ),
            // Marker
            MarkerLayer(
              markers: [
                Marker(
                  point: _selectedLocation,
                  width: 40,
                  height: 40,
                  child: const Icon(
                    Icons.location_on,
                    color: Color(0xFFDC2626),
                    size: 40,
                  ),
                ),
              ],
            ),
          ],
        ),
        // Zoom controls
        Positioned(
          right: 12,
          bottom: 80,
          child: Column(
            children: [
              _buildZoomButton(Icons.add, () {
                _currentZoom = (_currentZoom + 1).clamp(1, 18);
                _mapController.move(_mapController.camera.center, _currentZoom);
              }),
              const SizedBox(height: 4),
              _buildZoomButton(Icons.remove, () {
                _currentZoom = (_currentZoom - 1).clamp(1, 18);
                _mapController.move(_mapController.camera.center, _currentZoom);
              }),
            ],
          ),
        ),
        // GPS locate button
        if (!widget.readOnly)
          Positioned(
            right: 12,
            bottom: 40,
            child: _locating
                ? Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.15),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                    child: const Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                : _buildZoomButton(Icons.my_location, _getCurrentLocation),
          ),
        // Coordinates display
        Positioned(
          left: 12,
          bottom: 12,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 4,
                ),
              ],
            ),
            child: Text(
              '${_selectedLocation.latitude.toStringAsFixed(6)}, ${_selectedLocation.longitude.toStringAsFixed(6)}',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: Color(0xFF18181B)),
            ),
          ),
        ),
        // Instruction
        if (!widget.readOnly)
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 4,
                  ),
                ],
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.touch_app, size: 16, color: Color(0xFF1E3A5F)),
                  SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'Nhấn vào bản đồ để chọn vị trí chấm công',
                      style: TextStyle(fontSize: 12, color: Color(0xFF1E3A5F)),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );

    if (isMobile) {
      return Dialog(
        insetPadding: EdgeInsets.zero,
        child: SizedBox(
          width: double.infinity,
          height: double.infinity,
          child: Scaffold(
            appBar: AppBar(
              title: Text(widget.title ?? (widget.readOnly ? 'Xem vị trí' : 'Chọn vị trí trên bản đồ')),
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context, null),
              ),
            ),
            body: mapWidget,
            bottomNavigationBar: widget.readOnly
                ? null
                : Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, null),
                          child: const Text('Hủy', style: TextStyle(color: Color(0xFF71717A))),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton.icon(
                          onPressed: () => Navigator.pop(context, _selectedLocation),
                          icon: const Icon(Icons.check, size: 18),
                          label: const Text('Xác nhận vị trí'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1E3A5F),
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ),
      );
    }

    return AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Icon(
            widget.readOnly ? Icons.map : Icons.edit_location_alt,
            color: const Color(0xFF1E3A5F),
          ),
          const SizedBox(width: 12),
          Text(
            widget.title ?? (widget.readOnly ? 'Xem vị trí' : 'Chọn vị trí trên bản đồ'),
            style: const TextStyle(color: Color(0xFF18181B), fontSize: 18),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.grey),
            onPressed: () => Navigator.pop(context, null),
          ),
        ],
      ),
      content: SizedBox(
        width: 600,
        height: 450,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: mapWidget,
        ),
      ),
      actions: widget.readOnly
          ? [
              TextButton(
                onPressed: () => Navigator.pop(context, null),
                child: const Text('Đóng'),
              ),
            ]
          : [
              TextButton(
                onPressed: () => Navigator.pop(context, null),
                child: const Text('Hủy', style: TextStyle(color: Color(0xFF71717A))),
              ),
              ElevatedButton.icon(
                onPressed: () => Navigator.pop(context, _selectedLocation),
                icon: const Icon(Icons.check, size: 18),
                label: const Text('Xác nhận vị trí'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E3A5F),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
    );
  }

  Widget _buildZoomButton(IconData icon, VoidCallback onPressed) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      elevation: 2,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 36,
          height: 36,
          child: Icon(icon, size: 20, color: const Color(0xFF18181B)),
        ),
      ),
    );
  }
}
