import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../theme.dart';
import 'page_curl.dart';

/// Dışarıdan sayfa çevirmeyi yöneten denetleyici.
class PageTurnerController extends ChangeNotifier {
  PageTurnerController({int initial = 0}) : _index = initial;
  _PageTurnerState? _state;
  int _index;

  int get index => _index;
  bool get busy => _state?._busy ?? false;

  void _set(int i) {
    if (i == _index) return;
    _index = i;
    notifyListeners();
  }

  /// Animasyonsuz atlama (ör. başka bir sayı açıldığında).
  void jump(int i) => _set(i);

  Future<void> next() async => _state?._go(_index + 1);
  Future<void> prev() async => _state?._go(_index - 1);
  Future<void> goTo(int i) async => _state?._go(i);
}

/// Kâğıt çevirme etkileşimi.
///
/// Navigasyon (dizin, sınırlar, kilit) efektten bağımsızdır; efekt aynı
/// navigasyonun üstüne çizilir. Sayfa kenarındaki dar şeritlerden yatay
/// sürükleyerek çevrilir: bulmaca alanındaki dokunmalar ve sürüklemeler
/// çakışmaz. Animasyon sürerken ikinci bir geçiş başlatılamaz.
///
/// "Animasyonları azalt" (uygulama ayarı ya da işletim sistemi) açıkken sade
/// bir çapraz geçiş kullanılır. Kare süreleri düşerse (düşük donanım)
/// perspektif ve gölge kapatılıp yalnızca kayma kullanılır.
class PageTurner extends StatefulWidget {
  const PageTurner({
    super.key,
    required this.controller,
    required this.itemCount,
    required this.itemBuilder,
    this.reduceMotion = false,
    this.onChanged,
    this.onTurn,
  });

  final PageTurnerController controller;
  final int itemCount;
  final Widget Function(BuildContext context, int index) itemBuilder;
  final bool reduceMotion;
  final ValueChanged<int>? onChanged;

  /// Sayfa çevirme başladığında/onaylandığında (ses için); `forward` ileri mi.
  final void Function(bool forward)? onTurn;

  @override
  State<PageTurner> createState() => _PageTurnerState();
}

class _PageTurnerState extends State<PageTurner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;
  int _from = 0;
  int _to = 0;
  bool _busy = false;
  bool _dragging = false;
  bool _lowQuality = false;

  /// Kıvrılmanın çıktığı dikey konum (0..1): sürüklemede parmağın başladığı
  /// yer, düğmeyle çevirmede alt köşeye yakın.
  double _anchorY = 0.9;
  int _slowFrames = 0;

  bool get _forward => _to > _from;
  int get _index => widget.controller.index.clamp(0, widget.itemCount - 1);

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this);
    widget.controller._state = this;
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  @override
  void didUpdateWidget(PageTurner old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller._state = null;
      widget.controller._state = this;
    }
  }

  @override
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    widget.controller._state = null;
    _anim.dispose();
    super.dispose();
  }

  void _onTimings(List<FrameTiming> t) {
    if (!_busy) return;
    for (final f in t) {
      if (f.totalSpan.inMilliseconds > 40) {
        _slowFrames++;
      } else if (_slowFrames > 0) {
        _slowFrames--;
      }
    }
    if (_slowFrames >= 4 && !_lowQuality && mounted) {
      setState(() => _lowQuality = true);
    }
  }

  bool _reduced(BuildContext context) =>
      widget.reduceMotion || MediaQuery.disableAnimationsOf(context);

  /// Güvenli sayfa geçişi: sınır dışı ve meşgulken yok sayılır.
  Future<void> _go(int target) async {
    if (_busy || target == _index) return;
    if (target < 0 || target >= widget.itemCount) return;
    _anchorY = 0.9;
    _begin(target);
    widget.onTurn?.call(_forward);
    await _anim.animateTo(
      1,
      duration: _reduced(context)
          ? const Duration(milliseconds: 180)
          : const Duration(milliseconds: 520),
      curve: Curves.easeInOutCubic,
    );
    _commit();
  }

  void _begin(int target) {
    setState(() {
      _from = _index;
      _to = target;
      _busy = true;
      _anim.value = 0;
    });
  }

  void _commit() {
    if (!mounted) return;
    setState(() {
      widget.controller._set(_to);
      _busy = false;
      _dragging = false;
      _anim.value = 0;
    });
    widget.onChanged?.call(_to);
  }

  void _cancel() {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _dragging = false;
      _anim.value = 0;
    });
  }

  // ------------------------------------------------------------- sürükleme

  /// [forward]: sağ kenardan sola sürükleyerek ileri; sol kenardan sağa geri.
  void _dragStart(bool forward, double anchorY) {
    _anchorY = anchorY.clamp(0.3, 1.0);
    if (_busy) return;
    final target = _index + (forward ? 1 : -1);
    if (target < 0 || target >= widget.itemCount) return;
    _begin(target);
    _dragging = true;
  }

  void _dragUpdate(DragUpdateDetails d, double width) {
    if (!_dragging) return;
    final delta = (_forward ? -d.delta.dx : d.delta.dx) / width;
    _anim.value = (_anim.value + delta).clamp(0.0, 1.0);
  }

  Future<void> _dragEnd(DragEndDetails d, double width) async {
    if (!_dragging) return;
    final raw =
        (_forward
            ? -d.velocity.pixelsPerSecond.dx
            : d.velocity.pixelsPerSecond.dx) /
        width;
    final v = raw.isFinite ? raw : 0.0;
    final complete = v > 0.8 || (v >= -0.8 && _anim.value > 0.4);
    if (complete) {
      widget.onTurn?.call(_forward);
      await _anim.animateTo(
        1,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
      );
      _commit();
    } else {
      await _anim.animateTo(
        0,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOut,
      );
      _cancel();
    }
  }

  // ---------------------------------------------------------------- çizim

  @override
  Widget build(BuildContext context) {
    final reduced = _reduced(context);
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        final current = RepaintBoundary(
          child: widget.itemBuilder(context, _index),
        );
        Widget stage;
        if (!_busy) {
          stage = current;
        } else {
          stage = AnimatedBuilder(
            animation: _anim,
            builder: (context, _) => _frame(context, reduced, w),
          );
        }
        final edge = (!reduced && !_busy) || _dragging;
        return Stack(
          children: [
            Positioned.fill(child: stage),
            if (!reduced) ...[
              _strip(
                left: 0,
                forward: false,
                width: w,
                height: box.maxHeight,
                enabled: edge && _index > 0,
              ),
              _strip(
                right: 0,
                forward: true,
                width: w,
                height: box.maxHeight,
                enabled: edge && _index < widget.itemCount - 1,
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _strip({
    double? left,
    double? right,
    required bool forward,
    required double width,
    required double height,
    required bool enabled,
  }) {
    return Positioned(
      left: left,
      right: right,
      top: 0,
      bottom: 0,
      width: 36,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        excludeFromSemantics: true,
        onHorizontalDragStart: enabled
            ? (d) => _dragStart(forward, d.localPosition.dy / height)
            : null,
        // Güncelleme/bitiş hep bağlı kalır; durumu işleyiciler denetler.
        onHorizontalDragUpdate: (d) => _dragUpdate(d, width * 0.85),
        onHorizontalDragEnd: (d) => _dragEnd(d, width * 0.85),
        onHorizontalDragCancel: () => _dragEnd(DragEndDetails(), width),
      ),
    );
  }

  Widget _frame(BuildContext context, bool reduced, double w) {
    final t = _anim.value;
    final under = RepaintBoundary(
      child: widget.itemBuilder(context, _forward ? _to : _from),
    );
    final flip = RepaintBoundary(
      child: widget.itemBuilder(context, _forward ? _from : _to),
    );
    if (reduced) {
      // Sade geçiş: çapraz solma.
      final k = _forward ? t : 1 - t;
      return Stack(
        fit: StackFit.expand,
        children: [
          under,
          Opacity(opacity: (1 - k).clamp(0.0, 1.0), child: flip),
        ],
      );
    }
    if (_lowQuality) {
      final dx = -(_forward ? t : 1 - t) * w;
      return Stack(
        fit: StackFit.expand,
        children: [
          under,
          Transform.translate(offset: Offset(dx, 0), child: flip),
        ],
      );
    }
    final pal = context.pal;
    // Gerçek kıvrılma: ileri giderken mevcut sayfa, geri giderken önceki sayfa
    // köşesinden katlanır (geri: 1 → 0).
    return PageCurl(
      front: flip,
      under: under,
      t: _forward ? t : 1 - t,
      anchorY: _anchorY,
      paper: pal.paper,
      backPaper: pal.paperDeep,
    );
  }
}
