@pragma('vm:entry-point')
void nativeCallback() => _helper();

void _helper() => _transitiveHelper();
void _transitiveHelper() {}

class NativeMethods {
  @pragma('vm:entry-point', 'call')
  static void callback() => _methodHelper();
}

void _methodHelper() {}

@pragma("vm:entry-point")
class NativeClass {
  void callback() => _classHelper();
}

void _classHelper() {}

class NativeFields {
  @pragma('vm:entry-point')
  static final callback = _fieldHelper;
}

void _fieldHelper() {}

void unusedControl() {}

@pragma('vm:prefer-inline')
void inlineControl() => _inlineHelper();

void _inlineHelper() {}

@pragma('')
void emptyPragmaControl() {}
