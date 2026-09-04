import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

class CopyButton extends StatefulWidget {
  final String code;

  const CopyButton({super.key, required this.code});
  @override
  State<CopyButton> createState() => CopyButtonState();
}

class CopyButtonState extends State<CopyButton> {
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return GestureDetector(
      onTap: () async {
        await Clipboard.setData(ClipboardData(text: widget.code));
        setState(() => _copied = true);
        await Future.delayed(Duration(seconds: 2));
        setState(() => _copied = false);
      },
      child: Row(
        children: [
          Icon(
            _copied ? Icons.check : Icons.copy,
            size: 14,
            color: isDark
                ? (_copied ? Color(0xFF4CAF50) : Color(0xFF888888))
                : (_copied
                      ? Color.fromARGB(255, 20, 74, 22)
                      : Colors.indigo.withValues(alpha: .9)),
          ),
          SizedBox(width: 4),
          Text(
            _copied ? 'کپی شد' : 'کپی',
            style: TextStyle(
              fontSize: 13,
              color: isDark
                  ? (_copied ? Color(0xFF4CAF50) : Color(0xFF888888))
                  : (_copied
                        ? Color.fromARGB(255, 20, 74, 22)
                        : Colors.indigo.withValues(alpha: .9)),
            ),
          ),
        ],
      ),
    );
  }
}

class CodeElementBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final code = element.textContent.trim();
    final classAttr = element.attributes['class'] ?? '';
    final lang = classAttr.replaceFirst('language-', '');

    if (lang.isEmpty) return null;
    if (!code.contains('\n') && code.split('').length <= 2) return null;

    return Directionality(
      textDirection: .ltr,
      child: Container(
        decoration: BoxDecoration(
          color: Color(0xFF1E1E2E),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: .start,
          children: [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                mainAxisAlignment: .spaceBetween,
                children: [
                  Text(
                    lang,
                    style: TextStyle(color: Color(0xFF888888), fontSize: 12),
                  ),
                  CopyButton(code: code),
                ],
              ),
            ),
            Divider(color: Color(0xFF333344), height: 1),
            HighlightView(
              code,
              language: lang,
              theme: atomOneDarkTheme,
              padding: EdgeInsets.all(12),
              textStyle: TextStyle(fontFamily: 'monospace', fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
