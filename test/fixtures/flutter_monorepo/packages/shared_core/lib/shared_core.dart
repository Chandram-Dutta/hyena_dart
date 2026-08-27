class SessionStore {
  String _token;
  int refreshCount = 0;

  SessionStore.production() : _token = 'anonymous';
  SessionStore.unused() : _token = 'unused';

  String get token => _token;
  set token(String value) => _token = value;

  void refresh() {
    refreshCount++;
    _persist();
  }

  void unusedMethod() {}

  void _persist() {}
}

class DeferredService {
  DeferredService.live();

  void activate() => _dependency();

  void _dependency() {}
}
