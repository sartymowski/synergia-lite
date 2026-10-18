import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:synergia_lite/features/messages/domain/message_body.dart';

import '../../helpers/messages_fakes.dart';

void main() {
  group('decodeMessageContent', () {
    test('zwykły base64 UTF-8 z polskimi znakami', () {
      expect(
        decodeMessageContent(b64('Zażółć gęślą jaźń')),
        'Zażółć gęślą jaźń',
      );
    });

    test('pełna wiadomość w XML/CDATA', () {
      expect(
        decodeMessageContent(fullMessage('<p>Dzień dobry</p>')),
        '<p>Dzień dobry</p>',
      );
    });

    test('podgląd ucięty w środku znaku wielobajtowego nie zgłasza błędu', () {
      final bytes = utf8.encode('Uwaga: ą');
      final cut = base64.encode(bytes.sublist(0, bytes.length - 1));
      expect(decodeMessageContent(cut), startsWith('Uwaga: '));
    });

    test('brak paddingu, białe znaki, puste i niepoprawne wartości', () {
      expect(decodeMessageContent(b64('ab').replaceAll('=', '')), 'ab');
      expect(decodeMessageContent(' ${b64('x')}\n'), 'x');
      expect(decodeMessageContent(null), '');
      expect(decodeMessageContent(''), '');
      expect(decodeMessageContent('%%%niebase64%%%'), '');
    });
  });

  group('htmlToSpans — bezpieczne renderowanie', () {
    String text(String html) => htmlToPlainText(html);

    test('zwykły tekst z nowymi liniami zachowuje podział', () {
      expect(text('Linia 1\nLinia 2'), 'Linia 1\nLinia 2');
    });

    test('br, akapity i listy', () {
      expect(text('a<br>b<br/>c'), 'a\nb\nc');
      expect(text('<p>Pierwszy</p><p>Drugi</p>'), 'Pierwszy\nDrugi');
      expect(text('<ul><li>jeden</li><li>dwa</li></ul>'), '• jeden\n• dwa');
    });

    test('pogrubienie, kursywa i odnośnik jako osobne fragmenty', () {
      final spans = htmlToSpans(
        'Zwykły <b>gruby</b> <i>pochyły</i> <a href="https://liblink.pl/abc">link</a>',
      );
      expect(spans.firstWhere((s) => s.text == 'gruby').bold, isTrue);
      expect(spans.firstWhere((s) => s.text == 'pochyły').italic, isTrue);
      expect(
        spans.firstWhere((s) => s.text == 'link').link,
        'https://liblink.pl/abc',
      );
    });

    test('skrypty, style, iframe i formularze nie trafiają do treści', () {
      final out = text(
        '<script>alert("x")</script><style>p{color:red}</style>'
        '<iframe src="https://evil.example"></iframe><form><input value="x"></form>Treść',
      );
      expect(out, 'Treść');
    });

    test('obrazy nie są ładowane; piksele śledzące znikają', () {
      expect(
        text(
          '<img src="https://tracker.example/p.gif" width="1" height="1">Tekst',
        ),
        'Tekst',
      );
      expect(
        text('<img src="https://cdn.example/a.png" alt="Plan">'),
        '[obraz: Plan]',
      );
      expect(text('<img src="https://cdn.example/a.png">'), '[obraz]');
    });

    test('odnośniki javascript: nie są traktowane jako link', () {
      final spans = htmlToSpans('<a href="javascript:alert(1)">kliknij</a>');
      expect(spans.single.link, isNull);
    });

    test('encje HTML i nadmiar spacji', () {
      expect(text('A &amp; B &lt;3&gt;   C'), 'A & B <3> C');
      expect(text('<p>x</p>\n\n\n\n<p>y</p>'), 'x\ny');
    });

    test('podgląd jest jednowierszowy i skrócony', () {
      expect(previewText('<p>Ala</p><p>ma kota</p>'), 'Ala ma kota');
      expect(previewText('x' * 300, max: 10), 'xxxxxxxxxx…');
    });
  });
}
