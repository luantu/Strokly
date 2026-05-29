#!/usr/bin/env bash
set -euo pipefail
export COPYFILE_DISABLE=1

MODE="${1:-run}"
APP_NAME="Strokly"
BUNDLE_ID="com.luantu.Strokly"
MIN_SYSTEM_VERSION="13.0"
APP_VERSION="0.2.0"
APP_BUILD="2"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
DMG_STAGING="$DIST_DIR/dmg-staging"
DMG_PATH="$DIST_DIR/$APP_NAME.dmg"
PKG_PATH="$DIST_DIR/$APP_NAME.pkg"
PKG_ROOT="$DIST_DIR/pkg-root"
SWIFT_BUILD_FLAGS="${SWIFT_BUILD_FLAGS:-}"

build_bundle() {
  # shellcheck disable=SC2086
  swift build $SWIFT_BUILD_FLAGS --product "$APP_NAME"
  # shellcheck disable=SC2086
  local build_dir
  build_dir="$(swift build $SWIFT_BUILD_FLAGS --show-bin-path)"
  local build_binary="$build_dir/$APP_NAME"

  rm -rf "$APP_BUNDLE"
  mkdir -p "$APP_MACOS" "$APP_CONTENTS/Resources"
  cp "$build_binary" "$APP_BINARY"
  chmod +x "$APP_BINARY"

  # Generate app icon
  generate_icon "$APP_CONTENTS"
  copy_localization_resources "$build_dir"

  cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleDevelopmentRegion</key>
  <string>zh-Hans</string>
  <key>CFBundleAllowMixedLocalizations</key>
  <true/>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$APP_BUILD</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon.icns</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSAppleEventsUsageDescription</key>
  <string>Strokly runs user-defined AppleScript actions when assigned to a mouse gesture.</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

  xattr -cr "$APP_BUNDLE" >/dev/null 2>&1 || true
  find "$APP_BUNDLE" -name '._*' -delete
  codesign --force --sign - "$APP_BUNDLE" >/dev/null 2>&1 || true
  xattr -cr "$APP_BUNDLE" >/dev/null 2>&1 || true
  find "$APP_BUNDLE" -name '._*' -delete
  refresh_app_registration
}

copy_localization_resources() {
  local build_dir="$1"
  local resources_dir="$APP_CONTENTS/Resources"

  # SwiftPM resources live in sidecar bundles next to the executable. Copy the
  # bundle for Bundle.module access and copy lproj folders to the main app
  # bundle so SwiftUI Text("key") localization also works.
  find "$build_dir" -maxdepth 1 -type d -name "${APP_NAME}_*.bundle" | while read -r bundle; do
    ditto --norsrc --noextattr "$bundle" "$resources_dir/$(basename "$bundle")"
    find "$bundle" -maxdepth 1 -type d -name "*.lproj" | while read -r lproj; do
      local name
      name="$(basename "$lproj")"
      rm -rf "$resources_dir/$name"
      ditto --norsrc --noextattr "$lproj" "$resources_dir/$name"
    done
  done

  # SwiftPM normalizes zh-Hans.lproj to zh-hans.lproj on disk. Keep both names
  # in the app bundle because CoreFoundation lookup is usually case-insensitive
  # on APFS, but explicit paths in our L10n helper are not.
  if [ -d "$resources_dir/zh-hans.lproj" ] && [ ! -d "$resources_dir/zh-Hans.lproj" ]; then
    ditto --norsrc --noextattr "$resources_dir/zh-hans.lproj" "$resources_dir/zh-Hans.lproj"
  fi
}

generate_icon() {
  local CONTENTS_DIR="${1:-$APP_CONTENTS}"
  local ICONSET_DIR="$DIST_DIR/AppIcon.iconset"
  local ICON_SRC="$DIST_DIR/icon_1024.png"
  local RESOURCES_DIR="$CONTENTS_DIR/Resources"
  local ICON_PATH="$RESOURCES_DIR/AppIcon.icns"

  rm -rf "$ICONSET_DIR"
  mkdir -p "$ICONSET_DIR" "$RESOURCES_DIR"

  # Generate 1024x1024 icon using Python
  export ICON_SRC
  python3 << 'PYEOF'
import struct, zlib, math, os

W, H = 1024, 1024
pixels = bytearray(W * H * 4)

for y in range(H):
    for x in range(W):
        i = (y * W + x) * 4
        cx, cy = x / W - 0.5, y / H - 0.5
        ax, ay = abs(cx), abs(cy)
        corner = max(ax - 0.38, 0) ** 2 + max(ay - 0.38, 0) ** 2
        in_shape = corner < 0.04 or (ax < 0.38 and ay < 0.42) or (ax < 0.42 and ay < 0.38)
        if not in_shape:
            pixels[i:i+4] = b'\x00\x00\x00\x00'
            continue
        t = (cy + 0.5)
        r_c = int(30 + t * 80)
        g_c = int(100 + (1-t) * 60)
        b_c = int(220 + t * 35)
        arc_cx, arc_cy = 0.0, 0.05
        arc_r = 0.28
        angle = math.atan2(cy - arc_cy, cx - arc_cx)
        dist_to_arc = abs(math.sqrt((cx-arc_cx)**2 + (cy-arc_cy)**2) - arc_r)
        in_arc = dist_to_arc < 0.035 and -0.8 < angle < 1.8
        finger_x, finger_y = 0.18, -0.18
        finger_dist = math.sqrt((cx-finger_x)**2 + (cy-finger_y)**2)
        in_finger = finger_dist < 0.07
        if in_arc or in_finger:
            r_c, g_c, b_c = 255, 255, 255
        pixels[i] = min(r_c, 255)
        pixels[i+1] = min(g_c, 255)
        pixels[i+2] = min(b_c, 255)
        pixels[i+3] = 255

def write_png(path, w, h, px):
    def chunk(ct, d):
        c = ct + d
        return struct.pack('>I', len(d)) + c + struct.pack('>I', zlib.crc32(c) & 0xffffffff)
    raw = b''
    for row in range(h):
        raw += b'\x00' + bytes(px[row*w*4:(row+1)*w*4])
    with open(path, 'wb') as f:
        f.write(b'\x89PNG\r\n\x1a\n')
        f.write(chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 6, 0, 0, 0)))
        f.write(chunk(b'IDAT', zlib.compress(raw)))
        f.write(chunk(b'IEND', b''))

write_png(os.environ.get('ICON_SRC', 'icon_1024.png'), W, H, pixels)
PYEOF

  if [ ! -f "$ICON_SRC" ]; then
    echo "error: icon source was not generated: $ICON_SRC" >&2
    exit 1
  fi

  for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$ICON_SRC" --out "$ICONSET_DIR/icon_${size}x${size}.png" >/dev/null 2>&1
    double=$((size * 2))
    sips -z "$double" "$double" "$ICON_SRC" --out "$ICONSET_DIR/icon_${size}x${size}@2x.png" >/dev/null 2>&1
  done
  cp "$ICON_SRC" "$ICONSET_DIR/icon_512x512@2x.png"

  rm -f "$ICON_PATH"
  iconutil -c icns "$ICONSET_DIR" -o "$ICON_PATH"
  cp "$ICON_PATH" "$DIST_DIR/AppIcon.icns"
  xattr -cr "$ICON_PATH" "$DIST_DIR/AppIcon.icns" >/dev/null 2>&1 || true
  rm -rf "$ICONSET_DIR" "$ICON_SRC"
  echo "Created $ICON_PATH"
}

package_installer() {
  build_bundle

  rm -rf "$PKG_ROOT" "$PKG_PATH"
  mkdir -p "$PKG_ROOT/Applications"
  ditto --norsrc --noextattr "$APP_BUNDLE" "$PKG_ROOT/Applications/$APP_NAME.app"
  pkgbuild \
    --root "$PKG_ROOT" \
    --identifier "$BUNDLE_ID.pkg" \
    --version "0.1.0" \
    --install-location / \
    --filter '(^|/)\._' \
    --filter '(^|/)\.__' \
    --filter '(^|/)\.DS_Store$' \
    "$PKG_PATH"
  echo "Created $PKG_PATH"
}

package_dmg() {
  rm -rf "$DMG_STAGING" "$DMG_PATH"
  mkdir -p "$DMG_STAGING"
  cp -R "$APP_BUNDLE" "$DMG_STAGING/"
  ln -s /Applications "$DMG_STAGING/Applications"
  if hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_STAGING" -ov -format UDZO "$DMG_PATH"; then
    echo "Created $DMG_PATH"
  else
    echo "Skipped DMG: hdiutil failed in this environment. Use $PKG_PATH instead." >&2
  fi
}

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

refresh_app_registration() {
  touch "$APP_BUNDLE"
  local lsregister="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
  if [ -x "$lsregister" ]; then
    "$lsregister" -f "$APP_BUNDLE" >/dev/null 2>&1 || true
  fi
}

stop_running_app() {
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
}

case "$MODE" in
  generate_icon|generate-icon|--generate-icon)
    generate_icon "$APP_CONTENTS"
    ;;
  build|--build)
    build_bundle
    ;;
  run)
    stop_running_app
    build_bundle
    open_app
    ;;
  --debug|debug)
    stop_running_app
    build_bundle
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    stop_running_app
    build_bundle
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    stop_running_app
    build_bundle
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    stop_running_app
    build_bundle
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  --package|package)
    package_installer
    package_dmg
    ;;
  clean|--clean)
    rm -rf "$DIST_DIR" "$ROOT_DIR/.build"
    ;;
  *)
    echo "usage: $0 [generate_icon|build|run|--debug|--logs|--telemetry|--verify|--package|clean]" >&2
    exit 2
    ;;
esac
