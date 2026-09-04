import 'dart:convert';
import 'dart:math';

class LocalAttachment {
  const LocalAttachment({
    required this.ref,
    required this.name,
    required this.mime,
    required this.bytes,
  });

  final String ref;
  final String name;
  final String mime;
  final List<int> bytes;

  bool get isImage => mime.startsWith('image/');

  String get dataUrl => 'data:$mime;base64,${base64Encode(bytes)}';
}

abstract final class LocalAttachmentStore {
  static const maxBytesPerFile = 10 * 1024 * 1024;
  static const maxTotalBytesPerRequest = 20 * 1024 * 1024;
  static const maxAttachments = 5;

  static const _maxRetained = 24;

  static final Map<String, LocalAttachment> _items = {};
  static final _random = Random.secure();

  static String put({
    required String name,
    required String mime,
    required List<int> bytes,
  }) {
    if (bytes.length > maxBytesPerFile) {
      throw ArgumentError('حجم فایل بیش از حد مجاز است.');
    }
    final ref =
        'win_${_random.nextInt(1 << 32).toRadixString(36)}'
        '${_random.nextInt(1 << 32).toRadixString(36)}'
        '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';
    while (_items.length >= _maxRetained) {
      _items.remove(_items.keys.first);
    }
    _items[ref] = LocalAttachment(
      ref: ref,
      name: name,
      mime: mime,
      bytes: bytes,
    );
    return ref;
  }

  static LocalAttachment? get(String ref) => _items[ref];

  static List<LocalAttachment> resolve(List<String>? refs) {
    if (refs == null || refs.isEmpty) return const [];
    if (refs.length > maxAttachments) {
      throw ArgumentError('تعداد فایل‌های پیوست بیش از حد مجاز است.');
    }
    final out = <LocalAttachment>[];
    var total = 0;
    for (final ref in refs) {
      final item = _items[ref];
      if (item == null) {
        throw ArgumentError(
          'فایل پیوست دیگر در دسترس نیست؛ دوباره انتخابش کن.',
        );
      }
      total += item.bytes.length;
      if (total > maxTotalBytesPerRequest) {
        throw ArgumentError('حجم مجموع فایل‌های پیوست بیش از حد مجاز است.');
      }
      out.add(item);
    }
    return out;
  }

  static void clear() => _items.clear();
}
