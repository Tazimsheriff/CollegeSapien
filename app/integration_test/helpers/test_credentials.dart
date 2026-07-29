import 'dart:io';

import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Local-only test-account credentials, read from `app/.env` (gitignored).
///
/// Copy `.env.example` to `.env` and fill in a dedicated non-production
/// test account before running integration tests that need to log in.
class TestCredentials {
  TestCredentials._();

  static bool _loaded = false;

  static void ensureLoaded() {
    if (_loaded) return;
    final file = File('.env');
    if (!file.existsSync()) {
      throw StateError(
        'app/.env not found. Copy .env.example to .env and fill in a '
        'test account before running integration tests that log in.',
      );
    }
    dotenv.testLoad(fileInput: file.readAsStringSync());
    _loaded = true;
  }

  static String _require(String key) {
    ensureLoaded();
    final value = dotenv.env[key];
    if (value == null || value.isEmpty) {
      throw StateError('$key is not set in app/.env');
    }
    return value;
  }

  static String get email => _require('TEST_ACCOUNT_EMAIL');
  static String get password => _require('TEST_ACCOUNT_PASSWORD');
}
