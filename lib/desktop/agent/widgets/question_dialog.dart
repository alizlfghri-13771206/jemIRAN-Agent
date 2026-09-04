import 'package:flutter/material.dart';
import 'package:jemiran/desktop/agent/tools/agent_tool.dart';
import 'package:jemiran/desktop/theme/desktop_tokens.dart';
import 'package:jemiran/desktop/theme/win_controls.dart';
import 'package:jemiran/themes/jemiran_design.dart';

Future<String?> showAgentQuestionDialog(
  BuildContext context,
  AgentQuestion question,
) => showDialog<String>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _QuestionDialog(question: question),
);

class _QuestionDialog extends StatefulWidget {
  const _QuestionDialog({required this.question});

  final AgentQuestion question;

  @override
  State<_QuestionDialog> createState() => _QuestionDialogState();
}

class _QuestionDialogState extends State<_QuestionDialog> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  String? _selected;

  @override
  void initState() {
    super.initState();
    if (widget.question.options.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _focus.requestFocus(),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  String? get _answer {
    final typed = _controller.text.trim();
    if (typed.isNotEmpty) return typed;
    return _selected;
  }

  void _submit() {
    final answer = _answer;
    if (answer == null || answer.isEmpty) return;
    Navigator.of(context).pop(answer);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final q = widget.question;
    final accent = JColor.primary(isDark);
    final canSubmit = (_answer ?? '').isNotEmpty;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Dialog(
        backgroundColor: WinSurface.card(isDark),
        surfaceTintColor: Colors.transparent,
        elevation: 12,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(WinRadius.layer),
          side: BorderSide(color: WinSurface.hairline(isDark)),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520, maxHeight: 600),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.all(WinSpace.xl),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 32,
                      width: 32,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: isDark ? .18 : .12),
                        borderRadius: BorderRadius.circular(WinRadius.card),
                      ),
                      child: Icon(
                        Icons.help_outline_rounded,
                        size: 17,
                        color: accent,
                      ),
                    ),
                    const SizedBox(width: WinSpace.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'جمیران یک سؤال دارد',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: JSurface.muted(isDark),
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            q.text,
                            style: TextStyle(
                              fontSize: WinText.body,
                              height: 1.7,
                              fontWeight: FontWeight.w700,
                              color: JSurface.text(isDark),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const WinSeam(),
              Flexible(
                child: WinScrollbar(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(WinSpace.xl),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final option in q.options) ...[
                          _option(option, isDark, accent),
                          const SizedBox(height: WinSpace.sm),
                        ],
                        if (q.freeText) ...[
                          if (q.options.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: WinSpace.sm,
                              ),
                              child: Text(
                                'یا پاسخ دلخواه بنویسید:',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: JSurface.muted(isDark),
                                ),
                              ),
                            ),
                          TextField(
                            controller: _controller,
                            focusNode: _focus,
                            onChanged: (_) => setState(() {}),
                            onSubmitted: (_) => _submit(),
                            style: TextStyle(
                              fontSize: WinText.body,
                              color: JSurface.text(isDark),
                            ),
                            decoration: InputDecoration(
                              hintText: q.placeholder ?? 'پاسخ شما…',
                              filled: true,
                              fillColor: WinSurface.window(isDark),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(
                                  WinRadius.card,
                                ),
                                borderSide: BorderSide(
                                  color: WinSurface.hairline(isDark),
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(
                                  WinRadius.card,
                                ),
                                borderSide: BorderSide(
                                  color: WinSurface.hairline(isDark),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              const WinSeam(),
              Padding(
                padding: const EdgeInsets.all(WinSpace.lg),
                child: Row(
                  children: [
                    Expanded(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: canSubmit
                              ? accent
                              : accent.withValues(alpha: .35),
                          borderRadius: BorderRadius.circular(
                            WinRadius.control,
                          ),
                        ),
                        child: WinHoverable(
                          onTap: canSubmit ? _submit : null,
                          radius: WinRadius.control,
                          padding: const EdgeInsets.symmetric(vertical: 11),
                          child: const Center(
                            child: Text(
                              'ادامه',
                              style: TextStyle(
                                fontSize: WinText.bodySm,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: WinSpace.sm),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(WinRadius.control),
                        border: Border.all(color: WinSurface.hairline(isDark)),
                      ),
                      child: WinHoverable(
                        onTap: () => Navigator.of(context).pop(),
                        radius: WinRadius.control,
                        padding: const EdgeInsets.symmetric(
                          vertical: 11,
                          horizontal: WinSpace.xl,
                        ),
                        child: Text(
                          'پاسخ نمی‌دهم',
                          style: TextStyle(
                            fontSize: WinText.bodySm,
                            fontWeight: FontWeight.w700,
                            color: JSurface.muted(isDark),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _option(String option, bool isDark, Color accent) {
    final selected = _selected == option && _controller.text.trim().isEmpty;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: selected
            ? accent.withValues(alpha: isDark ? .18 : .10)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(WinRadius.card),
        border: Border.all(
          color: selected ? accent : WinSurface.hairline(isDark),
        ),
      ),
      child: WinHoverable(
        radius: WinRadius.card,
        onTap: () => setState(() {
          _selected = option;
          _controller.clear();
        }),
        padding: const EdgeInsets.symmetric(
          horizontal: WinSpace.md,
          vertical: WinSpace.md,
        ),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_unchecked_rounded,
              size: 17,
              color: selected ? accent : JSurface.muted(isDark),
            ),
            const SizedBox(width: WinSpace.md),
            Expanded(
              child: Text(
                option,
                style: TextStyle(
                  fontSize: WinText.bodySm,
                  height: 1.6,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  color: JSurface.text(isDark),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
