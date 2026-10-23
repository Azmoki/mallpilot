"""Explainable, deterministic rule-based recommendations for MallPilot's GF shops.

Reads the existing team's shop category, subcategory, name, price range, and
estimated visit time. Does NOT train a model, scrape prices, or mutate data.
Shopping prices are broad catalogue estimates, not verified purchase prices.
"""

from __future__ import annotations

import re
from typing import Optional


def norm(text: object) -> str:
    return re.sub(r"[^a-z0-9]+", " ", str(text).casefold()).strip()


# The data has particular category/subcategory labels. Match those labels
# intentionally: asking for sportswear must NOT return every fashion store.
RULES = {
    "sportswear": {"aliases": ["sportswear", "activewear", "sports", "sports clothing", "sportwear", "sports equipment"],
                    "subcategories": ["Sports & Activewear"]},
    "food": {"aliases": ["food", "eat", "eating", "meal", "meals", "dine", "dining", "something to eat", "f&b"],
             "categories": ["Food & Beverage"]},
    "restaurant": {"aliases": ["restaurant", "restaurants", "sit down meal", "lunch", "dinner"],
                   "subcategories": ["Casual Dining & Restaurant"]},
    "fast_food": {"aliases": ["fast food", "fastfood", "snacks", "snack", "burger", "fried chicken"],
                  "subcategories": ["Fast Food & Snacks"]},
    "coffee": {"aliases": ["coffee", "cafe", "café", "kopi"],
               "names": ["coffee", "starbucks", "zus", "gigi", "black canyon"]},
    "tea": {"aliases": ["tea", "milk tea", "bubble tea", "boba"],
            "names": ["tealive", "chagee", "jomcha", "tea"]},
    "dessert": {"aliases": ["dessert", "desserts", "ice cream", "sweets", "yogurt"],
                "subcategories": ["Dessert & Ice Cream"]},
    "shoes": {"aliases": ["shoes", "shoe", "footwear", "slippers", "sandals"],
              "subcategories": ["Footwear & Shoes"]},
    "fashion": {"aliases": ["fashion", "clothing", "clothes", "apparel", "outfits"],
                "categories": ["Fashion"]},
    "beauty": {"aliases": ["beauty", "personal care", "health and beauty"],
               "categories": ["Health & Beauty"]},
    "skincare": {"aliases": ["skincare", "skin care", "cosmetics", "makeup", "make up"],
                 "subcategories": ["Cosmetics & Skincare"]},
    "pharmacy": {"aliases": ["pharmacy", "medicine", "drugstore", "health products"],
                 "subcategories": ["Pharmacy & Personal Care"]},
    "books": {"aliases": ["books", "book", "stationery", "library"],
              "subcategories": ["Books, Stationery & Library"]},
    "accessories": {"aliases": ["accessories", "accessory", "fashion accessories"],
                    "categories": ["Accessories"]},
    "jewellery": {"aliases": ["jewellery", "jewelry", "gold", "watches", "watch"],
                   "subcategories": ["Jewelry & Luxury Watches"]},
    "groceries": {"aliases": ["groceries", "grocery", "supermarket", "daily essentials"],
                  "subcategories": ["Supermarket & Fresh Groceries", "Convenience Store"]},
    "entertainment": {"aliases": ["entertainment", "arcade", "games", "family fun"],
                      "categories": ["Entertainment"]},
    "electronics": {"aliases": ["electronics", "gadgets", "phone", "smartphone"],
                    "subcategories": ["Gadgets & Electronics"]},
    "home": {"aliases": ["homeware", "home decor", "home items", "household"],
             "subcategories": ["Home & Variety Store"]},
}


def _contains_phrase(text: str, phrase: str) -> bool:
    return bool(re.search(r"(?<!\w)" + re.escape(norm(phrase)) + r"(?!\w)", text))


def interpret_interests(interests: Optional[list[str]] = None, query: Optional[str] = None) -> list[str]:
    """Map user supplied interests / simple natural language to recognized tags.

    Unknown short interests are retained as literal search terms, so names like
    'PUMA' can be searched. The free-text query is keyword matching, NOT an LLM.
    """
    resolved = []
    aliases = [(canonical, norm(alias)) for canonical, rule in RULES.items()
               for alias in rule["aliases"]]
    for raw in interests or []:
        token = norm(raw)
        if not token:
            continue
        canonical = next((key for key, alias in aliases if alias == token), None)
        canonical = canonical or token
        if canonical not in resolved:
            resolved.append(canonical)

    q = norm(query or "")
    if q:
        # Match complete words/phrases rather than 'eat' inside 'beauty'.
        for canonical, alias in aliases:
            if _contains_phrase(q, alias) and canonical not in resolved:
                resolved.append(canonical)
        # Single-term search also works for a particular brand/store name.
        if not resolved and len(q.split()) <= 4:
            resolved.append(q)
    return resolved


def parse_price_range(price_range: object) -> tuple[Optional[float], Optional[float]]:
    """Parse 'RM 150 - RM 1,500' into (150, 1500); unknown => (None, None)."""
    raw = str(price_range or "")
    if raw.strip().casefold() in ("n/a", "na", "", "none"):
        return None, None
    numbers = re.findall(r"(?<![\w])\d[\d,]*(?:\.\d+)?", raw)
    if len(numbers) != 2:
        return None, None
    lo, hi = (float(n.replace(",", "")) for n in numbers)
    if lo < 0 or hi < lo:
        return None, None
    return lo, hi


def _shop_match(shop: dict, interest: str) -> tuple[bool, int, str]:
    name = norm(shop.get("name", ""))
    category = norm(shop.get("category", ""))
    subcategory = norm(shop.get("sub_category", ""))
    rule = RULES.get(interest)
    if rule:
        if any(_contains_phrase(name, fragment) for fragment in rule.get("names", [])):
            return True, 45, "shop name"
        if subcategory in [norm(val) for val in rule.get("subcategories", [])]:
            return True, 35, "shop subcategory"
        if category in [norm(val) for val in rule.get("categories", [])]:
            return True, 25, "shop category"
        return False, 0, ""
    if any(_contains_phrase(field, interest) for field in (name, subcategory, category)):
        return True, 20, "name/category search"
    return False, 0, ""


def recommend_shops(manager, *, interests=None, query=None,
                    budget_rm=None, max_results: Optional[int] = 10,
                    mapped_only=False, exclude_shop_ids=()):
    if budget_rm is not None and budget_rm <= 0:
        raise ValueError("budget_rm must be positive")
    if max_results is not None and not 1 <= max_results <= 30:
        raise ValueError("max_results must be between 1 and 30")
    tags = interpret_interests(interests, query)
    if not tags:
        raise ValueError("Specify at least one interest or a recognizable query")

    excluded = {str(identifier).casefold() for identifier in exclude_shop_ids}
    stores = manager.mapped_stores() if mapped_only else manager.all_stores()
    recommendations = []
    for shop in stores:
        if shop["id"].casefold() in excluded:
            continue
        matched, match_reasons, score = [], [], 0
        for tag in tags:
            is_match, bonus, source = _shop_match(shop, tag)
            if is_match:
                matched.append(tag)
                score += 100 + bonus
                match_reasons.append(f"{tag} ({source})")
        if not matched:
            continue
        price_lo, price_hi = parse_price_range(shop.get("price_range"))
        # If capped, keep shops whose stated LOWER bound might fit; actual
        # purchases may cost more. Unknown prices are not deemed affordable.
        if budget_rm is not None and (price_lo is None or price_lo > budget_rm):
            continue
        recommendations.append({
            "shop_id": shop["id"],
            "name": shop["name"],
            "lot_id": shop["lot_id"],
            "floor": shop.get("floor", manager.floor),
            "category": shop.get("category"),
            "sub_category": shop.get("sub_category"),
            "price_range": shop.get("price_range"),
            "min_price_rm": price_lo,
            "max_price_rm": price_hi,
            "avg_visit_time_min": shop.get("avg_visit_time_min"),
            "node_id": shop.get("node_id"),
            "route_ready": bool(shop.get("node_id")),
            "relevance_score": score,
            "matched_interests": matched,
            "reason": "Matches " + ", ".join(match_reasons),
        })
    recommendations.sort(key=lambda s: (
        -len(s["matched_interests"]),
        -s["relevance_score"],
        s["min_price_rm"] if s["min_price_rm"] is not None else float("inf"),
        s["name"].casefold(),
    ))
    all_matches_count = len(recommendations)
    if max_results is not None:
        recommendations = recommendations[:max_results]
    return {
        "floor": manager.floor,
        "method": "explainable_rule_based",
        "interpreted_interests": tags,
        "budget_rm": budget_rm,
        "mapped_only": mapped_only,
        "count": len(recommendations),
        "total_matches_before_limit": all_matches_count,
        "recommendations": recommendations,
        "price_notice": (
            "Prices are broad store-category estimates in shops.json, not item quotes. "
            "A shop matching the budget lower bound is not guaranteed affordable."
        ),
        "ranking_notice": "Scores are heuristic preference matches, not learned ratings or real-time popularity.",
    }
