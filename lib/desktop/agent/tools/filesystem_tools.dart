import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../agent_workspace.dart';
import '../core/checkpoint_store.dart';
import '../policy/agent_policy.dart';
import 'agent_tool.dart';

abstract final class FsLimits {
  static const int maxReadBytes = 2 * 1024 * 1024;
  static const int maxDirEntries = 400;
  static const int maxSearchHits = 80;
  static const int maxSearchFileBytes = 1024 * 1024;
}

const _ignoredSegments = {
  '.git',
  '.dart_tool',
  'node_modules',
  'build',
  '.idea',
  '.vs',
  '__pycache__',
  '.gradle',
  'Pods',
  'venv',
  '.venv',
};

Stream<File> _walkFiles(
  Directory root, {
  required bool Function() isCancelled,
}) async* {
  final pending = Queue<Directory>()..add(root);
  while (pending.isNotEmpty) {
    if (isCancelled()) return;
    final dir = pending.removeFirst();
    List<FileSystemEntity> entries;
    try {
      entries = await dir.list(followLinks: false).toList();
    } catch (_) {
      continue;
    }
    for (final entity in entries) {
      if (isCancelled()) return;
      if (entity is Directory) {
        if (_ignoredSegments.contains(p.basename(entity.path))) continue;
        pending.add(entity);
      } else if (entity is File) {
        yield entity;
      }
    }
  }
}

bool _looksBinary(List<int> bytes) {
  final limit = bytes.length < 8000 ? bytes.length : 8000;
  for (var i = 0; i < limit; i++) {
    if (bytes[i] == 0) return true;
  }
  return false;
}

RegExp globToRegExp(String glob) {
  const specials = r'.()[]{}+^$|\';
  final buffer = StringBuffer('^');
  for (final char in glob.split('')) {
    if (char == '*') {
      buffer.write('.*');
    } else if (char == '?') {
      buffer.write('.');
    } else if (specials.contains(char)) {
      buffer.write(RegExp.escape(char));
    } else {
      buffer.write(char);
    }
  }
  buffer.write(r'$');
  return RegExp(buffer.toString(), caseSensitive: false);
}

String humanSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

String clip(String text, [int max = 200]) {
  final flat = text.replaceAll('\n', ' ⏎ ');
  return flat.length > max ? '${flat.substring(0, max)}…' : flat;
}

Future<(String?, ToolResult?)> _readEditableText(
  File file,
  String rawPath,
) async {
  List<int> bytes;
  try {
    bytes = await file.readAsBytes();
  } on FileSystemException catch (e) {
    return (
      null,
      ToolResult.failure(
        'خواندن «$rawPath» ممکن نشد: ${e.osError?.message ?? e.message}',
      ),
    );
  }
  if (_looksBinary(bytes)) {
    return (
      null,
      ToolResult.failure(
        '«$rawPath» فایل باینری است و ویرایش متنی روی آن انجام نمی‌شود.',
      ),
    );
  }
  try {
    return (utf8.decode(bytes), null);
  } on FormatException {
    return (
      null,
      ToolResult.failure(
        '«$rawPath» متن UTF-8 معتبر نیست؛ بازنویسی آن محتوای اصلی را خراب '
        'می‌کرد، پس انجام نشد.',
      ),
    );
  }
}

Future<ToolResult?> _checkpoint(ToolContext context, String path) async {
  final captured = await AgentCheckpointStore.capture(context.taskId, path);
  if (captured) return null;
  return ToolResult.failure(
    'برای این مسیر checkpoint امن ساخته نشد؛ عملیات انجام نشد. '
    'فایل‌های بزرگ‌تر از ۲۰ مگابایت یا پوشه‌های بسیار بزرگ باید دستی مدیریت شوند.',
  );
}

Future<void> _writeTextAtomic(File target, String content) async {
  await target.parent.create(recursive: true);
  final stamp = DateTime.now().microsecondsSinceEpoch;
  final temp = File('${target.path}.$stamp.tmp');
  final backup = File('${target.path}.$stamp.bak');
  await temp.writeAsString(content, encoding: utf8, flush: true);
  try {
    if (await target.exists()) await target.rename(backup.path);
    await temp.rename(target.path);
    if (await backup.exists()) await backup.delete();
  } catch (_) {
    if (!await target.exists() && await backup.exists()) {
      await backup.rename(target.path);
    }
    rethrow;
  } finally {
    if (await temp.exists()) await temp.delete();
  }
}

enum FsAccess { read, write, delete }

abstract class _FsTool extends AgentTool {
  const _FsTool();

  FsAccess get access;

  (String?, ToolResult?) resolveFor(String? rawPath) {
    if (rawPath == null || rawPath.trim().isEmpty) {
      return (null, ToolResult.failure('پارامتر path لازم است.'));
    }
    final absolute = AgentWorkspace.toAbsolute(rawPath);
    if (absolute == null) {
      return (
        null,
        ToolResult.failure(
          'مسیر «$rawPath» نسبی است و هیچ پوشهٔ کاری انتخاب نشده. '
          'اول باید کاربر یک پوشه اضافه کند.',
        ),
      );
    }

    final owner = AgentWorkspace.owner(absolute);
    if (owner == null) {
      return (
        null,
        ToolResult.failure(
          'مسیر «$rawPath» بیرون از منابع مجاز است. دسترسی داده نشد. '
          'اگر لازم است، از کاربر بخواه آن را به فهرست دسترسی‌ها اضافه کند.',
        ),
      );
    }

    final permitted = switch (access) {
      FsAccess.read => owner.canRead,
      FsAccess.write => owner.canWrite,
      FsAccess.delete => owner.canDelete,
    };
    if (!permitted) {
      final needed = switch (access) {
        FsAccess.read => 'خواندن',
        FsAccess.write => 'نوشتن',
        FsAccess.delete => 'حذف',
      };
      return (
        null,
        ToolResult.failure(
          'روی «${owner.name}» اجازهٔ $needed داده نشده '
          '(اجازه‌های فعلی: ${owner.permissionLabel}). '
          'کاربر باید در پنل دسترسی‌ها آن را روشن کند.',
        ),
      );
    }

    final resolved = AgentWorkspace.canonical(absolute);
    if (resolved == null) {
      return (
        null,
        ToolResult.failure(
          'مسیر واقعی «$rawPath» قابل تعیین نیست؛ عملیات انجام نشد.',
        ),
      );
    }
    return (resolved, null);
  }

  @override
  String? hardDeny(ToolCall call) {
    final raw = call.str('path') ?? call.str('from');
    if (raw == null) return null;
    final absolute = AgentWorkspace.toAbsolute(raw);
    if (absolute == null) return null;
    final owner = AgentWorkspace.owner(absolute);
    if (owner == null) return 'مسیر «$raw» بیرون از منابع مجاز است.';
    final permitted = switch (access) {
      FsAccess.read => owner.canRead,
      FsAccess.write => owner.canWrite,
      FsAccess.delete => owner.canDelete,
    };
    if (!permitted) {
      return 'روی «${owner.name}» این نوع دسترسی داده نشده '
          '(اجازه‌های فعلی: ${owner.permissionLabel}).';
    }
    return null;
  }

  @override
  bool get available => AgentWorkspace.hasRoot;

  String show(String absolute) => AgentWorkspace.display(absolute);
}

class ListDirTool extends _FsTool {
  @override
  bool get yieldsUntrustedContent => true;

  const ListDirTool();

  @override
  String get name => 'list_dir';
  @override
  String get label => 'فهرست پوشه';
  @override
  ToolRisk get risk => ToolRisk.read;
  @override
  String get permission => Perm.filesystemRead;
  @override
  FsAccess get access => FsAccess.read;
  @override
  String get signature =>
      'list_dir {"path": "."} — نام و اندازهٔ محتوای یک پوشه';

  @override
  Map<String, dynamic> get parameterSchema => const {
    'path': {'type': 'string', 'description': 'پیش‌فرض .'},
  };

  @override
  ToolPreview preview(ToolCall call) =>
      ToolPreview(title: 'فهرست پوشه', subtitle: call.str('path') ?? '.');

  @override
  Future<ToolResult> run(ToolCall call, ToolContext context) async {
    final (resolved, error) = resolveFor(call.str('path') ?? '.');
    if (error != null) return error;

    final dir = Directory(resolved!);
    if (!dir.existsSync()) {
      return ToolResult.failure('پوشه پیدا نشد: ${call.str('path') ?? '.'}');
    }

    final entries = <Map<String, dynamic>>[];
    var truncated = false;
    await for (final entity in dir.list(followLinks: false)) {
      if (entries.length >= FsLimits.maxDirEntries) {
        truncated = true;
        break;
      }
      final entryName = p.basename(entity.path);
      if (entity is File) {
        var size = 0;
        try {
          size = await entity.length();
        } catch (_) {}
        entries.add({'name': entryName, 'type': 'file', 'size': size});
      } else if (entity is Directory) {
        entries.add({'name': entryName, 'type': 'dir'});
      }
    }

    entries.sort((a, b) {
      final ta = a['type'] as String;
      final tb = b['type'] as String;
      if (ta != tb) return ta == 'dir' ? -1 : 1;
      return (a['name'] as String).toLowerCase().compareTo(
        (b['name'] as String).toLowerCase(),
      );
    });

    final detail = entries
        .map(
          (e) => e['type'] == 'dir'
              ? '[پوشه] ${e['name']}'
              : '${e['name']}  (${humanSize(e['size'] as int)})',
        )
        .join('\n');

    return ToolResult.success(
      summary: '${entries.length} مورد در ${show(resolved)}',
      data: {
        'path': show(resolved),
        'entries': entries,
        if (truncated) 'truncated': true,
      },
      detail: detail.isEmpty ? '(پوشه خالی است)' : detail,
    );
  }
}

class ReadFileTool extends _FsTool {
  @override
  bool get yieldsUntrustedContent => true;

  const ReadFileTool();

  @override
  String get name => 'read_file';
  @override
  String get label => 'خواندن فایل';
  @override
  ToolRisk get risk => ToolRisk.read;
  @override
  String get permission => Perm.filesystemRead;
  @override
  FsAccess get access => FsAccess.read;
  @override
  String get signature =>
      'read_file {"path": "a/b.txt", "offset": 1, "limit": 400} — خواندن فایل متنی؛ offset شمارهٔ خط شروع است و از ۱ می‌آغازد';

  @override
  Map<String, dynamic> get parameterSchema => const {
    'path': {'type': 'string'},
    'offset': {'type': 'integer', 'minimum': 1, 'description': 'خط شروع، از ۱'},
    'limit': {'type': 'integer', 'minimum': 1, 'description': 'تعداد خط'},
  };

  @override
  List<String> get requiredParameters => const ['path'];

  @override
  ToolPreview preview(ToolCall call) =>
      ToolPreview(title: 'خواندن فایل', subtitle: call.str('path'));

  @override
  Future<ToolResult> run(ToolCall call, ToolContext context) async {
    final (resolved, error) = resolveFor(call.str('path'));
    if (error != null) return error;

    final file = File(resolved!);
    if (!file.existsSync()) {
      return ToolResult.failure('فایل پیدا نشد: ${call.str('path')}');
    }

    final size = await file.length();
    if (size > FsLimits.maxReadBytes) {
      return ToolResult.failure(
        'فایل بزرگ‌تر از حد مجاز است (${humanSize(size)}). '
        'حداکثر ${humanSize(FsLimits.maxReadBytes)}.',
      );
    }

    final bytes = await file.readAsBytes();
    if (_looksBinary(bytes)) {
      return ToolResult.failure(
        'فایل باینری است و متنی خوانده نمی‌شود (${humanSize(size)}).',
      );
    }

    final text = utf8.decode(bytes, allowMalformed: true);

    final lines = const LineSplitter().convert(text);
    final offset = (call.integer('offset') ?? 1).clamp(1, 1 << 30);
    final limit = call.integer('limit')?.clamp(0, 1 << 30);
    final start = offset - 1;
    if (start >= lines.length && lines.isNotEmpty) {
      return ToolResult.failure(
        'خط شروع $offset از تعداد خطوط فایل (${lines.length}) بیشتر است.',
      );
    }
    final safeStart = start.clamp(0, lines.length);
    final end = limit == null
        ? lines.length
        : (safeStart + limit).clamp(0, lines.length);
    final slice = lines.sublist(safeStart, end);
    final body = slice.join('\n');

    return ToolResult.success(
      summary: '${slice.length} خط از ${show(resolved)} خوانده شد',
      data: {
        'path': show(resolved),
        'total_lines': lines.length,
        'from_line': offset,
        'content': body,
        if (end < lines.length) 'more_lines_after': lines.length - end,
      },
      detail: body,
    );
  }
}

class FileInfoTool extends _FsTool {
  const FileInfoTool();

  @override
  String get name => 'file_info';
  @override
  String get label => 'مشخصات فایل';
  @override
  ToolRisk get risk => ToolRisk.read;
  @override
  String get permission => Perm.filesystemRead;
  @override
  FsAccess get access => FsAccess.read;
  @override
  String get signature =>
      'file_info {"path": "a/b.txt"} — وجود، اندازه، تاریخ تغییر';

  @override
  Map<String, dynamic> get parameterSchema => const {
    'path': {'type': 'string'},
  };

  @override
  List<String> get requiredParameters => const ['path'];

  @override
  ToolPreview preview(ToolCall call) =>
      ToolPreview(title: 'مشخصات فایل', subtitle: call.str('path'));

  @override
  Future<ToolResult> run(ToolCall call, ToolContext context) async {
    final (resolved, error) = resolveFor(call.str('path'));
    if (error != null) return error;

    final type = FileSystemEntity.typeSync(resolved!, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      return ToolResult.success(
        summary: 'وجود ندارد: ${show(resolved)}',
        data: {'path': show(resolved), 'exists': false},
        detail: 'این مسیر وجود ندارد.',
      );
    }

    final stat = await FileStat.stat(resolved);
    final isDir = type == FileSystemEntityType.directory;
    final detail = [
      'مسیر: ${show(resolved)}',
      'نوع: ${isDir ? 'پوشه' : 'فایل'}',
      if (!isDir) 'اندازه: ${humanSize(stat.size)}',
      'آخرین تغییر: ${stat.modified.toLocal()}',
    ].join('\n');

    return ToolResult.success(
      summary: isDir
          ? 'پوشه · ${show(resolved)}'
          : '${humanSize(stat.size)} · ${show(resolved)}',
      data: {
        'path': show(resolved),
        'exists': true,
        'type': isDir ? 'dir' : 'file',
        'size': stat.size,
        'modified': stat.modified.toIso8601String(),
      },
      detail: detail,
    );
  }
}

class FindFilesTool extends _FsTool {
  @override
  bool get yieldsUntrustedContent => true;

  const FindFilesTool();

  @override
  String get name => 'find_files';
  @override
  String get label => 'یافتن فایل';
  @override
  ToolRisk get risk => ToolRisk.read;
  @override
  String get permission => Perm.filesystemRead;
  @override
  FsAccess get access => FsAccess.read;
  @override
  String get signature =>
      'find_files {"pattern": "*.dart", "path": "lib"} — جست‌وجوی نام فایل با الگوی * و ?';

  @override
  Map<String, dynamic> get parameterSchema => const {
    'pattern': {'type': 'string', 'description': 'الگوی نام با * و ?'},
    'path': {'type': 'string', 'description': 'پیش‌فرض .'},
  };

  @override
  List<String> get requiredParameters => const ['pattern'];

  @override
  ToolPreview preview(ToolCall call) => ToolPreview(
    title: 'یافتن فایل',
    subtitle: '${call.str('pattern') ?? '*'} در ${call.str('path') ?? '.'}',
  );

  @override
  Future<ToolResult> run(ToolCall call, ToolContext context) async {
    final (resolved, error) = resolveFor(call.str('path') ?? '.');
    if (error != null) return error;

    final dir = Directory(resolved!);
    if (!dir.existsSync()) {
      return ToolResult.failure('پوشه پیدا نشد: ${call.str('path') ?? '.'}');
    }

    final pattern = call.str('pattern') ?? '*';
    final regex = globToRegExp(pattern);
    final hits = <String>[];
    var truncated = false;

    await for (final entity in _walkFiles(
      dir,
      isCancelled: context.isCancelled,
    )) {
      if (!regex.hasMatch(p.basename(entity.path))) continue;
      hits.add(show(entity.path));
      if (hits.length >= FsLimits.maxDirEntries) {
        truncated = true;
        break;
      }
    }

    hits.sort();
    return ToolResult.success(
      summary: '${hits.length} فایل با الگوی $pattern',
      data: {
        'pattern': pattern,
        'files': hits,
        if (truncated) 'truncated': true,
      },
      detail: hits.isEmpty ? '(چیزی پیدا نشد)' : hits.join('\n'),
    );
  }
}

class SearchFilesTool extends _FsTool {
  @override
  bool get yieldsUntrustedContent => true;

  const SearchFilesTool();

  @override
  String get name => 'search_files';
  @override
  String get label => 'جست‌وجوی متن';
  @override
  ToolRisk get risk => ToolRisk.read;
  @override
  String get permission => Perm.filesystemRead;
  @override
  FsAccess get access => FsAccess.read;
  @override
  String get signature =>
      'search_files {"query": "TODO", "path": ".", "pattern": "*.dart"} — جست‌وجوی یک متن داخل فایل‌ها';

  @override
  Map<String, dynamic> get parameterSchema => const {
    'query': {'type': 'string', 'description': 'متن داخل فایل‌ها'},
    'path': {'type': 'string', 'description': 'پیش‌فرض .'},
    'pattern': {'type': 'string', 'description': 'فیلتر نام فایل'},
  };

  @override
  List<String> get requiredParameters => const ['query'];

  @override
  ToolPreview preview(ToolCall call) =>
      ToolPreview(title: 'جست‌وجوی متن', subtitle: call.str('query'));

  @override
  Future<ToolResult> run(ToolCall call, ToolContext context) async {
    final query = call.str('query');
    if (query == null) return ToolResult.failure('پارامتر query لازم است.');

    final (resolved, error) = resolveFor(call.str('path') ?? '.');
    if (error != null) return error;

    final dir = Directory(resolved!);
    if (!dir.existsSync()) {
      return ToolResult.failure('پوشه پیدا نشد: ${call.str('path') ?? '.'}');
    }

    final nameFilter = globToRegExp(call.str('pattern') ?? '*');
    final needle = query.toLowerCase();
    final matches = <Map<String, dynamic>>[];
    final lines = <String>[];
    var truncated = false;

    await for (final entity in _walkFiles(
      dir,
      isCancelled: context.isCancelled,
    )) {
      if (!nameFilter.hasMatch(p.basename(entity.path))) continue;

      int size;
      try {
        size = await entity.length();
      } catch (_) {
        continue;
      }
      if (size == 0 || size > FsLimits.maxSearchFileBytes) continue;

      List<int> bytes;
      try {
        bytes = await entity.readAsBytes();
      } catch (_) {
        continue;
      }
      if (_looksBinary(bytes)) continue;

      final text = utf8.decode(bytes, allowMalformed: true);
      if (!text.toLowerCase().contains(needle)) continue;

      final fileLines = const LineSplitter().convert(text);
      final shown = show(entity.path);
      for (var i = 0; i < fileLines.length; i++) {
        if (!fileLines[i].toLowerCase().contains(needle)) continue;
        final snippet = fileLines[i].trim();
        final clipped = snippet.length > 240
            ? '${snippet.substring(0, 240)}…'
            : snippet;
        matches.add({'file': shown, 'line': i + 1, 'text': clipped});
        lines.add('$shown:${i + 1}  $clipped');
        if (matches.length >= FsLimits.maxSearchHits) {
          truncated = true;
          break;
        }
      }
      if (truncated) break;
    }

    return ToolResult.success(
      summary: '${matches.length} نتیجه برای «$query»',
      data: {
        'query': query,
        'matches': matches,
        if (truncated) 'truncated': true,
      },
      detail: lines.isEmpty ? '(نتیجه‌ای پیدا نشد)' : lines.join('\n'),
    );
  }
}

class WriteFileTool extends _FsTool {
  const WriteFileTool();

  @override
  String get name => 'write_file';
  @override
  String get label => 'نوشتن فایل';
  @override
  ToolRisk get risk => ToolRisk.write;
  @override
  String get permission => Perm.filesystemWrite;
  @override
  FsAccess get access => FsAccess.write;
  @override
  String get signature =>
      'write_file {"path": "a/b.txt", "content": "..."} — ساخت فایل یا بازنویسی کاملش';

  @override
  Map<String, dynamic> get parameterSchema => const {
    'path': {'type': 'string'},
    'content': {
      'type': 'string',
      'description': 'کل فایل؛ قبلی جایگزین می‌شود',
    },
  };

  @override
  List<String> get requiredParameters => const ['path', 'content'];

  @override
  ToolPreview preview(ToolCall call) {
    final path = call.str('path');
    final absolute = path == null ? null : AgentWorkspace.toAbsolute(path);
    final exists = absolute != null && File(absolute).existsSync();
    return ToolPreview(
      title: exists ? 'بازنویسی کامل فایل' : 'ساخت فایل',
      subtitle: path,
      body: (call.args['content'] ?? '').toString(),
      bodyLanguage: 'text',
      warnings: [if (exists) 'محتوای فعلی این فایل کاملاً جایگزین می‌شود.'],
    );
  }

  @override
  Future<ToolResult> run(ToolCall call, ToolContext context) async {
    final (resolved, error) = resolveFor(call.str('path'));
    if (error != null) return error;

    final content = (call.args['content'] ?? '').toString();
    final file = File(resolved!);
    final existed = file.existsSync();
    final checkpointError = await _checkpoint(context, resolved);
    if (checkpointError != null) return checkpointError;
    await _writeTextAtomic(file, content);

    return ToolResult.success(
      summary: existed
          ? '${show(resolved)} بازنویسی شد'
          : '${show(resolved)} ساخته شد',
      data: {
        'path': show(resolved),
        'bytes': utf8.encode(content).length,
        'created': !existed,
      },
      changedPaths: [resolved],
    );
  }
}

class AppendFileTool extends _FsTool {
  const AppendFileTool();

  @override
  String get name => 'append_file';
  @override
  String get label => 'افزودن به فایل';
  @override
  ToolRisk get risk => ToolRisk.write;
  @override
  String get permission => Perm.filesystemWrite;
  @override
  FsAccess get access => FsAccess.write;
  @override
  String get signature =>
      'append_file {"path": "a/b.txt", "content": "..."} — افزودن به انتهای فایل';

  @override
  Map<String, dynamic> get parameterSchema => const {
    'path': {'type': 'string'},
    'content': {'type': 'string', 'description': 'به انتها اضافه می‌شود'},
  };

  @override
  List<String> get requiredParameters => const ['path', 'content'];

  @override
  ToolPreview preview(ToolCall call) => ToolPreview(
    title: 'افزودن به انتهای فایل',
    subtitle: call.str('path'),
    body: (call.args['content'] ?? '').toString(),
    bodyLanguage: 'text',
  );

  @override
  Future<ToolResult> run(ToolCall call, ToolContext context) async {
    final (resolved, error) = resolveFor(call.str('path'));
    if (error != null) return error;

    final content = (call.args['content'] ?? '').toString();
    final file = File(resolved!);
    var original = '';
    if (await file.exists()) {
      final (text, readError) = await _readEditableText(
        file,
        call.str('path') ?? resolved,
      );
      if (readError != null) return readError;
      original = text!;
    }
    final checkpointError = await _checkpoint(context, resolved);
    if (checkpointError != null) return checkpointError;
    await _writeTextAtomic(file, '$original$content');

    return ToolResult.success(
      summary: 'به ${show(resolved)} اضافه شد',
      data: {
        'path': show(resolved),
        'appended_bytes': utf8.encode(content).length,
      },
      changedPaths: [resolved],
    );
  }
}

class EditFileTool extends _FsTool {
  const EditFileTool();

  @override
  String get name => 'edit_file';
  @override
  String get label => 'ویرایش فایل';
  @override
  ToolRisk get risk => ToolRisk.write;
  @override
  String get permission => Perm.filesystemWrite;
  @override
  FsAccess get access => FsAccess.write;
  @override
  String get signature =>
      'edit_file {"path": "a/b.txt", "old": "متن قبلی", "new": "متن جدید", "all": false} — جایگزینی دقیق رشته';

  @override
  Map<String, dynamic> get parameterSchema => const {
    'path': {'type': 'string'},
    'old': {'type': 'string', 'description': 'باید عیناً در فایل باشد'},
    'new': {'type': 'string'},
    'all': {'type': 'boolean', 'description': 'همهٔ تکرارها؛ پیش‌فرض false'},
  };

  @override
  List<String> get requiredParameters => const ['path', 'old', 'new'];

  @override
  ToolPreview preview(ToolCall call) {
    final oldText = (call.args['old'] ?? '').toString();
    final newText = (call.args['new'] ?? '').toString();
    final diff = [
      ...oldText.split('\n').map((l) => '- $l'),
      ...newText.split('\n').map((l) => '+ $l'),
    ].join('\n');
    return ToolPreview(
      title: 'ویرایش فایل',
      subtitle: call.str('path'),
      body: diff,
      bodyLanguage: 'diff',
      warnings: [
        if (call.flag('all')) 'همهٔ موارد این متن در فایل جایگزین می‌شوند.',
      ],
    );
  }

  @override
  Future<ToolResult> run(ToolCall call, ToolContext context) async {
    final (resolved, error) = resolveFor(call.str('path'));
    if (error != null) return error;

    final oldText = (call.args['old'] ?? '').toString();
    final newText = (call.args['new'] ?? '').toString();
    if (oldText.isEmpty) {
      return ToolResult.failure('پارامتر old نباید خالی باشد.');
    }

    final file = File(resolved!);
    if (!file.existsSync()) {
      return ToolResult.failure('فایل پیدا نشد: ${call.str('path')}');
    }

    final (original, readError) = await _readEditableText(
      file,
      call.str('path') ?? resolved,
    );
    if (readError != null) return readError;
    final occurrences = oldText.allMatches(original!).length;
    if (occurrences == 0) {
      return ToolResult.failure(
        'متن مورد نظر در فایل پیدا نشد. عیناً همان متن فایل را بفرست.',
      );
    }

    final all = call.flag('all');
    if (occurrences > 1 && !all) {
      return ToolResult.failure(
        'این متن $occurrences بار در فایل آمده است. '
        'متن یکتاتری بده یا "all": true بگذار.',
      );
    }

    final updated = all
        ? original.replaceAll(oldText, newText)
        : original.replaceFirst(oldText, newText);
    final checkpointError = await _checkpoint(context, resolved);
    if (checkpointError != null) return checkpointError;
    await _writeTextAtomic(file, updated);

    return ToolResult.success(
      summary: '${show(resolved)} ویرایش شد ($occurrences مورد)',
      data: {'path': show(resolved), 'replaced': all ? occurrences : 1},
      detail: '- ${clip(oldText)}\n+ ${clip(newText)}',
      changedPaths: [resolved],
    );
  }
}

class MakeDirTool extends _FsTool {
  const MakeDirTool();

  @override
  String get name => 'make_dir';
  @override
  String get label => 'ساخت پوشه';
  @override
  ToolRisk get risk => ToolRisk.write;
  @override
  String get permission => Perm.filesystemCreate;
  @override
  FsAccess get access => FsAccess.write;
  @override
  String get signature =>
      'make_dir {"path": "reports/2026"} — ساخت پوشه همراه والدها';

  @override
  Map<String, dynamic> get parameterSchema => const {
    'path': {'type': 'string', 'description': 'والدها هم ساخته می‌شوند'},
  };

  @override
  List<String> get requiredParameters => const ['path'];

  @override
  ToolPreview preview(ToolCall call) =>
      ToolPreview(title: 'ساخت پوشه', subtitle: call.str('path'));

  @override
  Future<ToolResult> run(ToolCall call, ToolContext context) async {
    final (resolved, error) = resolveFor(call.str('path'));
    if (error != null) return error;

    final dir = Directory(resolved!);
    final existed = dir.existsSync();
    if (!existed) {
      final checkpointError = await _checkpoint(context, resolved);
      if (checkpointError != null) return checkpointError;
      await dir.create(recursive: true);
    }

    return ToolResult.success(
      summary: existed
          ? 'پوشه از قبل بود: ${show(resolved)}'
          : 'پوشه ساخته شد: ${show(resolved)}',
      data: {'path': show(resolved), 'created': !existed},
      changedPaths: existed ? const [] : [resolved],
    );
  }
}

class MovePathTool extends _FsTool {
  const MovePathTool();

  @override
  String get name => 'move_path';
  @override
  String get label => 'انتقال یا تغییر نام';
  @override
  ToolRisk get risk => ToolRisk.destructive;
  @override
  String get permission => Perm.filesystemWrite;
  @override
  FsAccess get access => FsAccess.write;
  @override
  String get signature => 'move_path {"from": "a.txt", "to": "b/a.txt"}';

  @override
  Map<String, dynamic> get parameterSchema => const {
    'from': {'type': 'string'},
    'to': {'type': 'string'},
  };

  @override
  List<String> get requiredParameters => const ['from', 'to'];

  @override
  String? hardDeny(ToolCall call) {
    final fromDeny = super.hardDeny(call);
    if (fromDeny != null) return fromDeny;
    final rawTo = call.str('to');
    if (rawTo == null) return null;
    final absolute = AgentWorkspace.toAbsolute(rawTo);
    if (absolute == null) return null;
    final owner = AgentWorkspace.owner(absolute);
    if (owner == null) return 'مقصد «$rawTo» بیرون از منابع مجاز است.';
    if (!owner.canWrite) {
      return 'روی «${owner.name}» اجازهٔ نوشتن داده نشده '
          '(اجازه‌های فعلی: ${owner.permissionLabel}).';
    }

    final rawFrom = call.str('from') ?? call.str('path');
    if (rawFrom == null) return null;
    final fromAbsolute = AgentWorkspace.toAbsolute(rawFrom);
    if (fromAbsolute == null) return null;
    final fromOwner = AgentWorkspace.owner(fromAbsolute);
    if (fromOwner == null) return null;
    final leavesResource = !p.equals(fromOwner.path, owner.path);
    if (leavesResource && !fromOwner.canDelete) {
      return 'بردن «$rawFrom» بیرون از «${fromOwner.name}» برای آن منبع یک '
          'حذف است و اجازهٔ حذف داده نشده '
          '(اجازه‌های فعلی: ${fromOwner.permissionLabel}).';
    }
    return null;
  }

  @override
  ToolPreview preview(ToolCall call) => ToolPreview(
    title: 'انتقال یا تغییر نام',
    subtitle: '${call.str('from') ?? '?'}  →  ${call.str('to') ?? '?'}',
  );

  @override
  Future<ToolResult> run(ToolCall call, ToolContext context) async {
    final rawFrom = call.str('from') ?? call.str('path');
    final rawTo = call.str('to');
    if (rawFrom == null || rawTo == null) {
      return ToolResult.failure('پارامترهای from و to لازم است.');
    }

    final (from, fromError) = resolveFor(rawFrom);
    if (fromError != null) return fromError;
    final (to, toError) = resolveFor(rawTo);
    if (toError != null) return toError;

    if (AgentWorkspace.isResourceRoot(from!)) {
      return ToolResult.failure('جابه‌جا کردن ریشهٔ منابع مجاز اجازه ندارد.');
    }

    final type = FileSystemEntity.typeSync(from, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      return ToolResult.failure('مبدأ پیدا نشد: $rawFrom');
    }
    if (FileSystemEntity.typeSync(to!) != FileSystemEntityType.notFound) {
      return ToolResult.failure('مقصد از قبل وجود دارد: $rawTo');
    }

    final fromCheckpoint = await _checkpoint(context, from);
    if (fromCheckpoint != null) return fromCheckpoint;
    final toCheckpoint = await _checkpoint(context, to);
    if (toCheckpoint != null) return toCheckpoint;

    await Directory(p.dirname(to)).create(recursive: true);
    if (type == FileSystemEntityType.directory) {
      await Directory(from).rename(to);
    } else {
      await File(from).rename(to);
    }

    return ToolResult.success(
      summary: '${show(from)} → ${show(to)}',
      data: {'from': show(from), 'to': show(to)},
      changedPaths: [from, to],
    );
  }
}

class DeletePathTool extends _FsTool {
  const DeletePathTool();

  @override
  String get name => 'delete_path';
  @override
  String get label => 'حذف';
  @override
  ToolRisk get risk => ToolRisk.destructive;
  @override
  String get permission => Perm.filesystemDelete;
  @override
  FsAccess get access => FsAccess.delete;
  @override
  String get signature =>
      'delete_path {"path": "tmp.txt", "recursive": false} — حذف فایل یا پوشه';

  @override
  Map<String, dynamic> get parameterSchema => const {
    'path': {'type': 'string'},
    'recursive': {
      'type': 'boolean',
      'description': 'برای پوشهٔ غیرخالی لازم است',
    },
  };

  @override
  List<String> get requiredParameters => const ['path'];

  @override
  ToolPreview preview(ToolCall call) {
    final path = call.str('path');
    final absolute = path == null ? null : AgentWorkspace.toAbsolute(path);
    final isDir =
        absolute != null &&
        FileSystemEntity.typeSync(absolute) == FileSystemEntityType.directory;
    return ToolPreview(
      title: 'حذف دائمی',
      subtitle: path,
      warnings: [
        'این عملیات برگشت‌پذیر نیست و فایل به سطل بازیافت نمی‌رود.',
        if (isDir && call.flag('recursive'))
          'کل محتوای این پوشه هم حذف می‌شود.',
      ],
    );
  }

  @override
  Future<ToolResult> run(ToolCall call, ToolContext context) async {
    final (resolved, error) = resolveFor(call.str('path'));
    if (error != null) return error;

    if (AgentWorkspace.isResourceRoot(resolved!)) {
      return ToolResult.failure('حذف ریشهٔ منابع مجاز اجازه ندارد.');
    }

    final type = FileSystemEntity.typeSync(resolved, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      return ToolResult.failure('مسیر پیدا نشد: ${call.str('path')}');
    }

    final checkpointError = await _checkpoint(context, resolved);
    if (checkpointError != null) return checkpointError;

    if (type == FileSystemEntityType.directory) {
      final recursive = call.flag('recursive');
      final dir = Directory(resolved);
      final notEmpty = dir.listSync().isNotEmpty;
      if (notEmpty && !recursive) {
        return ToolResult.failure(
          'پوشه خالی نیست. برای حذف محتوا "recursive": true لازم است.',
        );
      }
      await dir.delete(recursive: recursive);
    } else {
      await File(resolved).delete();
    }

    return ToolResult.success(
      summary: 'حذف شد: ${show(resolved)}',
      data: {'path': show(resolved), 'deleted': true},
      changedPaths: [resolved],
    );
  }
}

const filesystemTools = <AgentTool>[
  ListDirTool(),
  ReadFileTool(),
  FileInfoTool(),
  FindFilesTool(),
  SearchFilesTool(),
  WriteFileTool(),
  AppendFileTool(),
  EditFileTool(),
  MakeDirTool(),
  MovePathTool(),
  DeletePathTool(),
];
