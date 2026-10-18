import 'dart:async';

/// Wykonuje żądania pojedynczo, z minimalnym odstępem — żeby nie obciążać
/// serwerów Librusa (regulamin §4 ust. 3c). Błąd jednego zadania nie blokuje
/// kolejnych.
class RequestQueue {
  RequestQueue({this.minInterval = const Duration(milliseconds: 300)});

  final Duration minInterval;
  Future<void> _tail = Future.value();
  DateTime? _last;

  Future<T> run<T>(Future<T> Function() task) {
    final result = _tail.then((_) async {
      final last = _last;
      if (last != null) {
        final wait = minInterval - DateTime.now().difference(last);
        if (wait > Duration.zero) await Future<void>.delayed(wait);
      }
      try {
        return await task();
      } finally {
        _last = DateTime.now();
      }
    });
    _tail = result.then<void>((_) {}, onError: (_) {});
    return result;
  }
}
