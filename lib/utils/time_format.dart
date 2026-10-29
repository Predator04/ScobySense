import 'package:intl/intl.dart';

DateFormat appDateTimeFormat(bool use24Hour) =>
    use24Hour ? DateFormat('MMM d, HH:mm') : DateFormat('MMM d, h:mm a');

String formatAppDateTime(DateTime d, bool use24Hour) =>
    appDateTimeFormat(use24Hour).format(d);
