import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:jemiran/desktop/agent/core/agent_storage.dart';
import 'package:jemiran/desktop/agent/memory/agent_memory.dart';
import 'package:jemiran/desktop/agent/policy/agent_policy.dart';
import 'package:jemiran/desktop/agent/skills/agent_skill.dart';
import 'package:jemiran/desktop/agent/tools/agent_tool.dart';
import 'package:jemiran/desktop/agent/tools/knowledge_tools.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  var scopeCounter = 0;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('jemiran_persist');
    AgentStorage.setBaseRootForTesting(temp);
    AgentStorage.setAccountScope('persist-test-${scopeCounter++}');
  });

  tearDown(() {
    AgentStorage.setBaseRootForTesting(null);
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  group('نوشتن ماندگار بدون تأیید انجام نمی‌شود', () {
    const remember = RememberTool();
    const saveSkill = SaveSkillTool();

    test('در حالت خودگردان هم می‌پرسد', () {
      const state = AgentPolicyState(mode: AgentMode.autonomous);
      for (final tool in <AgentTool>[remember, saveSkill]) {
        expect(
          state
              .evaluate(
                tool: tool,
                call: ToolCall(name: tool.name, args: const {'text': 'x'}),
              )
              .outcome,
          PolicyOutcome.ask,
          reason: tool.name,
        );
      }
    });

    test('اجازهٔ نشست هم آن را باز نمی‌کند', () {
      const state = AgentPolicyState(
        mode: AgentMode.autonomous,
        sessionGrants: {Perm.memoryWrite, Perm.skillWrite},
      );
      expect(
        state
            .evaluate(
              tool: remember,
              call: ToolCall(name: 'remember', args: const {'text': 'x'}),
            )
            .outcome,
        PolicyOutcome.ask,
      );
    });

    test('هر دو مجوز در فهرست «همیشه تأیید» هستند', () {
      expect(Perm.alwaysConfirm, contains(Perm.memoryWrite));
      expect(Perm.alwaysConfirm, contains(Perm.skillWrite));
    });
  });

  group('سقف حافظه', () {
    test('یادداشت بلند بریده می‌شود', () async {
      final store = MemoryStore.instance;
      await store.clearScope(MemoryScope.user);

      final note = await store.remember(
        scope: MemoryScope.user,
        text: 'ا' * 5000,
      );

      expect(note.text.length, lessThanOrEqualTo(MemoryStore.maxNoteChars + 1));
      expect(note.text, endsWith('…'));
    });

    test('یادداشت تکراری دوباره ذخیره نمی‌شود', () async {
      final store = MemoryStore.instance;
      await store.clearScope(MemoryScope.user);

      final first = await store.remember(
        scope: MemoryScope.user,
        text: 'همیشه از پروکسی استفاده کن',
      );
      final second = await store.remember(
        scope: MemoryScope.user,
        text: 'همیشه از پروکسی استفاده کن',
      );

      expect(second.id, first.id);
      expect(store.relevantFor(null).length, 1);
    });

    test('تعداد یادداشت‌ها سقف دارد و قدیمی‌ها هرس می‌شوند', () async {
      final store = MemoryStore.instance;
      await store.clearScope(MemoryScope.user);

      for (var i = 0; i < MemoryStore.maxNotesPerScope + 15; i++) {
        await store.remember(scope: MemoryScope.user, text: 'یادداشت $i');
      }

      final notes = store.relevantFor(null);
      expect(notes.length, MemoryStore.maxNotesPerScope);
      expect(
        notes.first.text,
        contains('${MemoryStore.maxNotesPerScope + 14}'),
      );
      expect(notes.any((n) => n.text == 'یادداشت 0'), isFalse);
    });

    test('راز داخل یادداشت پاک می‌شود', () async {
      final store = MemoryStore.instance;
      await store.clearScope(MemoryScope.user);

      final note = await store.remember(
        scope: MemoryScope.user,
        text: 'کلید: api_key=abcd1234efgh5678ijkl',
      );

      expect(note.text, isNot(contains('abcd1234efgh5678ijkl')));
    });
  });

  group('سقف مهارت', () {
    test('بیش از سقف، مهارت تازه پذیرفته نمی‌شود', () async {
      final store = SkillStore.instance;
      await store.load();

      var accepted = 0;
      for (var i = 0; i < SkillStore.maxSkills + 5; i++) {
        final ok = await store.save(
          AgentSkill(
            id: 'skill_test_$i',
            name: 'مهارت $i',
            purpose: 'آزمون',
            diagnosticSteps: const ['یک'],
          ),
        );
        if (ok) accepted++;
      }

      expect(accepted, SkillStore.maxSkills);
      expect(store.all.length, SkillStore.maxSkills);
    });

    test('به‌روزرسانی مهارت موجود همیشه ممکن است', () async {
      final store = SkillStore.instance;
      await store.load();

      for (var i = 0; i < SkillStore.maxSkills; i++) {
        await store.save(
          AgentSkill(
            id: 'skill_full_$i',
            name: 'مهارت $i',
            purpose: 'آزمون',
            diagnosticSteps: const ['یک'],
          ),
        );
      }
      final updated = await store.save(
        AgentSkill(
          id: 'skill_full_0',
          name: 'مهارت اصلاح‌شده',
          purpose: 'آزمون',
          diagnosticSteps: const ['دو'],
        ),
      );
      expect(updated, isTrue);
      expect(
        store.all.firstWhere((s) => s.id == 'skill_full_0').name,
        'مهارت اصلاح‌شده',
      );
    });
  });

  group('پوشهٔ ذخیره‌سازی', () {
    test('مهارت‌ها بیرون از فضای حساب نوشته نمی‌شوند', () async {
      final store = SkillStore.instance;
      await store.load();
      await store.save(
        AgentSkill(
          id: 'skill_scope_1',
          name: 'الف',
          purpose: 'آزمون',
          diagnosticSteps: const ['یک'],
        ),
      );
      final dir = AgentStorage.subdir('skills');
      expect(dir, isNotNull);
      expect(p.isWithin(temp.path, dir!.path), isTrue);
    });
  });
}
