/// Small calendar helpers for reminder recurrence presets (not full RRULE).
DateTime addCalendarMonths(DateTime d, int months) {
  var y = d.year;
  var m = d.month + months;
  while (m > 12) {
    m -= 12;
    y++;
  }
  while (m < 1) {
    m += 12;
    y--;
  }
  final lastDay = DateTime(y, m + 1, 0).day;
  final day = d.day > lastDay ? lastDay : d.day;
  return DateTime(y, m, day, d.hour, d.minute, d.second);
}

DateTime nextReminderDue(DateTime from, String? rrule) {
  switch (rrule) {
    case 'FREQ=WEEKLY':
      return from.add(const Duration(days: 7));
    case 'FREQ=MONTHLY':
      return addCalendarMonths(from, 1);
    case 'FREQ=MONTHLY;INTERVAL=3':
      return addCalendarMonths(from, 3);
    case 'FREQ=MONTHLY;INTERVAL=6':
      return addCalendarMonths(from, 6);
    case 'FREQ=YEARLY':
      return addCalendarMonths(from, 12);
    default:
      return from;
  }
}

/// Advance [due] until it is strictly after [now] when recurring.
DateTime rollForwardDue(DateTime due, String? rrule, DateTime now) {
  if (rrule == null || rrule.trim().isEmpty) return due;
  var next = due;
  var guard = 0;
  while (!next.isAfter(now) && guard < 240) {
    next = nextReminderDue(next, rrule);
    guard++;
  }
  return next;
}
