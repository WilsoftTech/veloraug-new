import 'package:flutter/material.dart';

import '../widgets/empty_state.dart';
import '../widgets/screen_body.dart';

class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const ScreenBody(
      heading: 'Account',
      children: [
        EmptyState(
          icon: Icons.person_off_outlined,
          title: "You're signed out",
          message:
              "Accounts aren't available yet, so there is no way to sign in. "
              'Sign-in will be added in a later step.',
        ),
      ],
    );
  }
}
