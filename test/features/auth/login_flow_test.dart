import 'package:flutter_test/flutter_test.dart';
import 'package:synergia_lite/features/auth/domain/login_flow.dart';
import 'package:synergia_lite/features/auth/domain/nav_log.dart';

Uri u(String s) => Uri.parse(s);

void main() {
  late DateTime now;
  late LoginFlow flow;

  setUp(() {
    now = DateTime(2026, 10, 18, 12);
    flow = LoginFlow(clock: () => now);
  });

  group('przekierowania głównej ramki', () {
    test('pełny łańcuch między domenami Librusa jest dozwolony', () {
      for (final url in [
        'https://portal.librus.pl/rodzina',
        'https://portal.librus.pl/rodzina/synergia/loguj',
        'https://synergia.librus.pl/loguj/portalRodzina?v=1',
        'https://api.librus.pl/OAuth/Authorization?client_id=46&state=x',
        'https://api.librus.pl/OAuth/Authorization/2FA?client_id=46',
        'https://api.librus.pl/OAuth/Authorization/Grant?client_id=46',
        'https://synergia.librus.pl/loguj/portalRodzina?code=c&state=s',
      ]) {
        expect(flow.onMainFrameStarted(u(url)), PageAction.none, reason: url);
        expect(flow.onMainFrameFinished(u(url)), PageAction.none, reason: url);
      }
    });

    test('obca strona lub http w głównej ramce jest zamykana', () {
      for (final url in [
        'https://example.com/',
        'http://portal.librus.pl/rodzina',
        'https://librus.pl.evil.example/',
        'https://challenges.cloudflare.com/x',
      ]) {
        expect(
          flow.onMainFrameStarted(u(url)),
          PageAction.leaveForbidden,
          reason: url,
        );
        expect(
          flow.onMainFrameFinished(u(url)),
          PageAction.leaveForbidden,
          reason: url,
        );
        expect(
          flow.onUrlChange(u(url)),
          PageAction.leaveForbidden,
          reason: url,
        );
      }
    });

    test(
      'nowe okno (window.open / target=_blank) trafia do głównej ramki i podlega tym samym zasadom',
      () {
        // webview_flutter_android ładuje URL nowego okna w tym samym WebView.
        expect(
          flow.onMainFrameStarted(u('https://www.facebook.com/librus')),
          PageAction.leaveForbidden,
        );
        expect(
          flow.onMainFrameStarted(u('https://www.librus.pl/szkoly/')),
          PageAction.none,
        );
      },
    );

    test('formularz OAuth poza ramką jest rozpoznawany (do logu)', () {
      expect(
        isOAuthFormOutsideFrame(
          u('https://api.librus.pl/OAuth/Authorization?client_id=46'),
        ),
        isTrue,
      );
      expect(
        isOAuthFormOutsideFrame(
          u('https://portal.librus.pl/rodzina/synergia/loguj'),
        ),
        isFalse,
      );
    });
  });

  group('wykrywanie zakończenia logowania', () {
    test('strona Synergii po logowaniu → jedno sprawdzenie sesji', () {
      final home = u('https://synergia.librus.pl/rodzic/index');
      expect(flow.onMainFrameFinished(home), PageAction.verifySession);
      expect(
        flow.onMainFrameFinished(home),
        PageAction.none,
        reason: 'bez powtórek',
      );
      expect(flow.onUrlChange(home), PageAction.none);
    });

    test('kroki OAuth i powrót z code/state nie są zakończeniem', () {
      for (final url in [
        'https://synergia.librus.pl/loguj/portalRodzina?code=c&state=s',
        'https://api.librus.pl/OAuth/Authorization/Grant',
        'https://portal.librus.pl/rodzina/synergia/loguj',
        'https://synergia.librus.pl/gateway/api/2.0/Me',
        'https://synergia.librus.pl/wyloguj',
      ]) {
        expect(flow.onMainFrameFinished(u(url)), PageAction.none, reason: url);
      }
    });

    test(
      'zmiana adresu (history API) na Synergię też uruchamia sprawdzenie',
      () {
        expect(
          flow.onUrlChange(u('https://synergia.librus.pl/uczen/index')),
          PageAction.verifySession,
        );
      },
    );

    test('ciasteczko sesji: tylko pojawienie się lub zmiana', () {
      expect(flow.shouldVerifyForCookie(null), isFalse);
      expect(flow.shouldVerifyForCookie('a1'), isTrue);
      expect(flow.shouldVerifyForCookie('a1'), isFalse);
      expect(flow.shouldVerifyForCookie('b2'), isTrue);
      flow.allowVerifyAgain();
      expect(
        flow.shouldVerifyForCookie('b2'),
        isTrue,
        reason: 'ręczne sprawdzenie',
      );
    });
  });

  group('zapobieganie pętlom', () {
    final portal = u('https://portal.librus.pl/rodzina');

    test('portal odsyłający w kółko na /rodzina zatrzymuje automatykę', () {
      expect(flow.onMainFrameFinished(portal), PageAction.none);
      expect(flow.onMainFrameFinished(portal), PageAction.none);
      expect(flow.onMainFrameFinished(portal), PageAction.none);
      expect(flow.onMainFrameFinished(portal), PageAction.stopLoop);
      expect(flow.loopDetected, isTrue);
      // Po wykryciu pętli: żadnych sprawdzeń ani reakcji.
      expect(
        flow.onMainFrameFinished(u('https://synergia.librus.pl/rodzic/index')),
        PageAction.none,
      );
      expect(flow.shouldVerifyForCookie('x'), isFalse);
    });

    test(
      'pętla z zapytaniem w adresie jest rozpoznawana mimo różnych parametrów',
      () {
        for (var i = 0; i < 3; i++) {
          expect(
            flow.onMainFrameFinished(
              u('https://portal.librus.pl/rodzina?t=$i'),
            ),
            PageAction.none,
          );
        }
        expect(
          flow.onMainFrameFinished(u('https://portal.librus.pl/rodzina?t=9')),
          PageAction.stopLoop,
        );
      },
    );

    test('powroty rozłożone w czasie to nie pętla', () {
      for (var i = 0; i < 6; i++) {
        expect(flow.onMainFrameFinished(portal), PageAction.none);
        now = now.add(const Duration(seconds: 31));
      }
      expect(flow.loopDetected, isFalse);
    });

    test('różne strony nie sumują się', () {
      for (var i = 0; i < 3; i++) {
        flow.onMainFrameFinished(portal);
        flow.onMainFrameFinished(
          u('https://portal.librus.pl/rodzina/synergia/loguj'),
        );
      }
      expect(flow.loopDetected, isFalse);
    });

    test('„Zacznij od nowa” zeruje stan', () {
      for (var i = 0; i < 4; i++) {
        flow.onMainFrameFinished(portal);
      }
      expect(flow.loopDetected, isTrue);
      flow.reset();
      expect(flow.loopDetected, isFalse);
      expect(
        flow.onMainFrameFinished(u('https://synergia.librus.pl/rodzic/index')),
        PageAction.verifySession,
      );
    });
  });

  group('bezpieczne logi', () {
    test('safeLocation usuwa zapytanie i maskuje identyfikatory', () {
      expect(
        safeLocation(
          u(
            'https://synergia.librus.pl/loguj/portalRodzina?code=SEKRET&state=S#f',
          ),
        ),
        'synergia.librus.pl/loguj/portalRodzina',
      );
      expect(
        safeLocation(u('https://synergia.librus.pl/wiadomosci/1/5/123456/f0')),
        'synergia.librus.pl/wiadomosci/1/5/:id/f0',
      );
      expect(
        safeLocation(u('https://api.librus.pl/x/${'a' * 40}')),
        'api.librus.pl/x/:id',
      );
      expect(safeLocation(u('javascript:alert(1)')), 'javascript:…');
      expect(safeLocation(u('intent://x#Intent;end')), 'intent:…');
      expect(safeLocation(null), '(brak adresu)');
    });

    test('NavEvent i NavLog nie zawierają parametrów OAuth', () {
      final log = NavLog(echo: false);
      log.add(
        NavEvent(
          'onPageStarted',
          u(
            'https://synergia.librus.pl/loguj/portalRodzina?code=SEKRET1&state=SEKRET2',
          ),
          mainFrame: true,
          decision: 'ALLOW',
          at: DateTime(2026, 10, 18, 12, 0, 1),
        ),
      );
      log.add(
        NavEvent(
          'onHttpError',
          u('https://api.librus.pl/OAuth/Authorization?pass=SEKRET3'),
          status: 403,
        ),
      );
      final text = log.toText();
      expect(text, isNot(contains('SEKRET')));
      expect(
        text,
        contains(
          'onPageStarted | main | synergia.librus.pl/loguj/portalRodzina | ALLOW',
        ),
      );
      expect(text, contains('HTTP 403'));
    });

    test('bufor logu ma ograniczoną pojemność', () {
      final log = NavLog(capacity: 3, echo: false);
      for (var i = 0; i < 5; i++) {
        log.add(NavEvent('e$i', null));
      }
      expect(log.events.map((e) => e.callback), ['e2', 'e3', 'e4']);
    });
  });
}
