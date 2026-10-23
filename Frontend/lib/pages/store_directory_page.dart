import 'package:flutter/material.dart';
import '../data/store_repository.dart';
import '../models/store.dart';
import '../state/stop_list.dart';
import '../widgets/store_logo.dart';
import '../widgets/mall_glass_card.dart';
import '../services/app_language.dart';

/// Page 2: searchable, filterable list of all stores.
class StoreDirectoryPage extends StatefulWidget {
  /// When embedded in the map, the exact same directory UI is shown in a sheet.
  final bool embeddedInMap;
  final ValueChanged<Store>? onLocateStore;
  /// Optional route-local selection for Plan My Journey. When omitted, the
  /// normal Explore Map & Stores screen continues using the shared stopList.
  final List<Store>? initialSelectedStores;
  final bool Function(Store)? onToggleSelectedStore;
  final VoidCallback? onClearSelectedStores;

  const StoreDirectoryPage({
    super.key,
    this.embeddedInMap = false,
    this.onLocateStore,
    this.initialSelectedStores,
    this.onToggleSelectedStore,
    this.onClearSelectedStores,
  });

  @override
  State<StoreDirectoryPage> createState() => _StoreDirectoryPageState();
}

class _StoreDirectoryPageState extends State<StoreDirectoryPage> {
  // Load the stores once, when this page is created.
  late final Future<List<Store>> _storesFuture = StoreRepository.loadStores();

  ValueNotifier<List<Store>>? _routeSelected;

  @override
  void initState() {
    super.initState();
    if (widget.initialSelectedStores != null) {
      _routeSelected = ValueNotifier(List<Store>.of(widget.initialSelectedStores!));
    }
  }

  @override
  void dispose() {
    _routeSelected?.dispose();
    super.dispose();
  }

  Listenable get _selectionChanges => _routeSelected ?? stopList;
  List<Store> get _selectedShops => _routeSelected?.value ?? stopList.stops;
  bool _isSelected(Store store) => _selectedShops.any((s) => s.id == store.id);

  void _toggleSelected(Store store) {
    if (_routeSelected == null) {
      stopList.toggle(store);
      return;
    }
    // Don't display a selected item if its route cannot be updated.
    if (widget.onToggleSelectedStore?.call(store) == false) return;
    final changed = List<Store>.of(_routeSelected!.value);
    if (changed.any((s) => s.id == store.id)) {
      changed.removeWhere((s) => s.id == store.id);
    } else {
      changed.add(store);
    }
    _routeSelected!.value = changed;
  }

  void _clearSelection() {
    if (_routeSelected == null) {
      stopList.clear();
    } else {
      widget.onClearSelectedStores?.call();
      _routeSelected!.value = [];
    }
  }

  String _query = '';
  final Set<String> _categories = {}; // selected categories (empty = all)

  int get _filterCount => _categories.length;

  /// A store is shown only if it passes the search AND every filter.
  bool _passes(Store s) {
    return s.matches(_query) &&
        (_categories.isEmpty || _categories.contains(s.category));
  }

  /// Add or remove [value] from [set], then redraw the page.
  void _toggle<T>(Set<T> set, T value, bool on) {
    setState(() {
      if (on) {
        set.add(value);
      } else {
        set.remove(value);
      }
    });
  }

  /// The filter panel that slides up from the bottom.
  void _openFilters(List<String> categories) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        // setSheetState redraws the panel itself; setState redraws the page.
        builder: (context, setSheetState) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(AppLanguage.t('filter_title'),
                        style: Theme.of(context).textTheme.titleLarge),
                    const Spacer(),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _categories.clear();
                        });
                        setSheetState(() {});
                      },
                      child: Text(AppLanguage.t('btn_clear_all')),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(AppLanguage.t('filter_category')),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    for (final c in categories)
                      FilterChip(
                        label: Text(AppLanguage.category(c)),
                        selected: _categories.contains(c),
                        onSelected: (on) {
                          _toggle(_categories, c, on);
                          setSheetState(() {});
                        },
                      ),
                  ],
                ),

                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(AppLanguage.t('show_results')),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Confirm before removing every planned stop from the shared route list.
  Future<void> _confirmClearSelectedShops(BuildContext sheetContext) async {
    final shouldClear = await showDialog<bool>(
      context: sheetContext,
      builder: (dialogContext) => AlertDialog(
        title: Text(AppLanguage.t('clear_all_selected_title')),
        content: Text(AppLanguage.t('clear_all_selected_desc')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(AppLanguage.t('btn_cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(AppLanguage.t('btn_clear_all')),
          ),
        ],
      ),
    );
    if (shouldClear == true) {
      _clearSelection();
    }
  }

  /// Preview selected shops and allow users to remove entries.
  void _showSelectedShopsPreview() {
    FocusManager.instance.primaryFocus?.unfocus();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: SizedBox(
          height: MediaQuery.of(sheetContext).size.height * 0.65,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        AppLanguage.t('selected_shops_title'),
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                      ),
                    ),
                    ListenableBuilder(
                      listenable: _selectionChanges,
                      builder: (context, _) => _selectedShops.isEmpty
                          ? const SizedBox.shrink()
                          : TextButton.icon(
                              onPressed: () =>
                                  _confirmClearSelectedShops(sheetContext),
                              icon: const Icon(Icons.delete_sweep_outlined),
                              label: Text(AppLanguage.t('btn_clear_all')),
                            ),
                    ),
                    IconButton(
                      tooltip: AppLanguage.t('tooltip_close_preview'),
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(sheetContext),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListenableBuilder(
                  listenable: _selectionChanges,
                  builder: (context, _) {
                    final selected = _selectedShops;
                    if (selected.isEmpty) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            AppLanguage.t('no_shops_selected'),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      );
                    }
                    return ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: selected.length,
                      separatorBuilder: (_, __) => const Divider(
                        height: 1,
                        indent: 72,
                      ),
                      itemBuilder: (context, index) {
                        final store = selected[index];
                        return ListTile(
                          leading: StoreLogo(store: store),
                          title: Text(store.name),
                          subtitle: Text(
                            '${store.localizedSubCategory}\n${store.priceText}',
                          ),
                          isThreeLine: true,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              TextButton.icon(
                                onPressed: () => _toggleSelected(store),
                                icon: const Icon(Icons.close, size: 16),
                                label: Text(AppLanguage.t('btn_remove')),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MallGlassStyle.pageBackground,
      appBar: AppBar(
        title: Text(widget.embeddedInMap ? AppLanguage.t('search_add_stores') : AppLanguage.t('store_directory_title')),
        leading: widget.embeddedInMap
            ? IconButton(
                tooltip: AppLanguage.t('tooltip_back_to_map'),
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              )
            : null,
        // The selected-shops preview supports removing shops or clearing all.
        actions: [
          ListenableBuilder(
            listenable: _selectionChanges,
            builder: (context, _) => IconButton(
              tooltip: AppLanguage.t('tooltip_preview_selected'),
              icon: Badge(
                label: Text('${_selectedShops.length}'),
                isLabelVisible: _selectedShops.isNotEmpty,
                child: const Icon(Icons.shopping_bag_outlined),
              ),
              onPressed: _showSelectedShopsPreview,
            ),
          ),
        ],
      ),
      body: FutureBuilder<List<Store>>(
        future: _storesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          return _buildContent(snapshot.data!);
        },
      ),
    );
  }

  /// Search bar + filter button + result count + the list.
  Widget _buildContent(List<Store> all) {
    // Category names come from the data itself, so a new category in the
    // Google Sheet appears in the filter automatically.
    final categories = all
        .map((s) => s.category)
        .where((c) => c.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    final stores = all.where(_passes).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: AppLanguage.t('search_store_hint'),
                    border: const OutlineInputBorder(),
                  ),
                  // Every keystroke: remember the text and redraw the list.
                  onChanged: (value) => setState(() => _query = value.trim()),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: AppLanguage.t('filter_title'),
                icon: Badge(
                  label: Text('$_filterCount'),
                  isLabelVisible: _filterCount > 0,
                  child: const Icon(Icons.tune),
                ),
                onPressed: () => _openFilters(categories),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('${stores.length} ${AppLanguage.t('shops_count_suffix')}'),
          ),
        ),
        Expanded(
          child: stores.isEmpty
              ? Center(child: Text(AppLanguage.t('no_stores_found')))
              : ListView.builder(
                  itemCount: stores.length,
                  itemBuilder: (context, i) {
                    final s = stores[i];
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      child: MallGlassCard(
                        padding: EdgeInsets.zero,
                        radius: 16,
                        blur: false, // Fast scrolling through the full directory.
                        child: ListTile(
                          onTap: widget.onLocateStore == null
                          ? null
                          : () => widget.onLocateStore!(s),
                          leading: StoreLogo(store: s),
                          title: Text(s.name),
                          subtitle: Text(
                            '${s.localizedSubCategory}\n${s.priceText}',
                          ),
                          isThreeLine: true,
                          // Save / un-save button for this store.
                          trailing: ListenableBuilder(
                        listenable: _selectionChanges,
                        builder: (context, _) => IconButton(
                          tooltip: _isSelected(s)
                              ? AppLanguage.t('tooltip_remove_stop')
                              : AppLanguage.t('tooltip_add_stop'),
                          icon: Icon(
                            _isSelected(s)
                                ? Icons.check_circle
                                : Icons.add_circle_outline,
                            color: _isSelected(s)
                                ? const Color(0xFF10B981)
                                : null,
                          ),
                          onPressed: () => _toggleSelected(s),
                        ),
                      ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
