import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:markdown_widget/markdown_widget.dart';
import 'package:flutter_math_fork/flutter_math.dart';

bool containsPersian(String text) => RegExp(r'[\u0600-\u06FF]').hasMatch(text);

bool looksLikeMath(String text) =>
    RegExp(r'[\\^_=+\-*/{}()\[\]0-9a-zA-Z]').hasMatch(text) &&
    text.trim().isNotEmpty;

String cleanFormula(String formula) {
  return formula
      .replaceAll(r'\(', '')
      .replaceAll(r'\)', '')
      .replaceAll(r'\[', '')
      .replaceAll(r'\]', '')
      .replaceAll(r'$', '')
      .replaceAll(r'\operatorname', r'\mathrm')
      .replaceAll(r'\begin{align*}', r'\begin{aligned}')
      .replaceAll(r'\end{align*}', r'\end{aligned}')
      .trim();
}

String _latexToPlainText(String content) {
  return content
      .replaceAllMapped(
        RegExp(r'\\(?:text|mathrm|mathbf|mathit|mathsf|mbox)\{([^}]*)\}'),
        (m) => m[1]!,
      )
      .replaceAllMapped(
        RegExp(r'\\frac\{([^}]*)\}\{([^}]*)\}'),
        (m) => '${m[1]!}/${m[2]!}',
      )
      .replaceAll(r'\times', '×')
      .replaceAll(r'\cdot', '·')
      .replaceAll(r'\pm', '±')
      .replaceAll(RegExp(r'\\[a-zA-Z]+'), '')
      .replaceAll(RegExp(r'[{}]'), '')
      .replaceAll(r'$', '')
      .trim();
}

String _stripPersianFromLatex(String text) {
  text = text.replaceAllMapped(RegExp(r'\$\$([\s\S]*?)\$\$'), (m) {
    final content = m[1]!;
    if (containsPersian(content)) return _latexToPlainText(content);
    return m[0]!;
  });
  text = text.replaceAllMapped(
    RegExp(r'(?<!\$)\$(?!\$)([^\$\n]{1,300})(?<!\$)\$(?!\$)'),
    (m) {
      final content = m[1]!;
      if (containsPersian(content)) return _latexToPlainText(content);
      return m[0]!;
    },
  );
  return text;
}

String preprocessMarkdown(String text) {
  final List<String> codeBlocks = [];
  text = text.replaceAllMapped(RegExp(r'(```[\s\S]*?```|`[^`]+`)'), (m) {
    final idx = codeBlocks.length;
    codeBlocks.add(m[0]!);
    return '\x00CODE$idx\x00';
  });

  final List<String> mathBlocks = [];
  text = text.replaceAllMapped(
    RegExp(r'(\$\$[\s\S]*?\$\$|(?<!\$)\$(?!\$)[\s\S]*?(?<!\$)\$(?!\$))'),
    (m) {
      final idx = mathBlocks.length;
      mathBlocks.add(m[0]!);
      return '\x00MATHBLOCK$idx\x00';
    },
  );

  text = text.replaceAll('(', '\u200F(').replaceAll(')', ')\u200F');

  text = text.replaceAllMapped(RegExp(r'\x00MATHBLOCK(\d+)\x00'), (m) {
    return mathBlocks[int.parse(m[1]!)];
  });

  text = _stripPersianFromLatex(text);

  text = text.replaceAllMapped(
    RegExp(r'\(\((.*?)\)\)', dotAll: true),
    (m) => '\$${m[1]!.trim()}\$',
  );

  text = text.replaceAllMapped(
    RegExp(r'\*\*([a-zA-Z])\*\*'),
    (m) => '\$${m[1]!}\$',
  );

  text = text.replaceAllMapped(RegExp(r'\$\$(.*?)\$\$', dotAll: true), (m) {
    final content = m[1]!;
    if (containsPersian(content)) return _latexToPlainText(content).trim();
    return '\$\$${content.trim()}\$\$';
  });

  text = text.replaceAllMapped(
    RegExp(r'(?<!\$)\$(?!\$)(.*?)(?<!\$)\$(?!\$)', dotAll: true),
    (m) {
      final content = m[1]!;
      if (containsPersian(content) || !looksLikeMath(content)) {
        return content.trim();
      }
      final cleaned = content.replaceAll('\n', ' ').trim();
      return '\$$cleaned\$';
    },
  );

  text = text.replaceAllMapped(
    RegExp(r'\x00CODE(\d+)\x00'),
    (m) => codeBlocks[int.parse(m[1]!)],
  );

  return text;
}

class InlineMathNode extends SpanNode {
  final String formula;
  InlineMathNode(this.formula);

  @override
  InlineSpan build() => WidgetSpan(
    alignment: PlaceholderAlignment.middle,
    child: Builder(
      builder: (context) {
        final theme = Theme.of(context);
        final isDark = theme.brightness == Brightness.dark;

        return Directionality(
          textDirection: TextDirection.ltr,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            primary: false,
            child: Container(
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF333333)
                    : const Color.fromARGB(255, 233, 239, 253),
                borderRadius: BorderRadius.circular(5),
              ),
              margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Math.tex(
                cleanFormula(formula),
                onErrorFallback: (err) => SelectableText(
                  formula,
                  style: TextStyle(
                    fontSize: 15,
                    color: isDark ? Colors.blueAccent : const Color(0xFF4F7CFF),
                  ),
                ),
                textStyle: TextStyle(
                  fontSize: 15,
                  fontWeight: .w600,
                  color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                ),
              ),
            ),
          ),
        );
      },
    ),
  );
}

class BlockMathNode extends SpanNode {
  final String formula;
  BlockMathNode(this.formula);

  @override
  InlineSpan build() => WidgetSpan(
    alignment: PlaceholderAlignment.middle,
    child: Builder(
      builder: (context) {
        final theme = Theme.of(context);
        final isDark = theme.brightness == Brightness.dark;
        final backgroundColor = isDark
            ? const Color(0xFF252526)
            : const Color(0xFFF0F4FF);
        final borderColor = isDark
            ? const Color(0xFF3F3F3F)
            : const Color(0xFF4F7CFF).withValues(alpha: .3);
        final textColor = isDark
            ? const Color(0xFFE0E0E0)
            : const Color(0xFF333333);
        final accentColor = isDark
            ? const Color(0xFF7CA6FF)
            : const Color(0xFF4F7CFF);
        return LayoutBuilder(
          builder: (context, constraints) {
            final maxWidth = constraints.maxWidth > 0
                ? constraints.maxWidth
                : MediaQuery.of(context).size.width - 80;
            return ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: backgroundColor,
                  border: Border.all(color: borderColor),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        border: Border(bottom: BorderSide(color: borderColor)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'MATH',
                            style: TextStyle(
                              color: accentColor,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'monospace',
                            ),
                          ),
                          InkWell(
                            onTap: () =>
                                Clipboard.setData(ClipboardData(text: formula)),
                            child: Row(
                              children: [
                                Icon(Icons.copy, size: 13, color: accentColor),
                                const SizedBox(width: 4),
                                Text(
                                  'کپی',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: accentColor,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      primary: false,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      child: Math.tex(
                        cleanFormula(formula),
                        onErrorFallback: (err) => SelectableText(
                          formula,
                          style: TextStyle(
                            color: textColor,
                            fontFamily: 'monospace',
                          ),
                        ),
                        textStyle: TextStyle(fontSize: 17, color: textColor),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    ),
  );
}
