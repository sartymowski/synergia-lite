import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// Adapter HTTP dla Dio bez sieci: odpowiedzi definiuje test.
class FakeAdapter implements HttpClientAdapter {
  FakeAdapter(this.handler);

  final FutureOr<ResponseBody> Function(RequestOptions options) handler;
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody jsonBody(
  Object json, {
  int status = 200,
  Map<String, List<String>> headers = const {},
}) => ResponseBody.fromString(
  jsonEncode(json),
  status,
  headers: {
    Headers.contentTypeHeader: ['application/json'],
    ...headers,
  },
);

ResponseBody textBody(String text, {int status = 200}) =>
    ResponseBody.fromString(
      text,
      status,
      headers: {
        Headers.contentTypeHeader: ['text/html; charset=utf-8'],
      },
    );

Dio fakeDio(FakeAdapter adapter) => Dio()..httpClientAdapter = adapter;

Map<String, dynamic> fixture(String name) =>
    jsonDecode(File('test/fixtures/$name').readAsStringSync())
        as Map<String, dynamic>;
