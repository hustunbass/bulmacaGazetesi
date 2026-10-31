import 'package:flutter/material.dart';

import '../data/settings.dart';

/// Gazete baskısı paleti. Renk tek başına anlam taşımaz: hata/başarı ayrıca
/// simge, çizgi veya şekille de gösterilir.
class Palette {
  const Palette({
    required this.brightness,
    required this.paper,
    required this.paperDeep,
    required this.ink,
    required this.inkSoft,
    required this.rule,
    required this.accent,
    required this.ok,
    required this.bad,
    required this.selection,
    required this.related,
    required this.hintFill,
    required this.block,
  });

  final Brightness brightness;
  final Color paper;
  final Color paperDeep;
  final Color ink;
  final Color inkSoft;
  final Color rule;
  final Color accent;
  final Color ok;
  final Color bad;
  final Color selection;
  final Color related;
  final Color hintFill;
  final Color block;

  static const ivory = Palette(
    brightness: Brightness.light,
    paper: Color(0xFFF4EEDF),
    paperDeep: Color(0xFFE9E1CD),
    ink: Color(0xFF1E1B18),
    inkSoft: Color(0xFF5B544B),
    rule: Color(0xFFBDB5A3),
    accent: Color(0xFF8E2B21),
    ok: Color(0xFF2F6B3A),
    bad: Color(0xFFA6261B),
    selection: Color(0xFFF3D98B),
    related: Color(0xFFE8DDB5),
    hintFill: Color(0xFFDCE6D3),
    block: Color(0xFF2A2622),
  );

  static const white = Palette(
    brightness: Brightness.light,
    paper: Color(0xFFFBFAF6),
    paperDeep: Color(0xFFEFEDE6),
    ink: Color(0xFF16171A),
    inkSoft: Color(0xFF55585E),
    rule: Color(0xFFC4C4BF),
    accent: Color(0xFF7A2E24),
    ok: Color(0xFF2F6B3A),
    bad: Color(0xFFA6261B),
    selection: Color(0xFFF1DC95),
    related: Color(0xFFEAE3C3),
    hintFill: Color(0xFFDDE8D6),
    block: Color(0xFF26282C),
  );

  static const night = Palette(
    brightness: Brightness.dark,
    paper: Color(0xFF1C1B19),
    paperDeep: Color(0xFF292723),
    ink: Color(0xFFEDE6D6),
    inkSoft: Color(0xFFB0A894),
    rule: Color(0xFF4B473F),
    accent: Color(0xFFE08B7B),
    ok: Color(0xFF86C493),
    bad: Color(0xFFFF8E80),
    selection: Color(0xFF6B5A22),
    related: Color(0xFF3B362A),
    hintFill: Color(0xFF2F4332),
    block: Color(0xFF0C0B0A),
  );

  static Palette of(PaperTheme t) => switch (t) {
    PaperTheme.ivory => ivory,
    PaperTheme.white => white,
    PaperTheme.night => night,
  };
}

class PaletteExt extends ThemeExtension<PaletteExt> {
  const PaletteExt(this.palette);
  final Palette palette;
  @override
  PaletteExt copyWith({Palette? palette}) =>
      PaletteExt(palette ?? this.palette);
  @override
  PaletteExt lerp(ThemeExtension<PaletteExt>? other, double t) => this;
}

extension PaletteContext on BuildContext {
  Palette get pal => Theme.of(this).extension<PaletteExt>()!.palette;
}

class AppFonts {
  AppFonts._();
  static const serif = 'Playfair';
  static const sans = 'SourceSans';
}

TextStyle serifStyle(
  Color c,
  double size, {
  FontWeight w = FontWeight.w700,
  double? h,
  double? ls,
}) => TextStyle(
  fontFamily: AppFonts.serif,
  color: c,
  fontSize: size,
  fontWeight: w,
  height: h,
  letterSpacing: ls,
);

TextStyle sansStyle(
  Color c,
  double size, {
  FontWeight w = FontWeight.w500,
  double? h,
  double? ls,
}) => TextStyle(
  fontFamily: AppFonts.sans,
  color: c,
  fontSize: size,
  fontWeight: w,
  height: h,
  letterSpacing: ls,
);

ThemeData buildTheme(PaperTheme t) {
  final p = Palette.of(t);
  final base = ThemeData(
    useMaterial3: true,
    brightness: p.brightness,
    fontFamily: AppFonts.sans,
    scaffoldBackgroundColor: p.paper,
    colorScheme:
        ColorScheme.fromSeed(
          seedColor: p.accent,
          brightness: p.brightness,
        ).copyWith(
          surface: p.paper,
          onSurface: p.ink,
          primary: p.accent,
          error: p.bad,
          outline: p.rule,
        ),
    dividerColor: p.rule,
    splashFactory: InkRipple.splashFactory,
    extensions: [PaletteExt(p)],
  );
  return base.copyWith(
    appBarTheme: AppBarTheme(
      backgroundColor: p.paper,
      foregroundColor: p.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: serifStyle(p.ink, 20),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.paper,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
        side: BorderSide(color: p.rule),
      ),
      titleTextStyle: serifStyle(p.ink, 20),
      contentTextStyle: sansStyle(p.ink, 16, h: 1.4),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.paper,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: p.ink,
      contentTextStyle: sansStyle(p.paper, 15),
      behavior: SnackBarBehavior.floating,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: p.ink,
        foregroundColor: p.paper,
        minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
        textStyle: sansStyle(p.paper, 16, w: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: p.ink,
        minimumSize: const Size(48, 48),
        side: BorderSide(color: p.ink, width: 1),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(3)),
        textStyle: sansStyle(p.ink, 16, w: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: p.accent,
        minimumSize: const Size(48, 48),
        textStyle: sansStyle(p.accent, 16, w: FontWeight.w700),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? p.paper : p.inkSoft,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? p.ink : p.paperDeep,
      ),
    ),
  );
}
