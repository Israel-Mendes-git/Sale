import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ui/palettes.dart';

/// Onde ficam as preferências de quem usa o aparelho (não vão para o
/// servidor: cada celular pode ter a sua cara).
abstract interface class SettingsStore {
  String? read(String key);
  Future<void> write(String key, String value);
}

/// Usada nos testes e enquanto o app não abriu o armazenamento do sistema.
class MemorySettingsStore implements SettingsStore {
  final _values = <String, String>{};

  @override
  String? read(String key) => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;
}

class PrefsSettingsStore implements SettingsStore {
  PrefsSettingsStore(this._prefs);

  final SharedPreferences _prefs;

  static Future<PrefsSettingsStore> open() async =>
      PrefsSettingsStore(await SharedPreferences.getInstance());

  @override
  String? read(String key) => _prefs.getString(key);

  @override
  Future<void> write(String key, String value) => _prefs.setString(key, value);
}

final settingsStoreProvider = Provider<SettingsStore>(
  (ref) => MemorySettingsStore(),
);

/// Tema escolhido e claro/escuro.
@immutable
class Appearance {
  const Appearance({required this.palette, required this.mode});

  final Palette palette;
  final ThemeMode mode;
}

final appearanceProvider = NotifierProvider<AppearanceChoice, Appearance>(
  AppearanceChoice.new,
);

class AppearanceChoice extends Notifier<Appearance> {
  static const _paletteKey = 'aparencia.tema';
  static const _modeKey = 'aparencia.modo';

  @override
  Appearance build() {
    final store = ref.watch(settingsStoreProvider);
    return Appearance(
      palette: paletteById(store.read(_paletteKey) ?? defaultPaletteId),
      mode: switch (store.read(_modeKey)) {
        'claro' => ThemeMode.light,
        'escuro' => ThemeMode.dark,
        _ => ThemeMode.system,
      },
    );
  }

  Future<void> choosePalette(Palette palette) async {
    state = Appearance(palette: palette, mode: state.mode);
    await ref.read(settingsStoreProvider).write(_paletteKey, palette.id);
  }

  Future<void> chooseMode(ThemeMode mode) async {
    state = Appearance(palette: state.palette, mode: mode);
    await ref.read(settingsStoreProvider).write(_modeKey, switch (mode) {
      ThemeMode.light => 'claro',
      ThemeMode.dark => 'escuro',
      ThemeMode.system => 'sistema',
    });
  }
}
