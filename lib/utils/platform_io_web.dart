import 'dart:js_interop';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:web/web.dart' as web;

http.Client createHttpClient() => http.Client();

bool get isWindowsPlatform => false;

bool isNoInternetError(Object e) => false;
String tempFilePath(String fileName) => '';

Future<Uint8List?> readLocalBytes(String path) async {
  if (path.isEmpty) return null;
  try {
    final res = await http.get(Uri.parse(path));
    if (res.statusCode >= 400) return null;
    return res.bodyBytes;
  } catch (_) {
    return null;
  }
}

void deleteLocalFile(String path) {
  if (!path.startsWith('blob:')) return;
  try {
    web.URL.revokeObjectURL(path);
  } catch (_) {}
}

List<int>? gzipEncode(List<int> data) => null;

List<int>? gzipDecode(List<int> data) => null;

Future<List<int>?> gzipEncodeAsync(List<int> data) async {
  try {
    final blob = web.Blob(
      [Uint8List.fromList(data).toJS].toJS,
      web.BlobPropertyBag(type: 'application/octet-stream'),
    );
    final compressed = blob.stream().pipeThrough(
      web.CompressionStream('gzip') as web.ReadableWritablePair,
    );
    final buf = await web.Response(compressed).arrayBuffer().toDart;
    return buf.toDart.asUint8List();
  } catch (_) {
    return null;
  }
}

void triggerBrowserDownload(String url, String fileName) {
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = fileName
    ..style.display = 'none';
  web.document.body?.appendChild(anchor);
  anchor.click();
  anchor.remove();
}
