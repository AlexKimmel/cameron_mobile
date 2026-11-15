import 'package:material_ui/material_ui.dart';

const plannerSeed = Color(0xff9d3b23);
const plannerTapTarget = 48.0;

ThemeData plannerTheme(ColorScheme? dynamicScheme, {bool dark = false}) {
  final scheme =
      dynamicScheme ??
      ColorScheme.fromSeed(
        seedColor: plannerSeed,
        brightness: dark ? Brightness.dark : Brightness.light,
      );
  return ThemeData(
    useMaterial3: true,
    visualDensity: VisualDensity.standard,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    iconButtonTheme: const IconButtonThemeData(
      style: ButtonStyle(
        minimumSize: WidgetStatePropertyAll(Size.square(plannerTapTarget)),
      ),
    ),
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
    ),
  );
}

extension PlannerThemeContext on BuildContext {
  ColorScheme get palette => Theme.of(this).colorScheme;
  TextTheme get type => Theme.of(this).textTheme;
  bool get reduceMotion => MediaQuery.disableAnimationsOf(this);
  AnimationStyle? get reducedMotionStyle =>
      reduceMotion ? AnimationStyle.noAnimation : null;

  String clock(int minutes) => MaterialLocalizations.of(this).formatTimeOfDay(
    TimeOfDay(hour: minutes ~/ 60 % 24, minute: minutes % 60),
    alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(this),
  );
}

String durationLabel(int minutes) {
  if (minutes < 60) return '${minutes}m';
  if (minutes % 60 == 0) return '${minutes ~/ 60}h';
  return '${minutes ~/ 60}h ${minutes % 60}m';
}

class Panel extends StatelessWidget {
  const Panel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.color,
    this.radius = 26,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final double radius;

  @override
  Widget build(BuildContext context) => Material(
    color: color ?? context.palette.surfaceContainerLow,
    borderRadius: BorderRadius.circular(radius),
    clipBehavior: Clip.antiAlias,
    child: Padding(padding: padding, child: child),
  );
}

class Pill extends StatelessWidget {
  const Pill(this.label, {super.key, this.icon, this.color, this.foreground});

  final String label;
  final IconData? icon;
  final Color? color;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final ink = foreground ?? palette.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: ShapeDecoration(
        shape: const StadiumBorder(),
        color: color ?? palette.surfaceContainerHigh,
      ),
      child: Text.rich(
        TextSpan(
          children: [
            if (icon case final glyph?)
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Icon(glyph, size: 14, color: ink),
                ),
              ),
            TextSpan(text: label),
          ],
        ),
        style: context.type.labelSmall!.copyWith(
          color: ink,
          fontWeight: FontWeight.w600,
          height: 1.2,
        ),
      ),
    );
  }
}

class IconBadge extends StatelessWidget {
  const IconBadge(
    this.icon, {
    super.key,
    this.size = 32,
    this.color,
    this.foreground,
  });

  final IconData icon;
  final double size;
  final Color? color;
  final Color? foreground;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: color ?? context.palette.primaryContainer,
    ),
    alignment: Alignment.center,
    child: Icon(
      icon,
      size: size * .56,
      color: foreground ?? context.palette.onPrimaryContainer,
    ),
  );
}

class SectionHeading extends StatelessWidget {
  const SectionHeading(this.title, {super.key, this.trailing, this.icon});

  final String title;
  final Widget? trailing;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4),
    child: Wrap(
      spacing: 12,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      alignment: WrapAlignment.spaceBetween,
      children: [
        Semantics(
          header: true,
          child: Text.rich(
            TextSpan(
              children: [
                if (icon case final glyph?)
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 7),
                      child: Icon(
                        glyph,
                        size: 18,
                        color: context.palette.primary,
                      ),
                    ),
                  ),
                TextSpan(text: title),
              ],
            ),
            style: context.type.titleMedium!.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        ?trailing,
      ],
    ),
  );
}
