#!/bin/bash
# Publishes site/ to GitHub Pages (branch gh-pages) → https://stvl.github.io/sunriseapp/
# Commit your site changes first; this pushes what's committed.
#   ./scripts/site-links.py && git commit -am "Update landing" && ./scripts/publish-site.sh
set -euo pipefail
cd "$(dirname "$0")/.."

git subtree split --prefix site -b gh-pages-publish >/dev/null
git -c http.postBuffer=524288000 push --force origin gh-pages-publish:gh-pages
git branch -D gh-pages-publish >/dev/null
echo "Published → https://stvl.github.io/sunriseapp/ (live in a minute or two)"
