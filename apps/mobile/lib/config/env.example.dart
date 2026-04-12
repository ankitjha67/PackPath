/// Copy this file to `env.dart` and fill in real values. `env.dart` is
/// gitignored so secrets stay local.
///
/// Only the providers you actually want as a tile layer need keys here —
/// routing always goes through the backend proxy.
class Env {
  static const String apiBaseUrl = 'http://10.0.2.2:8000';
  static const String wsBaseUrl = 'ws://10.0.2.2:8000';

  static const String mapboxPublicToken = 'pk.REPLACE_ME';
  static const String mapboxStyleUrl =
      'https://api.mapbox.com/styles/v1/mapbox/streets-v12/tiles/256/{z}/{x}/{y}@2x';

  static const String mapplsRestKey = '';
  static const String hereApiKey = '';
  static const String tomtomApiKey = '';
}
