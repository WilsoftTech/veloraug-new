import 'package:flutter/material.dart';

import '../widgets/empty_state.dart';
import '../widgets/screen_body.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ScreenBody(
      heading: 'Welcome to VeloraUG',
      children: [
        Text(
          'A movie platform for web and Android, still being built.',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
        const EmptyState(
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
