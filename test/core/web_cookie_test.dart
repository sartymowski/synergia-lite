import 'package:flutter_test/flutter_test.dart';
import 'package:synergia_lite/core/network/session_cookies.dart';
import 'package:synergia_lite/core/network/web_cookie.dart';

void main() {
  test('pełne atrybuty z getCookieInfo', () {
    final c = WebCookie.parse(
      'oauth_token=SEKRET; Domain=synergia.librus.pl; Path=/; '
      'Expires=Sun, 18 Oct 2026 11:01:14 GMT; Secure; HttpOnly; SameSite=Lax',
    )!;
    expect(c.name, 'oauth_token');
    expect(c.value, 'SEKRET');
    expect(c.domain, 'synergia.librus.pl');
    expect(c.path, '/');
    expect(c.secure, isTrue);
    expect(c.httpOnly, isTrue);
    expect(c.sameSite, 'Lax');
    expect(c.expires, DateTime.utc(2026, 10, 18, 11, 1, 14));
    expect(c.isSession, isFalse);
  });

  test('ciasteczko sesyjne', () {
    final c = WebCookie.parse('DZIENNIKSID=x; Path=/; Secure; HttpOnly')!;
    expect(c.isSession, isTrue);
  });

  test('stary WebView: tylko nazwa=wartość, atrybuty nieznane', () {
    final c = WebCookie.parse('DZIENNIKSID=a=b')!;
    expect(c.value, 'a=b');
    expect(c.attributesKnown, isFalse);
    expect(c.secure, isNull);
    expect(c.isSession, isNull);
  });

  test('wartość nigdy nie trafia do describe() ani toString()', () {
    final c = WebCookie.parse('oauth_token=SEKRET123; Path=/; Secure')!;
    expect(c.describe(), isNot(contains('SEKRET123')));
    expect(c.toString(), isNot(contains('SEKRET123')));
    expect(c.describe(), contains('oauth_token'));
  });

  test('błędny wpis i niepoprawna data', () {
    expect(WebCookie.parse('bez-rownosci'), isNull);
    expect(WebCookie.parse('=x'), isNull);
    expect(WebCookie.parse('a=b; Expires=jutro')!.expires, isNull);
  });

  test('SessionCookies.fromWebCookies przenosi tylko nazwy i wartości', () {
    final s = SessionCookies.fromWebCookies([
      WebCookie.parse('A=1; Path=/')!,
      WebCookie.parse('B=2')!,
    ]);
    expect(s.toHeader(), 'A=1; B=2');
  });
}
