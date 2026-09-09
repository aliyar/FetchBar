#!/bin/bash
# Point the landing page at a release: the version and the download links, plus the
# sitemap date. Every fact the page states about the download lives here, so a release
# cannot leave the site claiming an older build.
#
# The version is written in exactly one visible place, the requirements line under the
# hero. It used to be repeated in the download button and in every page's footer, where
# the copies quietly went stale. Size and checksum are deliberately not published: the
# disk image is signed and notarized, so nobody has to verify a hash by hand, and a
# number that has to be right in three places is a number that goes wrong.
#
# Usage: Scripts/site-version.sh <version> [repo-slug]
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:-}"; REPO="${2:-aliyar/FetchBar}"
PAGE="site/index.html"
MAP="site/sitemap.xml"

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "usage: $0 <x.y.z> [repo]" >&2; exit 1; }
[[ -f "$PAGE" ]] || { echo "no such page: $PAGE" >&2; exit 1; }

TODAY=$(date +%Y-%m-%d)
URL="https://github.com/$REPO/releases/download/v$VERSION/FetchBar-$VERSION.dmg"

# Each edit is matched on shape, not on the outgoing value, and verified after it runs,
# so a markup change here fails the release instead of silently skipping a fact.
edit() { # <sed-expression> <expected-substring> <what>
  sed -i '' "$1" "$PAGE"
  grep -qF "$2" "$PAGE" || { echo "site-version: could not set $3 in $PAGE" >&2; exit 1; }
}

edit "s|\"softwareVersion\": \"[^\"]*\"|\"softwareVersion\": \"$VERSION\"|" \
     "\"softwareVersion\": \"$VERSION\"" "JSON-LD version"
edit "s|releases/download/v[0-9][0-9.]*/FetchBar-[0-9][0-9.]*\.dmg|releases/download/v$VERSION/FetchBar-$VERSION.dmg|g" \
     "$URL" "download links"
edit "s|<li>[0-9][0-9.]*</li><li>macOS|<li>$VERSION</li><li>macOS|" \
     "<li>$VERSION</li><li>macOS" "requirements line"

if [[ -f "$MAP" ]]; then
  sed -i '' "s|<lastmod>[0-9-]*</lastmod>|<lastmod>$TODAY</lastmod>|g" "$MAP"
fi

# Nothing may still point at an older release.
STALE=$(grep -oE 'FetchBar-[0-9]+\.[0-9]+\.[0-9]+\.(dmg|zip)' "$PAGE" | grep -v "FetchBar-$VERSION.dmg" || true)
[[ -z "$STALE" ]] || { echo "site-version: stale download links left: $STALE" >&2; exit 1; }

echo "  site: $VERSION · sitemap $TODAY"
