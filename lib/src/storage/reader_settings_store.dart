import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/reader_settings.dart';

abstract class ReaderSettingsStore {
  Future<ReaderSettings?> load();

  Future<void> save(ReaderSettings settings);
}

class SharedPreferencesReaderSettingsStore implements ReaderSettingsStore {
  const SharedPreferencesReaderSettingsStore({
    this.preferencesKey = 'bookReader.settings.v1',
  });

  final String preferencesKey;

  @override
  Future<ReaderSettings?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(preferencesKey);
    if (raw == null || raw.isEmpty) {
      return null;
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      return null;
    }
    return ReaderSettings.fromJson(decoded.cast<String, Object?>());
  }

  @override
  Future<void> save(ReaderSettings settings) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(preferencesKey, jsonEncode(settings.toJson()));
  }
}
