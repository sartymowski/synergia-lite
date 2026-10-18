import 'package:flutter_test/flutter_test.dart';
import 'package:synergia_lite/features/auth/data/webview_session.dart';
import 'package:synergia_lite/features/auth/domain/account_info.dart';

void main() {
  // Zmiana 2026-10-18: formularz Synergii działa tylko w iframe portalu
  // (redirectToPortalIfNotInIframe), więc start to strona portalu.
  test('adres startowy to strona główna portalu Librus Rodzina', () {
    expect(loginStartUri().toString(), 'https://portal.librus.pl/rodzina');
  });

  group('isAllowedMainFrame', () {
    final allowed = [
      'https://synergia.librus.pl/loguj/portalRodzina',
      'https://api.librus.pl/OAuth/Authorization?client_id=46',
      'https://portal.librus.pl/rodzina',
      'about:blank',
    ];
    final blocked = [
      'http://api.librus.pl/OAuth/Authorization',
      'https://librus.pl.evil.example/',
      'https://evillibrus.pl/',
      'https://challenges.cloudflare.com/turnstile',
      'intent://x#Intent;end',
      'file:///sdcard/x',
      'javascript:alert(1)',
    ];
    for (final u in allowed) {
      test(
        'dozwolone: $u',
        () => expect(isAllowedMainFrame(Uri.parse(u)), isTrue),
      );
    }
    for (final u in blocked) {
      test(
        'zablokowane: $u',
        () => expect(isAllowedMainFrame(Uri.parse(u)), isFalse),
      );
    }
  });

  group('isPostLoginUrl', () {
    test('strona główna rodzica i ucznia', () {
      expect(
        isPostLoginUrl(Uri.parse('https://synergia.librus.pl/rodzic/index')),
        isTrue,
      );
      expect(
        isPostLoginUrl(Uri.parse('https://synergia.librus.pl/uczen/index')),
        isTrue,
      );
    });
    test('powrót OAuth z code/state to jeszcze nie koniec', () {
      expect(
        isPostLoginUrl(
          Uri.parse(
            'https://synergia.librus.pl/loguj/portalRodzina?code=a&state=b',
          ),
        ),
        isFalse,
      );
    });
    test('inne hosty, wylogowanie, http, null', () {
      expect(
        isPostLoginUrl(
          Uri.parse('https://api.librus.pl/OAuth/Authorization/Grant'),
        ),
        isFalse,
      );
      expect(
        isPostLoginUrl(Uri.parse('https://synergia.librus.pl/wyloguj')),
        isFalse,
      );
      expect(
        isPostLoginUrl(Uri.parse('http://synergia.librus.pl/rodzic/index')),
        isFalse,
      );
      expect(isPostLoginUrl(null), isFalse);
    });
  });

  test('redactUrl usuwa code, state i fragment', () {
    expect(
      redactUrl(
        Uri.parse(
          'https://synergia.librus.pl/loguj/portalRodzina?code=SEKRET&state=S2#x',
        ),
      ),
      'https://synergia.librus.pl/loguj/portalRodzina',
    );
  });

  group('AccountInfo.tryParse', () {
    test('wymaga obiektu konta', () {
      expect(AccountInfo.tryParse({'Me': {}}), isNull);
      expect(
        AccountInfo.tryParse({
          'Me': {'Account': 'x'},
        }),
        isNull,
      );
      expect(AccountInfo.tryParse({'Other': {}}), isNull);
    });
    test('wystarczy Account albo User', () {
      expect(
        AccountInfo.tryParse({
          'Me': {'Account': {}},
        }),
        isNotNull,
      );
      expect(
        AccountInfo.tryParse({
          'Me': {
            'User': {'FirstName': 'Ola'},
          },
        })!.studentFirstName,
        'Ola',
      );
    });
  });
}
