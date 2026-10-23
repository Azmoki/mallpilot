import 'package:flutter/material.dart';
import '../models/route_mode.dart';
import '../state/stop_list.dart';
import '../state/trip_settings.dart';
import 'navigation_page.dart';
import 'map_start_picker_page.dart';
import '../state/pinned_start.dart';

/// Shows the saved stops. The order here = the "follow my sequence" order.
class StopListPage extends StatelessWidget {
  const StopListPage({super.key});

  /// Pop-up that asks: follow my sequence, or shortest path?
  Future<void> _chooseMode(BuildContext context) async {
    // showDialog waits until the user picks something, then gives it back.
    final mode = await showDialog<RouteMode>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('How do you want to go?'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, RouteMode.sequence),
            child: const ListTile(
              leading: Icon(Icons.format_list_numbered),
              title: Text('Follow my sequence'),
              subtitle: Text('Visit the stops in the order of my list'),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, RouteMode.shortest),
            child: const ListTile(
              leading: Icon(Icons.alt_route),
              title: Text('Shortest path'),
              subtitle: Text('Reorder the stops to walk the least'),
            ),
          ),
        ],
      ),
    );

    // User tapped outside the pop-up, or the page is gone: do nothing.
    if (mode == null || !context.mounted) return;

    var start = pinnedStart.value;
    if (start == null) {
      start = await Navigator.push<PinnedStart>(context,
        MaterialPageRoute(builder: (_) => const MapStartPickerPage()));
      if (start == null || !context.mounted) return;
      pinnedStart.value = start;
    }
    if (!context.mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => NavigationPage(
          mode: mode, stops: stopList.stops, startPosition: start)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Added Shops')),
      // ListenableBuilder redraws this part whenever stopList changes.
      body: ListenableBuilder(
        listenable: stopList,
        builder: (context, _) {
          final stops = stopList.stops;
          if (stops.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No stops yet.\nSave stores from the Store Directory.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return Column(
            children: [
              const _TimeSummary(),
              Expanded(
                child: ReorderableListView.builder(
                  buildDefaultDragHandles: false,
                  itemCount: stops.length,
                  onReorder: stopList.reorder,
                  itemBuilder: (context, i) {
                    final s = stops[i];
                    return ListTile(
                      key: ValueKey(s.id), // needed so Flutter can track each row
                      leading: CircleAvatar(child: Text('${i + 1}')),
                      title: Text(s.name),
                      subtitle: Text(
                        '${s.floorLabel} · about ${s.avgVisitMinutes} min visit',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.delete_outline),
                            tooltip: 'Remove',
                            onPressed: () => stopList.remove(s),
                          ),
                          ReorderableDragStartListener(
                            index: i,
                            child: const Icon(Icons.drag_handle),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: FilledButton.icon(
                      icon: const Icon(Icons.directions_walk),
                      label: const Text("Let's go!"),
                      onPressed: stops.isEmpty ? null : () => _chooseMode(context),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Top of the Stop List: visiting + walking time compared with the time available.
class _TimeSummary extends StatelessWidget {
  const _TimeSummary();

  @override
  Widget build(BuildContext context) {
    // Redraw when the stops OR the time budget change.
    return ListenableBuilder(
      listenable: Listenable.merge([stopList, tripSettings]),
      builder: (context, _) {
        final budget = tripSettings.timeBudgetMinutes;
        final visiting = stopList.totalMinutes;
        final planned = visiting;
        final over = budget != null && planned > budget;
        final errorColor = Theme.of(context).colorScheme.error;

        // Choices in the drop-down (plus the current value if it is unusual).
        final options = <int?>[null, 30, 60, 90, 120, 180];
        if (budget != null && !options.contains(budget)) options.add(budget);

        return Card(
          margin: const EdgeInsets.all(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.schedule),
                    const SizedBox(width: 8),
                    Text(
                      '${stopList.stops.length} stops',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
                Row(
                  children: [
                    const Text('Time available: '),
                    DropdownButton<int?>(
                      value: budget,
                      items: [
                        for (final m in options)
                          DropdownMenuItem<int?>(
                            value: m,
                            child: Text(TripSettings.label(m)),
                          ),
                      ],
                      onChanged: tripSettings.setTimeBudget,
                    ),
                  ],
                ),
                const Text('Your starting point is a separate map pin. All selected shops are destinations.'),
                Text('Destination visit time: about $visiting min (walking time not calibrated).'),
                if (stopList.stops.isEmpty)
                  const Text('Add at least one GF shop to plan a route.'),
                if (budget != null) ...[
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: (planned / budget).clamp(0.0, 1.0).toDouble(),
                    color: over ? errorColor : null,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    over
                        ? 'Visit times alone exceed limit by ${planned - budget} min. '
                            'Remove a stop or choose more time.'
                        : '${budget - planned} min remaining for walking (not yet measured)',
                    style: over ? TextStyle(color: errorColor) : null,
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
