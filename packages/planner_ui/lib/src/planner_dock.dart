import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:material_3_expressive/material_3_expressive.dart';
import 'package:material_ui/material_ui.dart';

import 'design.dart';

class PlannerDock extends StatelessWidget {
  const PlannerDock({
    super.key,
    required this.tab,
    required this.onTab,
    required this.onVoice,
    required this.listening,
    required this.busy,
    required this.level,
  });

  final int tab;
  final ValueChanged<int> onTab;
  final VoidCallback? onVoice;
  final bool listening;
  final bool busy;
  final ValueListenable<double> level;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final dark = palette.brightness == Brightness.dark;
    final dockColor = dark
        ? palette.surfaceContainerHighest
        : palette.inverseSurface;
    final dockInk = dark ? palette.onSurface : palette.onInverseSurface;
    const voiceSize = 65.0;
    final showsVoice = onVoice != null || listening || busy;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: ExcludeSemantics(
                excluding: listening,
                child: ExcludeFocus(
                  excluding: listening,
                  child: IgnorePointer(
                    ignoring: listening,
                    child: Material(
                      color: dockColor,
                      elevation: 4,
                      shadowColor: context.palette.shadow,
                      shape: const StadiumBorder(),
                      child: Padding(
                        padding: const EdgeInsets.all(5),
                        child: M3EButtonGroup(
                          semanticLabel: 'Planner sections',
                          size: M3EButtonSize.md,
                          selectedIndex: tab,
                          selectionRequired: true,
                          onSelectedIndexChanged: (index) {
                            if (index != null) onTab(index);
                          },
                          decoration: M3EButtonDecoration(
                            backgroundColor: WidgetStateProperty.resolveWith(
                              (states) => states.contains(WidgetState.selected)
                                  ? context.palette.secondaryContainer
                                  : Colors.transparent,
                            ),
                            foregroundColor: WidgetStateProperty.resolveWith(
                              (states) => states.contains(WidgetState.selected)
                                  ? dockInk
                                  : dockInk.withValues(alpha: .8),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            iconSize: 21,
                            minimumSize: const Size.square(plannerTapTarget),
                            tapTargetSize: MaterialTapTargetSize.padded,
                            animationDuration: context.reduceMotion
                                ? Duration.zero
                                : null,
                            textStyle: context.type.labelMedium,
                            selectedRadius: 32,
                            unselectedRadius: 32,
                          ),
                          actions: [
                            for (final (index, item) in const [
                              (Icons.view_day_outlined, 'Briefing'),
                              (Icons.checklist_rounded, 'Tasks'),
                            ].indexed)
                              M3EButtonGroupAction(
                                icon: Icon(item.$1),
                                label: index == tab ? Text(item.$2) : null,
                                semanticLabel: item.$2,
                                tooltip: index == tab ? null : item.$2,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (showsVoice)
              const SizedBox(width: voiceSize + 6, height: voiceSize),
          ],
        ),
        if (showsVoice)
          Positioned.fill(
            child: LayoutBuilder(
              builder: (context, constraints) => TweenAnimationBuilder<double>(
                tween: Tween(end: listening ? 1 : 0),
                duration: context.reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                builder: (context, coverage, child) => Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: SizedBox(
                    key: const ValueKey('voice-bubble'),
                    width:
                        voiceSize +
                        (constraints.maxWidth - voiceSize) * coverage,
                    height:
                        voiceSize +
                        (constraints.maxHeight - voiceSize) * coverage,
                    child: child,
                  ),
                ),
                child: _VoiceButton(
                  onPressed: onVoice,
                  listening: listening,
                  busy: busy,
                  level: level,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _VoiceButton extends StatelessWidget {
  const _VoiceButton({
    required this.onPressed,
    required this.listening,
    required this.busy,
    required this.level,
  });

  final VoidCallback? onPressed;
  final bool listening;
  final bool busy;
  final ValueListenable<double> level;

  @override
  Widget build(BuildContext context) {
    final label = listening
        ? 'Listening. Tap to finish'
        : busy
        ? 'Working'
        : 'Start dictation';
    final palette = context.palette;
    final ink = listening ? palette.onPrimary : palette.onSecondaryContainer;
    return Tooltip(
      message: label,
      excludeFromSemantics: true,
      child: Semantics(
        label: label,
        button: true,
        liveRegion: listening,
        child: Material(
          color: listening ? palette.primary : palette.secondaryContainer,
          elevation: 4,
          shadowColor: palette.shadow,
          borderRadius: BorderRadius.circular(18),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: Center(
              child: listening
                  ? _ListeningWave(level: level, color: ink)
                  : busy
                  ? context.reduceMotion
                        ? Icon(Icons.hourglass_top, color: ink)
                        : SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: ink,
                            ),
                          )
                  : Icon(Icons.mic_none_rounded, color: ink, size: 25),
            ),
          ),
        ),
      ),
    );
  }
}

class _ListeningWave extends StatefulWidget {
  const _ListeningWave({required this.level, required this.color});

  final ValueListenable<double> level;
  final Color color;

  @override
  State<_ListeningWave> createState() => _ListeningWaveState();
}

class _ListeningWaveState extends State<_ListeningWave>
    with SingleTickerProviderStateMixin {
  late final _phase = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1150),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (context.reduceMotion) {
      _phase.stop();
    } else if (!_phase.isAnimating) {
      _phase.repeat();
    }
  }

  @override
  void dispose() {
    _phase.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CustomPaint(
    key: const ValueKey('listening-wave'),
    size: const Size(62, 26),
    painter: _WavePainter(
      phase: _phase,
      level: widget.level,
      color: widget.color,
    ),
  );
}

class _WavePainter extends CustomPainter {
  _WavePainter({required this.phase, required this.level, required this.color})
    : super(repaint: Listenable.merge([phase, level]));

  final Animation<double> phase;
  final ValueListenable<double> level;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final middle = size.height / 2;
    final waveEnd = size.width * .65;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    final wave = Path();
    final amplitude = 2.5 + level.value * 7;
    for (var i = 0; i <= 40; i++) {
      final t = i / 40;
      final y =
          middle +
          math.sin(t * math.pi) *
              amplitude *
              math.sin((t * 2.3 - phase.value) * 2 * math.pi);
      if (i == 0) {
        wave.moveTo(2, y);
      } else {
        wave.lineTo(2 + t * (waveEnd - 5), y);
      }
    }
    canvas.drawPath(wave, paint);
    canvas.drawLine(
      Offset(waveEnd + 2, middle - 8),
      Offset(waveEnd + 2, middle + 8),
      paint,
    );
    paint.color = color.withValues(alpha: .35);
    canvas.drawLine(
      Offset(waveEnd + 8, middle),
      Offset(size.width - 2, middle),
      paint,
    );
  }

  @override
  bool shouldRepaint(_WavePainter oldDelegate) =>
      phase != oldDelegate.phase ||
      level != oldDelegate.level ||
      color != oldDelegate.color;
}
