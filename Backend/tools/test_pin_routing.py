"""Run from Backend/: python tools/test_pin_routing.py"""
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from fastapi.testclient import TestClient
from api import app, load_graph, load_manager
from modules.journey_optimizer import _build_network
from modules.pin_routing import prepare_pinned_graph

client = TestClient(app)
assert client.get('/health').status_code == 200
services = client.get('/public-services').json()['services']
assert len(services) >= 5

pin = {'x': 585, 'y': 528, 'floor': 'GF'}
result = client.post('/snap-position', json=pin)
assert result.status_code == 200, result.text
snap = result.json()
assert snap['snap_distance_px'] < 65
for point in ({'x': -4, 'y': 0}, {'x': 10, 'y': 10}):
    assert client.post('/snap-position', json=point).status_code == 422

manager = load_manager()
ids = [row['id'] for row in manager.mapped_stores()[:3]]
facility = services[0]['id']
order = [ids[0], f'facility:{facility}', ids[1], ids[2]]
for mode in ('sequence', 'shortest'):
    response = client.post('/plan-route', json={
        'start_position': pin, 'shop_ids': ids, 'public_service_ids': [facility],
        'destination_order': order, 'mode': mode,
    })
    assert response.status_code == 200, response.text
    route = response.json()
    assert route['legs'][0]['path'][0]['floor'] == 'GF'
    assert abs(route['legs'][0]['path'][0]['x'] - route['snapped_start']['x']) < 0.001
    assert len(route['legs']) == 4
    if mode == 'sequence':
        assert [s['shop_id'] for s in route['visit_order']] == order
    else:
        assert route['total_distance_px'] <= sequence_distance + 0.001
    if mode == 'sequence':
        sequence_distance = route['total_distance_px']

# A single service is sufficient for a route; two shops are not required.
assert client.post('/plan-route', json={
    'start_position': pin, 'shop_ids': [], 'public_service_ids': [facility],
}).status_code == 200
assert client.post('/plan-route', json={
    'start_position': pin, 'shop_ids': ids, 'destination_order': ids[:2],
}).status_code == 422

# Two pins on one corridor preserve valid positive edge weights.
g = load_graph()
augmented, positions = prepare_pinned_graph(g, {
    'one': {'x': 585, 'y': 528}, 'two': {'x': 590, 'y': 528},
})
network = _build_network(augmented, 'GF')
for row in positions.values():
    assert row['node_id'] in network
assert all(edge['weight'] > 0 for _, _, edge in network.edges(data=True))

rec = client.post('/recommend-journey-from-pin', json={
    'start_position': pin, 'query': 'sportswear, food', 'max_stops': 3,
})
assert rec.status_code == 200, rec.text
assert rec.json()['status'] in ('ok', 'no_feasible_recommendations')
print('Pinned-start, mixed public-service and recommendation API tests passed.')
