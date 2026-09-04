import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jemiran/desktop/agent/agent_workspace.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late Directory allowed;
  late Directory outside;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    temp = await Directory.systemTemp.createTemp('jemiran_ws_test');
    allowed = Directory(p.join(temp.path, 'allowed'))..createSync();
    outside = Directory(p.join(temp.path, 'outside'))..createSync();
    File(p.join(allowed.path, 'note.txt')).writeAsStringSync('salam');
    File(p.join(outside.path, 'secret.txt')).writeAsStringSync('nope');
    await AgentWorkspace.clear();
  });

  tearDown(() async {
    await AgentWorkspace.clear();
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  group('مرز دسترسی', () {
    test('مسیر داخل پوشهٔ مجاز حل می‌شود', () async {
      await AgentWorkspace.addDirectory(allowed.path);
      expect(AgentWorkspace.resolve('note.txt'), isNotNull);
    });

    test('مسیر مطلقِ بیرون رد می‌شود', () async {
      await AgentWorkspace.addDirectory(allowed.path);
      final target = p.join(outside.path, 'secret.txt');
      expect(AgentWorkspace.resolve(target), isNull);
    });

    test('فرار با ".." رد می‌شود', () async {
      await AgentWorkspace.addDirectory(allowed.path);
      expect(AgentWorkspace.resolve('../outside/secret.txt'), isNull);
      expect(AgentWorkspace.resolve('..\\outside\\secret.txt'), isNull);
      expect(AgentWorkspace.resolve('subdir/../../outside/secret.txt'), isNull);
    });

    test('بدون هیچ منبعی، هیچ مسیری حل نمی‌شود', () {
      expect(AgentWorkspace.resolve('note.txt'), isNull);
      expect(AgentWorkspace.resolve(r'C:\Windows\System32'), isNull);
    });

    test('زیرپوشه با مجوز مستقل زیر والد حفظ می‌شود', () async {
      final child = Directory(p.join(allowed.path, 'child'))..createSync();
      await AgentWorkspace.addDirectory(child.path, canWrite: false);
      await AgentWorkspace.addDirectory(allowed.path);
      expect(AgentWorkspace.resources, hasLength(2));
      expect(AgentWorkspace.canWrite(p.join(child.path, 'new.txt')), isFalse);
      expect(AgentWorkspace.canWrite(p.join(allowed.path, 'new.txt')), isTrue);
    });

    test('لینک داخل workspace نمی‌تواند به بیرون فرار کند', () async {
      await AgentWorkspace.addDirectory(allowed.path);
      final link = Link(p.join(allowed.path, 'escape'));
      try {
        await link.create(outside.path, recursive: false);
      } on FileSystemException {
        return;
      }

      expect(AgentWorkspace.resolve('escape/secret.txt'), isNull);
      expect(AgentWorkspace.resolve('escape/new.txt'), isNull);
    });
  });

  group('اجازه‌های هر منبع', () {
    test('پیش‌فرض: خواندن و نوشتن بله، حذف نه', () async {
      await AgentWorkspace.addDirectory(allowed.path);
      final path = p.join(allowed.path, 'note.txt');
      expect(AgentWorkspace.canRead(path), isTrue);
      expect(AgentWorkspace.canWrite(path), isTrue);
      expect(AgentWorkspace.canDelete(path), isFalse);
    });

    test('خاموش کردن نوشتن روی منبع اثر می‌کند', () async {
      await AgentWorkspace.addDirectory(allowed.path);
      await AgentWorkspace.setPermissions(allowed.path, canWrite: false);
      final path = p.join(allowed.path, 'note.txt');
      expect(AgentWorkspace.canRead(path), isTrue);
      expect(AgentWorkspace.canWrite(path), isFalse);
    });

    test('فایل تکی هم می‌تواند منبع باشد', () async {
      final file = p.join(allowed.path, 'note.txt');
      await AgentWorkspace.addFile(file);
      expect(AgentWorkspace.isAllowed(file), isTrue);
      expect(
        AgentWorkspace.isAllowed(p.join(allowed.path, 'other.txt')),
        isFalse,
      );
    });
  });

  group('ماندگاری', () {
    test('منابع بعد از load برمی‌گردند', () async {
      await AgentWorkspace.addDirectory(allowed.path, canDelete: true);
      await AgentWorkspace.load();
      final res = AgentWorkspace.resources.single;
      expect(res.canDelete, isTrue);
    });

    test('پروژهٔ فعال بین چند پوشه مستقل انتخاب و ماندگار می‌شود', () async {
      await AgentWorkspace.addDirectory(allowed.path);
      await AgentWorkspace.addDirectory(outside.path);
      final canonicalAllowed = allowed.resolveSymbolicLinksSync();
      final canonicalOutside = outside.resolveSymbolicLinksSync();
      expect(AgentWorkspace.primaryRoot, canonicalAllowed);

      await AgentWorkspace.setPrimaryProject(outside.path);
      expect(AgentWorkspace.primaryRoot, canonicalOutside);

      await AgentWorkspace.load();
      expect(AgentWorkspace.primaryRoot, canonicalOutside);
    });
  });

  test('snapshot دو Work هم‌زمان مسیر و مجوز یکدیگر را نمی‌بیند', () async {
    await AgentWorkspace.replace([
      AgentResource(
        path: allowed.path,
        kind: ResourceKind.directory,
        canWrite: true,
      ),
    ], activeProjectPath: allowed.path);
    final snapshotA = AgentWorkspace.snapshot();
    await AgentWorkspace.replace([
      AgentResource(
        path: outside.path,
        kind: ResourceKind.directory,
        canWrite: false,
      ),
    ], activeProjectPath: outside.path);
    final snapshotB = AgentWorkspace.snapshot();

    final results = await Future.wait([
      AgentWorkspace.runWithSnapshot(snapshotA, () async {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        return (
          root: AgentWorkspace.primaryRoot,
          own: AgentWorkspace.isAllowed(p.join(allowed.path, 'a.txt')),
          other: AgentWorkspace.isAllowed(p.join(outside.path, 'b.txt')),
        );
      }),
      AgentWorkspace.runWithSnapshot(snapshotB, () async {
        await Future<void>.delayed(const Duration(milliseconds: 1));
        return (
          root: AgentWorkspace.primaryRoot,
          own: AgentWorkspace.isAllowed(p.join(outside.path, 'b.txt')),
          other: AgentWorkspace.isAllowed(p.join(allowed.path, 'a.txt')),
        );
      }),
    ]);

    expect(p.basename(results[0].root!), 'allowed');
    expect(results[0].own, isTrue);
    expect(results[0].other, isFalse);
    expect(p.basename(results[1].root!), 'outside');
    expect(results[1].own, isTrue);
    expect(results[1].other, isFalse);
  });
}
