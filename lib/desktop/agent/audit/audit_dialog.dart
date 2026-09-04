import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:jemiran/desktop/theme/desktop_tokens.dart';
import 'package:jemiran/themes/colors.dart';
import 'package:jemiran/themes/jemiran_design.dart';

import 'audit_log.dart';

Future<void> showAuditLogDialog(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const _AuditDialog());

class _AuditDialog extends StatefulWidget {
  const _AuditDialog();

  @override
  State<_AuditDialog> createState() => _AuditDialogState();
}

class _AuditDialogState extends State<_AuditDialog> {
  final _search = TextEditingController();
  AuditKind? _kind;
  String? _status;
  late List<AuditEntry> _entries = _load();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<AuditEntry> _load() => AuditLog.read(
    limit: 300,
    kinds: _kind == null ? null : {_kind!},
    contains: _search.text.trim().isEmpty ? null : _search.text.trim(),
  );

  void _refresh() => setState(() => _entries = _load());

  Future<void> _export() async {
    final content = AuditLog.exportJsonl();
    if (content.isEmpty) {
      setState(() => _status = 'چیزی برای خروجی گرفتن نیست.');
      return;
    }
    try {
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'ذخیرهٔ دفتر فعالیت',
        fileName: 'jemiran-audit.jsonl',
      );
      if (path == null) return;
      await File(path).writeAsString(content, flush: true);
      if (!mounted) return;
      setState(() => _status = 'ذخیره شد.');
    } catch (error) {
      if (!mounted) return;
      setState(() => _status = 'ذخیره نشد: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: const Text('دفتر فعالیت'),
        content: SizedBox(
          width: 640,
          height: 460,
          child: Column(
            children: [
              Text(
                'هرچه ایجنت روی این دستگاه انجام داده — بدون کلید و رمز، '
                'چون پیش از نوشتن پاک‌سازی می‌شود.',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.8,
                  color: JSurface.muted(isDark),
                ),
              ),
              const SizedBox(height: WinSpace.md),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _search,
                      onSubmitted: (_) => _refresh(),
                      decoration: const InputDecoration(
                        isDense: true,
                        hintText: 'جست‌وجو — مثلاً یک فرمان یا مسیر',
                        prefixIcon: Icon(Icons.search_rounded, size: 18),
                      ),
                    ),
                  ),
                  const SizedBox(width: WinSpace.sm),
                  DropdownButton<AuditKind?>(
                    value: _kind,
                    hint: const Text('همه'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('همه')),
                      for (final kind in AuditKind.values)
                        DropdownMenuItem(
                          value: kind,
                          child: Text(_label(kind)),
                        ),
                    ],
                    onChanged: (value) {
                      _kind = value;
                      _refresh();
                    },
                  ),
                ],
              ),
              const SizedBox(height: WinSpace.md),
              Expanded(
                child: _entries.isEmpty
                    ? Center(
                        child: Text(
                          'ردیفی پیدا نشد.',
                          style: TextStyle(color: JSurface.muted(isDark)),
                        ),
                      )
                    : ListView.separated(
                        itemCount: _entries.length,
                        separatorBuilder: (_, _) => Divider(
                          height: 1,
                          color: WinSurface.hairline(isDark),
                        ),
                        itemBuilder: (_, index) =>
                            _Row(isDark: isDark, entry: _entries[index]),
                      ),
              ),
              if (_status != null) ...[
                const SizedBox(height: WinSpace.sm),
                Text(
                  _status!,
                  style: TextStyle(fontSize: 12, color: JSurface.muted(isDark)),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('بستن'),
          ),
          TextButton(onPressed: _refresh, child: const Text('تازه‌سازی')),
          FilledButton(onPressed: _export, child: const Text('خروجی')),
        ],
      ),
    );
  }

  static String _label(AuditKind kind) => switch (kind) {
    AuditKind.taskStarted => 'شروع کار',
    AuditKind.taskFinished => 'پایان کار',
    AuditKind.tool => 'ابزار',
    AuditKind.permission => 'اجازه',
    AuditKind.modelSwitch => 'تعویض مدل',
    AuditKind.compaction => 'فشرده‌سازی',
    AuditKind.error => 'خطا',
  };
}

class _Row extends StatelessWidget {
  const _Row({required this.isDark, required this.entry});

  final bool isDark;
  final AuditEntry entry;

  @override
  Widget build(BuildContext context) {
    final at = entry.at;
    final time =
        '${at.hour.toString().padLeft(2, '0')}:'
        '${at.minute.toString().padLeft(2, '0')}';
    final date = '${at.year}/${at.month}/${at.day}';
    final target =
        (entry.fields['target'] ??
                entry.fields['reason'] ??
                entry.fields['goal'] ??
                entry.fields['message'] ??
                '')
            .toString();
    final tool = entry.fields['tool']?.toString();
    final failed = entry.fields['ok'] == false || entry.kind == 'error';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: WinSpace.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              '$date\n$time',
              style: TextStyle(
                fontSize: 11,
                height: 1.5,
                color: JSurface.muted(isDark),
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tool ??
                      _AuditDialogState._label(
                        AuditKind.values.firstWhere(
                          (kind) => kind.wire == entry.kind,
                          orElse: () => AuditKind.error,
                        ),
                      ),
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 12.5,
                    color: failed
                        ? (isDark ? DarkColors.danger : LightColors.danger)
                        : null,
                  ),
                ),
                if (target.isNotEmpty)
                  Text(
                    target,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.6,
                      color: JSurface.muted(isDark),
                    ),
                  ),
              ],
            ),
          ),
          if (entry.model != null)
            SizedBox(
              width: 130,
              child: Text(
                entry.model!,
                textAlign: TextAlign.left,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10.5, color: JSurface.muted(isDark)),
              ),
            ),
        ],
      ),
    );
  }
}
