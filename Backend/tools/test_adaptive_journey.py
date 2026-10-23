"""Run from Backend/: python tools/test_adaptive_journey.py"""
from fastapi.testclient import TestClient
from api import app

api = TestClient(app)
pin = {'x': 820, 'y': 650, 'floor': 'GF'}
base = {'start_position': pin, 'interests': ['food', 'fashion', 'beauty'],
        'spending': 'balanced', 'style': 'balanced'}
initial_response = api.post('/adaptive-journey', json=base)
assert initial_response.status_code == 200, initial_response.text
initial = initial_response.json()
assert initial['status'] == 'ok'
assert initial['count'] == 4
assert sum(p['shops'] for p in initial['composition']) == initial['count']
assert len({row['shop_id'] for row in initial['recommendations']}) == 4
assert all(row['matched_interests'] for row in initial['recommendations'])
assert 'total_visit_minutes' not in initial['journey']

locked = initial['recommendations'][0]['shop_id']
shuffle_response = api.post('/adaptive-journey', json={**base, 'variation': 3,
                                                      'locked_shop_ids': [locked]})
assert shuffle_response.status_code == 200, shuffle_response.text
assert locked in {row['shop_id'] for row in shuffle_response.json()['recommendations']}

ids = [row['shop_id'] for row in initial['recommendations']]
follow_response = api.post('/adaptive-journey', json={
    'start_shop_id': ids[-1], 'interests': base['interests'],
    'excluded_shop_ids': ids, 'history_shop_ids': ids,
    'style': 'balanced', 'max_stops': 3, 'variation': 4,
})
assert follow_response.status_code == 200, follow_response.text
follow = follow_response.json()
assert set(ids).isdisjoint({row['shop_id'] for row in follow['recommendations']})
assert follow['count'] == 3
for first, last in zip([ids[-1]] + [x['shop_id'] for x in follow['recommendations']][:-1],
                       [x['shop_id'] for x in follow['recommendations']]):
    leg = api.post('/route', json={'start_shop_id': first, 'end_shop_id': last})
    assert leg.status_code == 200, leg.text
    assert len(leg.json()['path']) >= 2

path = api.post('/plan-route', json={
    'start_position': pin, 'shop_ids': ids,
    'public_service_ids': [], 'mode': 'shortest',
})
assert path.status_code == 200, path.text
assert len(path.json()['legs']) == 4

bad = api.post('/adaptive-journey', json={
    **base, 'start_shop_id': ids[0],
})
assert bad.status_code == 422
print('PASS: pinned recommendations, category composition, lock/shuffle, '
      'excluded follow-ups, multi-stop routing, and input validation')
