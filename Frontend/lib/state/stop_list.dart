import 'package:flutter/foundation.dart';
import '../models/store.dart';

/// The user's list of stops. Every page uses the SAME list (see `stopList`
/// at the bottom). When it changes, pages that listen to it redraw themselves.
class StopList extends ChangeNotifier {
  final List<Store> _stops = [];

  /// Read-only view of the stops, in the order the user wants to visit them.
  List<Store> get stops => List.unmodifiable(_stops);

  bool contains(Store s) => _stops.any((x) => x.id == s.id);

  void add(Store s) {
    if (contains(s)) return;
    _stops.add(s);
    notifyListeners(); // tell every listening page: "I changed, redraw!"
  }

  void remove(Store s) {
    _stops.removeWhere((x) => x.id == s.id);
    notifyListeners();
  }

  void toggle(Store s) => contains(s) ? remove(s) : add(s);

  /// Called when the user drags a stop to a new position.
  void reorder(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex -= 1; // Flutter counts the gap one too far
    final item = _stops.removeAt(oldIndex);
    _stops.insert(newIndex, item);
    notifyListeners();
  }

  /// Atomically apply the edited order from the map's Added Shops sheet.
  /// The shared listeners refresh only after the whole list is updated.
  void replaceAll(List<Store> stores) {
    final seen = <String>{};
    _stops
      ..clear()
      ..addAll(stores.where((store) => seen.add(store.id)));
    notifyListeners();
  }

  void clear() {
    _stops.clear();
    notifyListeners();
  }

  /// Total estimated visiting time of all stops (walking time not included).
  int get totalMinutes => _stops.fold(0, (sum, s) => sum + s.avgVisitMinutes);

  /// ROUGH placeholder: 3 min between two stops, +2 min if the floor changes.
  /// The navigation teammate replaces this with the real walking time
  /// calculated from the route. This is the ONLY place that needs to change.
  int get estimatedWalkingMinutes {
    var total = 0;
    for (var i = 1; i < _stops.length; i++) {
      total += 3;
      if (_stops[i].floor != _stops[i - 1].floor) total += 2;
    }
    return total;
  }
}

/// The one shared list used by the whole app.
final StopList stopList = StopList();
