import 'package:hyena_dart/hyena_dart.dart';

Future<void> main(List<String> arguments) async {
  final runner = HyenaCommandRunner();
  await runner.run(arguments);
}
