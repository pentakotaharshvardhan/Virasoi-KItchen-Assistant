import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/constants/api_constants.dart';

/// Fetches a representative photo for an ingredient or dish name.
/// Falls back to null on any failure so the UI can show a placeholder icon
/// instead of crashing (e.g. missing/invalid Unsplash key, offline, etc.)
class UnsplashService {
  UnsplashService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  final Map<String, String> _cache = {};

  Future<String?> fetchImageUrl(String query) async {
    if (query.trim().isEmpty) return null;
    if (_cache.containsKey(query)) return _cache[query];
    try {
      final uri = Uri.parse('${ApiConstants.unsplashBaseUrl}${ApiConstants.unsplashSearchPhotos}').replace(
        queryParameters: {'query': query, 'per_page': '1', 'orientation': 'squarish'},
      );
      final res = await _client.get(
        uri,
        headers: {'Authorization': 'Client-ID ${ApiConstants.unsplashAccessKey}'},
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      final json = jsonDecode(res.body);
      final results = json['results'] as List<dynamic>?;
      if (results == null || results.isEmpty) return null;
      final url = results.first['urls']?['small']?.toString();
      if (url != null) _cache[query] = url;
      return url;
    } catch (_) {
      return null;
    }
  }
}
