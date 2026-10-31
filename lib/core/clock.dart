/// Süre hesabı için monotonik saat (cihaz saati değişse de etkilenmez).
abstract class MonotonicClock {
  int get millis;
}

class StopwatchClock implements MonotonicClock {
  StopwatchClock() {
    _sw.start();
  }
  final Stopwatch _sw = Stopwatch();
  @override
  int get millis => _sw.elapsedMilliseconds;
}

/// Testlerde elle ilerletilen saat.
class FakeClock implements MonotonicClock {
  int _now = 0;
  @override
  int get millis => _now;
  void advance(Duration d) => _now += d.inMilliseconds;
}
