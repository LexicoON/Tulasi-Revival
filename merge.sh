#!/bin/bash
# Tulasi+Papirus merge script
# Builds Tulasi PNGs, layers them on top of a downloaded Papirus base,
# and produces a single self-contained icon theme.
#
# Usage: bash merge.sh
# Output: ./Tulasi/ (the merged theme, ready to install)
#
# Requirements: librsvg2-bin, imagemagick, curl

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PAPIRUS_VERSION="${PAPIRUS_VERSION:-20260801}"
BUILD_DIR="$SCRIPT_DIR/build"

echo "=== Tulasi+Papirus merge build ==="
echo "    Papirus version: $PAPIRUS_VERSION"
echo "    Build dir: $BUILD_DIR"

# ─── 1. Download Papirus ───────────────────────────────────────────
if [ ! -d "papirus-src/Papirus" ]; then
  echo ""
  echo "=== Downloading Papirus $PAPIRUS_VERSION ==="
  mkdir -p papirus-src
  cd papirus-src
  curl -fL -o papirus.tar.gz \
    "https://github.com/PapirusDevelopmentTeam/papirus-icon-theme/archive/refs/tags/${PAPIRUS_VERSION}.tar.gz"
  tar -xzf papirus.tar.gz --strip-components=1
  rm papirus.tar.gz
  cd "$SCRIPT_DIR"
fi

# ─── 2. Check tools ───────────────────────────────────────────────
echo ""
echo "=== Checking build tools ==="
for tool in rsvg-convert; do
  if ! command -v "$tool" &> /dev/null; then
    echo "ERROR: $tool not found. Install with:"
    echo "  Debian/Ubuntu: sudo apt install librsvg2-bin"
    echo "  Arch:          sudo pacman -S librsvg"
    echo "  Fedora:        sudo dnf install librsvg2-tools"
    exit 1
  fi
done
if ! command -v magick &> /dev/null && ! command -v convert &> /dev/null; then
  echo "ERROR: ImageMagick (magick or convert) not found. Install with:"
  echo "  Debian/Ubuntu: sudo apt install imagemagick"
  echo "  Arch:          sudo pacman -S imagemagick"
  exit 1
fi
echo "    rsvg-convert: $(command -v rsvg-convert)"
if command -v magick &>/dev/null; then
  echo "    magick:       $(command -v magick)"
else
  echo "    convert:      $(command -v convert)"
fi

# ─── 3. Run Tulasi build ──────────────────────────────────────────
echo ""
echo "=== Building Tulasi PNGs ==="
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
cp -r cow "$BUILD_DIR/cow"
[ -d scalable ] && cp -r scalable "$BUILD_DIR/scalable"

# Use the upstream scale.sh to build Tulasi first
bash scale.sh
# Move everything from current dir into build/ for the merge step
cp -r 16x16 24x24 32x32 48x48 64x64 128x128 256x256 512x512 "$BUILD_DIR/" 2>/dev/null || true
cp -r scalable "$BUILD_DIR/" 2>/dev/null || true
cp index.theme "$BUILD_DIR/" 2>/dev/null || true
echo "    Tulasi built (119 source SVGs processed)"

# ─── 4. Layer Papirus underneath ──────────────────────────────────
echo ""
echo "=== Layering Papirus as the base ==="
cd "$BUILD_DIR"

# Copy Papirus into build/ — this is the base layer
cp -r "$SCRIPT_DIR/papirus-src/Papirus/." .
cp -r "$SCRIPT_DIR/papirus-src/Papirus-Dark/." Papirus-Dark/ 2>/dev/null || true
cp -r "$SCRIPT_DIR/papirus-src/Papirus-Light/." Papirus-Light/ 2>/dev/null || true

# Now copy Tulasi's apps/ folders on top — Tulasi wins
for size in 16x16 24x24 32x32 48x48 64x64 128x128 256x256 512x512; do
  if [ -d "$SCRIPT_DIR/$size/apps" ]; then
    cp -rf "$SCRIPT_DIR/$size/apps/." "$size/apps/"
  fi
done

if [ -d "$SCRIPT_DIR/scalable" ]; then
  cp -rf "$SCRIPT_DIR/scalable/." scalable/
fi

# ─── 5. Generate the merged index.theme ───────────────────────────
echo ""
echo "=== Generating merged index.theme ==="
ALL_DIRS=""
for size in 8x8 16x16 18x18 22x22 24x24 32x32 42x42 48x48 64x64 84x84 96x96 128x128 256x256 512x512; do
  for ctx in apps actions devices mimetypes places status categories emblems emotes panel; do
    if [ -d "$size/$ctx" ]; then
      ALL_DIRS="$ALL_DIRS,$size/$ctx"
    fi
  done
done
for size in 16x16 22x22 24x24 32x32 48x48 64x64; do
  if [ -d "${size}@2x" ]; then
    for ctx in apps actions devices mimetypes places status categories; do
      if [ -d "${size}@2x/$ctx" ]; then
        ALL_DIRS="$ALL_DIRS,${size}@2x/$ctx"
      fi
    done
  fi
done
ALL_DIRS="${ALL_DIRS#,}"

cat > index.theme <<HEADER
[Icon Theme]
Name=Tulasi
Comment=Tulasi pixel art layered on top of Papirus
Inherits=hicolor
FollowsColorScheme=true

DesktopDefault=48
DesktopSizes=16,22,24,32,48,64
ToolbarDefault=22
ToolbarSizes=16,22,24,32,48
MainToolbarDefault=22
MainToolbarSizes=16,22,24,32,48
SmallDefault=16
SmallSizes=16,22,24,32,48
PanelDefault=48
PanelSizes=16,22,24,32,48,64
DialogDefault=48
DialogSizes=16,22,24,32,48,64

Directories=${ALL_DIRS}
HEADER

# Append per-directory sections
for dir in $(echo "$ALL_DIRS" | tr ',' ' '); do
  size_part=$(echo "$dir" | cut -d'/' -f1)
  ctx_part=$(echo "$dir" | cut -d'/' -f2)

  if [[ "$size_part" == *"@"* ]]; then
    nominal=$(echo "$size_part" | sed -E 's/([0-9]+)x[0-9]+@.*/\1/')
    scale=$(echo "$size_part" | sed -E 's/.*@([0-9]+)x?/\1/')
    cat >> index.theme <<SECTION

[$dir]
Size=${nominal}
Scale=${scale}
Type=Scalable
MinSize=${nominal}
MaxSize=$((nominal * 4))
Context=${ctx_part^}
SECTION
  else
    nominal=$(echo "$size_part" | sed -E 's/([0-9]+)x.*/\1/')
    cat >> index.theme <<SECTION

[$dir]
Size=${nominal}
Type=Fixed
Context=${ctx_part^}
SECTION
  fi
done

# ─── 6. Final cleanup ─────────────────────────────────────────────
echo ""
echo "=== Final cleanup ==="
# Remove Papirus's own index.theme files (we have our merged one)
find . -name 'index.theme' ! -path './index.theme' -delete
# Remove icon cache
find . -name 'icon-theme.cache' -delete
# Remove Papirus's hidden desktop entry files (these are for the Papirus theme picker, not needed)
find . -name '.directory' -delete

# ─── 7. Move to output location ───────────────────────────────────
cd "$SCRIPT_DIR"
rm -rf Tulasi
mv "$BUILD_DIR" Tulasi

echo ""
echo "=== Build complete ==="
echo ""
echo "Theme location: $SCRIPT_DIR/Tulasi"
echo "Total PNGs:     $(find Tulasi -name '*.png' -type f | wc -l)"
echo "Total SVGs:     $(find Tulasi -name '*.svg' -type f | wc -l)"
echo ""
echo "Install with:"
echo "  cp -r Tulasi ~/.local/share/icons/"
echo "  gtk-update-icon-cache -f -t ~/.local/share/icons/Tulasi"
echo ""
echo "On KDE also run:"
echo "  rm -f ~/.cache/icon-cache.kcache"
echo "  kquitapp6 plasmashell && kstart plasmashell"
