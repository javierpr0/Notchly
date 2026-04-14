#!/bin/bash
set -euo pipefail

REMOTE="${NOTCHLY_RELEASE_REMOTE:-origin}"
CHANGELOG="$(cd "$(dirname "$0")/.." && pwd)/CHANGELOG.md"

# --- Parse arguments ---
FORCE=0
VERSION=""
for arg in "$@"; do
    case "$arg" in
        -f|--force)
            FORCE=1
            ;;
        -h|--help)
            echo "Uso: ./scripts/release.sh <version> [--force]"
            echo "  Ejemplo: ./scripts/release.sh 0.13.0"
            echo "  --force, -f   Borra tag local/remoto y release previo antes de recrearlo"
            exit 0
            ;;
        *)
            VERSION="$arg"
            ;;
    esac
done

if [ -z "$VERSION" ]; then
    echo "Uso: ./scripts/release.sh <version> [--force]"
    echo "  Ejemplo: ./scripts/release.sh 0.13.0"
    echo ""
    echo "Versiones existentes:"
    git tag -l 'v0.*' | sort -V | tail -5
    exit 1
fi

# Strip leading 'v' if provided
VERSION="${VERSION#v}"
TAG="v${VERSION}"

# --- Pre-flight checks ---
echo "==> Verificando pre-condiciones para $TAG..."
echo ""

# Check for uncommitted changes
if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "ERROR: Hay cambios sin commitear."
    echo "  Haz commit primero y vuelve a ejecutar."
    exit 1
fi

# Check tag doesn't already exist (or clean it up if --force)
TAG_EXISTS_LOCAL=0
TAG_EXISTS_REMOTE=0
if git tag -l "$TAG" | grep -q "^${TAG}$"; then
    TAG_EXISTS_LOCAL=1
fi
if git ls-remote --tags "$REMOTE" "refs/tags/${TAG}" | grep -q "$TAG"; then
    TAG_EXISTS_REMOTE=1
fi

if [ "$TAG_EXISTS_LOCAL" = "1" ] || [ "$TAG_EXISTS_REMOTE" = "1" ]; then
    if [ "$FORCE" != "1" ]; then
        echo "ERROR: El tag $TAG ya existe (local=$TAG_EXISTS_LOCAL, remoto=$TAG_EXISTS_REMOTE)."
        echo "  Usa --force para borrar tag y release previos y recrearlos:"
        echo "    ./scripts/release.sh $VERSION --force"
        exit 1
    fi

    echo "==> --force: limpiando tag y release previos para $TAG..."

    # Delete GitHub release if present (requires gh CLI).
    # Note: `gh release delete --cleanup-tag` also removes the associated git tag
    # on the remote, and sometimes the local tag too — so we re-check before
    # deleting tags ourselves.
    if command -v gh >/dev/null 2>&1; then
        if gh release view "$TAG" >/dev/null 2>&1; then
            echo "  Borrando GitHub Release $TAG..."
            gh release delete "$TAG" --yes --cleanup-tag 2>/dev/null \
                || gh release delete "$TAG" --yes 2>/dev/null \
                || true
        fi
    fi

    if git ls-remote --tags "$REMOTE" "refs/tags/${TAG}" | grep -q "$TAG"; then
        echo "  Borrando tag remoto $TAG..."
        git push "$REMOTE" --delete "$TAG" 2>/dev/null || true
    fi
    if git tag -l "$TAG" | grep -q "^${TAG}$"; then
        echo "  Borrando tag local $TAG..."
        git tag -d "$TAG" >/dev/null 2>&1 || true
    fi
    echo "  Limpieza OK"
    echo ""
fi

# --- Verify CHANGELOG ---
if ! grep -q "## \[${VERSION}\]" "$CHANGELOG"; then
    echo "ERROR: La version $VERSION no esta en CHANGELOG.md"
    echo ""
    echo "  Agrega una seccion como esta antes de [Unreleased]:"
    echo ""
    echo "  ## [${VERSION}] - $(date +%Y-%m-%d)"
    echo "  "
    echo "  ### Added"
    echo "  - ..."
    echo ""
    echo "  Y agrega el link al final del archivo:"
    echo "  [${VERSION}]: https://github.com/javierpr0/notchly/compare/vANTERIOR...v${VERSION}"
    echo ""
    read -p "  Presiona Enter cuando hayas actualizado CHANGELOG.md... " _

    # Re-check after user edits
    if ! grep -q "## \[${VERSION}\]" "$CHANGELOG"; then
        echo "ERROR: Sigue sin encontrarse [${VERSION}] en CHANGELOG.md. Abortando."
        exit 1
    fi

    # Check if CHANGELOG was modified but not committed
    if ! git diff --quiet "$CHANGELOG"; then
        echo ""
        echo "  CHANGELOG.md fue modificado. Commiteando..."
        git add "$CHANGELOG"
        git commit -m "docs: update changelog for v${VERSION}"
    fi
fi

# Check [Unreleased] section is clean (should have moved items to new version)
UNRELEASED_CONTENT=$(sed -n '/## \[Unreleased\]/,/## \[/p' "$CHANGELOG" | grep -E "^- " || true)
if [ -n "$UNRELEASED_CONTENT" ]; then
    echo "AVISO: La seccion [Unreleased] todavia tiene contenido:"
    echo "$UNRELEASED_CONTENT" | head -5
    echo ""
    read -p "  Continuar de todos modos? (s/N) " CONFIRM
    if [ "$CONFIRM" != "s" ] && [ "$CONFIRM" != "S" ]; then
        echo "Abortado."
        exit 1
    fi
fi

# Verify link exists at bottom of CHANGELOG
if ! grep -q "\[${VERSION}\]:" "$CHANGELOG"; then
    echo "AVISO: No hay link de comparacion para [${VERSION}] al final de CHANGELOG.md"
    read -p "  Continuar sin link? (s/N) " CONFIRM
    if [ "$CONFIRM" != "s" ] && [ "$CONFIRM" != "S" ]; then
        exit 1
    fi
fi

echo "  CHANGELOG.md OK"
echo ""

# --- Sync with remote ---
echo "==> Sincronizando con $REMOTE..."
if ! git push "$REMOTE" main 2>/dev/null; then
    echo "  Push rechazado, haciendo pull --rebase..."
    git pull "$REMOTE" main --rebase
    git push "$REMOTE" main
fi
echo "  Push OK"
echo ""

# --- Create tag and push ---
echo "==> Creando tag $TAG..."
git tag "$TAG"
git push "$REMOTE" "$TAG"
echo ""

# --- Summary ---
echo "============================================"
echo "  Release $TAG publicado!"
echo ""
echo "  GitHub Actions va a:"
echo "    1. Compilar el DMG"
echo "    2. Firmarlo con Sparkle"
echo "    3. Crear el GitHub Release"
echo "    4. Actualizar appcast.xml"
echo ""
echo "  Monitorea el progreso:"
echo "    gh run list --repo javierpr0/notchly --limit 1"
echo "============================================"
