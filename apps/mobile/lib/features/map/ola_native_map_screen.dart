import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../config/env.dart';
import '../../shared/models/waypoint.dart';
import '../profile/me_repository.dart';
import '../trips/trips_repository.dart';
import '../trips/waypoints_repository.dart';
import 'live_trip_controller.dart';

/// Full-screen native Ola Maps (Ola Krutrim) map, rendered via MapLibre GL.
/// Ola is an Indian provider, so it serves the official Survey-of-India
/// boundaries by default. Unlike the Mappls native SDK, MapLibre is a plain
/// renderer: a missing or unauthorized key shows a blank map, never a crash.
///
/// Ola's key must ride on the style document *and* its nested tile / glyph /
/// sprite URLs, so we fetch the style JSON and rewrite those URLs before
/// handing it to MapLibre as a raw style string.
class OlaNativeMapScreen extends ConsumerStatefulWidget {
  const OlaNativeMapScreen({super.key, required this.tripId});
  final String tripId;

  @override
  ConsumerState<OlaNativeMapScreen> createState() => _OlaNativeMapScreenState();
}

const _olaStyleUrl =
    'https://api.olamaps.io/tiles/vector/v1/styles/default-light-standard/style.json';

class _OlaNativeMapScreenState extends ConsumerState<OlaNativeMapScreen> {
  MapLibreMapController? _ctrl;
  String? _style; // rewritten style JSON
  String? _error;
  bool _styleReady = false;
  bool _framed = false;

  @override
  void initState() {
    super.initState();
    _loadStyle();
  }

  String _withKey(String url) {
    final key = Env.olaMapsApiKey;
    if (key.isEmpty ||
        !url.contains('olamaps.io') ||
        url.contains('api_key=')) {
      return url;
    }
    return '$url${url.contains('?') ? '&' : '?'}api_key=$key';
  }

  Future<void> _loadStyle() async {
    final key = Env.olaMapsApiKey;
    if (key.isEmpty) {
      setState(() => _error = 'No Ola Maps key set (Env.olaMapsApiKey).');
      return;
    }
    try {
      final dio = Dio();
      final res = await dio.get<String>(
        _withKey(_olaStyleUrl),
        options: Options(responseType: ResponseType.plain),
      );
      final style = json.decode(res.data!) as Map<String, dynamic>;

      if (style['glyphs'] is String) {
        style['glyphs'] = _withKey(style['glyphs'] as String);
      }
      if (style['sprite'] is String) {
        style['sprite'] = _withKey(style['sprite'] as String);
      }
      // Each vector source points at a TileJSON (`url`) whose own tile URLs
      // carry no key, so MapLibre would fetch keyless tiles and 401. Resolve
      // each TileJSON here and inline its tiles with the key, dropping `url`.
      final sources = style['sources'];
      if (sources is Map) {
        for (final src in sources.values) {
          if (src is! Map) continue;
          final url = src['url'];
          if (url is String && url.contains('olamaps.io')) {
            try {
              final tj = await dio.get<String>(
                _withKey(url),
                options: Options(responseType: ResponseType.plain),
              );
              final tjson = json.decode(tj.data!) as Map<String, dynamic>;
              final tiles = (tjson['tiles'] as List?)
                  ?.map((t) => t is String ? _withKey(t) : t)
                  .toList();
              if (tiles != null && tiles.isNotEmpty) {
                src['tiles'] = tiles;
                if (tjson['minzoom'] != null) src['minzoom'] = tjson['minzoom'];
                if (tjson['maxzoom'] != null) src['maxzoom'] = tjson['maxzoom'];
                src.remove('url');
              } else {
                src['url'] = _withKey(url);
              }
            } catch (_) {
              src['url'] = _withKey(url);
            }
          } else if (src['tiles'] is List) {
            src['tiles'] = (src['tiles'] as List)
                .map((t) => t is String ? _withKey(t) : t)
                .toList();
          }
        }
      }
      if (mounted) setState(() => _style = json.encode(style));
    } catch (e) {
      if (mounted) setState(() => _error = 'Failed to load Ola style: $e');
    }
  }

  Future<void> _render() async {
    final c = _ctrl;
    if (c == null || !_styleReady) return;
    await c.clearCircles();
    await c.clearLines();

    final myId = ref.read(meProvider).valueOrNull?.id;
    final live = ref.read(liveTripProvider(widget.tripId));
    final colors = ref.read(tripDetailProvider(widget.tripId)).maybeWhen(
          data: (t) => {for (final m in t.members) m.userId: m.color},
          orElse: () => const <String, String>{},
        );
    final route = ref.read(tripRouteProvider(widget.tripId)).valueOrNull;
    final waypoints =
        ref.read(tripWaypointsProvider(widget.tripId)).valueOrNull ??
            const <WaypointDto>[];

    final pts = <LatLng>[];

    if (route != null && route.points.length >= 2) {
      await c.addLine(LineOptions(
        geometry:
            route.points.map((p) => LatLng(p.latitude, p.longitude)).toList(),
        lineColor: '#3F7E4E',
        lineWidth: 5.0,
        lineOpacity: 0.9,
      ));
    }

    for (final w in waypoints) {
      final ll.LatLng g = w.latLng;
      final pos = LatLng(g.latitude, g.longitude);
      pts.add(pos);
      await c.addCircle(CircleOptions(
        geometry: pos,
        circleRadius: 7.0,
        circleColor: '#C36B1D',
        circleStrokeColor: '#FFFFFF',
        circleStrokeWidth: 2.0,
      ));
    }

    for (final e in live.members.entries) {
      final isMe = e.key == myId;
      final p = e.value.position;
      final pos = LatLng(p.latitude, p.longitude);
      pts.add(pos);
      await c.addCircle(CircleOptions(
        geometry: pos,
        circleRadius: isMe ? 11.0 : 8.0,
        circleColor: isMe ? '#4E8F5C' : (colors[e.key] ?? '#879D9A'),
        circleStrokeColor: '#FFFFFF',
        circleStrokeWidth: isMe ? 3.0 : 2.0,
      ));
    }

    if (!_framed && pts.isNotEmpty) {
      _framed = true;
      await _frame(pts);
    }
  }

  Future<void> _frame(List<LatLng> pts) async {
    final c = _ctrl;
    if (c == null || pts.isEmpty) return;
    if (pts.length == 1) {
      await c.animateCamera(CameraUpdate.newLatLngZoom(pts.first, 14));
      return;
    }
    var minLat = pts.first.latitude, maxLat = pts.first.latitude;
    var minLng = pts.first.longitude, maxLng = pts.first.longitude;
    for (final p in pts) {
      minLat = p.latitude < minLat ? p.latitude : minLat;
      maxLat = p.latitude > maxLat ? p.latitude : maxLat;
      minLng = p.longitude < minLng ? p.longitude : minLng;
      maxLng = p.longitude > maxLng ? p.longitude : maxLng;
    }
    await c.animateCamera(CameraUpdate.newLatLngBounds(
      LatLngBounds(
        southwest: LatLng(minLat, minLng),
        northeast: LatLng(maxLat, maxLng),
      ),
      left: 48,
      right: 48,
      top: 96,
      bottom: 96,
    ));
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(liveTripProvider(widget.tripId), (_, __) => _render());
    ref.listen(tripWaypointsProvider(widget.tripId), (_, __) => _render());

    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ola · India map'),
        actions: [
          IconButton(
            tooltip: 'Frame everyone',
            icon: const Icon(Icons.center_focus_strong),
            onPressed: () {
              _framed = false;
              _render();
            },
          ),
        ],
      ),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_error!,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: scheme.onSurfaceVariant)),
              ),
            )
          : _style == null
              ? const Center(child: CircularProgressIndicator())
              : MapLibreMap(
                  styleString: _style!,
                  initialCameraPosition: const CameraPosition(
                    target: LatLng(22.9734, 78.6569), // centre of India
                    zoom: 4,
                  ),
                  myLocationEnabled: true,
                  onMapCreated: (c) => _ctrl = c,
                  onStyleLoadedCallback: () {
                    _styleReady = true;
                    _render();
                  },
                ),
    );
  }
}
