import 'package:flutter/foundation.dart';

/// Settings for today's visit. For now: how much time the user has.
/// Shared by the chat (which asks for it) and the Stop List (which shows it).
class TripSettings extends ChangeNotifier {
  int? _timeBudgetMinutes; // null = no time limit

  int? get timeBudgetMinutes => _timeBudgetMinutes;

  void setTimeBudget(int? minutes) {
    _timeBudgetMinutes = minutes;
    notifyListeners();
  }

  /// 90 -> '90 min', 120 -> '2 hours', null -> 'No limit'
  static String label(int? minutes) {
    if (minutes == null) return 'No limit';
    if (minutes >= 60 && minutes % 60 == 0) {
      return minutes == 60 ? '1 hour' : '${minutes ~/ 60} hours';
    }
    return '$minutes min';
  }
}

/// The one shared instance used by the whole app.
final TripSettings tripSettings = TripSettings();
