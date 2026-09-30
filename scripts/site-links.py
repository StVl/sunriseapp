#!/usr/bin/env python3
"""Points the landing page's buttons at real URLs.

The landing (site/index.html) is a bundled export: its markup lives in a JSON string, so
attributes appear as href=\\"#download\\". This rewrites those placeholders in place and can be
re-run after every re-export.

    ./scripts/site-links.py                 # uses the URLs below
    BUY_URL=https://buy.polar.sh/… ./scripts/site-links.py
"""
import os
import pathlib
import sys

SITE = pathlib.Path(__file__).resolve().parent.parent / "site" / "index.html"

# Latest GitHub release asset named exactly "Sunrise.dmg" (see scripts/release.sh).
DOWNLOAD_URL = os.environ.get("DOWNLOAD_URL", "https://github.com/StVl/sunriseapp/releases/latest/download/Sunrise.dmg")
# Polar → Products → Sunrise → Checkout Links. Empty = leave the button as is.
BUY_URL = os.environ.get("BUY_URL", "https://buy.polar.sh/polar_cl_QdDOIQeErSAshNIub87iwSeOFJ9ZlLc9HgSXb3alJIp")

# Price shown on the Purchase button (must match the Polar product).
PRICE = os.environ.get("PRICE", "$7")
# Prices the design may carry that get replaced with PRICE.
DESIGN_PRICES = ["$9.99"]

# placeholder href in the export → URL
LINKS = {
    "#download": DOWNLOAD_URL,
    "#buy": BUY_URL,
}


def main() -> int:
    html = SITE.read_text(encoding="utf-8")
    changed = []
    for placeholder, url in LINKS.items():
        if not url:
            continue
        old = f'href=\\"{placeholder}\\"'
        new = f'href=\\"{url}\\"'
        count = html.count(old)
        if count:
            html = html.replace(old, new)
            changed.append(f"{placeholder} → {url} ({count}×)")
    for old_price in DESIGN_PRICES:
        count = html.count(f">{old_price}<")
        if count and old_price != PRICE:
            html = html.replace(f">{old_price}<", f">{PRICE}<")
            changed.append(f"price {old_price} → {PRICE} ({count}×)")
    SITE.write_text(html, encoding="utf-8")
    for line in changed:
        print(line)
    if not BUY_URL:
        print("BUY_URL not set: the Purchase button still points to #buy", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
