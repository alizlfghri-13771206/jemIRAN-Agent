import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:record/record.dart';

class RecordingFormat {
  final AudioEncoder encoder;
  final String extension;
  final String mime;

  const RecordingFormat(this.encoder, this.extension, this.mime);

  static const RecordingFormat mobile = RecordingFormat(
    AudioEncoder.aacLc,
    'm4a',
    'audio/mp4',
  );

  static const RecordingFormat _webOpus = RecordingFormat(
    AudioEncoder.opus,
    'webm',
    'audio/webm',
  );

  static const RecordingFormat _webWav = RecordingFormat(
    AudioEncoder.wav,
    'wav',
    'audio/wav',
  );

  String fileName(String base) => '$base.$extension';

  RecordConfig get config =>
      RecordConfig(encoder: encoder, bitRate: 48000, numChannels: 1);

  static Future<RecordingFormat> pick(AudioRecorder recorder) async {
    if (!kIsWeb) return mobile;
    for (final format in const [mobile, _webOpus, _webWav]) {
      try {
        if (await recorder.isEncoderSupported(format.encoder)) return format;
      } catch (_) {}
    }
    return _webOpus;
  }
}
