import 'package:flutter/material.dart';

import '../../domain/calendar.dart';

/// Barra horizontal com as faixas de um dia dentro de uma janela de horário.
class RangeBar extends StatelessWidget {
  const RangeBar({
    super.key,
    required this.ranges,
    required this.window,
    required this.color,
    this.height = 14,
    this.onTap,
    this.tooltipBuilder,
  });

  final List<TimeRange> ranges;
  final TimeRange window;
  final Color color;
  final double height;
  final void Function(TimeRange range)? onTap;
  final String Function(TimeRange range)? tooltipBuilder;

  @override
  Widget build(BuildContext context) {
    final track = Theme.of(context).colorScheme.surfaceContainerHighest;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        double x(int minute) => (minute - window.start) / window.length * width;

        return SizedBox(
          height: height,
          child: Stack(
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: track,
                    borderRadius: BorderRadius.circular(height / 2),
                  ),
                ),
              ),
              for (final r in ranges)
                if (r.intersect(window) case final visible?)
                  Positioned(
                    left: x(visible.start),
                    width: x(visible.end) - x(visible.start),
                    top: 0,
                    bottom: 0,
                    child: _Segment(
                      color: color,
                      radius: height / 2,
                      tooltip: tooltipBuilder?.call(r),
                      onTap: onTap == null ? null : () => onTap!(r),
                    ),
                  ),
            ],
          ),
        );
      },
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.color,
    required this.radius,
    this.tooltip,
    this.onTap,
  });

  final Color color;
  final double radius;
  final String? tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    Widget child = Material(
      color: color,
      borderRadius: BorderRadius.circular(radius),
      child: InkWell(borderRadius: BorderRadius.circular(radius), onTap: onTap),
    );
    if (tooltip != null) child = Tooltip(message: tooltip!, child: child);
    return child;
  }
}
