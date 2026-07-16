import 'dart:convert';
import 'dart:typed_data';
import 'package:pointycastle/export.dart';
import 'package:crypto/crypto.dart';

class PasswordService {
  static bool verify(String password, String storedHash) {
    if (storedHash.startsWith('scrypt\$')) {
      final parts = storedHash.split('\$');
      if (parts.length < 6) return false;

      final n = int.tryParse(parts[1]) ?? 16384;
      final r = int.tryParse(parts[2]) ?? 8;
      final p = int.tryParse(parts[3]) ?? 1;
      final saltHex = parts[4];
      final keyHex = parts[5];

      final salt = _hexDecode(saltHex);
      final storedKey = _hexDecode(keyHex);

      try {
        final derivator = KeyDerivator('scrypt');
        derivator.init(ScryptParameters(n, r, p, storedKey.length, salt));
        final derivedKey = derivator.process(Uint8List.fromList(utf8.encode(password)));

        if (derivedKey.length != storedKey.length) return false;
        for (var i = 0; i < derivedKey.length; i++) {
          if (derivedKey[i] != storedKey[i]) return false;
        }
        return true;
      } catch (e) {
        return false;
      }
    } else {
      // Legacy SHA-256 fallback
      final bytes = utf8.encode(password);
      final digest = sha256.convert(bytes);
      return digest.toString() == storedHash;
    }
  }

  static Uint8List _hexDecode(String hex) {
    final result = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < result.length; i++) {
      result[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return result;
  }
}
