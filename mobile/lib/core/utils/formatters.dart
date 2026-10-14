/// Fungsi format kecil yang dipakai lintas layar.
library;

/// `Duration(hours: 1, minutes: 1, seconds: 1)` → "1:01:01"; 12 menit → "12:00".
String formatDuration(Duration d) {
  if (d.isNegative) d = Duration.zero;
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60);
  final mm = h > 0 ? m.toString().padLeft(2, '0') : m.toString();
  final ss = s.toString().padLeft(2, '0');
  return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
}

/// Ambil tahun 4 digit dari teks bebas ("Released: 2019", "2012-2014").
String? yearOf(String? text) {
  if (text == null) return null;
  final m = RegExp(r'(19|20)\d{2}').firstMatch(text);
  return m?.group(0);
}

/// Hostname ringkas untuk label tautan.
String hostOf(String url) {
  if (url.startsWith('magnet:')) return 'magnet';
  try {
    final host = Uri.parse(url).host;
    return host.startsWith('www.') ? host.substring(4) : host;
  } catch (_) {
    return 'tautan';
  }
}

/// Peringkat resolusi untuk sort (tertinggi dulu).
int resolutionRank(String res) {
  final m = RegExp(r'(\d{3,4})').firstMatch(res);
  if (m != null) return int.tryParse(m.group(1)!) ?? 0;
  final lower = res.toLowerCase();
  if (lower.contains('4k') || lower.contains('uhd')) return 2160;
  if (lower.contains('fhd')) return 1080;
  if (lower.contains('hd')) return 720;
  return 0;
}

/// Bersihkan skor seperti "Rating 8.7 / 10" → "8.7".
String? cleanScore(String? score) {
  if (score == null) return null;
  final m = RegExp(r'\d+(?:[.,]\d+)?').firstMatch(score);
  return m?.group(0)?.replaceAll(',', '.');
}

/// Potong teks panjang dengan elipsis.
String truncate(String text, int max) =>
    text.length <= max ? text : '${text.substring(0, max).trimRight()}…';

const _idMonths = <String, int>{
  'januari': 1, 'februari': 2, 'maret': 3, 'april': 4, 'mei': 5, 'juni': 6,
  'juli': 7, 'agustus': 8, 'september': 9, 'oktober': 10, 'november': 11,
  'desember': 12,
  'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'jun': 6, 'jul': 7, 'agu': 8,
  'aug': 8, 'sep': 9, 'okt': 10, 'oct': 10, 'nov': 11, 'des': 12, 'dec': 12,
  'january': 1, 'february': 2, 'march': 3, 'may': 5, 'june': 6, 'july': 7,
  'august': 8, 'october': 10, 'december': 12,
};

/// Parse tanggal rilis dari berbagai format sumber:
/// ISO ("2026-10-14"), "14 Oktober 2026", "October 14, 2026", "14/10/2026".
DateTime? parseLooseDate(String? text) {
  if (text == null) return null;
  final t = text.trim();
  if (t.isEmpty) return null;

  final iso = DateTime.tryParse(t);
  if (iso != null) return iso;

  final dmy = RegExp(r'(\d{1,2})[/-](\d{1,2})[/-](\d{4})').firstMatch(t);
  if (dmy != null) {
    return DateTime(int.parse(dmy.group(3)!), int.parse(dmy.group(2)!),
        int.parse(dmy.group(1)!));
  }

  final dMonthY =
      RegExp(r'(\d{1,2})\s+([A-Za-z]+)\s*,?\s*(\d{4})').firstMatch(t);
  if (dMonthY != null) {
    final month = _idMonths[dMonthY.group(2)!.toLowerCase()];
    if (month != null) {
      return DateTime(int.parse(dMonthY.group(3)!), month,
          int.parse(dMonthY.group(1)!));
    }
  }

  final monthDY =
      RegExp(r'([A-Za-z]+)\s+(\d{1,2})\s*,?\s*(\d{4})').firstMatch(t);
  if (monthDY != null) {
    final month = _idMonths[monthDY.group(1)!.toLowerCase()];
    if (month != null) {
      return DateTime(int.parse(monthDY.group(3)!), month,
          int.parse(monthDY.group(2)!));
    }
  }
  return null;
}

const weekdayNamesId = <String>[
  'Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu', 'Minggu',
];

const weekdayShortId = <String>['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'];

/// "Hari ini", "Kemarin", "3 hari lalu", atau tanggal singkat.
String relativeDate(DateTime d) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(d.year, d.month, d.day);
  final diff = today.difference(day).inDays;
  if (diff <= 0) return 'Hari ini';
  if (diff == 1) return 'Kemarin';
  if (diff < 7) return '$diff hari lalu';
  return '${d.day}/${d.month}/${d.year}';
}
