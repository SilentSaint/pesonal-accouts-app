class AuthenticationSessionGuard {
  int _generation = 0;

  int beginOperation() => _generation;

  bool isCurrent(int generation) => generation == _generation;

  void invalidate() {
    _generation++;
  }
}
