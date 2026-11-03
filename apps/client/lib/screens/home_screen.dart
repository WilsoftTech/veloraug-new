import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import '../widgets/empty_state.dart';
import '../widgets/screen_body.dart';
import '../widgets/status_badge.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ScreenBody(
      heading: 'Welcome to VeloraUG',
      intro: 'A movie platform for web and Android, still being built.',
      status: StatusBadge(label: 'In development', tone: StatusTone.info),
      hero: true,
      maxWidth: VeloraLayout.browseWidth,
      children: [
        EmptyState(
          icon: Icons.movie_outlined,
          title: 'No movies yet',
          message:
              "The catalogue isn't connected, so there is nothing to browse "
              'yet. Movies will appear here in a later step.',
        ),
      ],
    );
  }
}
