abstract class Widget {
  const Widget();
}

class BuildContext {
  const BuildContext();
}

abstract class StatelessWidget extends Widget {
  const StatelessWidget();

  Widget build(BuildContext context);
}

class MaterialApp extends Widget {
  final Widget home;

  const MaterialApp({required this.home});
}

class Text extends Widget {
  final String data;

  const Text(this.data);
}

void runApp(Widget app) {}
