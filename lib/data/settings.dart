enum PaperTheme {
  ivory('Fildişi'),
  white('Beyaz kâğıt'),
  night('Gece baskısı');

  const PaperTheme(this.label);
  final String label;
}

class AppSettings {
  const AppSettings({
    this.paper = PaperTheme.ivory,
    this.textScale = 1.0,
    this.sound = true,
    this.haptics = true,
    this.reduceMotion = false,
    this.highlightErrors = true,
    this.liveFeedback = true,
    this.showTimer = true,
    this.sudokuAutoClear = false,
    this.sudokuShowConflicts = true,
    this.onboardingDone = false,
    this.lastIssueId,
    this.lastPage = 0,
    this.firstLaunchDate,
  });

  final PaperTheme paper;

  /// 0.9 … 1.4 arası, sistem yazı büyüklüğüyle çarpılır.
  final double textScale;
  final bool sound;
  final bool haptics;
  final bool reduceMotion;
  final bool highlightErrors;

  /// Yazarken yanlış harf anında kırmızı, doğru kelime yeşil gösterilir.
  final bool liveFeedback;
  final bool showTimer;
  final bool sudokuAutoClear;
  final bool sudokuShowConflicts;
  final bool onboardingDone;
  final String? lastIssueId;
  final int lastPage;

  /// Uygulamanın ilk açıldığı yerel gün (yyyy-MM-dd). Sayı numarasının
  /// başlangıcıdır: o gün 1. Sayı.
  final String? firstLaunchDate;

  AppSettings copyWith({
    PaperTheme? paper,
    double? textScale,
    bool? sound,
    bool? haptics,
    bool? reduceMotion,
    bool? highlightErrors,
    bool? liveFeedback,
    bool? showTimer,
    bool? sudokuAutoClear,
    bool? sudokuShowConflicts,
    bool? onboardingDone,
    String? lastIssueId,
    int? lastPage,
    String? firstLaunchDate,
  }) => AppSettings(
    paper: paper ?? this.paper,
    textScale: textScale ?? this.textScale,
    sound: sound ?? this.sound,
    haptics: haptics ?? this.haptics,
    reduceMotion: reduceMotion ?? this.reduceMotion,
    highlightErrors: highlightErrors ?? this.highlightErrors,
    liveFeedback: liveFeedback ?? this.liveFeedback,
    showTimer: showTimer ?? this.showTimer,
    sudokuAutoClear: sudokuAutoClear ?? this.sudokuAutoClear,
    sudokuShowConflicts: sudokuShowConflicts ?? this.sudokuShowConflicts,
    onboardingDone: onboardingDone ?? this.onboardingDone,
    lastIssueId: lastIssueId ?? this.lastIssueId,
    lastPage: lastPage ?? this.lastPage,
    firstLaunchDate: firstLaunchDate ?? this.firstLaunchDate,
  );

  Map<String, dynamic> toJson() => {
    'schema': 1,
    'paper': paper.name,
    'textScale': textScale,
    'sfx': sound,
    'haptics': haptics,
    'reduceMotion': reduceMotion,
    'highlightErrors': highlightErrors,
    'liveFeedback': liveFeedback,
    'showTimer': showTimer,
    'sudokuAutoClear': sudokuAutoClear,
    'sudokuShowConflicts': sudokuShowConflicts,
    'onboardingDone': onboardingDone,
    'lastIssueId': lastIssueId,
    'lastPage': lastPage,
    'firstLaunch': firstLaunchDate,
  };

  /// Eksik/yanlış alanlar varsayılana düşer; ayar dosyası yüzünden uygulama
  /// açılışı engellenmez.
  factory AppSettings.fromJson(Map<String, dynamic> j) {
    bool b(String k, bool d) => j[k] is bool ? j[k] as bool : d;
    final ts = j['textScale'];
    return AppSettings(
      paper: PaperTheme.values.firstWhere(
        (p) => p.name == j['paper'],
        orElse: () => PaperTheme.ivory,
      ),
      textScale: ts is num ? ts.toDouble().clamp(0.9, 1.4) : 1.0,
      sound: b('sfx', true),
      haptics: b('haptics', true),
      reduceMotion: b('reduceMotion', false),
      highlightErrors: b('highlightErrors', true),
      liveFeedback: b('liveFeedback', true),
      showTimer: b('showTimer', true),
      sudokuAutoClear: b('sudokuAutoClear', false),
      sudokuShowConflicts: b('sudokuShowConflicts', true),
      onboardingDone: b('onboardingDone', false),
      lastIssueId: j['lastIssueId'] is String
          ? j['lastIssueId'] as String
          : null,
      lastPage: j['lastPage'] is int ? j['lastPage'] as int : 0,
      firstLaunchDate: j['firstLaunch'] is String
          ? j['firstLaunch'] as String
          : null,
    );
  }
}
