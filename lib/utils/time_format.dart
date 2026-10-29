import 'package:intl/intl.dart';

DateFormat kombuDateTimeFormat(bool use24Hour) =>
    use24Hour ? DateFormat('MMM d, HH:mm') : DateFormat('MMM d, h:mm a');

String formatKombuDateTime(DateTime d, bool use24Hour) =>
    kombuDateTimeFormat(use24Hour).format(d);
