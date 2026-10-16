import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const storage = FlutterSecureStorage(
  wOptions: WindowsOptions(useBackwardCompatibility: false),
);
const storageKey = 'mirage_x5_connection';
