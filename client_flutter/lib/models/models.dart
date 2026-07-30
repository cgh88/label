export 'sauce_item.dart';

class AppCategory {
  final int id;
  final String name;
  final String emoji;
  final int sortOrder;

  AppCategory({
    required this.id,
    required this.name,
    required this.emoji,
    required this.sortOrder,
  });

  factory AppCategory.fromJson(Map<String, dynamic> json) {
    return AppCategory(
      id: json['id'] as int,
      name: json['name'] as String,
      emoji: json['emoji'] as String? ?? '',
      sortOrder: json['sort_order'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'emoji': emoji,
        'sort_order': sortOrder,
      };
}

class StorageLocation {
  final int id;
  final String name;
  final int sortOrder;

  StorageLocation({
    required this.id,
    required this.name,
    required this.sortOrder,
  });

  factory StorageLocation.fromJson(Map<String, dynamic> json) {
    return StorageLocation(
      id: json['id'] as int,
      name: json['name'] as String,
      sortOrder: json['sort_order'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'sort_order': sortOrder,
      };
}

class LabelSizePreset {
  final int id;
  final int width;
  final int height;
  final int isDefault;

  LabelSizePreset({
    required this.id,
    required this.width,
    required this.height,
    required this.isDefault,
  });

  factory LabelSizePreset.fromJson(Map<String, dynamic> json) {
    return LabelSizePreset(
      id: json['id'] as int,
      width: json['width'] as int,
      height: json['height'] as int,
      isDefault: json['is_default'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'width': width,
        'height': height,
        'is_default': isDefault,
      };
}

class IngredientStorageLimit {
  final int id;
  final int days; // Stored as 'days' for DB schema but represents hours/days in UI

  IngredientStorageLimit({
    required this.id,
    required this.days,
  });

  factory IngredientStorageLimit.fromJson(Map<String, dynamic> json) {
    return IngredientStorageLimit(
      id: json['id'] as int,
      days: json['days'] as int,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'days': days,
      };
}

class Ingredient {
  final String name;
  final String category;
  final String abbr;
  final bool isSauce;
  final int sortOrder;
  final Map<String, IngredientStorageLimit> storage; // key: storage location name, value: limit config

  Ingredient({
    required this.name,
    required this.category,
    required this.abbr,
    this.isSauce = false,
    this.sortOrder = 0,
    required this.storage,
  });

  factory Ingredient.fromJson(Map<String, dynamic> json) {
    final storageMap = <String, IngredientStorageLimit>{};
    if (json['storage'] != null && json['storage'] is Map) {
      (json['storage'] as Map).forEach((key, value) {
        storageMap[key.toString()] = IngredientStorageLimit.fromJson(value as Map<String, dynamic>);
      });
    }
    return Ingredient(
      name: json['name'] as String,
      category: json['category'] as String,
      abbr: json['abbr'] as String? ?? '',
      isSauce: json['is_sauce'] == 1 || json['is_sauce'] == true || json['isSauce'] == true,
      sortOrder: json['sort_order'] as int? ?? json['sortOrder'] as int? ?? 0,
      storage: storageMap,
    );
  }

  int get sauceBottleValidMin {
    if (storage.containsKey('소스보틀')) {
      final hours = storage['소스보틀']!.days;
      if (hours > 0) return hours * 60;
    }
    for (final entry in storage.entries) {
      if (entry.key.contains('소스') || entry.key.contains('보틀')) {
        if (entry.value.days > 0) return entry.value.days * 60;
      }
    }
    return 600; // Default 10h = 600m
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'category': category,
        'abbr': abbr,
        'is_sauce': isSauce ? 1 : 0,
        'isSauce': isSauce,
        'storage': storage.map((k, v) => MapEntry(k, v.toJson())),
      };
}
