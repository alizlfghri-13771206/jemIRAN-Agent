import "package:intl/intl.dart";
import "package:shamsi_date/shamsi_date.dart";

extension JalaliFormat on DateTime {
  String toShamsi() {
    final j = Jalali.fromDateTime(this);
    final month = j.month.toString().padLeft(2, '0');
    final day = j.day.toString().padLeft(2, '0');
    final time = DateFormat('HH:mm').format(this);
    return "$month/$day  $time";
  }
}
