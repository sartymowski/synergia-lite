import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:synergia_lite/core/network/session_cookies.dart';
import 'package:synergia_lite/core/security/session_store.dart';
import 'package:synergia_lite/features/messages/data/messages_api_client.dart';

import 'fake_http.dart';

/// Fikcyjne dane — żadnych prawdziwych wiadomości ani osób.
String b64(String s) => base64.encode(utf8.encode(s));

String fullMessage(String html) =>
    b64('<Message><Content><![CDATA[$html]]></Content></Message>');

Map<String, Object?> inboxItem(
  String id, {
  String sender = 'Ewa Przykładowa',
  String topic = 'Temat testowy',
  String content = 'Podgląd treści',
  String? readDate = '2026-10-10 08:00:00',
  bool attachment = false,
}) => {
  'messageId': id,
  'senderFirstName': sender.split(' ').first,
  'senderLastName': sender.split(' ').last,
  'senderName': sender,
  'topic': topic,
  'content': b64(content),
  'sendDate': '2026-10-09 12:30:00',
  'readDate': readDate,
  'isAnyFileAttached': attachment,
  'tags': <String>[],
  'category': null,
};

Map<String, Object?> outboxItem(String id, {String receiver = 'Jan Testowy'}) =>
    {
      'messageId': id,
      'receiverFirstName': receiver.split(' ').first,
      'receiverLastName': receiver.split(' ').last,
      'receiverName': receiver,
      'topic': 'Wysłany temat',
      'content': b64('Treść wysłana'),
      'sendDate': '2026-10-08 09:00:00',
      'isAnyFileAttached': false,
    };

ResponseBody redirect(String location, {List<String> setCookie = const []}) =>
    ResponseBody.fromString(
      '',
      302,
      headers: {
        'location': [location],
        if (setCookie.isNotEmpty) 'set-cookie': setCookie,
      },
    );

/// Odpowiedzi serwisu: domyślnie poprawna inicjalizacja przez wiadomosci3,
/// dalej [api] dla `wiadomosci.librus.pl/api/...` (klucz: ścieżka po `/api/`).
class FakeMessagesServer {
  FakeMessagesServer({this.api = const {}, this.bootstrap});

  final Map<String, FutureOr<ResponseBody> Function(RequestOptions)> api;
  final ResponseBody Function(RequestOptions)? bootstrap;
  final calls = <String>[];
  int bootstraps = 0;

  FutureOr<ResponseBody> handle(RequestOptions o) {
    final u = o.uri;
    calls.add('${o.method} ${u.host}${u.path}');
    if (u.host == 'synergia.librus.pl' && u.path == '/wiadomosci3') {
      bootstraps++;
      return bootstrap?.call(o) ??
          redirect(
            'https://wiadomosci.librus.pl/MultiDomainLogon?token=JEDNORAZOWY',
          );
    }
    if (u.host == 'wiadomosci.librus.pl' && u.path == '/MultiDomainLogon') {
      return redirect(
        '/module/inbox',
        setCookie: ['WIADSID=w$bootstraps; path=/; secure; HttpOnly'],
      );
    }
    if (u.host == 'wiadomosci.librus.pl' && u.path == '/module/inbox') {
      return textBody('<html>wiadomości</html>');
    }
    if (u.host == 'wiadomosci.librus.pl' && u.path.startsWith('/api/')) {
      final key = u.path.substring('/api/'.length);
      final route = api[key];
      if (route != null) return route(o);
    }
    return jsonBody({}, status: 404);
  }
}

({MessagesApiClient client, FakeAdapter adapter, InMemorySessionStore store})
fakeMessagesClient(
  FakeMessagesServer server, {
  void Function()? onSynergiaCookiesChanged,
}) {
  final adapter = FakeAdapter(server.handle);
  final store = InMemorySessionStore(
    SessionCookies({'DZIENNIKSID': 'syn1', 'oauth_token': 'tok'}),
  );
  final client = MessagesApiClient(
    synergiaSession: store,
    dio: fakeDio(adapter),
    minInterval: Duration.zero,
    onSynergiaCookiesChanged: onSynergiaCookiesChanged,
  );
  return (client: client, adapter: adapter, store: store);
}
