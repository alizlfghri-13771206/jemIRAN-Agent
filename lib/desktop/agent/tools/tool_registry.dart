import 'agent_tool.dart';
import 'browser_tools.dart';
import 'capability_tools.dart';
import 'docx_tool.dart';
import 'install_package_tool.dart';
import 'network_tool.dart';
import 'pdf_tool.dart';
import 'filesystem_tools.dart';
import 'git_tool.dart';
import 'knowledge_tools.dart';
import 'question_tool.dart';
import 'terminal_tool.dart';

class ToolRegistry {
  ToolRegistry._(this._tools);

  factory ToolRegistry.windows() => ToolRegistry._([
    ...filesystemTools,
    const RunCommandTool(),
    const GitTool(),
    const AskUserTool(),
    ...browserTools,
    ...capabilityTools,
    const MakeDocxTool(),
    const InstallPackageTool(),
    const MakePdfTool(),
    const CheckNetworkTool(),
    ...knowledgeTools,
  ]);

  factory ToolRegistry.of(List<AgentTool> tools) => ToolRegistry._([...tools]);

  final List<AgentTool> _tools;

  List<AgentTool> get all => List.unmodifiable(_tools);

  List<AgentTool> get available =>
      _tools.where((t) => t.available).toList(growable: false);

  AgentTool? find(String name) {
    for (final t in _tools) {
      if (t.name == name) return t;
    }
    return null;
  }

  bool isKnown(String name) => find(name) != null;

  void register(AgentTool tool) {
    _tools.removeWhere((t) => t.name == tool.name);
    _tools.add(tool);
  }

  void unregister(String name) => _tools.removeWhere((t) => t.name == name);

  String promptSection() => available.map((t) => '- ${t.signature}').join('\n');
}
