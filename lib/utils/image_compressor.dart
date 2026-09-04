import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';

class ImageCompressor {
  static const int _maxDimension = 1600;
  static const int _quality = 82;
  static const int _skipBelowBytes = 120 * 1024;
  static const _compressibleMimes = {
    'image/jpeg',
    'image/png',
    'image/webp',
    'image/heic',
  };

  static Future<({Uint8List bytes, String mime})> compressIfNeeded(
    Uint8List bytes,
    String mime,
  ) async {
    if (!_compressibleMimes.contains(mime) || bytes.length < _skipBelowBytes) {
      return (bytes: bytes, mime: mime);
    }

    for (final attempt in const [
      (format: CompressFormat.webp, mime: 'image/webp'),
      (format: CompressFormat.jpeg, mime: 'image/jpeg'),
    ]) {
      try {
        final result = await FlutterImageCompress.compressWithList(
          bytes,
          minWidth: _maxDimension,
          minHeight: _maxDimension,
          quality: _quality,
          format: attempt.format,
          autoCorrectionAngle: true,
          keepExif: false,
        );
        if (result.isNotEmpty && result.length < bytes.length) {
          return (bytes: result, mime: attempt.mime);
        }
      } catch (e) {
        debugPrint(
          'ImageCompressor: قالب ${attempt.mime} روی این پلتفرم نشد ($e)',
        );
      }
    }

    return (bytes: bytes, mime: mime);
  }
}
