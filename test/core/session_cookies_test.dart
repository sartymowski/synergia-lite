import 'package:flutter_test/flutter_test.dart';
import 'package:synergia_lite/core/network/session_cookies.dart';

void main() {
  final base = SessionCookies({'DZIENNIKSID': 'a1', 'oauth_token': 't1'});

  test('buduje nagłówek Cookie', () {
    expect(base.toHeader(), 'DZIENNIKSID=a1; oauth_token=t1');
    expect(base.hasAuthMarker, isTrue);
  });

  test('toString nie ujawnia wartości', () {
    expect(base.toString(), isNot(contains('a1')));
    expect(base.toString(), isNot(contains('t1')));
    expect(base.toString(), contains('DZIENNIKSID'));
  });

  test('merge uwzględnia rotację i usuwanie ciasteczek', () {
    final next = base.merge([
      'DZIENNIKSID=b2; path=/; secure; HttpOnly',
      'oauth_token=deleted; expires=Thu, 01 Jan 1970 00:00:01 GMT',
      'SDZIENNIKSID=c3; Max-Age=3600',
      'zly-naglowek',
    ]);
    expect(next.toHeader(), 'DZIENNIKSID=b2; SDZIENNIKSID=c3');
    expect(next.hasAuthMarker, isFalse);
    expect(next.obtainedAt, base.obtainedAt);
  });

  test('merge zwraca ten sam obiekt, gdy nic się nie zmienia', () {
    expect(identical(base.merge(['DZIENNIKSID=a1; path=/']), base), isTrue);
    expect(identical(base.merge(['other=x; Max-Age=0']), base), isTrue);
  });

  test('przeterminowane Expires usuwa ciasteczko', () {
    final next = base.merge([
      'oauth_token=t2; Expires=Thu, 01 Jan 2015 00:00:00 GMT; Path=/',
    ]);
    expect(next.names, ['DZIENNIKSID']);
  });

  test('Expires w przyszłości aktualizuje wartość', () {
    final next = base.merge([
      'oauth_token=t2; Expires=Fri, 01 Jan 2100 00:00:00 GMT; Path=/',
    ]);
    expect(next.toHeader(), 'DZIENNIKSID=a1; oauth_token=t2');
  });

  test('ciasteczko dla obcej domeny jest ignorowane', () {
    final next = base.merge([
      'DZIENNIKSID=zly; Domain=api.librus.pl',
      'X=1; Domain=example.com',
      'Y=2; Domain=.librus.pl',
    ]);
    expect(next.toHeader(), 'DZIENNIKSID=a1; oauth_token=t1; Y=2');
  });

  test('serializacja JSON w obie strony', () {
    final restored = SessionCookies.tryFromJson(base.toJson())!;
    expect(restored.toHeader(), base.toHeader());
    expect(
      restored.obtainedAt.millisecondsSinceEpoch,
      base.obtainedAt.millisecondsSinceEpoch,
    );
  });

  test('uszkodzony zapis daje null zamiast wyjątku', () {
    expect(SessionCookies.tryFromJson(null), isNull);
    expect(SessionCookies.tryFromJson('{nie json'), isNull);
    expect(SessionCookies.tryFromJson('{"cookies": 5}'), isNull);
  });
}
