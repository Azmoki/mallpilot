"""Adaptive, category-diverse shop suggestions from existing mapped GF shops.

All scores are heuristics. Directory prices are broad estimates; no visit-duration,
real-time popularity or walking-minutes claims are made here. Distances are map pixels.
"""
from collections import Counter
import hashlib
import math
import random

import networkx as nx

from modules.journey_optimizer import _build_network, optimize_journey
from modules.recommender import _shop_match, interpret_interests, parse_price_range

STYLE_DEFAULTS = {'quick': 3, 'balanced': 4, 'discovery': 5}


def _unit_prices(stores):
    """Relative price ranking *within category*, not a total shopping budget."""
    by_category = {}
    for store in stores:
        low, high = parse_price_range(store.get('price_range'))
        if low is not None and high is not None:
            by_category.setdefault(store.get('category') or 'Other', []).append((low + high) / 2)
    for prices in by_category.values():
        prices.sort()
    return by_category


def _spending_fit(shop, level, prices_by_category):
    low, high = parse_price_range(shop.get('price_range'))
    prices = prices_by_category.get(shop.get('category') or 'Other', [])
    if low is None or high is None or not prices:
        return .5  # Do not invent a price for unknown stores.
    mid = (low + high) / 2
    rank = sum(p < mid for p in prices) / max(1, len(prices) - 1)
    if level == 'affordable':
        return 1 - rank
    if level == 'premium':
        return rank
    return 1 - abs(rank - .5) * 1.4


def recommend_adaptive(graph, manager, *, start_shop_id, interests, spending='balanced',
                       style='balanced', max_stops=None, excluded_shop_ids=(),
                       history_shop_ids=(), locked_shop_ids=(), variation=0):
    if spending not in {'affordable', 'balanced', 'premium'}:
        raise ValueError('Invalid spending preference')
    if style not in STYLE_DEFAULTS:
        raise ValueError('Invalid journey style')
    count = STYLE_DEFAULTS[style] if max_stops is None else max_stops
    if not 1 <= count <= 7:
        raise ValueError('Choose between 1 and 7 recommended shops')
    tags = interpret_interests(interests)
    if not tags:
        raise ValueError('Choose at least one shopping interest')
    if len(tags) > 8:
        raise ValueError('Choose up to eight interests')

    network = _build_network(graph, manager.floor)
    start = manager.get(start_shop_id)
    start_node = start.get('node_id')
    if not start_node or start_node not in network:
        raise ValueError('Start is not connected to the walking graph')
    reachable = nx.node_connected_component(network, start_node)
    excluded = {str(i) for i in excluded_shop_ids} | {start['id']}
    locked = []
    for locked_id in dict.fromkeys(locked_shop_ids):
        if locked_id in excluded:
            raise ValueError('A locked shop cannot also be excluded')
        shop = manager.get(locked_id)
        if not shop.get('node_id') or shop['node_id'] not in reachable:
            raise ValueError(f'Locked shop is not reachable: {locked_id}')
        if shop['node_id'] not in network or network.nodes[shop['node_id']].get('type') != 'store_entrance':
            raise ValueError(f'Locked shop is not a mapped shop entrance: {locked_id}')
        locked.append(shop)
    if len(locked) > count:
        raise ValueError('Too many locked shops for requested journey size')
    history = Counter()
    for shop_id in set(history_shop_ids):
        try:
            shop = manager.get(shop_id)
        except (KeyError, ValueError):
            continue
        for tag in tags:
            if _shop_match(shop, tag)[0]:
                history[tag] += 1

    stores = [s for s in manager.mapped_stores()
              if s['id'] not in excluded and s['id'] not in {l['id'] for l in locked} and s['node_id'] in reachable
              and network.nodes[s['node_id']].get('type') == 'store_entrance']
    prices = _unit_prices(stores)
    choices = []
    for shop in stores:
        matches = [(tag, _shop_match(shop, tag)[1]) for tag in tags if _shop_match(shop, tag)[0]]
        if not matches:
            continue
        choices.append({**shop, '_matches': matches,
                        '_price_fit': _spending_fit(shop, spending, prices)})
    if not choices and not locked:
        return {'status': 'no_matches', 'visit_order': [], 'recommendations': [],
                'composition': [], 'journey': None,
                'notice': 'No matching mapped and reachable shops are available.'}

    seed = int(hashlib.sha256(f'{variation}:{start_shop_id}:{"|".join(tags)}'.encode()).hexdigest()[:16], 16)
    rng = random.Random(seed)
    jitter = {s['id']: rng.random() for s in choices}
    current_node = locked[-1]['node_id'] if locked else start_node
    chosen = list(locked)
    distribution = Counter(history)
    category_by_shop = {}
    for shop in locked:
        matches = [tag for tag in tags if _shop_match(shop, tag)[0]]
        if not matches:
            raise ValueError(f'Locked shop does not match selected interests: {shop["name"]}')
        dominant = min(matches, key=lambda tag: distribution[tag])
        category_by_shop[shop['id']] = dominant
        distribution[dominant] += 1
    while choices and len(chosen) < count:
        distances = nx.single_source_dijkstra_path_length(network, current_node, weight='weight')
        candidates = []
        for shop in choices:
            distance = distances.get(shop['node_id'], math.inf)
            if not math.isfinite(distance):
                continue
            # Multi-interest matching matters; balance across user-selected interests.
            match_quality = min(1, (max(bonus for _, bonus in shop['_matches']) / 45 +
                                    .23 * (len(shop['_matches']) - 1)))
            least_covered = min(shop['_matches'], key=lambda p: (distribution[p[0]], -p[1]))[0]
            max_coverage = max(distribution.values(), default=0)
            diversity = 1.0 if max_coverage == 0 else (max_coverage - distribution[least_covered] + 1) / (max_coverage + 1)
            # Pixel distance is uncalibrated, used only for relative route-efficiency scoring.
            proximity = 1.0 / (1 + distance / 270.0)
            # Shuffle changes the candidates without replacing preference matching with randomness.
            score = (.45 * match_quality + .27 * diversity +
                     .16 * proximity + .12 * shop['_price_fit'] +
                     (jitter[shop['id']] - .5) * (.14 if variation else .025))
            candidates.append((score, shop['id'], shop, least_covered))
        if not candidates:
            break
        _, _, pick, dominant = max(candidates, key=lambda row: (row[0], row[1]))
        chosen.append(pick)
        category_by_shop[pick['id']] = dominant
        distribution[dominant] += 1
        current_node = pick['node_id']
        choices.remove(pick)

    if not chosen:
        return {'status': 'no_matches', 'visit_order': [], 'recommendations': [],
                'composition': [], 'journey': None,
                'notice': 'No accessible matching destinations found.'}

    # The existing Held-Karp route optimiser chooses walking order only; its
    # placeholder visit-time values are NOT used to pick shops or shown in UI.
    planned = optimize_journey(graph, manager, start['id'], [s['id'] for s in chosen], mode='visit_all')
    chosen_by_id = {s['id']: s for s in chosen}
    count_by_tag = Counter(category_by_shop.values())
    suggested = []
    for item in planned['visit_order']:
        shop = chosen_by_id[item['shop_id']]
        suggested.append({'shop_id': shop['id'], 'name': shop['name'],
                          'lot_id': shop.get('lot_id'), 'category': shop.get('category'),
                          'sub_category': shop.get('sub_category'),
                          'price_range': shop.get('price_range'),
                          'matched_interests': [tag for tag in tags if _shop_match(shop, tag)[0]],
                          'composition_interest': category_by_shop[shop['id']],
                          'reason': 'Matches ' + ', '.join(tag for tag in tags if _shop_match(shop, tag)[0])})
    return {
        'status': 'ok', 'floor': manager.floor, 'start_shop_id': start['id'],
        'interpreted_interests': tags, 'style': style, 'spending': spending,
        'count': len(suggested), 'recommendations': suggested,
        'composition': [{'interest': tag, 'shops': count_by_tag[tag],
                         'percent': round(100 * count_by_tag[tag] / len(chosen), 1)}
                        for tag in tags if count_by_tag[tag]],
        'cumulative_composition': [{'interest': tag, 'shops': distribution[tag]}
                                   for tag in tags],
        'journey': {'total_distance_px': planned['total_distance_px'],
                    'visit_order': planned['visit_order'], 'legs': planned['legs']},
        'notice': 'Spending tiers use approximate catalogue price ranges. '
                  'Walking distances are image pixels. No visit times or actual purchase costs are predicted.',
    }
