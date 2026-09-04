import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../core/agent_storage.dart';

final class _Blob extends Struct {
  @Uint32()
  external int cb;
  external Pointer<Uint8> pb;
}

abstract final class SecretVault {
  static const _fileName = 'byok_secrets.json';

  static const _lptr = 0x0040;

  static const _uiForbidden = 0x1;

  static bool get isSupported => Platform.isWindows;

  static DynamicLibrary? _crypt;
  static DynamicLibrary? _kernel;

  static DynamicLibrary get _crypt32 =>
      _crypt ??= DynamicLibrary.open('crypt32.dll');
  static DynamicLibrary get _kernel32 =>
      _kernel ??= DynamicLibrary.open('kernel32.dll');

  static Pointer<Uint8> _alloc(int bytes) =>
      _kernel32.lookupFunction<
        Pointer<Uint8> Function(Uint32, IntPtr),
        Pointer<Uint8> Function(int, int)
      >('LocalAlloc')(_lptr, bytes < 1 ? 1 : bytes);

  static void _free(Pointer<Uint8> pointer) {
    if (pointer == nullptr) return;
    _kernel32.lookupFunction<
      Pointer<Uint8> Function(Pointer<Uint8>),
      Pointer<Uint8> Function(Pointer<Uint8>)
    >('LocalFree')(pointer);
  }

  static Uint8List _entropy() => Uint8List.fromList(
    utf8.encode('jemiran-byok-v1:${AgentStorage.accountKey}'),
  );

  static Pointer<_Blob> _blobFrom(List<int> bytes) {
    final buffer = _alloc(bytes.length);
    if (bytes.isNotEmpty) buffer.asTypedList(bytes.length).setAll(0, bytes);
    final blob = _alloc(sizeOf<_Blob>()).cast<_Blob>();
    blob.ref
      ..cb = bytes.length
      ..pb = buffer;
    return blob;
  }

  static Uint8List _protect(List<int> plain) {
    final input = _blobFrom(plain);
    final entropy = _blobFrom(_entropy());
    final output = _alloc(sizeOf<_Blob>()).cast<_Blob>();
    try {
      final ok = _crypt32
          .lookupFunction<
            Int32 Function(
              Pointer<_Blob>,
              Pointer<Uint16>,
              Pointer<_Blob>,
              Pointer<Void>,
              Pointer<Void>,
              Uint32,
              Pointer<_Blob>,
            ),
            int Function(
              Pointer<_Blob>,
              Pointer<Uint16>,
              Pointer<_Blob>,
              Pointer<Void>,
              Pointer<Void>,
              int,
              Pointer<_Blob>,
            )
          >(
            'CryptProtectData',
          )(input, nullptr, entropy, nullptr, nullptr, _uiForbidden, output);
      if (ok == 0) throw StateError('رمزگذاری کلید توسط ویندوز انجام نشد.');
      return Uint8List.fromList(output.ref.pb.asTypedList(output.ref.cb));
    } finally {
      _free(output.ref.pb);
      _free(output.cast());
      _free(input.ref.pb);
      _free(input.cast());
      _free(entropy.ref.pb);
      _free(entropy.cast());
    }
  }

  static String? _unprotect(Uint8List cipher) {
    final input = _blobFrom(cipher);
    final entropy = _blobFrom(_entropy());
    final output = _alloc(sizeOf<_Blob>()).cast<_Blob>();
    try {
      final ok = _crypt32
          .lookupFunction<
            Int32 Function(
              Pointer<_Blob>,
              Pointer<Pointer<Uint16>>,
              Pointer<_Blob>,
              Pointer<Void>,
              Pointer<Void>,
              Uint32,
              Pointer<_Blob>,
            ),
            int Function(
              Pointer<_Blob>,
              Pointer<Pointer<Uint16>>,
              Pointer<_Blob>,
              Pointer<Void>,
              Pointer<Void>,
              int,
              Pointer<_Blob>,
            )
          >(
            'CryptUnprotectData',
          )(input, nullptr, entropy, nullptr, nullptr, _uiForbidden, output);
      if (ok == 0) return null;
      return utf8.decode(output.ref.pb.asTypedList(output.ref.cb));
    } catch (_) {
      return null;
    } finally {
      _free(output.ref.pb);
      _free(output.cast());
      _free(input.ref.pb);
      _free(input.cast());
      _free(entropy.ref.pb);
      _free(entropy.cast());
    }
  }

  static File? _file() {
    final root = AgentStorage.root;
    if (root == null) return null;
    return File(p.join(root.path, _fileName));
  }

  static Map<String, dynamic> _readAll() {
    try {
      final file = _file();
      if (file == null) return {};
      final backup = File('${file.path}.bak');
      if (!file.existsSync() && backup.existsSync()) {
        backup.renameSync(file.path);
      }
      if (!file.existsSync()) return {};
      final decoded = jsonDecode(file.readAsStringSync());
      return decoded is Map ? Map<String, dynamic>.from(decoded) : {};
    } catch (_) {
      return {};
    }
  }

  static void _writeAll(Map<String, dynamic> data) {
    final file = _file();
    if (file == null) throw StateError('فضای ذخیره‌سازی ایجنت در دسترس نیست.');
    final temp = File(
      '${file.path}.${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    final backup = File('${file.path}.bak');
    temp.writeAsStringSync(jsonEncode(data), flush: true);
    try {
      if (backup.existsSync()) backup.deleteSync();
      if (file.existsSync()) file.renameSync(backup.path);
      temp.renameSync(file.path);
      if (backup.existsSync()) backup.deleteSync();
    } catch (_) {
      if (!file.existsSync() && backup.existsSync()) {
        backup.renameSync(file.path);
      }
      rethrow;
    } finally {
      if (temp.existsSync()) temp.deleteSync();
    }
  }

  static void write(String ref, String secret) {
    if (!isSupported) {
      throw UnsupportedError('ذخیرهٔ امن کلید فقط روی ویندوز پشتیبانی می‌شود.');
    }
    if (secret.trim().isEmpty) throw ArgumentError('کلید خالی است.');
    final data = _readAll();
    data[ref] = base64Encode(_protect(utf8.encode(secret)));
    _writeAll(data);
  }

  static String? read(String ref) {
    if (!isSupported) return null;
    final raw = _readAll()[ref];
    if (raw is! String || raw.isEmpty) return null;
    try {
      return _unprotect(base64Decode(raw));
    } catch (_) {
      return null;
    }
  }

  static bool has(String ref) => _readAll()[ref] is String;

  static void delete(String ref) {
    final data = _readAll();
    if (data.remove(ref) == null) return;
    _writeAll(data);
  }

  static void clear() {
    final file = _file();
    if (file != null && file.existsSync()) file.deleteSync();
  }

  static Set<String> refs() => _readAll().keys.toSet();
}
