import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FavoritesService {
  FavoritesService._privateConstructor();
  static final FavoritesService instance =
      FavoritesService._privateConstructor();

  static const String _prefKey = 'favorite_ingredient_names';

  final Set<String> _favorites = <String>{};
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  bool _initialized = false;

  Set<String> get favorites => Set<String>.unmodifiable(_favorites);
  int get count => _favorites.length;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList(_prefKey) ?? <String>[];
      _favorites.clear();
      _favorites.addAll(list);
      _notify();
    } catch (e) {
      debugPrint('FavoritesService init error: $e');
    }
  }

  bool isFavorite(String name) {
    return _favorites.contains(name);
  }

  Future<bool> toggle(String name) async {
    if (isFavorite(name)) {
      await remove(name);
      return false;
    } else {
      await add(name);
      return true;
    }
  }

  Future<void> add(String name) async {
    if (_favorites.add(name)) {
      await _save();
      _notify();
    }
  }

  Future<void> remove(String name) async {
    if (_favorites.remove(name)) {
      await _save();
      _notify();
    }
  }

  Future<void> clear() async {
    if (_favorites.isNotEmpty) {
      _favorites.clear();
      await _save();
      _notify();
    }
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_prefKey, _favorites.toList());
    } catch (e) {
      debugPrint('FavoritesService save error: $e');
    }
  }

  void _notify() {
    revision.value++;
  }
}
