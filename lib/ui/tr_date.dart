const trMonths = [
  'Ocak',
  'Şubat',
  'Mart',
  'Nisan',
  'Mayıs',
  'Haziran',
  'Temmuz',
  'Ağustos',
  'Eylül',
  'Ekim',
  'Kasım',
  'Aralık',
];
const trDays = [
  'Pazartesi',
  'Salı',
  'Çarşamba',
  'Perşembe',
  'Cuma',
  'Cumartesi',
  'Pazar',
];

/// “30 Ekim 2026 Cuma” (yerel tarih; locale verisi gerektirmez).
String trDate(DateTime d) =>
    '${d.day} ${trMonths[d.month - 1]} ${d.year} ${trDays[d.weekday - 1]}';
