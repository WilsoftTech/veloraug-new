import 'package:flutter/material.dart';

import '../theme/palette.dart';
import '../theme/tokens.dart';
import '../theme/velora_theme.dart';
import '../widgets/brand.dart';
import '../widgets/empty_state.dart';
import '../widgets/loading_placeholder.dart';
import '../widgets/movie_card.dart';
import '../widgets/screen_body.dart';
import '../widgets/status_badge.dart';
import '../widgets/velora_button.dart';
import '../widgets/velora_search_field.dart';
import '../widgets/velora_text_field.dart';

/// Development-only catalogue of the design system. It opens only through
/// showcaseEnabled, and everything in it is demonstration content.
class DesignSystemShowcase extends StatefulWidget {
  const DesignSystemShowcase({super.key});

  @override
  State<DesignSystemShowcase> createState() => _DesignSystemShowcaseState();
}

class _DesignSystemShowcaseState extends State<DesignSystemShowcase> {
  bool _simulateReducedMotion = false;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VeloraUG design system (development only)',
      debugShowCheckedModeBanner: false,
      theme: buildVeloraTheme(),
      builder: (context, child) {
        if (!_simulateReducedMotion) return child!;
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        );
      },
      home: DefaultTabController(
        length: _tabs.length,
        child: Scaffold(
          appBar: AppBar(
            title: const VeloraWordmark(),
            bottom: TabBar(
              isScrollable: true,
              tabs: [for (final (name, _) in _tabs) Tab(text: name)],
            ),
          ),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _DevelopmentBanner(),
              Expanded(
                child: TabBarView(
                  children: [
                    for (final (_, builder) in _tabs)
                      Builder(
                        builder: (context) => builder(
                          _simulateReducedMotion,
                          (value) =>
                              setState(() => _simulateReducedMotion = value),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

typedef _TabBuilder = Widget Function(
  bool reduced,
  ValueChanged<bool> setReduced,
);

final List<(String, _TabBuilder)> _tabs = [
  ('Tokens', (_, _) => const _TokensTab()),
  ('Actions', (_, _) => const _ActionsTab()),
  ('Fields', (_, _) => const _FieldsTab()),
  ('Movies', (_, _) => const _MoviesTab()),
  (
    'Feedback',
    (reduced, setReduced) =>
        _FeedbackTab(reduced: reduced, setReduced: setReduced),
  ),
  ('Layouts', (_, _) => const _LayoutsTab()),
  ('Text size', (_, _) => const _TextSizeTab()),
];

class _DevelopmentBanner extends StatelessWidget {
  const _DevelopmentBanner();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: VeloraPalette.of(context).warningContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: VeloraSpacing.md,
          vertical: VeloraSpacing.xs,
        ),
        child: Text(
          'Design system showcase. Development only. All titles and results '
          'here are demonstration content, not real movies.',
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: VeloraPalette.of(context).warning),
        ),
      ),
    );
  }
}

class _TabPage extends StatelessWidget {
  const _TabPage({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final gutter = VeloraLayout.gutterFor(MediaQuery.sizeOf(context).width);
    return ListView(
      padding: EdgeInsets.symmetric(
        horizontal: gutter,
        vertical: VeloraSpacing.lg,
      ),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: VeloraLayout.browseWidth,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: VeloraSpacing.xl,
              children: children,
            ),
          ),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, this.note, required this.child});

  final String title;
  final String? note;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final note = this.note;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          header: true,
          child: Text(title, style: theme.textTheme.headlineSmall),
        ),
        if (note != null) ...[
          const SizedBox(height: VeloraSpacing.xxs),
          Text(
            note,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: VeloraSpacing.md),
        child,
      ],
    );
  }
}

// ---------------------------------------------------------------- Tokens

double _luminance(Color color) => color.computeLuminance();

double _contrast(Color a, Color b) {
  final (x, y) = (_luminance(a), _luminance(b));
  return (x > y ? x + 0.05 : y + 0.05) / (x > y ? y + 0.05 : x + 0.05);
}

String _hex(Color color) =>
    '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

class _TokensTab extends StatelessWidget {
  const _TokensTab();

  static const _surfaces = {
    'canvas': VeloraColors.canvas,
    'surface': VeloraColors.surface,
    'surfaceRaised': VeloraColors.surfaceRaised,
    'surfaceOverlay': VeloraColors.surfaceOverlay,
  };
  static const _foregrounds = {
    'textPrimary': VeloraColors.textPrimary,
    'textSecondary': VeloraColors.textSecondary,
    'textMuted': VeloraColors.textMuted,
    'accentText': VeloraColors.accentText,
    'success': VeloraColors.success,
    'warning': VeloraColors.warning,
    'danger': VeloraColors.danger,
  };
  static const _fills = {
    'accent': VeloraColors.accent,
    'accentHover': VeloraColors.accentHover,
    'accentPressed': VeloraColors.accentPressed,
    'focusRing': VeloraColors.focusRing,
    'outline': VeloraColors.outline,
    'outlineSubtle': VeloraColors.outlineSubtle,
    'infoContainer': VeloraColors.infoContainer,
    'successContainer': VeloraColors.successContainer,
    'warningContainer': VeloraColors.warningContainer,
    'dangerContainer': VeloraColors.dangerContainer,
  };

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return _TabPage(
      children: [
        _Section(
          title: 'Surfaces',
          child: _SwatchWrap(
            children: [
              for (final MapEntry(key: name, value: color) in _surfaces.entries)
                _Swatch(name: name, color: color),
            ],
          ),
        ),
        _Section(
          title: 'Text and status on surfaces',
          note:
              'Each sample shows its contrast on that surface. The target is '
              '4.5:1.',
          child: _SwatchWrap(
            children: [
              for (final MapEntry(key: name, value: color)
                  in _foregrounds.entries)
                for (final MapEntry(key: surfaceName, value: surface)
                    in _surfaces.entries)
                  _ContrastSample(
                    name: name,
                    color: color,
                    surfaceName: surfaceName,
                    surface: surface,
                  ),
            ],
          ),
        ),
        _Section(
          title: 'Fills and lines',
          child: _SwatchWrap(
            children: [
              for (final MapEntry(key: name, value: color) in _fills.entries)
                _Swatch(name: name, color: color),
            ],
          ),
        ),
        _Section(
          title: 'Typography',
          note:
              'System fonts: Roboto, then Segoe UI, Helvetica Neue, Noto Sans '
              'and Arial.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: VeloraSpacing.sm,
            children: [
              Text('displayMedium 48', style: text.displayMedium),
              Text('displaySmall 36', style: text.displaySmall),
              Text('headlineLarge 32', style: text.headlineLarge),
              Text('headlineMedium 28', style: text.headlineMedium),
              Text('headlineSmall 22', style: text.headlineSmall),
              Text('titleLarge 20', style: text.titleLarge),
              Text('titleMedium 16', style: text.titleMedium),
              Text('titleSmall 14', style: text.titleSmall),
              Text(
                'bodyLarge 16: readable running text',
                style: text.bodyLarge,
              ),
              Text('bodyMedium 14: supporting text', style: text.bodyMedium),
              Text('bodySmall 12: helper text', style: text.bodySmall),
              Text('labelLarge 14: button labels', style: text.labelLarge),
              Text('labelMedium 12: badges', style: text.labelMedium),
            ],
          ),
        ),
        _Section(
          title: 'Spacing',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: VeloraSpacing.xs,
            children: [
              for (final (name, value) in const [
                ('xxs', VeloraSpacing.xxs),
                ('xs', VeloraSpacing.xs),
                ('sm', VeloraSpacing.sm),
                ('md', VeloraSpacing.md),
                ('lg', VeloraSpacing.lg),
                ('xl', VeloraSpacing.xl),
                ('xxl', VeloraSpacing.xxl),
                ('xxxl', VeloraSpacing.xxxl),
              ])
                Row(
                  children: [
                    SizedBox(
                      width: 72,
                      child: Text(
                        '$name ${value.toInt()}',
                        style: text.bodySmall,
                      ),
                    ),
                    Container(
                      width: value,
                      height: 12,
                      color: VeloraColors.accentText,
                    ),
                  ],
                ),
            ],
          ),
        ),
        _Section(
          title: 'Radii and depth',
          child: Wrap(
            spacing: VeloraSpacing.md,
            runSpacing: VeloraSpacing.md,
            children: [
              for (final (name, radius, shadow) in const [
                ('sm 8', VeloraRadii.sm, <BoxShadow>[]),
                ('md 12', VeloraRadii.md, <BoxShadow>[]),
                ('lg 16', VeloraRadii.lg, <BoxShadow>[]),
                ('md 12, raised', VeloraRadii.md, VeloraShadows.raised),
              ])
                Container(
                  width: 128,
                  padding: const EdgeInsets.all(VeloraSpacing.md),
                  decoration: BoxDecoration(
                    color: VeloraColors.surfaceRaised,
                    borderRadius: BorderRadius.circular(radius),
                    border: Border.all(color: VeloraColors.outlineSubtle),
                    boxShadow: shadow,
                  ),
                  child: Text(name, style: text.bodySmall),
                ),
            ],
          ),
        ),
        _Section(
          title: 'Motion',
          note: 'All of these become instant with reduced motion.',
          child: Text(
            'fast ${VeloraMotion.fast.inMilliseconds} ms   '
            'standard ${VeloraMotion.standard.inMilliseconds} ms   '
            'slow ${VeloraMotion.slow.inMilliseconds} ms   '
            'loading fade ${VeloraMotion.pulse.inMilliseconds} ms',
            style: text.bodyMedium,
          ),
        ),
      ],
    );
  }
}

class _SwatchWrap extends StatelessWidget {
  const _SwatchWrap({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: VeloraSpacing.sm,
      runSpacing: VeloraSpacing.sm,
      children: children,
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.name, required this.color});

  final String name;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return SizedBox(
      width: 140,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 56,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(VeloraRadii.sm),
              border: Border.all(color: VeloraColors.outlineSubtle),
            ),
          ),
          const SizedBox(height: VeloraSpacing.xxs),
          Text(name, style: text.labelMedium),
          Text(_hex(color), style: text.bodySmall),
        ],
      ),
    );
  }
}

class _ContrastSample extends StatelessWidget {
  const _ContrastSample({
    required this.name,
    required this.color,
    required this.surfaceName,
    required this.surface,
  });

  final String name;
  final Color color;
  final String surfaceName;
  final Color surface;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      width: 172,
      padding: const EdgeInsets.all(VeloraSpacing.sm),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(VeloraRadii.sm),
        border: Border.all(color: VeloraColors.outlineSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(name, style: text.labelLarge?.copyWith(color: color)),
          Text(
            '$surfaceName ${_contrast(color, surface).toStringAsFixed(1)}:1',
            style: text.bodySmall?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

// --------------------------------------------------------------- Actions

class _ActionsTab extends StatelessWidget {
  const _ActionsTab();

  @override
  Widget build(BuildContext context) {
    return _TabPage(
      children: [
        for (final variant in VeloraButtonVariant.values)
          _Section(
            title:
                '${variant.name[0].toUpperCase()}${variant.name.substring(1)} button',
            child: Wrap(
              spacing: VeloraSpacing.sm,
              runSpacing: VeloraSpacing.sm,
              children: [
                VeloraButton(
                  label: 'Enabled',
                  variant: variant,
                  onPressed: () {},
                ),
                VeloraButton(
                  label: 'With icon',
                  variant: variant,
                  icon: Icons.play_arrow,
                  onPressed: () {},
                ),
                _ForcedStateButton(
                  label: 'Hover',
                  variant: variant,
                  state: WidgetState.hovered,
                ),
                _ForcedStateButton(
                  label: 'Focus',
                  variant: variant,
                  state: WidgetState.focused,
                ),
                _ForcedStateButton(
                  label: 'Pressed',
                  variant: variant,
                  state: WidgetState.pressed,
                ),
                VeloraButton(
                  label: 'Disabled',
                  variant: variant,
                  onPressed: null,
                ),
                VeloraButton(
                  label: 'Loading',
                  variant: variant,
                  isLoading: true,
                  onPressed: () {},
                ),
              ],
            ),
          ),
        _Section(
          title: 'Full width',
          child: VeloraButton(
            label: 'Continue',
            expand: true,
            onPressed: () {},
          ),
        ),
        _Section(
          title: 'Themed built-in dialog and notification',
          note: 'These are plain Flutter widgets with the VeloraUG theme.',
          child: Wrap(
            spacing: VeloraSpacing.sm,
            runSpacing: VeloraSpacing.sm,
            children: [
              VeloraButton(
                label: 'Open dialog',
                variant: VeloraButtonVariant.secondary,
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Demonstration dialog'),
                    content: const Text(
                      'A themed AlertDialog. Nothing happens if you confirm.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Confirm'),
                      ),
                    ],
                  ),
                ),
              ),
              VeloraButton(
                label: 'Show notification',
                variant: VeloraButtonVariant.secondary,
                onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('Demonstration notification.'),
                    action: SnackBarAction(label: 'Undo', onPressed: () {}),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Holds a button in one visual state, so states can be compared side by side.
class _ForcedStateButton extends StatefulWidget {
  const _ForcedStateButton({
    required this.label,
    required this.variant,
    required this.state,
  });

  final String label;
  final VeloraButtonVariant variant;
  final WidgetState state;

  @override
  State<_ForcedStateButton> createState() => _ForcedStateButtonState();
}

class _ForcedStateButtonState extends State<_ForcedStateButton> {
  late final WidgetStatesController _controller = WidgetStatesController({
    widget.state,
  });

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: ExcludeFocus(
        child: VeloraButton(
          label: widget.label,
          variant: widget.variant,
          statesController: _controller,
          onPressed: () {},
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- Fields

class _FieldsTab extends StatefulWidget {
  const _FieldsTab();

  @override
  State<_FieldsTab> createState() => _FieldsTabState();
}

class _FieldsTabState extends State<_FieldsTab> {
  final _formKey = GlobalKey<FormState>();
  bool _validated = false;

  String? _requireEmail(String? value) {
    if (value == null || value.isEmpty) return 'Enter an email address.';
    if (!value.contains('@')) return 'Include an @ in the email address.';
    return null;
  }

  String? _requirePassword(String? value) =>
      (value == null || value.length < 8) ? 'Use at least 8 characters.' : null;

  @override
  Widget build(BuildContext context) {
    return _TabPage(
      children: [
        _Section(
          title: 'Demonstration form',
          note:
              'Validates on this device only. It sends nothing and signs '
              'nobody in. Press Validate with the fields empty to see errors.',
          child: Align(
            alignment: Alignment.topLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: VeloraLayout.formWidth,
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: VeloraSpacing.md,
                  children: [
                    VeloraTextField(
                      label: 'Email',
                      helperText: 'Demonstration only.',
                      keyboardType: TextInputType.emailAddress,
                      validator: _requireEmail,
                    ),
                    VeloraPasswordField(
                      helperText: 'At least 8 characters.',
                      validator: _requirePassword,
                    ),
                    VeloraButton(
                      label: 'Validate',
                      expand: true,
                      onPressed: () {
                        final valid = _formKey.currentState!.validate();
                        setState(() => _validated = valid);
                      },
                    ),
                    if (_validated)
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: StatusBadge(
                          label: 'Both fields are valid',
                          tone: StatusTone.success,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        _Section(
          title: 'Field states',
          child: Align(
            alignment: Alignment.topLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: VeloraLayout.formWidth,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: VeloraSpacing.md,
                children: const [
                  VeloraTextField(label: 'Empty'),
                  VeloraTextField(
                    label: 'With hint',
                    hintText: 'A hint appears when focused',
                  ),
                  VeloraTextField(label: 'Disabled', enabled: false),
                  VeloraPasswordField(
                    label: 'Disabled password',
                    enabled: false,
                  ),
                ],
              ),
            ),
          ),
        ),
        _Section(
          title: 'Search',
          note:
              'Type to reveal the clear control. Nothing you type is sent '
              'anywhere.',
          child: Align(
            alignment: Alignment.topLeft,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: VeloraLayout.readingWidth,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                spacing: VeloraSpacing.md,
                children: const [
                  VeloraSearchField(),
                  VeloraSearchField(
                    label: 'Search unavailable',
                    enabled: false,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- Movies

List<Widget> _demoCards({VoidCallback? onTap}) => [
  MovieCard(title: 'Demo Title One', subtitle: 'Demo, 2026', onTap: onTap),
  MovieCard(
    title: 'Demo Title Two',
    subtitle: 'Demo, 2025',
    status: const StatusBadge(label: 'Purchased', tone: StatusTone.success),
    onTap: onTap,
  ),
  MovieCard(
    title: 'A Deliberately Long Demonstration Title That Needs More Than Two Lines',
    subtitle: 'Demo, 2024',
    onTap: onTap,
  ),
  MovieCard(
    title: 'Demo Title Four',
    subtitle: 'Demo, 2023',
    status: const StatusBadge(label: 'Processing', tone: StatusTone.warning),
    onTap: onTap,
  ),
];

class _MoviesTab extends StatelessWidget {
  const _MoviesTab();

  @override
  Widget build(BuildContext context) {
    return _TabPage(
      children: [
        _Section(
          title: 'Movie cards',
          note:
              'Demonstration titles with neutral local artwork. Tab to one to '
              'see focus, hover with a mouse, or press and hold.',
          child: MovieCardGrid(
            children: [
              ..._demoCards(onTap: () {}),
              const MovieCard(
                title: 'Demo: no action',
                subtitle: 'Not tappable',
              ),
            ],
          ),
        ),
        const _Section(
          title: 'Loading placeholders',
          note: 'Fades slowly, and holds still with reduced motion.',
          child: VeloraLoadingRegion(
            label: 'Loading demonstration movies',
            child: MovieCardGrid(
              children: [
                MovieCardSkeleton(),
                MovieCardSkeleton(),
                MovieCardSkeleton(),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// -------------------------------------------------------------- Feedback

class _FeedbackTab extends StatelessWidget {
  const _FeedbackTab({required this.reduced, required this.setReduced});

  final bool reduced;
  final ValueChanged<bool> setReduced;

  @override
  Widget build(BuildContext context) {
    return _TabPage(
      children: [
        const _Section(
          title: 'Status badges',
          note: 'Each one has an icon and words, as well as a colour.',
          child: Wrap(
            spacing: VeloraSpacing.sm,
            runSpacing: VeloraSpacing.sm,
            children: [
              StatusBadge(label: 'Neutral'),
              StatusBadge(label: 'Information', tone: StatusTone.info),
              StatusBadge(label: 'Success', tone: StatusTone.success),
              StatusBadge(label: 'Warning', tone: StatusTone.warning),
              StatusBadge(label: 'Error', tone: StatusTone.danger),
            ],
          ),
        ),
        _Section(
          title: 'Empty state',
          child: EmptyState(
            icon: Icons.movie_outlined,
            title: 'Nothing here (demonstration)',
            message: 'An empty state explains why, and may offer a next step.',
            action: VeloraButton(
              label: 'Demonstration action',
              variant: VeloraButtonVariant.secondary,
              onPressed: () {},
            ),
          ),
        ),
        _Section(
          title: 'Error state',
          child: ErrorState(
            title: 'That failed (demonstration)',
            message: 'An error state says what happened and what to do next.',
            onRetry: () {},
          ),
        ),
        const _Section(
          title: 'Spinner',
          child: Row(
            spacing: VeloraSpacing.sm,
            children: [
              VeloraSpinner(),
              Expanded(child: Text('Loading demonstration content…')),
            ],
          ),
        ),
        _Section(
          title: 'Reduced motion',
          note:
              'The device setting reads as '
              '${MediaQuery.of(context).disableAnimations ? 'on' : 'off'} '
              'inside this page. The switch only simulates it for the '
              'showcase, and changes no device setting.',
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Simulate reduced motion'),
            value: reduced,
            onChanged: setReduced,
          ),
        ),
      ],
    );
  }
}

// --------------------------------------------------------------- Layouts

class _LayoutsTab extends StatelessWidget {
  const _LayoutsTab();

  @override
  Widget build(BuildContext context) {
    return const _TabPage(
      children: [
        _Section(
          title: 'Narrow: 360 pixels wide',
          note: 'A phone. Demonstration content, drawn smaller if needed.',
          child: _LayoutExample(size: Size(360, 640), label: 'Narrow layout'),
        ),
        _Section(
          title: 'Medium: 768 pixels wide',
          note: 'A tablet. Demonstration content, drawn smaller if needed.',
          child: _LayoutExample(size: Size(768, 560), label: 'Medium layout'),
        ),
        _Section(
          title: 'Wide: 1280 pixels wide',
          note: 'A desktop. Demonstration content, drawn smaller if needed.',
          child: _LayoutExample(size: Size(1280, 640), label: 'Wide layout'),
        ),
      ],
    );
  }
}

/// Draws a screen as it would appear on a device of [size], scaled to fit.
class _LayoutExample extends StatelessWidget {
  const _LayoutExample({required this.size, required this.label});

  final Size size;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topLeft,
      child: Semantics(
        label: '$label example',
        container: true,
        child: ExcludeSemantics(
          child: IgnorePointer(
            child: ExcludeFocus(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.topLeft,
                child: Container(
                  width: size.width,
                  height: size.height,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: VeloraColors.canvas,
                    border: Border.all(color: VeloraColors.outline),
                    borderRadius: BorderRadius.circular(VeloraRadii.md),
                  ),
                  child: MediaQuery(
                    data: MediaQuery.of(context).copyWith(size: size),
                    child: ScreenBody(
                      heading: 'Demonstration screen',
                      hero: true,
                      intro: 'Sample text, not a real catalogue.',
                      maxWidth: VeloraLayout.browseWidth,
                      children: [MovieCardGrid(children: _demoCards())],
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

// ------------------------------------------------------------- Text size

class _TextSizeTab extends StatelessWidget {
  const _TextSizeTab();

  @override
  Widget build(BuildContext context) {
    return _TabPage(
      children: [
        for (final scale in const [1.0, 1.3, 2.0])
          _Section(
            title: 'Text at ${(scale * 100).round()}%',
            child: MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: const _TextSizeSample(),
            ),
          ),
      ],
    );
  }
}

class _TextSizeSample extends StatelessWidget {
  const _TextSizeSample();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: VeloraSpacing.md,
      children: [
        Wrap(
          spacing: VeloraSpacing.sm,
          runSpacing: VeloraSpacing.sm,
          children: [
            VeloraButton(label: 'Demo action', onPressed: () {}),
            const StatusBadge(label: 'Demo status', tone: StatusTone.info),
          ],
        ),
        const VeloraSearchField(),
        const VeloraTextField(label: 'Demo field', helperText: 'Helper text.'),
        MovieCardGrid(children: _demoCards().take(2).toList()),
        const EmptyState(
          icon: Icons.movie_outlined,
          title: 'Demonstration empty state',
          message: 'Text grows, and the layout grows with it.',
        ),
      ],
    );
  }
}
