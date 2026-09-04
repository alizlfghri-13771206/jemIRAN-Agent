import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:jemiran/desktop/agent/core/agent_protocol.dart';
import 'package:jemiran/desktop/agent/policy/agent_policy.dart';
import 'package:jemiran/desktop/agent/tools/agent_tool.dart';
import 'package:jemiran/desktop/agent/tools/tool_registry.dart';

void main() {
  final windows = ToolRegistry.windows();

  group('schema ابزار', () {
    test('هر ابزار با آرگومان، properties واقعی اعلام می‌کند', () {
      const argumentless = {
        'browser_read',
        'browser_close',
        'browser_screenshot',
        'list_skills',
        'check_network',
      };

      for (final tool in windows.all) {
        final fn = tool.toolSchema['function'] as Map<String, dynamic>;
        final parameters = fn['parameters'] as Map<String, dynamic>;
        final properties = parameters['properties'] as Map<String, dynamic>;

        if (argumentless.contains(tool.name)) {
          expect(properties.keys, [
            'step',
          ], reason: '${tool.name} نباید آرگومان دیگری اعلام کند');
          continue;
        }
        expect(
          properties.length,
          greaterThan(1),
          reason: '${tool.name} هیچ آرگومانی اعلام نکرده است',
        );
        for (final entry in properties.entries) {
          final spec = entry.value;
          expect(
            spec,
            isA<Map<String, dynamic>>(),
            reason: '${tool.name}.${entry.key} یک schema معتبر نیست',
          );
          final map = spec as Map<String, dynamic>;
          expect(
            const {'string', 'integer', 'number', 'boolean', 'array', 'object'},
            contains(map['type']),
            reason: '${tool.name}.${entry.key} نوع معتبر ندارد',
          );
          final description = map['description'];
          if (description != null) {
            expect(
              (description as String).trim().isNotEmpty,
              isTrue,
              reason: '${tool.name}.${entry.key} توضیح خالی دارد',
            );
          }
        }
      }
    });

    test('`step` برای همهٔ ابزارها اعلام می‌شود', () {
      for (final tool in windows.all) {
        final fn = tool.toolSchema['function'] as Map<String, dynamic>;
        final properties =
            (fn['parameters'] as Map<String, dynamic>)['properties']
                as Map<String, dynamic>;
        expect(
          properties['step'],
          AgentTool.planStepProperty,
          reason: '${tool.name} کلید step را اعلام نکرده است',
        );
        expect(AgentTool.planStepProperty.containsKey('description'), isFalse);
      }
    });

    test('آرگومان‌های واجب با آنچه ابزار واقعاً می‌خواهد می‌خوانند', () {
      const expected = <String, List<String>>{
        'read_file': ['path'],
        'write_file': ['path', 'content'],
        'edit_file': ['path', 'old', 'new'],
        'move_path': ['from', 'to'],
        'run_command': ['command'],
        'git': ['action'],
        'ask_user': ['question'],
        'install_package': ['manager', 'package'],
        'remember': ['scope', 'text'],
      };
      for (final entry in expected.entries) {
        final tool = windows.find(entry.key);
        expect(tool, isNotNull, reason: '${entry.key} در رجیستری نیست');
        final fn = tool!.toolSchema['function'] as Map<String, dynamic>;
        final parameters = fn['parameters'] as Map<String, dynamic>;
        expect(parameters['required'], entry.value);
        final properties = parameters['properties'] as Map<String, dynamic>;
        for (final name in entry.value) {
          expect(
            properties.containsKey(name),
            isTrue,
            reason: '${entry.key} آرگومان واجب $name را اعلام نکرده',
          );
        }
      }
    });

    test('schema هیچ ابزاری از سقف ۴۰۰۰ نویسهٔ سرور رد نمی‌شود', () {
      for (final tool in windows.all) {
        final fn = tool.toolSchema['function'] as Map<String, dynamic>;
        expect(
          jsonEncode(fn['parameters']).length,
          lessThanOrEqualTo(4000),
          reason: '${tool.name} از سقف schema سرور بزرگ‌تر است',
        );
        expect(
          (fn['description'] as String).length,
          lessThanOrEqualTo(600),
          reason: '${tool.name} توضیحش روی سرور بریده می‌شود',
        );
      }
    });

    test('کل بستهٔ ابزارها در بودجهٔ پلن رایگان می‌ماند', () {
      final payload = jsonEncode([
        for (final tool in windows.all) tool.toolSchema,
      ]);
      final tokens = AgentProtocol.estimatedTokens(payload);
      expect(
        tokens,
        lessThanOrEqualTo(5000),
        reason:
            'بستهٔ ابزارها $tokens توکن است و از بودجهٔ پلن رایگان '
            'رد می‌شود؛ توضیح‌ها را کوتاه کن یا ابزار کم کن',
      );
    });

    test('`additionalProperties` باز می‌ماند', () {
      for (final tool in windows.all) {
        final fn = tool.toolSchema['function'] as Map<String, dynamic>;
        expect((fn['parameters'] as Map)['additionalProperties'], isTrue);
      }
    });
  });

  group('ارجاع بند نقشه در کانال ساختاری', () {
    test('`step` از داخل آرگومان‌ها خوانده می‌شود', () {
      expect(AgentProtocol.stepIdFromArgs(const {'step': 3}), 3);
      expect(AgentProtocol.stepIdFromArgs(const {'step_id': '4'}), 4);
    });

    test('مقدار بی‌معنی یعنی «ارجاعی نداریم»، نه یک بند اشتباه', () {
      expect(AgentProtocol.stepIdFromArgs(const {}), isNull);
      expect(AgentProtocol.stepIdFromArgs(const {'step': 0}), isNull);
      expect(AgentProtocol.stepIdFromArgs(const {'step': -2}), isNull);
      expect(AgentProtocol.stepIdFromArgs(const {'step': 'سه'}), isNull);
      expect(AgentProtocol.stepIdFromArgs(const {'step': null}), isNull);
    });

    test('پرامپت می‌گوید `step` را داخل آرگومان‌ها بگذار', () {
      final preamble = AgentProtocol.preamble(
        registry: ToolRegistry.of(const []),
        mode: AgentMode.manual,
      );
      expect(preamble, contains('در کانال ساختاری، `step` را **داخل**'));
    });
  });

  group('parseNativeToolCalls', () {
    List<Object> batch(Map<String, dynamic> overrides) => [
      {
        'id': 'call_1',
        'name': 'read_file',
        'arguments': const {'path': 'a.txt'},
        ...overrides,
      },
    ];

    test('ارجاع بند نقشه از آرگومان‌ها به ToolCall می‌رسد', () {
      final calls = AgentProtocol.parseNativeToolCalls([
        {
          'id': 'call_1',
          'name': 'run_command',
          'arguments': const {'command': 'flutter test', 'step': 3},
        },
      ]);
      expect(calls, hasLength(1));
      expect(calls!.single.stepId, 3);
      expect(calls.single.args['step'], 3);
    });

    test('نبود ارجاع یعنی هیچ بندی تیک نمی‌خورد', () {
      final calls = AgentProtocol.parseNativeToolCalls(batch(const {}));
      expect(calls!.single.stepId, isNull);
    });

    test('batch نیمه‌معتبر کاملاً رد می‌شود', () {
      expect(
        AgentProtocol.parseNativeToolCalls(batch(const {'id': ''})),
        isNull,
      );
      expect(
        AgentProtocol.parseNativeToolCalls(batch(const {'name': 'Read_File'})),
        isNull,
      );
      expect(
        AgentProtocol.parseNativeToolCalls(batch(const {'arguments': '[]'})),
        isNull,
      );
      expect(
        AgentProtocol.parseNativeToolCalls([
          {'id': 'x1', 'name': 'read_file', 'arguments': const {}},
          {'id': 'x1', 'name': 'list_dir', 'arguments': const {}},
        ]),
        isNull,
      );
    });

    test('batch بزرگ‌تر از سقف مشترک رد می‌شود', () {
      final oversized = [
        for (var i = 0; i <= AgentProtocol.maxToolCallsPerTurn; i++)
          {'id': 'call_$i', 'name': 'read_file', 'arguments': const {}},
      ];
      expect(oversized, hasLength(AgentProtocol.maxToolCallsPerTurn + 1));
      expect(AgentProtocol.parseNativeToolCalls(oversized), isNull);
    });

    test('کانال غایب با کانال خراب یکی نیست', () {
      expect(AgentProtocol.parseNativeToolCalls(null), isNull);
      expect(AgentProtocol.parseNativeToolCalls(const []), isNull);
    });
  });
}
