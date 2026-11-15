class CalendarEvent {
  const CalendarEvent({
    required this.title,
    required this.start,
    required this.end,
    required this.allDay,
  });

  final String title;
  final DateTime start;
  final DateTime end;
  final bool allDay;
}

abstract interface class DeviceCalendar {
  Future<bool> hasAccess();
  Future<bool> requestAccess();
  Future<void> openSettings();
  Future<List<CalendarEvent>> eventsOn(DateTime day);
}
