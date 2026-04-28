import 'dart:convert';
import 'package:http/http.dart' as http;

class GeocodingResult {
  final double lat;
  final double lng;
  final String displayName;

  const GeocodingResult({
    required this.lat,
    required this.lng,
    required this.displayName,
  });
}

bool isValidLatitude(double lat) => lat >= -90.0 && lat <= 90.0;
bool isValidLongitude(double lng) => lng >= -180.0 && lng <= 180.0;
bool isValidCoordinates(double lat, double lng) =>
    isValidLatitude(lat) && isValidLongitude(lng);

/// Routes geocoding through the backend to avoid Nominatim CORS issues on web.
class GeocodingService {
  static const _backendUrl = 'https://quadagents-gdg-solution-challenge.onrender.com';

  static Future<GeocodingResult?> geocodeAddress(String address) async {
    final trimmed = address.trim();
    if (trimmed.isEmpty) return null;

    try {
      final uri = Uri.parse('$_backendUrl/geo/geocode')
          .replace(queryParameters: {'q': trimmed});

      final response = await http.get(uri);
      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final results = data['results'] as List<dynamic>? ?? [];
      if (results.isEmpty) return null;

      final first = results.first as Map<String, dynamic>;
      final lat = double.tryParse(first['lat'] as String? ?? '');
      final lng = double.tryParse(first['lon'] as String? ?? '');

      if (lat == null || lng == null) return null;
      if (!isValidCoordinates(lat, lng)) return null;

      return GeocodingResult(
        lat: lat,
        lng: lng,
        displayName: first['display_name'] as String? ?? trimmed,
      );
    } catch (_) {
      return null;
    }
  }

  /// Reverse geocode lat/lng → address via backend.
  static Future<String?> reverseGeocode(double lat, double lng) async {
    try {
      final response = await http.get(
        Uri.parse('$_backendUrl/geo/reverse?lat=$lat&lng=$lng'),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return data['address'] as String?;
      }
    } catch (_) {}
    return null;
  }
}
