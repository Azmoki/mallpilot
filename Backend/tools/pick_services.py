"""Pick a public-service marker on the ORIGINAL Elmina GF floor-plan image.

From Backend/ run (example; change the facility to one physically confirmed):
    python tools/pick_services.py --id GF_WC_01 --name 'Ground-floor toilet' --category restroom

Left-click location, then S to save. Esc/Q cancels. Use the physical
facility entrance on a walkable corridor, not the center of a closed room.
Coordinates are original 1737x930 image pixels, NOT geographic GPS/metres.
This tool never marks a service as verified without --verified.
"""

import argparse
import json
from pathlib import Path
import sys

import cv2

DATA = Path(__file__).resolve().parent.parent / 'data'
IMAGE = DATA / 'gf_light_map.png'
SERVICES = DATA / 'public_services_GF.json'
CATEGORIES = ('restroom', 'accessible_toilet', 'lift', 'escalator',
              'information', 'surau', 'baby_care', 'stairs', 'entrance')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--id', required=True, help='Unique, stable ID, e.g. GF_WC_01')
    parser.add_argument('--name', required=True)
    parser.add_argument('--category', choices=CATEGORIES, required=True)
    parser.add_argument('--description', default='')
    parser.add_argument('--verified', action='store_true',
                        help='Use only after confirming the actual location')
    args = parser.parse_args()
    if not args.id.startswith('GF_'):
        parser.error('Use a GF_ prefixed ID for ground-floor facilities')
    image = cv2.imread(str(IMAGE))
    if image is None:
        sys.exit(f'Image not found: {IMAGE}')
    h, w = image.shape[:2]
    items = json.loads(SERVICES.read_text(encoding='utf-8')) if SERVICES.exists() else []
    if any(item.get('id') == args.id for item in items):
        sys.exit('That facility ID already exists. Edit or remove its entry before reusing the ID.')
    scale = min(1.0, 1250 / w, 850 / h)
    disp_w, disp_h = round(w * scale), round(h * scale)
    selected = [None]
    window = 'Elmina GF: click public service, S=save, Esc/Q=cancel'

    def draw():
        canvas = cv2.resize(image, (disp_w, disp_h)).copy()
        for item in items:
            if item.get('floor', 'GF') != 'GF':
                continue
            x, y = round(float(item['x']) * disp_w / w), round(float(item['y']) * disp_h / h)
            cv2.circle(canvas, (x, y), 6, (0, 170, 255), 2)
        if selected[0] is not None:
            x, y = selected[0]
            dx, dy = round(x * disp_w / w), round(y * disp_h / h)
            cv2.drawMarker(canvas, (dx, dy), (50, 220, 50), cv2.MARKER_CROSS, 22, 2)
            cv2.putText(canvas, f'({x}, {y})', (max(0, dx - 50), max(18, dy - 12)),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.55, (0, 0, 0), 3)
            cv2.putText(canvas, f'({x}, {y})', (max(0, dx - 50), max(18, dy - 12)),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.55, (255, 255, 255), 1)
        cv2.imshow(window, canvas)

    def on_mouse(event, x, y, flags, userdata):
        if event == cv2.EVENT_LBUTTONUP:
            selected[0] = (min(w - 1, max(0, round(x * w / disp_w))),
                           min(h - 1, max(0, round(y * h / disp_h))))
            draw()

    cv2.namedWindow(window, cv2.WINDOW_NORMAL)
    cv2.resizeWindow(window, disp_w, disp_h)
    cv2.setMouseCallback(window, on_mouse)
    draw()
    while True:
        key = cv2.waitKey(50) & 255
        if key in (27, ord('q')):
            print('Cancelled; no change to JSON.')
            break
        if key == ord('s'):
            if selected[0] is None:
                print('Click a facility location first.')
                continue
            x, y = selected[0]
            item = {
                'id': args.id, 'name': args.name, 'description': args.description,
                'x': x, 'y': y, 'floor': 'GF', 'category': args.category,
                'verified': args.verified,
            }
            items.append(item)
            SERVICES.write_text(json.dumps(items, indent=2, ensure_ascii=False) + '\n',
                                encoding='utf-8')
            print(f'Saved {args.id} at image pixel ({x},{y}) in {SERVICES}')
            break
    cv2.destroyAllWindows()


if __name__ == '__main__':
    main()
