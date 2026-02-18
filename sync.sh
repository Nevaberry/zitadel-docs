#!/bin/bash
# Sync Zitadel docs from the official zitadel/zitadel repository.
# Usage: ./sync.sh [branch|tag]
#   e.g. ./sync.sh main
#        ./sync.sh v3.1.0

set -euo pipefail

REF="${1:-main}"
REPO="https://github.com/zitadel/zitadel.git"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TMP_DIR=$(mktemp -d)

trap 'rm -rf "$TMP_DIR"' EXIT

echo "Syncing Zitadel docs from $REPO @ $REF ..."

# Sparse clone — only fetch what we need
git clone --depth 1 --branch "$REF" --filter=blob:none --sparse "$REPO" "$TMP_DIR/zitadel" 2>&1
cd "$TMP_DIR/zitadel"
git sparse-checkout set apps/docs/content proto 2>&1

# Fetch individual files that sparse-checkout can't handle
git show HEAD:apps/docs/frameworks.json > "$TMP_DIR/frameworks.json" 2>/dev/null || true
git show HEAD:apps/docs/redirects.json > "$TMP_DIR/redirects.json" 2>/dev/null || true

# Sync docs content
echo "Copying docs ..."
rm -rf "$SCRIPT_DIR/docs"
cp -r apps/docs/content "$SCRIPT_DIR/docs"

# Sync proto files
echo "Copying proto definitions ..."
rm -rf "$SCRIPT_DIR/proto"
cp -r proto "$SCRIPT_DIR/proto"

# Sync metadata files
cp -f "$TMP_DIR/frameworks.json" "$SCRIPT_DIR/" 2>/dev/null || true
cp -f "$TMP_DIR/redirects.json" "$SCRIPT_DIR/" 2>/dev/null || true

# Generate OpenAPI specs if buf is available
if command -v npx &>/dev/null; then
    echo "Generating OpenAPI specs from proto files ..."
    rm -rf "$SCRIPT_DIR/openapi"
    mkdir -p "$SCRIPT_DIR/openapi"

    # Get the buf template
    git show HEAD:apps/docs/buf.gen.yaml > "$TMP_DIR/buf.gen.yaml" 2>/dev/null
    npx @bufbuild/buf generate proto \
        --template "$TMP_DIR/buf.gen.yaml" \
        --output "$SCRIPT_DIR/openapi" 2>&1

    SPEC_COUNT=$(find "$SCRIPT_DIR/openapi" -name "*.json" | wc -l)
    echo "Generated $SPEC_COUNT OpenAPI spec files"
else
    echo "npx not found — skipping OpenAPI generation"
fi

# Summary
DOC_COUNT=$(find "$SCRIPT_DIR/docs" -type f | wc -l)
PROTO_COUNT=$(find "$SCRIPT_DIR/proto" -name "*.proto" | wc -l)
echo ""
echo "Done! Synced from $REF:"
echo "  docs/    $DOC_COUNT files"
echo "  proto/   $PROTO_COUNT proto files"
echo "  openapi/ $(find "$SCRIPT_DIR/openapi" -name "*.json" 2>/dev/null | wc -l) OpenAPI specs"
