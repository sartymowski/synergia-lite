import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../data/excuse_submitter.dart';
import '../data/excuses_repository.dart';
import '../domain/excuse.dart';

final excusesRepositoryProvider = Provider<ExcusesRepository>(
  (ref) => ExcusesRepository(ref.watch(apiClientProvider)),
);

/// Historia tylko w pamięci (bez trwałego cache) — znika przy wylogowaniu.
final excusesProvider = FutureProvider.autoDispose<List<ExcuseRequest>>(
  (ref) =>
      guardSession(ref, () => ref.watch(excusesRepositoryProvider).fetchAll()),
);

/// Wynik porównania historii przed i po wizycie w oficjalnym module.
sealed class SubmissionCheck {
  const SubmissionCheck();
}

/// Pojawiły się nowe zgłoszenia (identyfikatory nieobecne wcześniej).
final class NewExcusesFound extends SubmissionCheck {
  const NewExcusesFound(this.newOnes);

  final List<ExcuseRequest> newOnes;
}

/// Historii nie udało się porównać albo nic nowego nie widać.
final class NoNewExcuses extends SubmissionCheck {
  const NoNewExcuses();
}

SubmissionCheck compareHistory(
  List<ExcuseRequest> before,
  List<ExcuseRequest> after,
) {
  final known = before.map((e) => e.id).toSet();
  final added = after.where((e) => !known.contains(e.id)).toList();
  return added.isEmpty ? const NoNewExcuses() : NewExcusesFound(added);
}

final excuseSubmitterProvider = Provider<ExcuseSubmitter>(
  (ref) => ExcuseSubmitter(
    ref.watch(apiClientProvider),
    ref.watch(excusesRepositoryProvider),
  ),
);
