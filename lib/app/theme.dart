import 'package:flutter/material.dart';

const _seed = Color(0xFF2E6BD8);

ThemeData buildTheme(Brightness brightness) => ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(seedColor: _seed, brightness: brightness),
);
