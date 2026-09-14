import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:client_flutter/services/favorites_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('FavoritesService add, remove, toggle, persistence', () async {
    final service = FavoritesService.instance;
    await service.init();
    await service.clear();

    expect(service.count, 0);
    expect(service.isFavorite('페퍼로니'), isFalse);

    // Add
    await service.add('페퍼로니');
    expect(service.count, 1);
    expect(service.isFavorite('페퍼로니'), isTrue);

    // Toggle off
    final res1 = await service.toggle('페퍼로니');
    expect(res1, isFalse);
    expect(service.isFavorite('페퍼로니'), isFalse);
    expect(service.count, 0);

    // Toggle on
    final res2 = await service.toggle('모짜렐라 치즈');
    expect(res2, isTrue);
    expect(service.isFavorite('모짜렐라 치즈'), isTrue);
    expect(service.count, 1);

    // Verify persistence in SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList('favorite_ingredient_names');
    expect(saved, contains('모짜렐라 치즈'));

    // Remove
    await service.remove('모짜렐라 치즈');
    expect(service.isFavorite('모짜렐라 치즈'), isFalse);
    expect(service.count, 0);
  });
}
