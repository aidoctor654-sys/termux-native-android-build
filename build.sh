#!/data/data/com.termux/files/usr/bin/bash
# ============================================================
# π APK Builder — lekki workflow do robienia APK w Termuxie
# Pipeline: javac → jar → d8 → aapt package → aapt add → apksigner
# ============================================================
set -e

PROJECT="${1:-hello}"
PROJECT_DIR="$HOME/apk-builder/$PROJECT"
BUILD_DIR="$PROJECT_DIR/build"
ANDROID_JAR="/system/framework/framework.jar"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}╔══════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   π APK Builder — Termux Edition    ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════╝${NC}"
echo ""

# 1. Sprzątanie
echo -e "${YELLOW}[1/7]${NC} Czyszczenie build dir..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR/classes"

# 2. Kompilacja Java → .class
echo -e "${YELLOW}[2/7]${NC} javac --release 8 → .class..."
find "$PROJECT_DIR/src" -name "*.java" > "$BUILD_DIR/sources.txt"
if [ ! -s "$BUILD_DIR/sources.txt" ]; then
    echo "  ⚠ Brak plików .java w src/"
    exit 1
fi
javac --release 8 \
    -d "$BUILD_DIR/classes" \
    -classpath "$ANDROID_JAR" \
    @"$BUILD_DIR/sources.txt"
echo "  ✓ $(cat $BUILD_DIR/sources.txt | wc -l) plików skompilowanych"

# 3. Pakowanie .class → classes.jar
echo -e "${YELLOW}[3/7]${NC} jar cvf → classes.jar..."
cd "$BUILD_DIR/classes"
jar cvf "$BUILD_DIR/classes.jar" . >/dev/null
cd - >/dev/null
echo "  ✓ classes.jar"

# 4. Konwersja → classes.dex
echo -e "${YELLOW}[4/7]${NC} d8 → classes.dex..."
d8 --output "$BUILD_DIR" \
    --lib "$ANDROID_JAR" \
    --min-api 26 \
    "$BUILD_DIR/classes.jar"
echo "  ✓ classes.dex"

# 5. aapt package → resources.arsc + AndroidManifest.xml
echo -e "${YELLOW}[5/7]${NC} aapt package → base.apk..."
aapt package -f \
    -M "$PROJECT_DIR/AndroidManifest.xml" \
    -S "$PROJECT_DIR/res" \
    -I "$ANDROID_JAR" \
    -F "$BUILD_DIR/base.apk" \
    --min-sdk-version 26 \
    --target-sdk-version 35 \
    --version-code 1 \
    --version-name "1.0"
echo "  ✓ base.apk (resources.arsc + manifest)"

# 6. aapt add → classes.dex + assets
echo -e "${YELLOW}[6/7]${NC} aapt add → dex + assets..."
cd "$BUILD_DIR"
aapt add base.apk classes.dex >/dev/null
cd - >/dev/null

if [ -d "$PROJECT_DIR/assets" ]; then
    cd "$PROJECT_DIR"
    aapt add "$BUILD_DIR/base.apk" $(find assets -type f) >/dev/null
    cd - >/dev/null
    echo "  ✓ assets dodane"
fi

# 7. Podpisywanie
echo -e "${YELLOW}[7/7]${NC} apksigner → app-debug.apk..."
if [ ! -f "$HOME/.apk-builder-debug.keystore" ]; then
    keytool -genkey -v \
        -keystore "$HOME/.apk-builder-debug.keystore" \
        -alias debug \
        -keyalg RSA -keysize 2048 -validity 10000 \
        -storepass android -keypass android \
        -dname "CN=APK Builder, OU=Termux, O=Pi, L=Termux, ST=CLI, C=PL" \
        2>/dev/null
    echo "  ✓ klucz debug wygenerowany"
fi

apksigner sign \
    --ks "$HOME/.apk-builder-debug.keystore" \
    --ks-pass pass:android \
    --ks-key-alias debug \
    --key-pass pass:android \
    --out "$PROJECT_DIR/app-debug.apk" \
    "$BUILD_DIR/base.apk"

echo ""
echo -e "${GREEN}╔══════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  ✓ APK zbudowany!                   ║${NC}"
echo -e "${GREEN}║  📦 $PROJECT_DIR/app-debug.apk${NC}"
echo -e "${GREEN}╚══════════════════════════════════════╝${NC}"
echo ""
echo "  adb install $PROJECT_DIR/app-debug.apk"
