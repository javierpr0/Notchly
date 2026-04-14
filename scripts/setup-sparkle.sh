#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPO="javierpr0/notchly"
INFO_PLIST="$PROJECT_DIR/Notchy/Info.plist"
PRIVATE_KEY_FILE=$(mktemp)
rm -f "$PRIVATE_KEY_FILE"

echo "==> Buscando generate_keys de Sparkle..."
GEN_KEYS=$(find ~/Library/Developer/Xcode/DerivedData -name generate_keys -type f 2>/dev/null | head -1)

if [ -z "$GEN_KEYS" ]; then
    echo "ERROR: generate_keys no encontrado. Abre el proyecto en Xcode primero para que resuelva Sparkle."
    exit 1
fi

echo "    Encontrado: $GEN_KEYS"

echo ""
echo "==> Generando par de llaves EdDSA (o usando existente)..."
GEN_OUTPUT=$("$GEN_KEYS" 2>&1) || true
echo "$GEN_OUTPUT"

echo ""
echo "==> Obteniendo llave pública..."
PUBLIC_KEY=$("$GEN_KEYS" -p 2>&1)

if [ -z "$PUBLIC_KEY" ]; then
    echo "ERROR: No se pudo obtener la llave pública."
    exit 1
fi

echo "    Llave pública: $PUBLIC_KEY"

echo ""
echo "==> Exportando llave privada..."
"$GEN_KEYS" -x "$PRIVATE_KEY_FILE" 2>&1
PRIVATE_KEY=$(cat "$PRIVATE_KEY_FILE")
rm -f "$PRIVATE_KEY_FILE"

if [ -z "$PRIVATE_KEY" ]; then
    echo "ERROR: No se pudo exportar la llave privada."
    exit 1
fi

echo "    Llave privada exportada (${#PRIVATE_KEY} chars)"

echo ""
echo "==> Actualizando Info.plist con llave pública..."
/usr/libexec/PlistBuddy -c "Set :SUPublicEDKey $PUBLIC_KEY" "$INFO_PLIST"
echo "    Info.plist actualizado"

echo ""
echo "==> Configurando secret SPARKLE_PRIVATE_KEY en GitHub ($REPO)..."
if ! command -v gh &>/dev/null; then
    echo "ERROR: gh CLI no instalado. Instala con: brew install gh"
    exit 1
fi

if ! gh auth status &>/dev/null; then
    echo "ERROR: No estás autenticado en gh. Ejecuta: gh auth login"
    exit 1
fi

echo "$PRIVATE_KEY" | gh secret set SPARKLE_PRIVATE_KEY --repo "$REPO"
echo "    Secret configurado"

echo ""
echo "==> Verificando..."
STORED_KEY=$(/usr/libexec/PlistBuddy -c "Print :SUPublicEDKey" "$INFO_PLIST")
echo "    SUPublicEDKey en Info.plist: $STORED_KEY"
echo "    SPARKLE_PRIVATE_KEY: configurado en github.com/$REPO"

echo ""
echo "============================================"
echo "  Setup completo!"
echo "  Ahora haz commit de Notchy/Info.plist"
echo "  y ya puedes crear releases con auto-update."
echo "============================================"
