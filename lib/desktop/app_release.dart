import 'package:package_info_plus/package_info_plus.dart';

abstract final class AppRelease {
  static String version = '';

  static const commit = String.fromEnvironment('APP_COMMIT', defaultValue: '');

  static Future<void> initialize() async {
    final info = await PackageInfo.fromPlatform();
    version = info.buildNumber.isEmpty
        ? info.version
        : '${info.version}+${info.buildNumber}';
  }

  static String get label {
    if (version.isEmpty) return 'نسخهٔ توسعه (نامشخص)';
    return commit.isEmpty ? version : '$version · $commit';
  }
}
