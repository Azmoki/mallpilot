import 'package:flutter/material.dart';

import '../data/store_repository.dart';
import '../models/route_mode.dart';
import '../models/store.dart';
import '../widgets/store_logo.dart';
import '../widgets/mall_glass_card.dart';
import '../services/mallpilot_api.dart';
import '../services/app_language.dart';
import '../state/pinned_start.dart';
import 'map_start_picker_page.dart';
import 'navigation_page.dart';

/// Adaptive, interest-based recommendation flow. Retains the map-pinned start.
/// Visit durations are deliberately excluded: the directory's 20-minute values
/// are placeholders and do not represent observed customer visits.
class RecommendedJourneyPage extends StatefulWidget {
  const RecommendedJourneyPage({super.key});

  @override
  State<RecommendedJourneyPage> createState() => _RecommendedJourneyPageState();
}

class _InterestChoice {
  final String key;
  final String name;
  final IconData icon;
  const _InterestChoice(this.key, this.name, this.icon);

  String get displayName => switch (key) {
    'food' => AppLanguage.t('cat_food'),
    'fashion' => AppLanguage.t('cat_fashion'),
    'beauty' => AppLanguage.t('cat_beauty'),
    'electronics' => AppLanguage.t('cat_electronics'),
    'sportswear' => AppLanguage.t('cat_sportswear'),
    'home' => AppLanguage.t('cat_home'),
    'groceries' => AppLanguage.t('cat_groceries'),
    'accessories' => AppLanguage.t('cat_accessories'),
    'entertainment' => AppLanguage.t('cat_entertainment'),
    _ => name,
  };
}

const _choices = <_InterestChoice>[
  _InterestChoice('food', 'Food & Drinks', Icons.restaurant_outlined),
  _InterestChoice('fashion', 'Fashion', Icons.checkroom_outlined),
  _InterestChoice('beauty', 'Beauty & Care', Icons.spa_outlined),
  _InterestChoice('electronics', 'Electronics', Icons.phone_android_outlined),
  _InterestChoice('sportswear', 'Sports', Icons.sports_basketball_outlined),
  _InterestChoice('home', 'Home & Lifestyle', Icons.home_outlined),
  _InterestChoice('groceries', 'Groceries', Icons.shopping_basket_outlined),
  _InterestChoice('accessories', 'Accessories', Icons.watch_outlined),
  _InterestChoice('entertainment', 'Entertainment', Icons.sports_esports_outlined),
];

const _wine = MallGlassStyle.accent; // Consistent with home-screen action green.

class _RecommendedJourneyPageState extends State<RecommendedJourneyPage> {
  late final Future<List<Store>> _stores = StoreRepository.loadStores();
  final Set<String> _interests = {'food', 'fashion'};
  String _spending = 'balanced';
  String _style = 'balanced';
  int _step = 0; // 0: interests, 1: preferences, 2: journey preview.
  PinnedStart? _start = pinnedStart.value;
  bool _loading = false;
  String? _error;
  int _variation = 0;
  List<Store> _suggested = [];
  Set<String> _included = {};
  Set<String> _locked = {};
  Map<String, String> _matchedCategory = {};
  double? _distancePx;

  @override
  void initState() {
    super.initState();
    pinnedStart.addListener(_syncCurrentPin);
  }

  void _syncCurrentPin() {
    if (!mounted || pinnedStart.value == null) return;
    if (_start?.point == pinnedStart.value!.point) return;
    setState(() {
      _start = pinnedStart.value;
      // Keep suggestions editable; the route is regenerated from the updated
      // pin when the user next taps Generate Path.
      _distancePx = null;
    });
  }

  @override
  void dispose() {
    pinnedStart.removeListener(_syncCurrentPin);
    super.dispose();
  }

  void _clearRecommendations() {
    _suggested = [];
    _included.clear();
    _locked.clear();
    _matchedCategory.clear();
    _distancePx = null;
    _variation = 0;
    _error = null;
  }

  void _goBack() {
    if (_step == 0 || _loading) return;
    setState(() => _step--);
  }

  int get _defaultStops => switch (_style) {
    'quick' => 3,
    'discovery' => 5,
    _ => 4,
  };

  Future<void> _pickStart() async {
    final result = await Navigator.push<PinnedStart>(context,
      MaterialPageRoute(builder: (_) => MapStartPickerPage(initial: _start)));
    if (!mounted || result == null) return;
    pinnedStart.value = result;
    setState(() {
      _start = result;
      _clearRecommendations();
    });
  }

  Future<void> _recommend(List<Store> directory, {bool shuffle = false}) async {
    if (_interests.isEmpty) {
      setState(() => _error = 'Choose at least one interest.');
      return;
    }
    if (_start == null) {
      await _pickStart();
      if (!mounted || _start == null) return;
    }
    if (shuffle) _variation++;
    setState(() { _loading = true; _error = null; });
    try {
      final response = await MallPilotApi.adaptiveJourney(
        startPosition: _start!.toApi(), interests: _interests.toList(),
        spending: _spending, style: _style, maxStops: _defaultStops,
        lockedShopIds: shuffle ? _locked.toList() : const [],
        variation: _variation,
      );
      if (!mounted) return;
      final byId = {for (final shop in directory) shop.id: shop};
      final rows = (response['recommendations'] as List<dynamic>? ?? []);
      final stores = <Store>[];
      final matched = <String, String>{};
      for (final raw in rows) {
        final row = Map<String, dynamic>.from(raw as Map);
        final id = row['shop_id'].toString();
        final shop = byId[id];
        if (shop == null) continue;
        stores.add(shop);
        matched[id] = (row['composition_interest'] ?? '').toString();
      }
      setState(() {
        _suggested = stores;
        _matchedCategory = matched;
        _included = stores.map((shop) => shop.id).toSet();
        _locked = _locked.intersection(_included);
        _distancePx = ((response['journey'] as Map?)?['total_distance_px'] as num?)?.toDouble();
        _loading = false;
        if (stores.isEmpty) {
          _error = (response['notice'] ?? 'No matching mapped stores found.').toString();
        } else {
          _step = 2; // Open the third page only after suggestions are ready.
        }
      });
    } catch (error) {
      if (mounted) setState(() { _loading = false; _error = '$error'; });
    }
  }

  Future<List<Store>> _offerMore(BuildContext routeContext,
      String lastPlannedShopId, Set<String> alreadyPlanned) async {
    final directory = await _stores;
    final byId = {for (final store in directory) store.id: store};
    var variation = 0;
    var locked = <String>{};
    var selected = <String>{};
    var suggestions = <Store>[];
    String? error;
    var busy = false;
    var initialized = false;
    var sheetOpen = true;
    Map<String, String> followUpTags = {};
    final followUpCount = switch (_style) {
      'quick' => 2, 'discovery' => 4, _ => 3,
    };

    Future<void> fetch(void Function(void Function()) redraw) async {
      if (!sheetOpen) return;
      redraw(() { busy = true; error = null; });
      try {
        final response = await MallPilotApi.adaptiveJourney(
          startShopId: lastPlannedShopId,
          interests: _interests.toList(),
          spending: _spending, style: _style, maxStops: followUpCount,
          excludedShopIds: alreadyPlanned.toList(),
          historyShopIds: alreadyPlanned.toList(),
          lockedShopIds: locked.toList(), variation: variation,
        );
        final rows = (response['recommendations'] as List<dynamic>? ?? []);
        if (!sheetOpen) return;
        redraw(() {
          followUpTags = {
            for (final item in rows)
              (item as Map)['shop_id'].toString():
                  (item['composition_interest'] ?? '').toString(),
          };
          suggestions = [for (final row in rows)
            if (byId[(row as Map)['shop_id']] != null) byId[row['shop_id']]!];
          selected = suggestions.map((shop) => shop.id).toSet();
          busy = false;
        });
      } catch (e) {
        if (sheetOpen) redraw(() { busy = false; error = '$e'; });
      }
    }

    // The sheet appears after Arrived confirmation, with one shop still left.
    final answer = await showModalBottomSheet<List<Store>>(
      context: routeContext, isScrollControlled: true, useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, redraw) {
          // Schedule only the very first fetch after the sheet is built.
          if (!initialized) {
            initialized = true;
            busy = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (sheetContext.mounted) fetch(redraw);
            });
          }
          final currentMix = <String, int>{};
          for (final store in suggestions) {
            if (!selected.contains(store.id)) continue;
            final interest = followUpTags[store.id] ?? store.category;
            currentMix[interest] = (currentMix[interest] ?? 0) + 1;
          }
          final mixText = currentMix.entries
              .map((entry) => '${_interestName(entry.key)} ${entry.value}')
              .join('  ·  ');
          return Padding(
            padding: EdgeInsets.fromLTRB(18, 0, 18,
              MediaQuery.of(sheetContext).viewInsets.bottom + 18),
            child: SizedBox(
              height: MediaQuery.of(sheetContext).size.height * .66,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(AppLanguage.t('continue_exploring'), style: const TextStyle(fontSize: 22,
                    fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text(AppLanguage.t('continue_exploring_desc')),
                const SizedBox(height: 8),
                if (currentMix.isNotEmpty && !busy)
                  Padding(padding: const EdgeInsets.only(bottom: 8),
                    child: Text('${AppLanguage.t('new_category_mix')}: $mixText',
                      style: const TextStyle(fontSize: 12))),
                if (error != null) Text(error!, style: const TextStyle(color: Colors.red)),
                Expanded(child: busy
                  ? const Center(child: CircularProgressIndicator())
                  : suggestions.isEmpty
                    ? Center(child: Text(AppLanguage.t('no_more_matches')))
                    : ListView(children: [
                      for (final store in suggestions)
                        CheckboxListTile(
                          value: selected.contains(store.id),
                          onChanged: (value) => redraw(() {
                            if (value ?? false) { selected.add(store.id); }
                            else { selected.remove(store.id); locked.remove(store.id); }
                          }),
                          // Keep each shop's actual logo visible after Shuffle.
                          secondary: StoreLogo(store: store),
                          title: Row(children: [
                            Expanded(child: Text(store.name,
                              maxLines: 2, overflow: TextOverflow.ellipsis)),
                            IconButton(
                              tooltip: locked.contains(store.id)
                                  ? AppLanguage.t('unlock_shop') : AppLanguage.t('keep_when_shuffling'),
                              icon: Icon(locked.contains(store.id)
                                  ? Icons.lock : Icons.lock_open,
                                  color: locked.contains(store.id) ? _wine : null),
                              onPressed: () => redraw(() {
                                if (locked.contains(store.id)) { locked.remove(store.id); }
                                else { locked.add(store.id); selected.add(store.id); }
                              }),
                            ),
                          ]),
                          subtitle: Text('${store.localizedSubCategory} · ${store.priceText}'),
                        ),
                    ])),
                OutlinedButton.icon(
                  onPressed: busy ? null : () {
                    variation++;
                    fetch(redraw);
                  },
                  icon: const Icon(Icons.shuffle), label: Text(AppLanguage.t('shuffle_suggestions')),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: TextButton(
                    onPressed: busy ? null : () => Navigator.pop(sheetContext, <Store>[]),
                    child: Text(AppLanguage.t('finish_current_journey')))),
                  Expanded(child: FilledButton(
                    onPressed: busy || selected.isEmpty ? null : () => Navigator.pop(
                      sheetContext,
                      suggestions.where((s) => selected.contains(s.id)).toList()),
                    child: Text('${AppLanguage.t('btn_add_prefix')}${selected.length}${AppLanguage.t('btn_add_shops_suffix')}'))),
                ]),
              ]),
            ),
          );
        },
      ),
    );
    sheetOpen = false;
    return answer ?? <Store>[];
  }

  Widget _interestTile(_InterestChoice option) {
    final checked = _interests.contains(option.key);
    return FilterChip(
      avatar: Icon(option.icon, size: 17, color: _wine),
      label: Text(option.displayName), selected: checked,
      selectedColor: MallGlassStyle.selectedSurface,
      backgroundColor: MallGlassStyle.surfaceColor,
      checkmarkColor: MallGlassStyle.accent,
      side: BorderSide(
        color: checked ? MallGlassStyle.accent : MallGlassStyle.borderColor,
      ),
      onSelected: (value) => setState(() {
        if (value) { _interests.add(option.key); }
        else { _interests.remove(option.key); }
        _clearRecommendations();
      }),
    );
  }

  Widget _picker(String label, String selected, List<({String key, String name, String note})> options,
      ValueChanged<String> update) {
    return MallGlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        for (final item in options)
          RadioListTile<String>(
            dense: true,
            contentPadding: EdgeInsets.zero,
            activeColor: MallGlassStyle.accent,
            title: Text(item.name), subtitle: Text(item.note),
            value: item.key, groupValue: selected,
            onChanged: (value) { if (value != null) update(value); },
          ),
      ]),
    );
  }

  Widget _composition(List<Store> shown) {
    final counts = <String, int>{};
    for (final shop in shown) {
      final key = _matchedCategory[shop.id] ?? shop.category;
      counts[key] = (counts[key] ?? 0) + 1;
    }
    if (counts.isEmpty) return const SizedBox.shrink();
    const colors = [Color(0xFF10B981), Color(0xFF4B86B4), Color(0xFF8475BD), Color(0xFFE3A15A)];
    return MallGlassCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(AppLanguage.t('category_composition'), style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 9),
      ClipRRect(borderRadius: BorderRadius.circular(8), child: SizedBox(height: 14,
        child: Row(children: [for (var i = 0; i < counts.length; i++)
          Expanded(flex: counts.values.elementAt(i),
            child: ColoredBox(color: colors[i % colors.length]))]))),
      const SizedBox(height: 9),
      for (var i = 0; i < counts.length; i++)
        Padding(padding: const EdgeInsets.symmetric(vertical: 3), child: Row(children: [
          CircleAvatar(radius: 5, backgroundColor: colors[i % colors.length]),
          const SizedBox(width: 8),
          Expanded(child: Text(_interestName(counts.keys.elementAt(i)))),
          Text('${counts.values.elementAt(i)} ${AppLanguage.t('shops_count_suffix')} · '
              '${(100 * counts.values.elementAt(i) / shown.length).round()}%'),
        ])),
    ]));
  }

  String _interestName(String key) {
    for (final choice in _choices) { if (choice.key == key) return choice.displayName; }
    return key;
  }

  Future<void> _navigate() async {
    final stops = _suggested.where((s) => _included.contains(s.id)).toList();
    if (stops.isEmpty || _start == null) return;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => NavigationPage(
      mode: RouteMode.shortest, stops: stops,
      startPosition: _start, onExploreMore: _offerMore,
    )));
  }

  Widget _progressHeader() {
    final labels = [
      AppLanguage.t('step_interests'),
      AppLanguage.t('step_preferences'),
      AppLanguage.t('step_journey'),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        for (var i = 0; i < labels.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(child: Column(children: [
            Container(
              height: 5,
              decoration: BoxDecoration(
                color: i <= _step ? _wine : MallGlassStyle.borderColor,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            const SizedBox(height: 7),
            Text(labels[i], textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11,
                fontWeight: i == _step ? FontWeight.bold : FontWeight.normal,
                color: i == _step ? _wine : Colors.grey[700])),
          ])),
        ],
      ]),
      const SizedBox(height: 20),
    ]);
  }

  Widget _interestPage() => ListView(
    key: const ValueKey('journey-interests'),
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
    children: [
      _progressHeader(),
      Text(AppLanguage.t('what_interested_in'), style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 8),
      Text(AppLanguage.t('choose_interests_desc')),
      const SizedBox(height: 14),
      MallGlassCard(
        child: Wrap(spacing: 8, runSpacing: 4,
          children: [for (final option in _choices) _interestTile(option)]),
      ),
      const SizedBox(height: 24),
      Text(AppLanguage.t('where_starting'), style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: _loading ? null : _pickStart,
        icon: const Icon(Icons.add_location_alt_outlined),
        label: Text(_start == null ? AppLanguage.t('pin_start_btn') : AppLanguage.t('change_pin_start_btn')),
      ),
      if (_start != null) ListTile(
        contentPadding: EdgeInsets.zero,
        leading: const Icon(Icons.check_circle, color: Colors.green),
        title: Text(_start!.label),
        subtitle: Text(AppLanguage.t('start_pinned_desc')),
      ),
      if (_start == null) Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(AppLanguage.t('pin_start_hint'),
          style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ),
      const SizedBox(height: 20),
      FilledButton.icon(
        onPressed: _interests.isEmpty || _start == null || _loading
          ? null : () => setState(() => _step = 1),
        icon: const Icon(Icons.arrow_forward),
        label: Text(AppLanguage.t('btn_next_preferences')),
      ),
    ],
  );

  Widget _preferencesPage(List<Store> directory) => ListView(
    key: const ValueKey('journey-preferences'),
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
    children: [
      _progressHeader(),
      Text(AppLanguage.t('personalize_journey'), style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 8),
      Text(AppLanguage.t('personalize_desc')),
      const SizedBox(height: 20),
      _picker(AppLanguage.t('spending_pref'), _spending, [
        (key: 'affordable', name: AppLanguage.t('spending_affordable'), note: AppLanguage.t('spending_affordable_desc')),
        (key: 'balanced', name: AppLanguage.t('spending_balanced'), note: AppLanguage.t('spending_balanced_desc')),
        (key: 'premium', name: AppLanguage.t('spending_premium'), note: AppLanguage.t('spending_premium_desc')),
      ], (value) => setState(() { _spending = value; _clearRecommendations(); })),
      const SizedBox(height: 20),
      _picker(AppLanguage.t('journey_experience'), _style, [
        (key: 'quick', name: AppLanguage.t('style_quick'), note: AppLanguage.t('style_quick_desc')),
        (key: 'balanced', name: AppLanguage.t('style_balanced'), note: AppLanguage.t('style_balanced_desc')),
        (key: 'discovery', name: AppLanguage.t('style_discovery'), note: AppLanguage.t('style_discovery_desc')),
      ], (value) => setState(() { _style = value; _clearRecommendations(); })),
      const SizedBox(height: 14),
      if (_error != null) Padding(
        padding: const EdgeInsets.only(top: 14),
        child: Text(_error!, style: const TextStyle(color: Colors.red)),
      ),
      if (_loading) const Padding(padding: EdgeInsets.all(20),
        child: Center(child: CircularProgressIndicator())),
      const SizedBox(height: 20),
      FilledButton.icon(
        onPressed: _loading ? null : () => _recommend(directory),
        icon: const Icon(Icons.auto_awesome),
        label: Text(AppLanguage.t('btn_show_recommendations')),
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: _loading ? null : _goBack,
        icon: const Icon(Icons.arrow_back),
        label: Text(AppLanguage.t('btn_back_to_interests')),
      ),
    ],
  );

  Widget _resultsPage(List<Store> directory) {
    final included = _suggested.where((shop) => _included.contains(shop.id)).toList();
    return ListView(
      key: const ValueKey('journey-results'),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        _progressHeader(),
        Text(AppLanguage.t('your_recommended_journey'),
          style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text('${_suggested.length} ${AppLanguage.t('shops_count_suffix')} · ${_interests.length} ${AppLanguage.t('step_interests')}'),
        const SizedBox(height: 18),
        _composition(included),
        const SizedBox(height: 18),
        Text(AppLanguage.t('keep_lock_hint')),
        const SizedBox(height: 8),
        for (final store in _suggested) ...[
          MallGlassCard(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            selected: _included.contains(store.id),
            child: CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              activeColor: MallGlassStyle.accent,
            value: _included.contains(store.id),
            onChanged: _loading ? null : (value) => setState(() {
              if (value ?? false) { _included.add(store.id); }
              else { _included.remove(store.id); _locked.remove(store.id); }
            }),
            // A store logo is shown for both the first result and all
            // subsequent Shuffle recommendations.
            secondary: StoreLogo(store: store),
            title: Row(children: [
              Expanded(child: Text(store.name,
                maxLines: 2, overflow: TextOverflow.ellipsis)),
              IconButton(
                tooltip: _locked.contains(store.id)
                    ? AppLanguage.t('tooltip_unlock_shop') : AppLanguage.t('tooltip_keep_shuffling'),
                icon: Icon(_locked.contains(store.id)
                    ? Icons.lock : Icons.lock_open,
                    color: _locked.contains(store.id) ? _wine : null),
                onPressed: _loading ? null : () => setState(() {
                  if (_locked.contains(store.id)) { _locked.remove(store.id); }
                  else { _locked.add(store.id); _included.add(store.id); }
                }),
              ),
            ]),
            subtitle: Text('${store.localizedSubCategory} · ${store.priceText}'),
            ),
          ),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _loading ? null : () => _recommend(directory, shuffle: true),
          icon: const Icon(Icons.shuffle),
          label: Text(AppLanguage.t('btn_shuffle')),
        ),
        if (_loading) const Padding(padding: EdgeInsets.all(20),
          child: Center(child: CircularProgressIndicator())),
        if (_error != null) Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(_error!, style: const TextStyle(color: Colors.red)),
        ),

        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: included.isEmpty || _loading ? null : _navigate,
          icon: const Icon(Icons.route),
          label: Text('${AppLanguage.t('btn_generate_path')} · ${included.length} ${AppLanguage.t('shops_count_suffix')}'),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _loading ? null : () => setState(() => _step = 1),
          icon: const Icon(Icons.tune),
          label: Text(AppLanguage.t('btn_edit_spending')),
        ),
        TextButton(
          onPressed: _loading ? null : () => setState(() => _step = 0),
          child: Text(AppLanguage.t('btn_change_interests')),
        ),
        const SizedBox(height: 10),
        Text(
          AppLanguage.t('recommendation_footer_note'),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => WillPopScope(
    onWillPop: () async {
      if (_step > 0 && !_loading) {
        _goBack();
        return false;
      }
      return _step == 0;
    },
    child: Scaffold(
      backgroundColor: MallGlassStyle.pageBackground,
      appBar: AppBar(
        title: Text(AppLanguage.t('plan_journey')),
        leading: _step > 0 ? IconButton(
          tooltip: AppLanguage.t('tooltip_previous_step'),
          icon: const Icon(Icons.arrow_back),
          onPressed: _loading ? null : _goBack,
        ) : null,
      ),
      body: FutureBuilder<List<Store>>(
        future: _stores,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            if (snapshot.hasError) return Center(child: Text('${snapshot.error}'));
            return const Center(child: CircularProgressIndicator());
          }
          final directory = snapshot.data!;
          switch (_step) {
            case 0: return _interestPage();
            case 1: return _preferencesPage(directory);
            default: return _resultsPage(directory);
          }
        },
      ),
    ),
  );
}
