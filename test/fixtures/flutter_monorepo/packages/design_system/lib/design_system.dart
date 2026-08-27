// This fixture resolves dependencies from its own copied workspace.
// ignore_for_file: depend_on_referenced_packages

import 'package:flutter/material.dart';

class PrimaryButton extends StatelessWidget {
  final String label;

  const PrimaryButton({required this.label});

  @override
  Widget build(BuildContext context) => Text(label);
}

// These deliberate collisions verify that references are matched to resolved
// declarations rather than names in another workspace package.
class SessionStore {
  String token = '';
  int refreshCount = 0;

  SessionStore.production();

  void refresh() => refreshCount++;
}
