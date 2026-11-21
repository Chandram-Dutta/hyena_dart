class pragma {
  const pragma(String name);
}

@pragma('vm:entry-point')
void unusedCallback() => _unusedHelper();

void _unusedHelper() {}
