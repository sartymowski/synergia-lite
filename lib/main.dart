import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';

void main() {
  runApp(
    // Bez automatycznych ponowień: odświeżanie tylko na żądanie użytkownika,
    // żeby nie generować zbędnego ruchu do Synergii.
    ProviderScope(retry: (_, _) => null, child: const SynergiaLiteApp()),
  );
}
