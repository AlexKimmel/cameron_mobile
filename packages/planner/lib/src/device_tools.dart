import 'task.dart';

class DeviceToolField {
  const DeviceToolField(
    this.name,
    this.label,
    this.maxLength, {
    this.required = true,
    this.normalize,
  });

  final String name;
  final String label;
  final int maxLength;
  final bool required;
  final String Function(String)? normalize;

  String? read(Map<String, Object?> arguments) {
    final value = arguments[name];
    if (!required &&
        (value == null || (value is String && value.trim().isEmpty))) {
      return null;
    }
    if (value is! String ||
        value.trim().isEmpty ||
        value.trim().length > maxLength) {
      throw FormatException(
        'The assistant returned an invalid ${label.toLowerCase()}.',
      );
    }
    final text = value.trim();
    return normalize?.call(text) ?? text;
  }
}

class DeviceTool {
  const DeviceTool({
    required this.name,
    required this.label,
    required this.description,
    required this.reviewAction,
    required this.fields,
  });

  final String name;
  final String label;
  final String description;
  final String reviewAction;
  final List<DeviceToolField> fields;

  DeviceToolDraft draft(Map<String, Object?> arguments) {
    final values = <String, String>{};
    for (final field in fields) {
      if (field.read(arguments) case final value?) values[field.name] = value;
    }
    return DeviceToolDraft._(this, Map.unmodifiable(values));
  }
}

class DeviceToolDraft {
  const DeviceToolDraft._(this.tool, this.arguments);

  final DeviceTool tool;
  final Map<String, String> arguments;
}

abstract interface class DeviceToolStore {
  Future<bool> isEnabled(String name);
  Future<void> setEnabled(String name, bool enabled);
}

const phoneCallTool = DeviceTool(
  name: 'prepare_call',
  label: 'Phone calls',
  description:
      'Prepare a call to a phone number for the user to review and place.',
  reviewAction: 'Open phone',
  fields: [_phone],
);

const smsTool = DeviceTool(
  name: 'draft_message',
  label: 'SMS',
  description:
      'Draft an SMS to a phone number for the user to review and send.',
  reviewAction: 'Open Messages',
  fields: [_phone, _body],
);

const emailTool = DeviceTool(
  name: 'draft_email',
  label: 'Email',
  description:
      'Draft an email to one email address for the user to review and send.',
  reviewAction: 'Open email app',
  fields: [
    DeviceToolField('email', 'Email address', 254, normalize: _email),
    DeviceToolField(
      'subject',
      'Subject',
      200,
      required: false,
      normalize: _subject,
    ),
    _body,
  ],
);

const communicationTools = [phoneCallTool, smsTool, emailTool];

const taskCompletionTool = DeviceTool(
  name: 'complete_task',
  label: 'Task completion',
  description:
      'Mark an existing Cameron task complete after the user reviews it.',
  reviewAction: 'Mark complete',
  fields: [DeviceToolField('id', 'Task ID', 100)],
);

const calendarReadTool = DeviceTool(
  name: 'read_calendar',
  label: 'Calendar events',
  description: 'Read device calendar events for one local date after review.',
  reviewAction: 'Read calendar',
  fields: [
    DeviceToolField(
      'day',
      'Local date YYYY-MM-DD',
      10,
      normalize: _calendarDay,
    ),
  ],
);

String _calendarDay(String text) {
  final date = DateTime.tryParse(text);
  if (date == null || dayKey(date) != text) {
    throw const FormatException('Choose a calendar date in YYYY-MM-DD format.');
  }
  return text;
}

const _phone = DeviceToolField(
  'phone',
  'Phone number',
  35,
  normalize: _phoneNumber,
);
const _body = DeviceToolField('body', 'Message', 1500);

String _phoneNumber(String value) {
  final number = value.replaceAll(RegExp(r'[\s().-]'), '');
  if (!RegExp(r'^\+?[0-9]{3,15}$').hasMatch(number)) {
    throw const FormatException('Enter a valid phone number.');
  }
  return number;
}

String _email(String value) {
  final address = RegExp(
    r"^[A-Za-z0-9!#$%&'*+/=?^_`{|}~-]+(?:\.[A-Za-z0-9!#$%&'*+/=?^_`{|}~-]+)*"
    r'@(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)+'
    r'[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?$',
  );
  if (!address.hasMatch(value) || value.indexOf('@') > 64) {
    throw const FormatException('Enter one valid email address.');
  }
  return value;
}

String _subject(String value) {
  if (value.contains(RegExp(r'[\x00-\x1f\x7f]'))) {
    throw const FormatException('The email subject must be a single line.');
  }
  return value;
}
