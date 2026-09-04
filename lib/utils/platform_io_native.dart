import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

http.Client createHttpClient() {
  final inner = HttpClient()
    ..maxConnectionsPerHost = 6
    ..idleTimeout = const Duration(seconds: 50)
    ..connectionTimeout = const Duration(seconds: 15);
  return IOClient(inner);
}

bool get isWindowsPlatform => Platform.isWindows;

bool isNoInternetError(Object e) => e is SocketException;

String tempFilePath(String fileName) =>
    '${Directory.systemTemp.path}/$fileName';

Future<Uint8List?> readLocalBytes(String path) async {
  try {
    final file = File(path);
    if (!await file.exists()) return null;
    return await file.readAsBytes();
  } catch (_) {
    return null;
  }
}

void deleteLocalFile(String path) {
  if (path.isEmpty) return;
  unawaited(File(path).delete().catchError((Object _) => File(path)));
}

List<int>? gzipEncode(List<int> data) {
  try {
    return gzip.encode(data);
  } catch (_) {
    return null;
  }
}

List<int>? gzipDecode(List<int> data) {
  try {
    return gzip.decode(data);
  } catch (_) {
    return null;
  }
}

Future<List<int>?> gzipEncodeAsync(List<int> data) async => gzipEncode(data);
void triggerBrowserDownload(String url, String fileName) {}
