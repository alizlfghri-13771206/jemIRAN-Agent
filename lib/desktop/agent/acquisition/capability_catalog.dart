enum PackageManager {
  winget,
  pip,
  npm;

  String get command => switch (this) {
    PackageManager.winget => 'winget',
    PackageManager.pip => 'pip',
    PackageManager.npm => 'npm',
  };

  String get label => switch (this) {
    PackageManager.winget => 'winget (مایکروسافت)',
    PackageManager.pip => 'pip (پایتون)',
    PackageManager.npm => 'npm (نود)',
  };

  List<String> installArgs(String packageId) => switch (this) {
    PackageManager.winget => [
      'install',
      '--id',
      packageId,
      '--exact',
      '--scope',
      'user',
      '--silent',
      '--accept-package-agreements',
      '--accept-source-agreements',
    ],
    PackageManager.pip => ['install', '--user', packageId],
    PackageManager.npm => ['install', '--global', packageId],
  };

  bool get mayNeedAdmin => this == PackageManager.npm;
}

class CapabilityProvider {
  const CapabilityProvider({
    required this.manager,
    required this.packageId,
    required this.verifyCommand,
    this.note,
  });

  final PackageManager manager;
  final String packageId;

  final String verifyCommand;

  final String? note;
}

class Capability {
  const Capability({
    required this.key,
    required this.label,
    required this.description,
    this.builtinBy,
    this.existingCommands = const [],
    this.providers = const [],
  });

  final String key;
  final String label;
  final String description;

  final String? builtinBy;

  final List<String> existingCommands;

  final List<CapabilityProvider> providers;

  bool get isBuiltin => builtinBy != null;
}

abstract final class CapabilityCatalog {
  static const all = <Capability>[
    Capability(
      key: 'pdf',
      label: 'ساخت PDF',
      description: 'تبدیل Markdown یا HTML به فایل PDF',
      builtinBy: 'موتور چاپ مرورگر (بدون نیاز به نصب)',
    ),
    Capability(
      key: 'docx',
      label: 'ساخت فایل Word',
      description: 'ساخت مستقیم سند استاندارد Word با پسوند DOCX',
      builtinBy: 'سازندهٔ OpenXML جمیران (بدون نیاز به Python یا Office)',
    ),
    Capability(
      key: 'ocr',
      label: 'تشخیص متن از تصویر',
      description: 'خواندن متن داخل عکس یا PDF اسکن‌شده',
      existingCommands: ['tesseract'],
      providers: [
        CapabilityProvider(
          manager: PackageManager.winget,
          packageId: 'UB-Mannheim.TesseractOCR',
          verifyCommand: 'tesseract',
          note: 'برای فارسی، بستهٔ زبان fas هم لازم است.',
        ),
      ],
    ),
    Capability(
      key: 'document_convert',
      label: 'تبدیل سند',
      description: 'تبدیل بین Word، Markdown، HTML، EPUB و مانند آن',
      existingCommands: ['pandoc'],
      providers: [
        CapabilityProvider(
          manager: PackageManager.winget,
          packageId: 'JohnMacFarlane.Pandoc',
          verifyCommand: 'pandoc',
        ),
      ],
    ),
    Capability(
      key: 'image_convert',
      label: 'تبدیل و ویرایش تصویر',
      description: 'تغییر فرمت، اندازه و فشرده‌سازی تصویر',
      existingCommands: ['magick'],
      providers: [
        CapabilityProvider(
          manager: PackageManager.winget,
          packageId: 'ImageMagick.ImageMagick',
          verifyCommand: 'magick',
        ),
      ],
    ),
    Capability(
      key: 'compression',
      label: 'فشرده‌سازی',
      description: 'ساخت و باز کردن ZIP و 7z و RAR',
      existingCommands: ['7z'],
      providers: [
        CapabilityProvider(
          manager: PackageManager.winget,
          packageId: '7zip.7zip',
          verifyCommand: '7z',
        ),
      ],
    ),
    Capability(
      key: 'python',
      label: 'پایتون',
      description: 'اجرای اسکریپت پایتون',
      existingCommands: ['python', 'py'],
      providers: [
        CapabilityProvider(
          manager: PackageManager.winget,
          packageId: 'Python.Python.3.12',
          verifyCommand: 'python',
        ),
      ],
    ),
    Capability(
      key: 'node',
      label: 'نود جی‌اس',
      description: 'اجرای جاوااسکریپت بیرون از مرورگر',
      existingCommands: ['node'],
      providers: [
        CapabilityProvider(
          manager: PackageManager.winget,
          packageId: 'OpenJS.NodeJS.LTS',
          verifyCommand: 'node',
        ),
      ],
    ),
    Capability(
      key: 'git',
      label: 'گیت',
      description: 'کنترل نسخه',
      existingCommands: ['git'],
      providers: [
        CapabilityProvider(
          manager: PackageManager.winget,
          packageId: 'Git.Git',
          verifyCommand: 'git',
        ),
      ],
    ),
    Capability(
      key: 'linux',
      label: 'ابزارهای لینوکسی',
      description: 'اجرای ابزارهای لینوکس روی ویندوز از راه WSL',
      existingCommands: ['wsl'],
      providers: [
        CapabilityProvider(
          manager: PackageManager.winget,
          packageId: 'Canonical.Ubuntu.2204',
          verifyCommand: 'wsl',
          note:
              'نصب WSL ممکن است به راه‌اندازی مجدد نیاز داشته باشد. پس از آن '
              'بسته‌های apt با install_package و manager=wsl نصب می‌شوند.',
        ),
      ],
    ),
    Capability(
      key: 'ffmpeg',
      label: 'پردازش صدا و ویدیو',
      description: 'تبدیل، برش و استخراج صدا و ویدیو',
      existingCommands: ['ffmpeg'],
      providers: [
        CapabilityProvider(
          manager: PackageManager.winget,
          packageId: 'Gyan.FFmpeg',
          verifyCommand: 'ffmpeg',
        ),
      ],
    ),
  ];

  static Capability? find(String key) {
    final needle = key.trim().toLowerCase();
    for (final c in all) {
      if (c.key == needle) return c;
    }
    return null;
  }

  static List<String> get keys => [for (final c in all) c.key];
}
