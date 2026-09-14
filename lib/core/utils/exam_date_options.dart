List<DateTime> examDateOptions({DateTime? now}) {
  final today = _dateOnly(now ?? DateTime.now());
  return List.generate(61, (i) => today.add(Duration(days: i)));
}

DateTime _dateOnly(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

String formatExamDate(DateTime date) {
  final y = date.year.toString().padLeft(4, '0');
  final m = date.month.toString().padLeft(2, '0');
  final d = date.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}
