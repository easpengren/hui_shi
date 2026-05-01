import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/book.dart';

class LibraryService {
  static const _key = 'lu_ji_library';

  Future<List<LibraryEntry>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_key);
    if (jsonStr == null) return [];
    final list = json.decode(jsonStr) as List<dynamic>;
    return list
        .map((e) => LibraryEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> save(LibraryEntry entry) async {
    final entries = await loadAll();
    final idx = entries.indexWhere((e) => e.id == entry.id);
    if (idx >= 0) {
      entries[idx] = entry;
    } else {
      entries.insert(0, entry);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      json.encode(entries.map((e) => e.toJson()).toList()),
    );
  }

  Future<void> remove(String id) async {
    final entries = await loadAll();
    entries.removeWhere((e) => e.id == id);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      json.encode(entries.map((e) => e.toJson()).toList()),
    );
  }
}
