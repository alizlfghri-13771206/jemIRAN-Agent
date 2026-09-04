import 'package:jemiran/themes/colors.dart';
import 'package:jemiran/ui/screens/chat_room/widgets/chat_room_widgets.dart';
import 'package:jemiran/ui/screens/chat_room/widgets/guess_direction.dart';
import 'package:jemiran/ui/screens/chat_room/widgets/math_box.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus_latex/flutter_markdown_plus_latex.dart';
import 'package:markdown_widget/config/configs.dart';
import 'package:markdown_widget/config/markdown_generator.dart';
import 'package:markdown_widget/widget/blocks/leaf/code_block.dart';
import 'package:markdown_widget/widget/blocks/leaf/paragraph.dart';
import 'package:markdown_widget/widget/inlines/code.dart';
import 'package:markdown_widget/widget/markdown_block.dart';
import 'package:markdown_widget/widget/widget_visitor.dart';

class FadeInText extends StatefulWidget {
  final String text;
  final VoidCallback? onDone;

  const FadeInText({super.key, required this.text, this.onDone});

  @override
  State<FadeInText> createState() => _FadeInTextState();
}

class _FadeInTextState extends State<FadeInText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    final duration = Duration(
      milliseconds: (widget.text.length * 0.8).clamp(300, 800).toInt(),
    );

    _ctrl = AnimationController(vsync: this, duration: duration);
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeIn);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _ctrl.forward().whenComplete(() {
        if (mounted) widget.onDone?.call();
      });
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fade,
      child: AiMessageMarkdown(text: widget.text),
    );
  }
}

class AiMessageMarkdown extends StatelessWidget {
  final String text;
  const AiMessageMarkdown({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    final dir = detectDirection(text);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Directionality(
      textDirection: dir,
      child: MarkdownBlock(
        data: preprocessMarkdown(text),
        selectable: true,
        config: MarkdownConfig(
          configs: [
            PConfig(
              textStyle: TextStyle(
                color: isDark
                    ? const Color(0xFFE0E0E0)
                    : const Color(0xFF2D2D2D),
                fontSize: 15.5,
                height: 1.8,
              ),
            ),
            PreConfig(
              wrapper: (child, code, language) => Directionality(
                textDirection: TextDirection.ltr,
                child: _CodeBlock(code: code, language: language),
              ),
              theme: aiLightTheme,
              textStyle: const TextStyle(
                fontSize: 13.5,
                fontFamily: 'monospace',
                color: Color(0xFFCDD6F4),
              ),
              decoration: const BoxDecoration(color: Colors.transparent),
              padding: EdgeInsets.zero,
              margin: EdgeInsets.zero,
            ),
            CodeConfig(
              style: TextStyle(
                fontSize: 13.5,
                backgroundColor: isDark
                    ? const Color(0xFF2D2D2D)
                    : const Color(0xFFCDD6F4),
                color: isDark ? Colors.blue : Colors.indigo,
                fontWeight: FontWeight.w600,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
        generator: MarkdownGenerator(
          generators: [
            SpanNodeGeneratorWithTag(
              tag: 'latex',
              generator: (e, config, visitors) {
                final content = cleanFormula(e.textContent);
                return e.attributes['isBlock'] == 'true'
                    ? BlockMathNode(content)
                    : InlineMathNode(content);
              },
            ),
          ],
          inlineSyntaxList: [LatexInlineSyntax()],
          blockSyntaxList: [LatexBlockSyntax()],
        ),
      ),
    );
  }
}

class _CodeBlock extends StatelessWidget {
  final String code;
  final String language;

  const _CodeBlock({required this.code, required this.language});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF2D2D2D)
            : Colors.blueAccent.withValues(alpha: .2),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.black26, width: .5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: isDark
                      ? Colors.white.withValues(alpha: .1)
                      : const Color(0xFF2D2D2D).withValues(alpha: .3),
                ),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  language.isEmpty ? 'CODE' : language.toUpperCase(),
                  style: TextStyle(
                    color: isDark
                        ? const Color(0xFF888888)
                        : const Color(0xFF2D2D2D).withValues(alpha: .3),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                  ),
                ),
                CopyButton(code: code),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.all(14),
            child: SelectableText(
              code,
              style: TextStyle(
                fontSize: 13.5,
                fontFamily: 'monospace',
                color: isDark ? const Color(0xFFCDD6F4) : Colors.black87,
                height: 1.6,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
