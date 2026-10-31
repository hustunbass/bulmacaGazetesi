import '../core/clock.dart';

/// Aktif çözüm süresi. Yalnızca [start] ile [pause] arasında işler ve
/// monotonik saat kullandığı için cihaz saatinin değişmesinden etkilenmez.
class PlayTimer {
  PlayTimer(this._clock, {int elapsedMs = 0}) : _base = elapsedMs;

  final MonotonicClock _clock;
  int _base;
  int? _startedAt;

  bool get running => _startedAt != null;

  int get elapsedMs =>
      _base + (_startedAt == null ? 0 : _clock.millis - _startedAt!);

  void start() => _startedAt ??= _clock.millis;

  void pause() {
    final s = _startedAt;
    if (s == null) return;
    _base += _clock.millis - s;
    _startedAt = null;
  }

  void reset() {
    _base = 0;
    _startedAt = null;
  }
}
