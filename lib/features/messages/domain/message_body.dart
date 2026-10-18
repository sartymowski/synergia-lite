import 'dart:convert';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

/// Treść z API: UTF-8 w base64; pełna wiadomość dodatkowo w
/// `<Message><Content><![CDATA[…]]></Content></Message>`. Podgląd z listy bywa
/// ucięty w środku znaku wielobajtowego — dekodujemy pobłażliwie.
String decodeMessageContent(String? encoded) {
  if (encoded == null || encoded.trim().isEmpty) return '';
  var b64 = encoded.replaceAll(RegExp(r'\s'), '');
  b64 = b64.padRight(b64.length + (4 - b64.length % 4) % 4, '=');
  String text;
  try {
    text = utf8.decode(base64.decode(b64), allowMalformed: true);
  } on FormatException {
    return '';
  }
  final cdata = RegExp(
    r'<Content>\s*<!\[CDATA\[([\s\S]*?)\]\]>\s*</Content>',
  ).firstMatch(text);
  return cdata?.group(1) ?? text.replaceFirst(RegExp(r'^\s*<Message>\s*'), '');
}

/// Fragment treści do wyświetlenia — wyłącznie tekst i proste style.
class BodySpan {
  const BodySpan(
    this.text, {
    this.bold = false,
    this.italic = false,
    this.link,
  });

  final String text;
  final bool bold;
  final bool italic;

  /// Adres odnośnika (np. `liblink.pl` — Librus przepisuje linki). Aplikacja
  /// go nie otwiera automatycznie.
  final String? link;

  @override
  bool operator ==(Object other) =>
      other is BodySpan &&
      other.text == text &&
      other.bold == bold &&
      other.italic == italic &&
      other.link == link;

  @override
  int get hashCode => Object.hash(text, bold, italic, link);

  @override
  String toString() =>
      'BodySpan(${jsonEncode(text)}${bold ? ', b' : ''}${italic ? ', i' : ''}${link != null ? ', link' : ''})';
}

const _skipped = {
  'script',
  'style',
  'head',
  'title',
  'iframe',
  'frame',
  'object',
  'embed',
  'svg',
  'math',
  'noscript',
  'template',
  'video',
  'audio',
  'canvas',
  'form',
  'input',
  'button',
  'select',
  'textarea',
  'link',
  'meta',
  'base',
};
const _blocks = {
  'p',
  'div',
  'li',
  'ul',
  'ol',
  'tr',
  'table',
  'blockquote',
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
  'pre',
  'section',
  'article',
  'header',
  'footer',
  'hr',
};

/// HTML → fragmenty tekstu. Nie wykonuje skryptów i nie pobiera zasobów
/// (obrazy są zastępowane opisem, piksele śledzące nie są ładowane).
List<BodySpan> htmlToSpans(String html) {
  final out = _SpanBuilder();
  final fragment = html_parser.parseFragment(html);
  for (final node in fragment.nodes) {
    _walk(node, out, bold: false, italic: false, link: null);
  }
  return out.finish();
}

/// Zwykły tekst (np. do cytatu w odpowiedzi lub podglądu na liście).
String htmlToPlainText(String html) =>
    htmlToSpans(html).map((s) => s.text).join();

String previewText(String html, {int max = 140}) {
  final flat = htmlToPlainText(html).replaceAll(RegExp(r'\s+'), ' ').trim();
  return flat.length <= max ? flat : '${flat.substring(0, max).trimRight()}…';
}

void _walk(
  dom.Node node,
  _SpanBuilder out, {
  required bool bold,
  required bool italic,
  required String? link,
}) {
  if (node is dom.Text) {
    // Białe znaki formatujące źródło HTML między blokami nie są treścią.
    if (node.data.trim().isEmpty && _besideBlock(node)) return;
    out.text(node.data, bold: bold, italic: italic, link: link);
    return;
  }
  if (node is! dom.Element) return;
  final tag = node.localName ?? '';
  if (_skipped.contains(tag)) return;
  switch (tag) {
    case 'br':
      out.newline();
      return;
    case 'img':
      final alt = node.attributes['alt']?.trim();
      // Obrazów nie ładujemy; maleńkie (piksele śledzące) pomijamy całkiem.
      final w = int.tryParse(node.attributes['width'] ?? '');
      final h = int.tryParse(node.attributes['height'] ?? '');
      if ((w != null && w <= 2) || (h != null && h <= 2)) return;
      out.text(
        alt == null || alt.isEmpty ? '[obraz]' : '[obraz: $alt]',
        bold: bold,
        italic: true,
        link: link,
      );
      return;
  }
  final isBlock = _blocks.contains(tag);
  if (isBlock) out.block();
  if (tag == 'li') out.text('• ', bold: bold, italic: italic, link: null);
  final href = tag == 'a' ? node.attributes['href']?.trim() : null;
  final childLink =
      href != null &&
          href.isNotEmpty &&
          !href.toLowerCase().startsWith('javascript:')
      ? href
      : link;
  for (final child in node.nodes) {
    _walk(
      child,
      out,
      bold:
          bold ||
          tag == 'b' ||
          tag == 'strong' ||
          RegExp(r'^h[1-6]$').hasMatch(tag),
      italic: italic || tag == 'i' || tag == 'em',
      link: childLink,
    );
  }
  if (isBlock) out.block();
}

bool _besideBlock(dom.Node node) {
  final siblings = node.parentNode?.nodes;
  if (siblings == null) return false;
  final i = siblings.indexOf(node);
  bool isBlock(int j) =>
      j >= 0 &&
      j < siblings.length &&
      siblings[j] is dom.Element &&
      _blocks.contains((siblings[j] as dom.Element).localName);
  return isBlock(i - 1) || isBlock(i + 1);
}

class _SpanBuilder {
  final _spans = <BodySpan>[];
  final _buf = StringBuffer();
  bool _bold = false, _italic = false;
  String? _link;

  void text(
    String raw, {
    required bool bold,
    required bool italic,
    required String? link,
  }) {
    // Spacje i tabulatory zwijamy; nowe linie zostają (Librus je zachowuje).
    final t = raw
        .replaceAll('\r\n', '\n')
        .replaceAll(RegExp(r'[ \t\f ]+'), ' ');
    if (t.isEmpty) return;
    if (bold != _bold || italic != _italic || link != _link) {
      _flush();
      _bold = bold;
      _italic = italic;
      _link = link;
    }
    _buf.write(t);
  }

  void newline() {
    _flushIfStyled();
    _buf.write('\n');
  }

  void block() {
    _flushIfStyled();
    final s = _current();
    if (s.isNotEmpty && !s.endsWith('\n')) _buf.write('\n');
  }

  String _current() {
    if (_buf.isNotEmpty) return _buf.toString();
    return _spans.isEmpty ? '' : _spans.last.text;
  }

  void _flushIfStyled() {
    if (_bold || _italic || _link != null) {
      _flush();
      _bold = _italic = false;
      _link = null;
    }
  }

  void _flush() {
    if (_buf.isEmpty) return;
    _spans.add(
      BodySpan(_buf.toString(), bold: _bold, italic: _italic, link: _link),
    );
    _buf.clear();
  }

  List<BodySpan> finish() {
    _flush();
    // Scal sąsiednie fragmenty o tym samym stylu, ogranicz puste linie.
    final merged = <BodySpan>[];
    for (final s in _spans) {
      final last = merged.isEmpty ? null : merged.last;
      if (last != null &&
          last.bold == s.bold &&
          last.italic == s.italic &&
          last.link == s.link) {
        merged[merged.length - 1] = BodySpan(
          last.text + s.text,
          bold: s.bold,
          italic: s.italic,
          link: s.link,
        );
      } else {
        merged.add(s);
      }
    }
    final result = <BodySpan>[];
    for (final s in merged) {
      final text = s.text
          .replaceAll(RegExp(r' *\n *'), '\n')
          .replaceAll(RegExp(r'\n{3,}'), '\n\n');
      result.add(BodySpan(text, bold: s.bold, italic: s.italic, link: s.link));
    }
    if (result.isNotEmpty) {
      final first = result.first;
      result[0] = BodySpan(
        first.text.replaceFirst(RegExp(r'^\s+'), ''),
        bold: first.bold,
        italic: first.italic,
        link: first.link,
      );
      final last = result.last;
      result[result.length - 1] = BodySpan(
        last.text.replaceFirst(RegExp(r'\s+$'), ''),
        bold: last.bold,
        italic: last.italic,
        link: last.link,
      );
    }
    return result.where((s) => s.text.isNotEmpty).toList();
  }
}
