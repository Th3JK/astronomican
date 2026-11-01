import 'package:flutter/material.dart';

import '../core/level_controller.dart';
import '../core/map_level.dart';
import 'level_selector_theme.dart';

/// Picks which level a map shows.
///
/// Closed it is a single tile carrying the level showing, with a chevron under
/// it; tapped it grows into a column of every level, and closes as soon as one
/// is chosen. It drives any [LevelController], so the same selector sits on an
/// image map of floor plans and on a street map with indoor floors.
///
/// With fewer than two levels there is nothing to choose, so the control
/// slides off to the side rather than vanishing — moving between a building on
/// two floors and one on a single floor reads as the control leaving, not as
/// the screen changing shape. Place it at the right edge for that to look
/// right.
class LevelSelector extends StatefulWidget {
  /// A selector over [controller]'s levels.
  const LevelSelector({
    super.key,
    required this.controller,
    this.onSelected,
    this.theme = const LevelSelectorThemeData(),
    this.semanticLabel = 'Level',
    this.topLevelFirst = true,
  });

  /// The map whose level is picked.
  final LevelController controller;

  /// Called after the controller has switched to a newly picked level.
  final ValueChanged<MapLevel>? onSelected;

  /// Colours and measurements.
  final LevelSelectorThemeData theme;

  /// Read out for the control as a whole.
  final String semanticLabel;

  /// Lists the highest level at the top, like the buttons in a lift. Off lists
  /// them in the controller's order, lowest first.
  final bool topLevelFirst;

  @override
  State<LevelSelector> createState() => LevelSelectorState();
}

/// State of a [LevelSelector]; reach it with a `GlobalKey` to [close] it.
class LevelSelectorState extends State<LevelSelector> {
  static const Duration _grow = Duration(milliseconds: 220);
  static const Duration _slide = Duration(milliseconds: 300);

  bool _open = false;

  /// Whether the column of levels is showing.
  bool get isOpen => _open;

  /// Shuts the selector from outside — for a map to call when the visitor
  /// touches anything else, so an open column does not sit over the picture.
  void close() {
    if (_open && mounted) setState(() => _open = false);
  }

  void _select(MapLevel level) {
    setState(() => _open = false);
    if (level.id == widget.controller.activeLevelId) return;
    widget.controller.showLevel(level.id);
    widget.onSelected?.call(level);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) => _build(context),
    );
  }

  Widget _build(BuildContext context) {
    final theme = widget.theme;
    final scheme = Theme.of(context).colorScheme;
    final background = theme.backgroundColor ?? scheme.primary;
    final active = theme.activeColor ?? scheme.onPrimary;
    final activeLabel = theme.activeLabelColor ?? scheme.primary;
    final label = theme.labelColor ?? scheme.onPrimary;

    final levels = widget.topLevelFirst
        ? widget.controller.levels.reversed.toList()
        : widget.controller.levels;
    final visible = levels.length >= 2;
    // Shut on the way out, so it does not slide back in still expanded.
    if (!visible) _open = false;
    final current = widget.controller.activeLevel;

    Widget tile(
      MapLevel level, {
      required bool isActive,
      required VoidCallback onTap,
    }) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Material(
          color: isActive ? active : Colors.transparent,
          borderRadius: theme.tileRadius,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Semantics(
              button: true,
              selected: isActive,
              child: SizedBox.square(
                dimension: theme.tileSize,
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        level.label,
                        style:
                            (theme.labelStyle ??
                                    const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ))
                                .copyWith(
                                  color: isActive ? activeLabel : label,
                                ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedSlide(
        // Far enough to clear its own shadow.
        offset: visible ? Offset.zero : const Offset(1.6, 0),
        duration: _slide,
        curve: Curves.easeOutCubic,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: _slide,
          curve: Curves.easeOut,
          child: Semantics(
            container: true,
            label: widget.semanticLabel,
            child: Material(
              color: background,
              borderRadius: theme.frameRadius,
              elevation: theme.elevation,
              shadowColor: theme.shadowColor,
              clipBehavior: Clip.antiAlias,
              child: AnimatedSize(
                duration: _grow,
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: SizedBox(
                  width: theme.tileSize + theme.inset * 2,
                  child: Padding(
                    padding: EdgeInsets.all(theme.inset),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_open)
                          for (final level in levels)
                            tile(
                              level,
                              isActive: level.id == current?.id,
                              onTap: () => _select(level),
                            )
                        else if (current != null)
                          tile(
                            current,
                            isActive: true,
                            onTap: () => setState(() => _open = true),
                          ),
                        InkWell(
                          onTap: () => setState(() => _open = !_open),
                          borderRadius: BorderRadius.circular(8),
                          child: SizedBox(
                            width: theme.tileSize,
                            height: 18,
                            child: AnimatedRotation(
                              turns: _open ? 0.5 : 0,
                              duration: _grow,
                              curve: Curves.easeOutCubic,
                              child: Icon(
                                Icons.expand_more_rounded,
                                size: 18,
                                color: label,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
