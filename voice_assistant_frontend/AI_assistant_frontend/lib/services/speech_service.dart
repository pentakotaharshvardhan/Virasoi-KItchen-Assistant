import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../core/constants/api_constants.dart';
import '../core/utils/result.dart';
import '../core/utils/secure_storage.dart';

class SpeechService {
  SpeechService({http.Client? client, SecureStorage? storage})
      : _client = client ?? http.Client(),
        _storage = storage ?? SecureStorage.instance;

  final http.Client _client;
  final SecureStorage _storage;

  Future<Result<String>> transcribeWav(File file) async {
    if (!await file.exists())
      return const Failure('The audio file is missing.');
    final size = await file.length();
    if (size == 0) return const Failure('The audio file is empty.');
    if (size > 9 * 1024 * 1024) {
      return const Failure('Choose a WAV recording smaller than 9 MB.');
    }

    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('${ApiConstants.baseUrl}${ApiConstants.transcribe}'),
      );
      final token = await _storage.accessToken;
      if (token == null || token.isEmpty) {
        return const Failure('Please sign in again before uploading audio.');
      }
      request.headers['Authorization'] = 'Bearer $token';
      request.files.add(
        await http.MultipartFile.fromPath(
          'file',
          file.path,
          filename: file.uri.pathSegments.last,
        ),
      );

      final streamed =
          await _client.send(request).timeout(const Duration(seconds: 60));
      final response = await http.Response.fromStream(streamed);
      dynamic decoded;
      try {
        decoded = response.body.isEmpty ? {} : jsonDecode(response.body);
      } on FormatException {
        return Failure(
            'The transcription service returned an invalid response.');
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final message = decoded is Map && decoded['message'] != null
            ? decoded['message'].toString()
            : 'Audio transcription failed (${response.statusCode}).';
        return Failure(message);
      }
      final transcript = decoded is Map ? decoded['text']?.toString() : null;
      if (transcript == null || transcript.trim().isEmpty) {
        return const Failure(
            'No speech was recognized. Try a clearer or longer recording.');
      }
      return Success(transcript.trim());
    } on Exception catch (error) {
      if (error is SocketException) {
        return const Failure('No internet connection. Check your network.');
      }
      if (error is TimeoutException) {
        return const Failure('Transcription timed out. Please try again.');
      }
      return const Failure('Could not upload the recording. Please try again.');
    }
  }
}
