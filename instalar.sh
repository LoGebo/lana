#!/bin/bash
# Instala Lana en el iPhone conectado por cable.
set -e
cd "$(dirname "$0")"

echo "▸ Buscando iPhone conectado..."
DISPOSITIVO=$(xcrun devicectl list devices 2>/dev/null | grep -iE "iphone" | head -1)
if [ -z "$DISPOSITIVO" ]; then
  echo "✗ No veo ningún iPhone. Conéctalo por cable, desbloquéalo y dale 'Confiar en esta computadora'."
  exit 1
fi
UDID=$(echo "$DISPOSITIVO" | grep -oE "[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}" | head -1)
echo "  $DISPOSITIVO"

echo "▸ Buscando tu equipo de desarrollo..."
# El Team ID sale de la cuenta de Xcode; el certificado lo crea xcodebuild solo.
EQUIPO="${DEVELOPMENT_TEAM:-$(defaults read com.apple.dt.Xcode 2>/dev/null | grep -A2 IDEProvisioningTeamByIdentifier | grep teamID | grep -oE '[A-Z0-9]{10}' | head -1)}"
if [ -z "$EQUIPO" ]; then
  echo "✗ No hay cuenta de Apple en Xcode. Xcode → Settings → Apple Accounts → Add Apple Account…"
  exit 1
fi
echo "  Team ID: $EQUIPO"

echo "▸ Generando proyecto..."
DEVELOPMENT_TEAM="$EQUIPO" xcodegen generate >/dev/null

echo "▸ Compilando (puede tardar la primera vez)..."
xcodebuild -project Lana.xcodeproj -scheme Lana \
  -destination "id=$UDID" -configuration Debug \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
  DEVELOPMENT_TEAM="$EQUIPO" \
  -derivedDataPath build build 2>&1 | grep -E "error:|BUILD" || true

APP="build/Build/Products/Debug-iphoneos/Lana.app"
[ -d "$APP" ] || { echo "✗ No se generó la app. Revisa los errores de arriba."; exit 1; }

echo "▸ Instalando en el iPhone..."
xcrun devicectl device install app --device "$UDID" "$APP"
xcrun devicectl device process launch --device "$UDID" com.geboou.lana >/dev/null 2>&1 || true

echo "✓ Listo. Búscala como 'Lana' en tu pantalla de inicio."
echo "  La primera vez: Ajustes → General → VPN y gestión de dispositivos → confía en tu perfil de desarrollador."
