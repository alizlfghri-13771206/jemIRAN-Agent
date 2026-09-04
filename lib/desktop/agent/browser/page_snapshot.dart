class PageElement {
  const PageElement({
    required this.ref,
    required this.tag,
    required this.label,
    this.type,
    this.name,
    this.value,
    this.placeholder,
    this.required = false,
    this.disabled = false,
    this.checked,
    this.display,
    this.options = const [],
  });

  final String ref;
  final String tag;

  final String label;

  final String? type;
  final String? name;
  final String? value;
  final String? placeholder;
  final bool required;
  final bool disabled;
  final bool? checked;

  final String? display;

  String? get shownValue => display ?? value;

  final List<String> options;

  factory PageElement.fromJson(Map<Object?, Object?> j) => PageElement(
    ref: j['ref']?.toString() ?? '',
    tag: j['tag']?.toString() ?? '',
    label: j['label']?.toString() ?? '',
    type: j['type']?.toString(),
    name: j['name']?.toString(),
    value: j['value']?.toString(),
    placeholder: j['placeholder']?.toString(),
    required: j['required'] == true,
    disabled: j['disabled'] == true,
    checked: j['checked'] is bool ? j['checked'] as bool : null,
    display: j['display']?.toString(),
    options:
        (j['options'] as List?)?.map((e) => e.toString()).toList() ?? const [],
  );

  Map<String, dynamic> toJson() => {
    'ref': ref,
    'tag': tag,
    'label': label,
    if (type != null) 'type': type,
    if (name != null) 'name': name,
    if (value != null && value!.isNotEmpty) 'value': value,
    if (placeholder != null) 'placeholder': placeholder,
    if (required) 'required': true,
    if (disabled) 'disabled': true,
    if (checked != null) 'checked': checked,
    if (display != null) 'display': display,
    if (options.isNotEmpty) 'options': options,
  };

  bool get isTextInput =>
      tag == 'input' &&
      !const {
        'checkbox',
        'radio',
        'submit',
        'button',
        'file',
        'image',
        'reset',
      }.contains(type);

  bool get isSubmitControl =>
      (tag == 'button' && (type == null || type == 'submit')) ||
      (tag == 'input' && const {'submit', 'image'}.contains(type));
}

class PageForm {
  const PageForm({
    required this.ref,
    required this.name,
    required this.fieldRefs,
    this.action,
    this.method,
  });

  final String ref;
  final String name;
  final List<String> fieldRefs;
  final String? action;
  final String? method;

  factory PageForm.fromJson(Map<Object?, Object?> j) => PageForm(
    ref: j['ref']?.toString() ?? '',
    name: j['name']?.toString() ?? '',
    fieldRefs:
        (j['fields'] as List?)?.map((e) => e.toString()).toList() ?? const [],
    action: j['action']?.toString(),
    method: j['method']?.toString(),
  );

  Map<String, dynamic> toJson() => {
    'ref': ref,
    'name': name,
    'fields': fieldRefs,
    if (action != null) 'action': action,
    if (method != null) 'method': method,
  };
}

class PageSnapshot {
  const PageSnapshot({
    required this.url,
    required this.title,
    required this.text,
    required this.elements,
    required this.forms,
    this.truncated = false,
  });

  final String url;
  final String title;

  final String text;

  final List<PageElement> elements;
  final List<PageForm> forms;
  final bool truncated;

  factory PageSnapshot.fromJson(Map<Object?, Object?> j) => PageSnapshot(
    url: j['url']?.toString() ?? '',
    title: j['title']?.toString() ?? '',
    text: j['text']?.toString() ?? '',
    truncated: j['truncated'] == true,
    elements: (j['elements'] as List? ?? const [])
        .whereType<Map<Object?, Object?>>()
        .map(PageElement.fromJson)
        .toList(),
    forms: (j['forms'] as List? ?? const [])
        .whereType<Map<Object?, Object?>>()
        .map(PageForm.fromJson)
        .toList(),
  );

  PageElement? byRef(String ref) {
    for (final e in elements) {
      if (e.ref == ref) return e;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
    'url': url,
    'title': title,
    'text': text,
    if (truncated) 'text_truncated': true,
    'elements': elements.map((e) => e.toJson()).toList(),
    if (forms.isNotEmpty) 'forms': forms.map((f) => f.toJson()).toList(),
  };
}

const String kPageSnapshotJs = r'''
(() => {
  const MAX_ELEMENTS = 150;
  const MAX_TEXT = 4000;
  const MAX_LABEL = 120;

  const refs = [];
  window.__jemiranRefs = refs;

  const clean = (s) => (s || '').replace(/\s+/g, ' ').trim().slice(0, MAX_LABEL);

  const visible = (el) => {
    const style = window.getComputedStyle(el);
    if (style.visibility === 'hidden' || style.display === 'none') return false;
    if (parseFloat(style.opacity || '1') < 0.05) return false;
    const rect = el.getBoundingClientRect();
    return rect.width > 1 && rect.height > 1;
  };

  const labelOf = (el) => {
    const aria = el.getAttribute('aria-label');
    if (aria) return clean(aria);

    const labelledBy = el.getAttribute('aria-labelledby');
    if (labelledBy) {
      const target = document.getElementById(labelledBy);
      if (target) return clean(target.innerText);
    }

    if (el.id) {
      const forLabel = document.querySelector('label[for="' + CSS.escape(el.id) + '"]');
      if (forLabel) return clean(forLabel.innerText);
    }

    const wrapping = el.closest('label');
    if (wrapping) return clean(wrapping.innerText);

    const placeholder = el.getAttribute('placeholder');
    if (placeholder) return clean(placeholder);

    const title = el.getAttribute('title');
    if (title) return clean(title);

    if (el.tagName === 'INPUT' && (el.type === 'submit' || el.type === 'button')) {
      return clean(el.value);
    }

    const text = clean(el.innerText);
    if (text) return text;

    return clean(el.getAttribute('name') || el.id || '');
  };

  const SELECTOR = [
    'a[href]', 'button', 'input:not([type=hidden])', 'select', 'textarea',
    '[role=button]', '[role=link]', '[role=checkbox]', '[role=radio]',
    '[role=tab]', '[role=menuitem]', '[contenteditable=true]'
  ].join(',');

  const elements = [];
  const formMap = new Map();

  for (const el of document.querySelectorAll(SELECTOR)) {
    if (elements.length >= MAX_ELEMENTS) break;
    if (!visible(el)) continue;

    const ref = 'ref_' + refs.length;
    refs.push(el);

    const tag = el.tagName.toLowerCase();
    const entry = { ref: ref, tag: tag, label: labelOf(el) };

    if (el.type) entry.type = el.type;
    if (el.name) entry.name = el.name;
    if (el.getAttribute && el.getAttribute('required') !== null) entry.required = true;
    if (el.disabled) entry.disabled = true;

    if (tag === 'input' || tag === 'textarea') {
      if (el.type === 'checkbox' || el.type === 'radio') {
        entry.checked = !!el.checked;
      } else if (el.type !== 'password') {
        // مقدار فیلد رمز هرگز خوانده نمی‌شود.
        entry.value = clean(el.value);
      }
    } else if (tag === 'select') {
      entry.value = clean(el.value);
      // متنی که کاربر روی صفحه می‌بیند — برای مرور نهایی قبل از ارسال.
      // نشان دادن `math` به‌جای «ریاضی» یعنی کاربر چیزی را تأیید می‌کند
      // که نمی‌فهمد.
      const chosen = el.options[el.selectedIndex];
      if (chosen) entry.display = clean(chosen.text);
      entry.options = Array.from(el.options).slice(0, 40).map(o => clean(o.text));
    } else if (tag === 'a') {
      entry.href = (el.getAttribute('href') || '').slice(0, 300);
    }

    elements.push(entry);

    const form = el.form || el.closest('form');
    if (form) {
      if (!formMap.has(form)) {
        formMap.set(form, {
          ref: 'form_' + formMap.size,
          name: clean(form.getAttribute('name') || form.id || 'فرم'),
          action: (form.getAttribute('action') || '').slice(0, 300),
          method: (form.getAttribute('method') || 'get').toLowerCase(),
          fields: []
        });
      }
      formMap.get(form).fields.push(ref);
    }
  }

  const bodyText = (document.body ? document.body.innerText : '') || '';
  const trimmed = bodyText.replace(/\n{3,}/g, '\n\n').trim();

  return {
    url: location.href,
    title: document.title || '',
    text: trimmed.slice(0, MAX_TEXT),
    truncated: trimmed.length > MAX_TEXT,
    elements: elements,
    forms: Array.from(formMap.values())
  };
})()
''';
