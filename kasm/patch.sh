#!/bin/bash
# Patch KasmVNC web assets to remove branding and apply customisations.
# Run once after installing the kasmvnc .deb package.
set -euo pipefail

WWW=/usr/share/kasmvnc/www

# The mascot assets are served without cache-control, etag, or last-modified,
# so a browser has nothing to revalidate against and will keep serving an old
# copy across ordinary reloads - which silently runs stale behaviour against a
# freshly built image. Version the URLs by content hash, the same way KasmVNC
# content-hashes its own bundle filenames, so changing either file changes the
# URL and the browser is obliged to refetch.
mascot_css_version="$(sha256sum "$WWW/assets/mascot.css" | cut -c1-12)"
mascot_js_version="$(sha256sum "$WWW/assets/mascot.js" | cut -c1-12)"

head_injection="<link rel=\"icon\" type=\"image/svg+xml\" href=\"./assets/favicon.svg\">"
head_injection+="<link rel=\"stylesheet\" href=\"./assets/custom.css\">"
head_injection+="<link rel=\"stylesheet\" href=\"./assets/mascot.css?v=${mascot_css_version}\">"
head_injection+="<script defer src=\"./assets/mascot.js?v=${mascot_js_version}\"></script>"
head_injection+="</head>"

# 1. Inject custom assets, rebrand the title, and replace upstream icon links.
find "$WWW" -maxdepth 1 -name '*.html' -exec sed -i \
    -e 's|<title>[^<]*</title>|<title>Pantalk Ghost</title>|' \
    -e 's|<link[^>]*rel="icon"[^>]*>||g' \
    -e 's|<link[^>]*rel="apple-touch-icon"[^>]*>||g' \
    -e "s|</head>|${head_injection}|" \
    {} +

if ! grep -Rq -F "assets/mascot.js?v=${mascot_js_version}" "$WWW"/*.html; then
    echo "[kasm-patch] the mascot overlay was not injected" >&2
    exit 1
fi

# 2. Replace the "KasmVNC" brand string and keep the browser title fixed.
# KasmVNC otherwise replaces it after connecting with the VNC desktop name,
# which contains Docker's generated hostname.
find "$WWW/assets" -name 'ui-*.js' -exec sed -i \
    -e 's|"KasmVNC"|"Pantalk Ghost"|g' \
    -e 's|document.title=r.detail.name+" - "+ox|document.title=ox|g' \
    {} +

if grep -ERq 'document\.title=[[:alnum:]_$]+\.detail\.name\+" - "\+' \
    "$WWW/assets"/ui-*.js; then
    echo "[kasm-patch] dynamic VNC desktop title was not removed" >&2
    exit 1
fi

echo "[kasm-patch] KasmVNC UI patched successfully"
