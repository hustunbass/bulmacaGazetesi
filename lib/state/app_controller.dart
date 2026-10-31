import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/ads.dart';
import '../core/clock.dart';
import '../core/sfx.dart';
import '../data/content_library.dart';
import '../data/file_store.dart';
import '../data/settings.dart';
import '../domain/attempt.dart';
import '../domain/issue_planner.dart';
import '../domain/newspaper.dart';
import '../domain/play_timer.dart';
import '../domain/puzzle.dart';
import '../domain/puzzle_game.dart';
import '../domain/sudoku_game.dart';
import '../domain/sudoku_generator.dart';
import '../domain/validator.dart';
import '../domain/word_game.dart';
import '../domain/word_structure.dart';
import 'attempt_session.dart';

enum NewPuzzleOutcome { replaced, exhausted, generationFailed, busy }

/// Bir yuvanın kayıt okuma sorunu.
class SlotProblem {
  const SlotProblem(this.slotId, this.reason);
  final String slotId;
  final String reason;
}

/// Arşiv listesi için özet.
class IssueSummary {
  const IssueSummary({
    required this.issue,
    required this.completed,
    required this.inProgress,
    required this.total,
    required this.types,
    required this.difficulties,
  });
  final NewspaperIssue issue;
  final int completed;
  final int inProgress;
  final int total;
  final Set<PuzzleType> types;
  final Set<Difficulty> difficulties;

  bool get notStarted => completed == 0 && inProgress == 0;
  bool get isComplete => total > 0 && completed == total;
}

/// Uygulama durumunun sahibi: gazete sayısı, oturumlar, ayarlar, kayıt.
class AppController extends ChangeNotifier implements SessionHost {
  AppController({
    required this.store,
    required this.library,
    MonotonicClock? clock,
    DateTime Function()? now,
    this.sfx = const NoopSfx(),
    this.ads = const NoopAds(),
  }) : clock = clock ?? StopwatchClock(),
       _now = now ?? DateTime.now;

  final FileStore store;
  final ContentLibrary library;
  final MonotonicClock clock;
  final Sfx sfx;
  final Ads ads;
  final DateTime Function() _now;

  AppSettings settings = const AppSettings();
  NewspaperIssue? issue;
  final Map<String, AttemptSession> _sessions = {};
  final Map<String, SlotProblem> problems = {};
  final List<String> notices = [];
  List<CompletionRecord> completions = [];
  AttemptSession? active;
  bool ready = false;
  String? fatalError;

  /// Bugünün sayısı, kullanıcının açık olan sayısından farklıysa kimliği.
  String? newerIssueId;

  Timer? _ticker;

  /// Aynı yuvada eşzamanlı sıfırla/yeni bulmaca/kurtarma çakışmasın.
  final Set<String> _busySlots = {};
  final Map<String, AttemptSession> _justCreated = {};
  int _idCounter = 0;

  // ---------------------------------------------------------------- açılış

  Future<void> init() async {
    try {
      await store.init();
    } on StoreTooNewException catch (e) {
      fatalError =
          'Bu kayıtlar uygulamanın daha yeni bir sürümüyle yazılmış '
          '(${e.found}). Veriler silinmedi; lütfen uygulamayı güncelleyin.';
      ready = true;
      notifyListeners();
      return;
    } on Object catch (e) {
      fatalError = 'Depolama açılamadı: $e';
      ready = true;
      notifyListeners();
      return;
    }
    settings = await _loadSettings();
    await _ensureFirstLaunchDate();
    await _loadGenerated();
    completions = await _loadCompletions();
    if (library.puzzles.isEmpty) {
      fatalError =
          'Bulmaca içeriği yüklenemedi. Bu sürümde internetten yeni '
          'içerik indirilmez; uygulamayı yeniden yüklemeyi deneyin.';
      ready = true;
      notifyListeners();
      return;
    }
    final todayId = NewspaperIssue.idFor(_now());
    final last = settings.lastIssueId;
    var openId = todayId;
    if (last != null && last != todayId) {
      final lastIssue = await _readIssue(last);
      if (lastIssue != null && await _hasUnfinishedProgress(lastIssue)) {
        openId = last;
        newerIssueId = todayId;
      }
    }
    await openIssue(openId, createIfMissing: true);
    ready = true;
    _ticker = Timer.periodic(const Duration(seconds: 10), (_) => _tick());
    notifyListeners();
  }

  /// İlk açılış gününü sabitler (sayı numaralaması buradan başlar). Ayar
  /// kaydı kaybolduysa numaralama sıfırlanmasın diye en eski sayıdan kurtarılır.
  Future<void> _ensureFirstLaunchDate() async {
    if (settings.firstLaunchDate != null) return;
    final ids = await store.list('issues')
      ..sort();
    final first = ids.isNotEmpty ? ids.first : NewspaperIssue.idFor(_now());
    settings = settings.copyWith(firstLaunchDate: first);
    store.writeJson('settings.json', settings.toJson());
  }

  DateTime get _firstLaunch {
    final f = settings.firstLaunchDate;
    return f == null ? _now() : NewspaperIssue.parseIssueDate(f);
  }

  Future<AppSettings> _loadSettings() async {
    try {
      final j = await store.readJson('settings.json');
      return j == null ? const AppSettings() : AppSettings.fromJson(j);
    } on StoreCorruptException {
      await store.quarantine('settings.json');
      notices.add(
        'Ayar dosyası okunamadı; varsayılan ayarlar kullanıldı. '
        'Eski dosya "quarantine" klasöründe saklandı.',
      );
      return const AppSettings();
    }
  }

  Future<void> _loadGenerated() async {
    for (final id in await store.list('generated')) {
      try {
        final j = await store.readJson('generated/$id.json');
        if (j == null) continue;
        final p = PuzzleDefinition.fromJson(j);
        // Bu uygulamanın kendi yazdığı dosyalar: hafif doğrulama yeter
        // (derin çözüm sayımı her açılışta maliyeti büyütürdü).
        if (ContentValidator.validate(p, deep: false).isEmpty) library.add(p);
      } on Object {
        await store.quarantine('generated/$id.json');
      }
    }
  }

  Future<List<CompletionRecord>> _loadCompletions() async {
    try {
      final j = await store.readJson('completions.json');
      if (j == null) return [];
      return [
        for (final r in (j['records'] as List))
          CompletionRecord.fromJson(r as Map<String, dynamic>),
      ];
    } on Object {
      await store.quarantine('completions.json');
      notices.add(
        'İstatistik kayıtları okunamadı ve ayrı bir yere alındı; '
        'istatistikler sıfırdan başlıyor.',
      );
      return [];
    }
  }

  // ------------------------------------------------------------------- ses

  void sfxPen() {
    if (settings.sound) sfx.pen();
  }

  void sfxErase() {
    if (settings.sound) sfx.erase();
  }

  void sfxPage({bool back = false}) {
    if (settings.sound) sfx.page(back: back);
  }

  // ----------------------------------------------------------------- ayarlar

  void updateSettings(AppSettings s) {
    settings = s;
    store.writeJson('settings.json', s.toJson());
    notifyListeners();
  }

  // ------------------------------------------------------------------ sayılar

  Future<NewspaperIssue?> _readIssue(String id) async {
    try {
      final j = await store.readJson('issues/$id.json');
      return j == null ? null : NewspaperIssue.fromJson(j);
    } on Object {
      await store.quarantine('issues/$id.json');
      notices.add(
        '$id tarihli sayının kaydı okunamadı; dosya korunarak '
        'sayı yeniden kuruldu. Eski denemeler diskte duruyor.',
      );
      return null;
    }
  }

  Future<bool> _hasUnfinishedProgress(NewspaperIssue iss) async {
    for (final s in iss.slots) {
      final m = await _readAttemptMeta(s.attemptId);
      if (m != null && !m.completed && m.touched) return true;
    }
    return false;
  }

  Future<AttemptMeta?> _readAttemptMeta(String id) async {
    try {
      final j = await store.readJson('attempts/$id.json');
      return j == null ? null : AttemptMeta.fromJson(j);
    } on Object {
      return null;
    }
  }

  Set<String> get _seenPuzzleIds => {
    for (final s in _sessions.values) s.def.id,
  };

  /// Sayıyı açar; yoksa (ve izin varsa) günün deterministik planıyla kurar.
  Future<void> openIssue(String id, {bool createIfMissing = false}) async {
    pauseAll();
    var iss = await _readIssue(id);
    if (iss == null) {
      if (!createIfMissing) return;
      iss = await _createIssue(NewspaperIssue.parseIssueDate(id));
      if (iss == null) {
        fatalError = 'Sayı kurulamadı: yeterli bulmaca içeriği yok.';
        notifyListeners();
        return;
      }
    }
    for (final s in _sessions.values) {
      s.dispose();
    }
    _sessions.clear();
    problems.clear();
    issue = iss;
    for (final slot in iss.slots) {
      await _loadSession(iss, slot);
    }
    for (final s in _justCreated.values) {
      s.dispose();
    }
    _justCreated.clear();
    // Başka bir sayıya geçildiyse önceki sayının sayfa indeksi taşınmaz.
    final changed = settings.lastIssueId != id;
    settings = settings.copyWith(
      lastIssueId: id,
      lastPage: changed ? 0 : settings.lastPage,
    );
    store.writeJson('settings.json', settings.toJson());
    if (id == NewspaperIssue.idFor(_now())) newerIssueId = null;
    notifyListeners();
  }

  Future<NewspaperIssue?> _createIssue(DateTime date) async {
    final id = NewspaperIssue.idFor(date);
    final seed = date.year * 10000 + date.month * 100 + date.day;
    // Daha önce verilmiş bulmacalardan kaçınmak için tüm deneme üst verileri
    // yerine yalnızca anlık oturumlar ve tamamlama kayıtları kullanılır.
    final seen = {..._seenPuzzleIds, for (final c in completions) c.puzzleId};
    final plan = IssuePlanner.plan(
      dateSeed: seed,
      pool: library.puzzles,
      seenPuzzleIds: seen,
    );
    if (plan.isEmpty) return null;
    final pages = <NewspaperPage>[];
    for (var p = 0; p < plan.length; p++) {
      final slots = <PuzzleSlot>[];
      for (var s = 0; s < plan[p].length; s++) {
        final ps = plan[p][s];
        final slotId = 'p${p + 1}s${s + 1}';
        final attempt = _freshAttempt(id, slotId, ps.puzzle);
        await _saveNew(attempt);
        _justCreated[attempt.meta.id] = attempt;
        slots.add(
          PuzzleSlot(
            id: slotId,
            type: ps.type,
            difficulty: ps.difficulty,
            attemptId: attempt.meta.id,
          ),
        );
      }
      pages.add(NewspaperPage(index: p, slots: slots));
    }
    final iss = NewspaperIssue(
      id: id,
      date: date,
      number: NewspaperIssue.numberFor(date, since: _firstLaunch),
      pages: pages,
    );
    store.writeJson('issues/$id.json', iss.toJson());
    return iss;
  }

  // ------------------------------------------------------------------ oturum

  AttemptSession? sessionFor(PuzzleSlot slot) => _sessions[slot.attemptId];

  AttemptSession _freshAttempt(
    String issueId,
    String slotId,
    PuzzleDefinition def,
  ) {
    final meta = AttemptMeta(
      id: _newId(),
      puzzleId: def.id,
      puzzleVersion: def.version,
      issueId: issueId,
      slotId: slotId,
      createdAtMs: _now().millisecondsSinceEpoch,
    );
    return _buildSession(meta, def, null);
  }

  String _newId() =>
      'a${_now().microsecondsSinceEpoch.toRadixString(36)}${(_idCounter++).toRadixString(36)}';

  AttemptSession _buildSession(
    AttemptMeta meta,
    PuzzleDefinition def,
    Map<String, dynamic>? state,
  ) {
    final PuzzleGame game;
    if (def.type == PuzzleType.sudoku) {
      game = state == null ? SudokuGame(def) : SudokuGame.fromJson(def, state);
    } else {
      final st = WordStructure.build(def);
      game = state == null ? WordGame(st) : WordGame.fromJson(st, state);
    }
    return AttemptSession(
      meta: meta,
      def: def,
      game: game,
      timer: PlayTimer(clock, elapsedMs: meta.elapsedMs),
      host: this,
    );
  }

  Future<void> _saveNew(AttemptSession s) async {
    // Denemenin bağlı olduğu tanım sürümü ayrıca saklanır; içerik güncellenirse
    // açık deneme eski sürümle devam eder.
    store.writeJson(
      'snapshots/${s.def.id}@${s.def.version}.json',
      s.def.toJson(),
    );
    store.writeJson('attempts/${s.meta.id}.json', s.toJson());
  }

  Future<PuzzleDefinition?> _resolveDefinition(AttemptMeta m) async {
    final live = library.byId(m.puzzleId);
    if (live != null && live.version == m.puzzleVersion) return live;
    final j = await store.readJson(
      'snapshots/${m.puzzleId}@${m.puzzleVersion}.json',
    );
    return j == null ? null : PuzzleDefinition.fromJson(j);
  }

  Future<AttemptSession?> _readSession(String attemptId) async {
    final j = await store.readJson('attempts/$attemptId.json');
    if (j == null) return null;
    final meta = AttemptMeta.fromJson(j);
    final def = await _resolveDefinition(meta);
    if (def == null) {
      throw StoreCorruptException(
        'attempts/$attemptId.json',
        'Bulmaca tanımı (${meta.puzzleId} v${meta.puzzleVersion}) bulunamadı',
      );
    }
    final state = j['state'];
    if (state is! Map<String, dynamic>) {
      throw StoreCorruptException('attempts/$attemptId.json', 'Durum eksik');
    }
    try {
      return _buildSession(meta, def, state);
    } on CorruptStateException catch (e) {
      throw StoreCorruptException('attempts/$attemptId.json', e.message);
    }
  }

  Future<void> _loadSession(NewspaperIssue iss, PuzzleSlot slot) async {
    // Az önce kurulan sayının oturumları diskten yeniden okunmaz.
    final created = _justCreated.remove(slot.attemptId);
    if (created != null) {
      _sessions[slot.attemptId] = created;
      return;
    }
    try {
      final s = await _readSession(slot.attemptId);
      if (s == null) {
        problems[slot.id] = const SlotProblem('', 'Deneme kaydı bulunamadı');
        return;
      }
      _sessions[slot.attemptId] = s;
    } on Object catch (e) {
      final why = e is StoreCorruptException ? e.reason : '$e';
      problems[slot.id] = SlotProblem(slot.id, why);
      await store.quarantine('attempts/${slot.attemptId}.json');
    }
  }

  /// Okunamayan yuva için kullanıcı onayıyla yeni bir bulmaca verir.
  /// Bozuk dosya karantinada kalır.
  Future<void> recoverSlot(PuzzleSlot slot) async {
    if (!_busySlots.add(slot.id)) return;
    try {
      await _recoverSlot(slot);
    } finally {
      _busySlots.remove(slot.id);
    }
  }

  Future<void> _recoverSlot(PuzzleSlot slot) async {
    final iss = issue;
    if (iss == null) return;
    final def = IssuePlanner.pickFor(
      type: slot.type,
      difficulty: slot.difficulty,
      pool: library.puzzles,
      avoid: _seenPuzzleIds,
      fallbackAvoid: const {},
      salt: slot.id.hashCode,
    );
    if (def == null) return;
    final s = _freshAttempt(iss.id, slot.id, def);
    slot.attemptId = s.meta.id;
    await _saveNew(s);
    _sessions[s.meta.id] = s;
    problems.remove(slot.id);
    store.writeJson('issues/${iss.id}.json', iss.toJson());
    notifyListeners();
  }

  // ------------------------------------------------------------- SessionHost

  @override
  void activate(AttemptSession s) {
    if (active == s && s.timer.running) return;
    pauseAll();
    active = s;
    if (!s.meta.completed) s.timer.start();
  }

  void pauseAll() {
    final a = active;
    if (a == null) return;
    a.timer.pause();
    a.meta.elapsedMs = a.timer.elapsedMs;
    store.writeJson('attempts/${a.meta.id}.json', a.toJson());
    active = null;
  }

  void _tick() {
    final a = active;
    if (a != null && a.timer.running) {
      a.meta.elapsedMs = a.timer.elapsedMs;
      store.writeJson('attempts/${a.meta.id}.json', a.toJson());
      a.touchNotify();
    }
  }

  @override
  void persist(AttemptSession s) {
    store.writeJson('attempts/${s.meta.id}.json', s.toJson());
  }

  /// Tamamlanma bir deneme için yalnızca bir kez kaydedilir.
  @override
  void completed(AttemptSession s) {
    if (s.meta.completionRecorded) return;
    s.meta.completionRecorded = true;
    final rec = CompletionRecord(
      attemptId: s.meta.id,
      puzzleId: s.def.id,
      type: s.def.type,
      difficulty: s.def.difficulty,
      elapsedMs: s.timer.elapsedMs,
      hintCount: s.game.hintCount,
      completedAtMs: s.meta.completedAtMs ?? _now().millisecondsSinceEpoch,
    );
    if (completions.any((c) => c.attemptId == rec.attemptId)) return;
    completions = [...completions, rec];
    store.writeJson('completions.json', {
      'schema': 1,
      'records': [for (final c in completions) c.toJson()],
    });
    if (active == s) active = null;
  }

  // ---------------------------------------------------------------- sıfırla

  /// Aynı bulmacayı baştan başlatır: yeni deneme kimliği, aynı bulmaca.
  /// Tamamlanmış eski deneme ve kaydı korunur; tamamlanmamış olan silinir
  /// (kullanıcı onayı çağıran tarafta alınmıştır).
  Future<void> resetPuzzle(PuzzleSlot slot) async {
    if (!_busySlots.add(slot.id)) return;
    try {
      await _resetPuzzle(slot);
    } finally {
      _busySlots.remove(slot.id);
    }
  }

  Future<void> _resetPuzzle(PuzzleSlot slot) async {
    final iss = issue;
    final old = _sessions[slot.attemptId];
    if (iss == null || old == null) return;
    pauseAll();
    final fresh = _freshAttempt(iss.id, slot.id, old.def);
    final oldId = old.meta.id;
    final keepOld = old.meta.completed;
    if (keepOld) {
      old.meta.archived = true;
      store.writeJson('attempts/$oldId.json', old.toJson());
      slot.history.add(oldId);
    }
    _sessions.remove(oldId);
    old.dispose();
    slot.attemptId = fresh.meta.id;
    _sessions[fresh.meta.id] = fresh;
    await _saveNew(fresh);
    store.writeJson('issues/${iss.id}.json', iss.toJson());
    if (!keepOld) await store.delete('attempts/$oldId.json');
    notifyListeners();
  }

  // ----------------------------------------------------------- yeni bulmaca

  /// Yalnızca bu yuvadaki bulmacayı değiştirir. Mevcut deneme arşivlenir.
  /// Uygun içerik yoksa (ve Sudoku üretilemiyorsa) hiçbir şeyi değiştirmez.
  Future<NewPuzzleOutcome> newPuzzle(
    PuzzleSlot slot, {
    PuzzleType? type,
    Difficulty? difficulty,
  }) async {
    if (!_busySlots.add(slot.id)) return NewPuzzleOutcome.busy;
    try {
      return await _newPuzzle(slot, type: type, difficulty: difficulty);
    } finally {
      _busySlots.remove(slot.id);
    }
  }

  Future<NewPuzzleOutcome> _newPuzzle(
    PuzzleSlot slot, {
    PuzzleType? type,
    Difficulty? difficulty,
  }) async {
    final iss = issue;
    final cur = _sessions[slot.attemptId];
    if (iss == null || cur == null) return NewPuzzleOutcome.exhausted;
    final wantType = type ?? slot.type;
    final wantDiff = difficulty ?? slot.difficulty;

    final avoid = <String>{cur.def.id};
    for (final h in slot.history) {
      final m = await _readAttemptMeta(h);
      if (m != null) avoid.add(m.puzzleId);
    }
    for (final p in iss.pages) {
      for (final s in p.slots) {
        final ss = _sessions[s.attemptId];
        if (ss != null) avoid.add(ss.def.id);
      }
    }
    // Daha önce tamamlanmış bulmacalara en son başvurulur.
    final done = {for (final c in completions) c.puzzleId};
    final salt = _now().millisecondsSinceEpoch;
    var pick = IssuePlanner.pickFor(
      type: wantType,
      difficulty: wantDiff,
      pool: library.puzzles,
      avoid: {...avoid, ...done},
      fallbackAvoid: avoid,
      salt: salt,
    );
    if (pick == null && wantType == PuzzleType.sudoku) {
      pick = await _generateSudoku(wantDiff);
      if (pick == null) return NewPuzzleOutcome.generationFailed;
    }
    if (pick == null) return NewPuzzleOutcome.exhausted;
    // Beklemeler sırasında sayı/oturum değiştiyse eski duruma dokunma.
    if (issue != iss || _sessions[slot.attemptId] != cur) {
      return NewPuzzleOutcome.busy;
    }

    pauseAll();
    cur.meta.archived = true;
    store.writeJson('attempts/${cur.meta.id}.json', cur.toJson());
    slot.history.add(cur.meta.id);
    _sessions.remove(cur.meta.id);
    cur.dispose();

    final fresh = _freshAttempt(iss.id, slot.id, pick);
    slot.type = wantType;
    slot.difficulty = pick.difficulty;
    slot.attemptId = fresh.meta.id;
    _sessions[fresh.meta.id] = fresh;
    await _saveNew(fresh);
    store.writeJson('issues/${iss.id}.json', iss.toJson());
    notifyListeners();
    return NewPuzzleOutcome.replaced;
  }

  /// Yerel Sudoku üretimi ana iş parçacığı dışında çalışır; sonuç yeniden
  /// doğrulanmadan havuza alınmaz.
  Future<PuzzleDefinition?> _generateSudoku(Difficulty d) async {
    final seed = _now().millisecondsSinceEpoch % 1000000;
    final g = await compute(generateSudokuIsolate, (d.index, seed));
    if (g == null) return null;
    final p = PuzzleDefinition(
      id: 'sudoku-yerel-${d.key}-$seed',
      version: 1,
      type: PuzzleType.sudoku,
      difficulty: g.difficulty,
      title: 'Sudoku (yerel üretim)',
      source: 'Cihazda üretildi; tek çözüm doğrulandı',
      license: 'Üretilen içerik (telif konusu yok)',
      rows: 9,
      cols: 9,
      givens: g.givens,
      solution: g.solution,
    );
    if (ContentValidator.validate(p).isNotEmpty) return null;
    library.add(p);
    store.writeJson('generated/${p.id}.json', p.toJson());
    return p;
  }

  // ------------------------------------------------------------------ arşiv

  Future<List<String>> issueIds() async =>
      (await store.list('issues'))..sort((a, b) => b.compareTo(a));

  Future<IssueSummary?> summarize(String id) async {
    final iss = await _readIssue(id);
    if (iss == null) return null;
    var done = 0, prog = 0, total = 0;
    final types = <PuzzleType>{};
    final diffs = <Difficulty>{};
    for (final s in iss.slots) {
      total++;
      final m = await _readAttemptMeta(s.attemptId);
      final def = m == null ? null : library.byId(m.puzzleId);
      if (def != null) {
        types.add(def.type);
        diffs.add(def.difficulty);
      }
      if (m == null) continue;
      if (m.completed) {
        done++;
      } else if (m.touched) {
        prog++;
      }
    }
    return IssueSummary(
      issue: iss,
      completed: done,
      inProgress: prog,
      total: total,
      types: types,
      difficulties: diffs,
    );
  }

  /// Bir yuvanın arşivlenmiş önceki denemeleri (en yeni önce).
  Future<List<AttemptMeta>> previousAttempts(PuzzleSlot slot) async {
    final out = <AttemptMeta>[];
    for (final id in slot.history.reversed) {
      final m = await _readAttemptMeta(id);
      if (m != null) out.add(m);
    }
    return out;
  }

  // ---------------------------------------------------------------- yaşam

  /// Arka plana geçerken: süre durur, tüm yazmalar diske iner.
  Future<void> onBackground() async {
    pauseAll();
    await store.flush();
  }

  /// Öne dönünce yeni gün başlamış mı bakar; kullanıcıyı zorla taşımaz.
  Future<void> onResume() async {
    final today = NewspaperIssue.idFor(_now());
    if (issue != null && issue!.id != today && library.puzzles.isNotEmpty) {
      if (await _readIssue(today) == null) {
        await _createIssue(NewspaperIssue.parseIssueDate(today));
      }
      newerIssueId = today;
      notifyListeners();
    }
  }

  void setLastPage(int page) {
    if (settings.lastPage == page) return;
    settings = settings.copyWith(lastPage: page);
    store.writeJson('settings.json', settings.toJson());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    for (final s in _sessions.values) {
      s.dispose();
    }
    super.dispose();
  }
}
