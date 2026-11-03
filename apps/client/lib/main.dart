import 'package:flutter/material.dart';

import 'app.dart';
import 'showcase/design_system_showcase.dart';
import 'showcase/showcase_gate.dart';

void main() {
  runApp(showcaseEnabled ? const DesignSystemShowcase() : const VeloraApp());
}
