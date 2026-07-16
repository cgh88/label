import 'dart:convert';
import 'dart:io' show File;
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'ssh_sync_service.dart';
import '../models/models.dart';

class DatabaseService {
  static final DatabaseService instance = DatabaseService._();
  DatabaseService._();

  dynamic _localFile;
  Map<String, dynamic> _dbData = {};

  List<AppCategory> categories = [];
  List<StorageLocation> locations = [];
  List<LabelSizePreset> presets = [];
  List<Ingredient> ingredients = [];
  List<Map<String, dynamic>> users = [];
  List<Map<String, dynamic>> printLogs = [];
  String lastUpdated = "";

  Future<void> init() async {
    if (kIsWeb) {
      await loadLocalDatabase();
    } else {
      final directory = await getApplicationSupportDirectory();
      _localFile = File('${directory.path}/local_database.json');
      if (!await (_localFile as File).parent.exists()) {
        await (_localFile as File).parent.create(recursive: true);
      }
      await loadLocalDatabase();
    }
  }

  Future<void> loadLocalDatabase() async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      final content = prefs.getString('web_local_database');
      if (content == null || content.isEmpty) {
        _dbData = await _getDefaultData();
        await save();
      } else {
        try {
          _dbData = jsonDecode(content) as Map<String, dynamic>;
        } catch (e) {
          _dbData = await _getDefaultData();
          await save();
        }
      }
    } else {
      final file = _localFile as File;
      if (!await file.exists()) {
        _dbData = await _getDefaultData();
        await save();
      } else {
        try {
          final content = await file.readAsString();
          _dbData = jsonDecode(content) as Map<String, dynamic>;
        } catch (e) {
          _dbData = await _getDefaultData();
          await save();
        }
      }
    }
    
    // Parse loaded/initialized database data
    _parseData();

    // If parsing results in empty lists (corrupt/empty DB), re-initialize from defaults
    if (categories.isEmpty || ingredients.isEmpty) {
      _dbData = await _getDefaultData();
      _parseData();
      await save();
    }
  }

  void _parseData() {
    lastUpdated = _dbData['last_updated'] as String? ?? '';
    
    categories = (_dbData['categories'] as List? ?? [])
        .map((c) => AppCategory.fromJson(c as Map<String, dynamic>))
        .toList();

    locations = (_dbData['storage_locations'] as List? ?? [])
        .map((l) => StorageLocation.fromJson(l as Map<String, dynamic>))
        .toList();

    presets = (_dbData['label_sizes'] as List? ?? [])
        .map((p) => LabelSizePreset.fromJson(p as Map<String, dynamic>))
        .toList();

    final rawIngList = _dbData['ingredients_v2'] as List? ?? [];
    final rawStorageMappings = _dbData['ingredient_storage'] as List? ?? [];

    ingredients = rawIngList.map((i) {
      final ingMap = Map<String, dynamic>.from(i as Map);
      final name = ingMap['name'] as String;
      
      final storageMap = <String, dynamic>{};
      final mappings = rawStorageMappings.where((m) => m['ingredient_name'] == name);
      for (final mapping in mappings) {
        final m = Map<String, dynamic>.from(mapping as Map);
        final storageId = m['storage_id'] as int;
        final shelfDays = m['shelf_days'] as int;
        
        final loc = locations.firstWhere((l) => l.id == storageId, orElse: () => StorageLocation(id: -1, name: '', sortOrder: 0));
        if (loc.id != -1) {
          storageMap[loc.name] = {
            'id': storageId,
            'days': shelfDays
          };
        }
      }
      
      ingMap['storage'] = storageMap;
      return Ingredient.fromJson(ingMap);
    }).toList();

    users = List<Map<String, dynamic>>.from(_dbData['users'] ?? []);
    printLogs = List<Map<String, dynamic>>.from(_dbData['print_logs'] ?? []);
  }

  Future<void> save() async {
    _dbData['last_updated'] = DateTime.now().toUtc().toIso8601String();
    _dbData['categories'] = categories.map((c) => c.toJson()).toList();
    _dbData['storage_locations'] = locations.map((l) => l.toJson()).toList();
    _dbData['label_sizes'] = presets.map((p) => p.toJson()).toList();
    _dbData['ingredients_v2'] = ingredients.map((i) => i.toJson()).toList();
    _dbData['users'] = users;
    _dbData['print_logs'] = printLogs;
    
    final mappingList = <Map<String, dynamic>>[];
    for (final ing in ingredients) {
      ing.storage.forEach((locName, limit) {
        mappingList.add({
          'ingredient_name': ing.name,
          'storage_id': limit.id,
          'shelf_days': limit.days,
        });
      });
    }
    _dbData['ingredient_storage'] = mappingList;

    final jsonStr = jsonEncode(_dbData);

    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('web_local_database', jsonStr);
    } else {
      if (_localFile != null) {
        await (_localFile as File).writeAsString(jsonStr);
      }
    }
    lastUpdated = _dbData['last_updated'];
  }

  Future<void> replaceDatabaseContent(String jsonContent) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('web_local_database', jsonContent);
      await loadLocalDatabase();
    } else {
      if (_localFile != null) {
        await (_localFile as File).writeAsString(jsonContent);
        await loadLocalDatabase();
      }
    }
  }

  Future<String> getRawJson() async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('web_local_database') ?? '';
    } else {
      if (_localFile == null) return '';
      return await (_localFile as File).readAsString();
    }
  }

  Future<void> resetToDefaults() async {
    _dbData = await _getDefaultData();
    _parseData();
    await save();
  }

  Future<void> downloadAndResetDatabase({
    required String url,
    required void Function(double progress) onProgress,
  }) async {
    final client = http.Client();
    try {
      final request = http.Request('GET', Uri.parse(url));
      final response = await client.send(request);

      if (response.statusCode != 200) {
        throw Exception('서버가 상태 코드 ${response.statusCode}을 반환했습니다.');
      }

      final contentLength = response.contentLength ?? 0;
      int downloaded = 0;
      final bytes = <int>[];

      await for (final chunk in response.stream) {
        bytes.addAll(chunk);
        downloaded += chunk.length;
        if (contentLength > 0) {
          onProgress(downloaded / contentLength);
        } else {
          onProgress(-1.0); // Indeterminate
        }
      }

      final jsonStr = utf8.decode(bytes);
      final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;

      _dbData = {
        "last_updated": DateTime.now().toUtc().toIso8601String(),
        "users": [],
        "categories": decoded["categories"] ?? [],
        "storage_locations": decoded["storage_locations"] ?? [],
        "label_sizes": decoded["label_sizes"] ?? [],
        "ingredients_v2": decoded["ingredients_v2"] ?? [],
        "ingredient_storage": decoded["ingredient_storage"] ?? [],
      };
      
      _parseData();
      await save();
    } finally {
      client.close();
    }
  }

  Future<void> addPrintLog({
    required String ingredientName,
    required String category,
    required String abbr,
    required String storageLocation,
    required String prepDate,
    required String expireDate,
    required String staff,
    required int quantity,
  }) async {
    final newLog = {
      'id': '${DateTime.now().millisecondsSinceEpoch}-${DateTime.now().microsecondsSinceEpoch}',
      'ingredient_name': ingredientName,
      'category': category,
      'abbr': abbr,
      'storage_location': storageLocation,
      'prep_date': prepDate,
      'expire_date': expireDate,
      'staff': staff,
      'quantity': quantity,
      'timestamp': DateTime.now().toUtc().toIso8601String(),
    };

    printLogs.add(newLog);
    await save();

    // Try to send via HTTP POST to http://<host>:3000/api/print-logs
    final serverHost = SshSyncService.instance.host.isNotEmpty 
        ? SshSyncService.instance.host 
        : 'localhost';
    final serverUrl = 'http://$serverHost:3000/api/print-logs';

    try {
      final response = await http.post(
        Uri.parse(serverUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(newLog),
      );
      if (response.statusCode != 200) {
        debugPrint('HTTP Print Log failed with status: ${response.statusCode}');
      } else {
        debugPrint('HTTP Print Log success: $serverUrl');
      }
    } catch (e) {
      debugPrint('HTTP Print Log error (possibly offline): $e');
    }
  }

  Future<Map<String, dynamic>> _getDefaultData() async {
    try {
      final String response = await rootBundle.loadString('assets/json/default_database.json');
      final Map<String, dynamic> defaultData = jsonDecode(response);
      
      return {
        "last_updated": DateTime.now().toUtc().toIso8601String(),
        "users": [],
        "categories": defaultData["categories"] ?? [],
        "storage_locations": defaultData["storage_locations"] ?? [],
        "label_sizes": defaultData["label_sizes"] ?? [],
        "ingredients_v2": defaultData["ingredients_v2"] ?? [],
        "ingredient_storage": defaultData["ingredient_storage"] ?? [],
      };
    } catch (e) {
      // Fallback empty structure
      return {
        "last_updated": DateTime.now().toUtc().toIso8601String(),
        "users": [],
        "categories": [],
        "storage_locations": [],
        "label_sizes": [],
        "ingredients_v2": [],
        "ingredient_storage": [],
      };
    }
  }
}
