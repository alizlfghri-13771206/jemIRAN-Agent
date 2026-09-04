import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:jemiran/desktop/agent/core/agent_protocol.dart';
import 'package:jemiran/desktop/agent/policy/agent_policy.dart';
import 'package:jemiran/desktop/agent/tools/tool_registry.dart';

void main() {
  test('baseline رجیستری واقعی Windows قابل بازتولید است', () {
    final registry = ToolRegistry.windows();
    final tools = registry.available.map((tool) => tool.toolSchema).toList();
    final prompt = AgentProtocol.preamble(
      registry: registry,
      mode: AgentMode.autonomous,
    );
    final promptWithMemory = AgentProtocol.preamble(
      registry: registry,
      mode: AgentMode.autonomous,
      skillsSection: List.filled(8, 'skill: مسیر کاری کوتاه').join('\n'),
      memorySection: List.filled(
        12,
        'memory: واقعیت مرتبط با پروژه',
      ).join('\n'),
    );
    final toolJson = jsonEncode(tools);
    final largeResult = jsonEncode({
      'ok': true,
      'stdout': List.filled(3000, 'خط خروجی ابزار').join('\n'),
    });

    final data = <String, Object>{
      'registered_tools': registry.all.length,
      'available_tools': registry.available.length,
      'text_tool_catalog_chars': registry.promptSection().length,
      'text_tool_catalog_estimated_tokens': AgentProtocol.estimatedTokens(
        registry.promptSection(),
      ),
      'native_tool_schema_chars': toolJson.length,
      'native_tool_schema_estimated_tokens':
          AgentProtocol.estimatedTokens(toolJson) + tools.length * 8,
      'autonomous_preamble_chars': prompt.length,
      'autonomous_preamble_estimated_tokens': AgentProtocol.estimatedTokens(
        prompt,
      ),
      'sample_skills_memory_increment_tokens':
          AgentProtocol.estimatedTokens(promptWithMemory) -
          AgentProtocol.estimatedTokens(prompt),
      'large_tool_result_chars': largeResult.length,
      'large_tool_result_estimated_tokens': AgentProtocol.estimatedTokens(
        largeResult,
      ),
    };

    // ignore: avoid_print
    print('JEMIRAN_TOKEN_BASELINE=${jsonEncode(data)}');
    expect(registry.all, isNotEmpty);
    expect(registry.available.length, lessThanOrEqualTo(registry.all.length));
    expect(data['autonomous_preamble_estimated_tokens'], greaterThan(0));
    expect(data['native_tool_schema_estimated_tokens'], greaterThan(0));
    expect(data['large_tool_result_estimated_tokens'], greaterThan(10_000));
  });
}
