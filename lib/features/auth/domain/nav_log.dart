import 'package:flutter/foundation.dart';

import 'login_flow.dart';

/// Zdarzenie nawigacji WebView. Zawiera wyłącznie host i znormalizowaną
/// ścieżkę (bez zapytania), nazwę callbacku, ramkę, decyzję i kody błędów —
/// nigdy treści formularzy, ciasteczek, nagłówków ani parametrów OAuth.
class NavEvent {
  NavEvent(
    this.callback,
    Uri? url, {
    this.mainFrame,
    this.decision,
    this.status,
    this.detail,
    DateTime? at,
  }) : location = safeLocation(url),
       at = at ?? DateTime.now();

  final DateTime at;
  final String callback;
  final String location;
  final bool? mainFrame;
  final String? decision;
  final int? status;

  /// Wyłącznie wartości kontrolowane przez aplikację (np. typ błędu, akcja).
  final String? detail;

  @override
  String toString() {
    final t = at.toIso8601String().substring(11, 23);
    final frame = switch (mainFrame) {
      true => 'main',
      false => 'sub',
      null => '-',
    };
    return [
      t,
      callback,
      frame,
      location,
      ?decision,
      if (status != null) 'HTTP $status',
      ?detail,
    ].join(' | ');
  }
}

/// Bufor zdarzeń ekranu logowania; w buildach debug także do logcat
/// (`adb logcat -s flutter`, prefiks `[SynergiaNav]`).
class NavLog {
  NavLog({this.capacity = 300, this.echo = kDebugMode});

  final int capacity;
  final bool echo;
  final _events = <NavEvent>[];

  List<NavEvent> get events => List.unmodifiable(_events);

  void add(NavEvent e) {
    if (_events.length >= capacity) _events.removeAt(0);
    _events.add(e);
    if (echo) debugPrint('[SynergiaNav] $e');
  }

  String toText() => _events.join('\n');
}
