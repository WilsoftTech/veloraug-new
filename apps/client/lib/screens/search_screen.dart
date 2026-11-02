import 'package:flutter/material.dart';

import '../widgets/empty_state.dart';
import '../widgets/screen_body.dart';

class SearchScreen extends StatelessWidget {
  const SearchScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ScreenBody(
      heading: 'Search',
      children: [
        TextField(
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            labelText: 'Search movies',
            prefixIcon: Icon(Icons.search),
            border: OutlineInputBorder(),
          ),
        ),
        EmptyState(
          icon: Icons.manage_search,
          title: "Search isn't connected yet",
          message:
              'Search will start working when the movie catalogue is added '
              "in a later step. What you type here isn't sent anywhere.",
        ),
      ],
    );
  }
}
