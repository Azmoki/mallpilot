"""Corridor snapping and temporary routing waypoints (GF prototype).

Image pixels are not geographic coordinates. Pins are projected onto actual
walkable graph edges; no path is drawn from a tap across a shop/wall.
"""
import copy
import math
from collections import defaultdict

# Prevent a tap deep inside a store or outside the mall being treated as if it
# were accurately located on a corridor.
MAX_SNAP_PX = 65.0
VIRTUAL_PREFIX = '__mallpilot_pin_'


def _project(x, y, a, b):
    dx, dy = float(b['x']) - float(a['x']), float(b['y']) - float(a['y'])
    denominator = dx * dx + dy * dy
    if denominator < 1e-12:
        return 0.0, float(a['x']), float(a['y'])
    t = max(0.0, min(1.0, ((x - float(a['x'])) * dx + (y - float(a['y'])) * dy) / denominator))
    return t, float(a['x']) + t * dx, float(a['y']) + t * dy


def _candidate_segments(graph):
    nodes = {node['id']: node for node in graph['nodes']}
    for edge in graph['edges']:
        a, b = nodes[edge['from']], nodes[edge['to']]
        # Only snap on publicly walkable corridor/facility links, NOT the
        # store-door branches that could lie inside retail lot footprints.
        if a.get('type') == 'store_entrance' or b.get('type') == 'store_entrance':
            continue
        yield edge, a, b


def snap_point(graph, x, y, *, max_distance=MAX_SNAP_PX):
    x, y = float(x), float(y)
    if not math.isfinite(x) or not math.isfinite(y):
        raise ValueError('Pin coordinates must be finite numbers')
    if not (0 <= x <= graph['image_width'] and 0 <= y <= graph['image_height']):
        raise ValueError('Pin is outside the Ground Floor map')
    best = None
    for edge, a, b in _candidate_segments(graph):
        t, px, py = _project(x, y, a, b)
        distance = math.hypot(px - x, py - y)
        if best is None or distance < best['snap_distance_px']:
            best = {
                'x': px, 'y': py, 'requested_x': x, 'requested_y': y,
                'snap_distance_px': distance, 'fraction': t,
                'edge_from': edge['from'], 'edge_to': edge['to'],
                'floor': 'GF',
            }
    if best is None:
        raise ValueError('No walkable corridor segments are mapped yet')
    if best['snap_distance_px'] > max_distance:
        raise ValueError('Selected point is too far from a mapped corridor. Tap closer to the walkway.')
    return best


def prepare_pinned_graph(graph_data, pins):
    """Return (augmented graph, pin start/target records).

    `pins` contains name -> {'x':..., 'y':...}. Multiple pins sharing a graph
    edge are inserted in proper edge order, preserving the original weight.
    """
    graph = copy.deepcopy(graph_data)
    original_edges = list(graph['edges'])
    groups = defaultdict(list)
    nodes = {n['id']: n for n in graph['nodes']}
    results = {}
    used_ids = set(nodes)
    for index, (name, position) in enumerate(pins.items()):
        snapped = snap_point(graph_data, position['x'], position['y'])
        t = snapped['fraction']
        # Reuse graph endpoints rather than creating zero-length edges.
        node_id = snapped['edge_from'] if t <= 1e-6 else (
            snapped['edge_to'] if t >= 1 - 1e-6 else f'{VIRTUAL_PREFIX}{index}')
        if node_id in used_ids and node_id.startswith(VIRTUAL_PREFIX):
            raise ValueError('Reserved routing ID collides with graph data')
        used_ids.add(node_id)
        snapped['node_id'] = node_id
        snapped['id'] = name
        results[name] = snapped
        if node_id.startswith(VIRTUAL_PREFIX):
            groups[(snapped['edge_from'], snapped['edge_to'])].append(snapped)

    graph['edges'] = []
    for edge in original_edges:
        points = sorted(groups.get((edge['from'], edge['to']), []), key=lambda p: p['fraction'])
        if not points:
            graph['edges'].append(edge)
            continue
        previous = edge['from']
        previous_t = 0.0
        for point in points:
            # Two waypoints may snap to exactly the same position. Reuse the
            # existing waypoint instead of inserting an invalid zero edge.
            if point['fraction'] - previous_t <= 1e-6:
                point['node_id'] = previous
                continue
            graph['nodes'].append({
                'id': point['node_id'], 'type': 'waypoint', 'floor': 'GF',
                'x': point['x'], 'y': point['y'],
            })
            graph['edges'].append({
                'from': previous, 'to': point['node_id'],
                'distance_px': float(edge['distance_px']) * (point['fraction'] - previous_t),
            })
            previous = point['node_id']
            previous_t = point['fraction']
        if 1.0 - previous_t > 1e-6:
            graph['edges'].append({
                'from': previous, 'to': edge['to'],
                'distance_px': float(edge['distance_px']) * (1.0 - previous_t),
            })
        elif previous != edge['to']:
            # Extremely close to the end: connect to graph endpoint via an
            # otherwise zero-length edge avoided by endpoint snapping above.
            graph['edges'].append({'from': previous, 'to': edge['to'],
                                   'distance_px': max(1e-8, float(edge['distance_px']) * (1 - previous_t))})
    return graph, results


class WaypointManager:
    """Adapter that adds synthetic start/facility destinations to shop manager."""
    def __init__(self, manager, waypoints):
        self.manager = manager
        self.floor = manager.floor
        self.waypoints = waypoints

    def get(self, identifier):
        if identifier in self.waypoints:
            return self.waypoints[identifier]
        return self.manager.get(identifier)

    def __getattr__(self, attr):
        return getattr(self.manager, attr)


def virtual_stop(identifier, label, snapped, *, kind):
    return {
        'id': identifier, 'name': label, 'lot_id': '',
        'node_id': snapped['node_id'], 'avg_visit_time_min': 0.0,
        'virtual_waypoint': True, 'kind': kind,
        'x': snapped['x'], 'y': snapped['y'],
    }
