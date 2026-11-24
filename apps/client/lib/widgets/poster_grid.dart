import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// How a poster grid is laid out at one width.
@immutable
class PosterGridLayout {
  const PosterGridLayout({
    required this.columns,
    required this.gap,
    required this.dense,
  });

  final int columns;

  /// The space between cards, across and down.
  final double gap;

  /// Compact cards: one-line titles and tighter padding.
  final bool dense;

  /// On a phone, a column narrower than this is too small to read a
  /// poster's title, so the grid uses two columns instead of three.
  static const double minPhoneColumnWidth = 96;

  /// On a phone, text scaled past this makes three columns clip, so the
  /// grid uses two.
  static const double maxPhoneTextScale = 1.3;

  /// Phones (narrower than the 600 px breakpoint) get three columns, as a
  /// 360 px phone with standard text does, so two rows show six posters and
  /// three rows nine. Two columns on unusually narrow screens or with large
  /// text. Wider screens fit as many columns of at least
  /// [VeloraLayout.minPosterWidthWide] as there is room for.
  static PosterGridLayout resolve({
    required double width,
    required double screenWidth,
    double textScale = 1,
  }) {
    if (screenWidth < VeloraLayout.mediumBreakpoint) {
      const gap = VeloraSpacing.xs;
      final third = (width - 2 * gap) / 3;
      final three =
          third >= minPhoneColumnWidth && textScale <= maxPhoneTextScale;
      return PosterGridLayout(columns: three ? 3 : 2, gap: gap, dense: true);
    }
    const gap = VeloraSpacing.md;
    final columns = ((width + gap) / (VeloraLayout.minPosterWidthWide + gap))
        .floor();
    return PosterGridLayout(
      columns: columns < 3 ? 3 : columns,
      gap: gap,
      dense: false,
    );
  }

  /// The layout for [context] in a box [width] wide.
  static PosterGridLayout of(BuildContext context, double width) => resolve(
    width: width,
    screenWidth: MediaQuery.sizeOf(context).width,
    textScale: MediaQuery.textScalerOf(context).scale(14) / 14,
  );
}

/// The poster grid shared by Search results, Filter results and every See
/// all page. Each row is as tall as its tallest card and every card in it
/// matches, so large text makes rows taller instead of clipping them.
///
/// [itemBuilder] receives whether the cards should be dense.
class PosterGrid extends StatelessWidget {
  const PosterGrid({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
  });

  final int itemCount;
  final Widget Function(BuildContext context, int index, bool dense)
  itemBuilder;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = PosterGridLayout.of(context, constraints.maxWidth);
        final columns = layout.columns;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: layout.gap,
          children: [
            for (var start = 0; start < itemCount; start += columns)
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: layout.gap,
                  children: [
                    for (var i = start; i < start + columns; i++)
                      Expanded(
                        child: i < itemCount
                            ? itemBuilder(context, i, layout.dense)
                            : const SizedBox.shrink(),
                      ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}
