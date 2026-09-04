import 'dart:convert';

import 'package:archive/archive.dart';

abstract final class DocxBuilder {
  static List<int> build({
    required String content,
    String? title,
    String? author,
    bool rtl = false,
  }) {
    final archive = Archive();
    final now = DateTime.now().toUtc().toIso8601String();
    final safeTitle = _xml(
      title?.trim().isNotEmpty == true ? title!.trim() : 'Document',
    );
    final safeAuthor = _xml(
      author?.trim().isNotEmpty == true ? author!.trim() : 'Jemiran Agent',
    );

    void add(String name, String value) {
      final bytes = utf8.encode(value);
      archive.addFile(ArchiveFile(name, bytes.length, bytes));
    }

    add('[Content_Types].xml', _contentTypes);
    add('_rels/.rels', _packageRelationships);
    add('word/document.xml', _document(content, title: title, rtl: rtl));
    add('word/styles.xml', _styles);
    add('word/settings.xml', _settings);
    add('word/_rels/document.xml.rels', _documentRelationships);
    add('docProps/core.xml', _coreProperties(safeTitle, safeAuthor, now));
    add('docProps/app.xml', _appProperties);

    return ZipEncoder().encode(archive, modified: DateTime.now());
  }

  static String _document(String content, {String? title, required bool rtl}) {
    final body = StringBuffer();
    if (title?.trim().isNotEmpty == true) {
      body.write(_paragraph(title!.trim(), style: 'Title', rtl: rtl));
    }
    final paragraphs = content
        .trim()
        .split(RegExp(r'\r?\n\s*\r?\n'))
        .where((part) => part.trim().isNotEmpty);
    for (final paragraph in paragraphs) {
      body.write(_paragraph(paragraph.trim(), rtl: rtl));
    }

    return '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:body>
    $body
    <w:sectPr>
      <w:pgSz w:w="12240" w:h="15840"/>
      <w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="720" w:footer="720" w:gutter="0"/>
    </w:sectPr>
  </w:body>
</w:document>''';
  }

  static String _paragraph(String value, {String? style, required bool rtl}) {
    final properties = <String>[
      if (style != null) '<w:pStyle w:val="$style"/>',
      if (rtl) '<w:bidi/>',
    ].join();
    final lines = value.split(RegExp(r'\r?\n'));
    final runs = <String>[];
    for (var i = 0; i < lines.length; i++) {
      if (i > 0) runs.add('<w:r><w:br/></w:r>');
      final runProperties = rtl ? '<w:rPr><w:rtl/></w:rPr>' : '';
      runs.add(
        '<w:r>$runProperties<w:t xml:space="preserve">${_xml(lines[i])}</w:t></w:r>',
      );
    }
    return '<w:p>${properties.isEmpty ? '' : '<w:pPr>$properties</w:pPr>'}${runs.join()}</w:p>';
  }

  static final _forbidden = RegExp(
    r'[\u0000-\u0008\u000b\u000c'
    r'\u000e-\u001f\ufffe\uffff]',
  );

  static String _xml(String value) => value
      .replaceAll(_forbidden, '')
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');

  static String _coreProperties(String title, String author, String now) =>
      '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:dcmitype="http://purl.org/dc/dcmitype/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <dc:title>$title</dc:title><dc:creator>$author</dc:creator><cp:lastModifiedBy>$author</cp:lastModifiedBy>
  <dcterms:created xsi:type="dcterms:W3CDTF">$now</dcterms:created><dcterms:modified xsi:type="dcterms:W3CDTF">$now</dcterms:modified>
</cp:coreProperties>''';

  static const _contentTypes =
      '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
  <Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
  <Override PartName="/word/settings.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml"/>
  <Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>
  <Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>
</Types>''';

  static const _packageRelationships =
      '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>
  <Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>
</Relationships>''';

  static const _documentRelationships =
      '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
  <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/settings" Target="settings.xml"/>
</Relationships>''';

  static const _styles =
      '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:docDefaults><w:rPrDefault><w:rPr><w:rFonts w:ascii="Aptos" w:hAnsi="Aptos" w:cs="Tahoma"/><w:sz w:val="22"/><w:szCs w:val="22"/></w:rPr></w:rPrDefault><w:pPrDefault/></w:docDefaults>
  <w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/><w:qFormat/></w:style>
  <w:style w:type="paragraph" w:styleId="Title"><w:name w:val="Title"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:qFormat/><w:pPr><w:spacing w:after="240"/><w:jc w:val="center"/></w:pPr><w:rPr><w:b/><w:sz w:val="36"/><w:szCs w:val="36"/></w:rPr></w:style>
</w:styles>''';

  static const _settings =
      '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:settings xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:zoom w:percent="100"/><w:defaultTabStop w:val="720"/><w:compat/></w:settings>''';

  static const _appProperties =
      '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties" xmlns:vt="http://schemas.openxmlformats.org/officeDocument/2006/docPropsVTypes"><Application>Jemiran Agent</Application><AppVersion>1.2</AppVersion></Properties>''';
}
