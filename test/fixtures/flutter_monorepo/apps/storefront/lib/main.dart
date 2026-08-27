// This fixture resolves dependencies from its own copied workspace.
// ignore_for_file: depend_on_referenced_packages

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:shared_core/shared_core.dart' as core;

class StorefrontApp extends StatelessWidget {
  final core.SessionStore store;

  const StorefrontApp(this.store);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(home: PrimaryButton(label: store.token));
  }
}

void neverRegistered() {
  final service = core.DeferredService.live();
  service.activate();
}

void invokeDynamic(dynamic plugin) => plugin.activate();

void main() {
  final store = core.SessionStore.production();
  store.token = 'signed-in';
  store.refresh();
  print(store.refreshCount);
  runApp(StorefrontApp(store));
}
