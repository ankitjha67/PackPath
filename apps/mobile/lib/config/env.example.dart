/// Copy this file to `env.dart` and fill in real values. `env.dart` is
/// gitignored so secrets stay local.
class Env {
  static const String apiBaseUrl = 'http://10.0.2.2:8000';
  static const String wsBaseUrl = 'ws://10.0.2.2:8000';

  /// Public Mapbox token (pk.*). Get one at https://account.mapbox.com.
  static const String mapboxPublicToken = 'pk.REPLACE_ME';

  /// Default map style URL. Falls back to Mapbox streets-v12.
  static const String mapboxStyleUrl =
      'https://api.mapbox.com/styles/v1/mapbox/streets-v12/tiles/256/{z}/{x}/{y}@2x';
}
