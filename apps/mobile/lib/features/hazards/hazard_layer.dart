import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../../core/theme/app_radii.dart';
import '../../core/theme/app_spacing.dart';
import 'hazard_model.dart';

/// Map tappable wrapping a MarkerLayer of hazard pins.
///
/// The class isn't itself a `MarkerLayer` — flutter_map's layer
/// contract wants a plain widget list inside `FlutterMap.children`.
/// `HazardLayer.build` returns the `MarkerLayer` directly so the
/// call site drops it in alongside `TileLayer`/`PolylineLayer`.
class HazardLayer extends StatelessWidget {
  const HazardLayer({super.key, required this.hazards});

  final List<HazardDto> hazards;

  @override
  Widget build(BuildContext context) {
    if (hazards.isEmpty) return const SizedBox.shrink();
    return MarkerLayer(
      markers: [
        for (final hazard in hazards)
          for (final geometry in hazard.geometries)
            Marker(
              point: geometry.anchor,
              width: 32,
              height: 32,
              child: _HazardPin(hazard: hazard),
            ),
      ],
    );
  }
}

class _HazardPin extends StatelessWidget {
  const _HazardPin({required this.hazard});

  final HazardDto hazard;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = _colorFor(hazard.category, scheme);
    return GestureDetector(
      onTap: () => _openDetails(context, hazard),
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: scheme.surface,
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              offset: const Offset(0, 2),
              blurRadius: 6,
              color: Colors.black.withValues(alpha: 0.2),
            ),
          ],
        ),
        child: Icon(
          _iconFor(hazard.category),
          color: scheme.onPrimary,
          size: 18,
        ),
      ),
    );
  }
}

/// Category → Material Symbols icon. The mapping is intentionally
/// coarse; a few EONET categories (dustHaze, manmade, drought,
/// waterColor) don't have a perfect symbol so we fall back to
/// `warning_amber_rounded`.
IconData _iconFor(String category) {
  switch (category) {
    case 'wildfires':
      return Icons.local_fire_department;
    case 'severeStorms':
      return Icons.thunderstorm;
    case 'floods':
      return Icons.water;
    case 'volcanoes':
      return Icons.volcano;
    case 'earthquakes':
      return Icons.landscape;
    case 'seaLakeIce':
    case 'snow':
      return Icons.ac_unit;
    case 'tempExtremes':
      return Icons.device_thermostat;
    case 'landslides':
      return Icons.terrain;
    default:
      return Icons.warning_amber_rounded;
  }
}

/// Category → theme color. Only the four "loud" categories map to
/// distinct tokens; everything else is the error color so it reads
/// as a warning in the map overlay.
Color _colorFor(String category, ColorScheme scheme) {
  switch (category) {
    case 'wildfires':
      return scheme.primary;
    case 'severeStorms':
      return scheme.tertiary;
    case 'floods':
      return scheme.secondary;
    default:
      return scheme.error;
  }
}

void _openDetails(BuildContext context, HazardDto hazard) {
  showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _HazardDetailsSheet(hazard: hazard),
  );
}

class _HazardDetailsSheet extends StatelessWidget {
  const _HazardDetailsSheet({required this.hazard});

  final HazardDto hazard;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final color = _colorFor(hazard.category, scheme);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.base,
        0,
        AppSpacing.base,
        AppSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _iconFor(hazard.category),
                  color: scheme.onPrimary,
                  size: 22,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(hazard.title, style: textTheme.titleMedium),
                    Text(
                      hazard.category.toUpperCase(),
                      style: textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              _SeverityBadge(severity: hazard.severity),
            ],
          ),
          const SizedBox(height: AppSpacing.base),
          _DetailRow(
            label: 'UPDATED',
            value: _formatTimestamp(hazard.updatedAt),
            textTheme: textTheme,
            scheme: scheme,
          ),
          const SizedBox(height: AppSpacing.sm),
          _DetailRow(
            label: 'GEOMETRIES',
            value: _summarizeGeometries(hazard.geometries),
            textTheme: textTheme,
            scheme: scheme,
          ),
          if (hazard.sourceUrl != null) ...[
            const SizedBox(height: AppSpacing.sm),
            _DetailRow(
              label: 'SOURCE',
              value: hazard.sourceUrl!,
              textTheme: textTheme,
              scheme: scheme,
            ),
          ],
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    required this.textTheme,
    required this.scheme,
  });

  final String label;
  final String value;
  final TextTheme textTheme;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 96,
          child: Text(
            label,
            style: textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: Text(value, style: textTheme.bodyMedium),
        ),
      ],
    );
  }
}

class _SeverityBadge extends StatelessWidget {
  const _SeverityBadge({required this.severity});

  final String severity;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (background, foreground) = switch (severity) {
      'severe' => (scheme.error, scheme.onError),
      'warning' => (scheme.primary, scheme.onPrimary),
      _ => (scheme.secondaryContainer, scheme.onSecondaryContainer),
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: AppRadii.xs,
      ),
      child: Text(
        severity.toUpperCase(),
        style: TextStyle(
          color: foreground,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

String _summarizeGeometries(List<GeometryDto> geometries) {
  var points = 0;
  var polygons = 0;
  for (final g in geometries) {
    if (g is PointGeometry) {
      points += 1;
    } else if (g is PolygonGeometry) {
      polygons += 1;
    }
  }
  final parts = <String>[];
  if (points > 0) parts.add('$points point${points == 1 ? '' : 's'}');
  if (polygons > 0) {
    parts.add('$polygons polygon${polygons == 1 ? '' : 's'}');
  }
  return parts.isEmpty ? 'none' : parts.join(', ');
}

String _formatTimestamp(DateTime when) {
  final delta = DateTime.now().difference(when);
  if (delta.inMinutes < 1) return 'just now';
  if (delta.inHours < 1) return '${delta.inMinutes} min ago';
  if (delta.inDays < 1) return '${delta.inHours} h ago';
  return '${delta.inDays} d ago';
}
