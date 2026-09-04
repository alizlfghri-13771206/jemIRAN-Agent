import 'dart:io';

import 'package:path/path.dart' as p;

class BrowserBinary {
  const BrowserBinary({required this.path, required this.label});

  final String path;

  final String label;
}

abstract final class ChromeLocator {
  static BrowserBinary? _cached;
  static bool _searched = false;

  static BrowserBinary? find() {
    if (_searched) return _cached;
    _searched = true;

    for (final candidate in _candidates()) {
      if (candidate.path.isNotEmpty && File(candidate.path).existsSync()) {
        _cached = candidate;
        return _cached;
      }
    }
    return null;
  }

  static bool get isAvailable => find() != null;

  static List<BrowserBinary> _candidates() {
    final programFiles =
        Platform.environment['ProgramFiles'] ?? r'C:\Program Files';
    final programFilesX86 =
        Platform.environment['ProgramFiles(x86)'] ?? r'C:\Program Files (x86)';
    final localAppData = Platform.environment['LOCALAPPDATA'] ?? '';

    return [
      BrowserBinary(
        path: p.join(
          programFiles,
          'Google',
          'Chrome',
          'Application',
          'chrome.exe',
        ),
        label: 'Google Chrome',
      ),
      BrowserBinary(
        path: p.join(
          programFilesX86,
          'Google',
          'Chrome',
          'Application',
          'chrome.exe',
        ),
        label: 'Google Chrome',
      ),
      if (localAppData.isNotEmpty)
        BrowserBinary(
          path: p.join(
            localAppData,
            'Google',
            'Chrome',
            'Application',
            'chrome.exe',
          ),
          label: 'Google Chrome',
        ),
      BrowserBinary(
        path: p.join(
          programFiles,
          'Microsoft',
          'Edge',
          'Application',
          'msedge.exe',
        ),
        label: 'Microsoft Edge',
      ),
      BrowserBinary(
        path: p.join(
          programFilesX86,
          'Microsoft',
          'Edge',
          'Application',
          'msedge.exe',
        ),
        label: 'Microsoft Edge',
      ),
    ];
  }

  static void resetCache() {
    _cached = null;
    _searched = false;
  }
}
