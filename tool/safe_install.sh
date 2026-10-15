#!/usr/bin/env bash
# safe_install.sh — data-preserving APK installer for Bragmat.
#
# Hard rules enforced by this script:
#   * NEVER runs `adb uninstall` or `flutter install`.
#   * Verifies the APK's package ID matches the expected package.
#   * Refuses a versionCode downgrade of an installed app.
#   * Uses `adb install -r` (update-in-place, data preserved).
#   * If install fails (e.g. signature mismatch), prints the error and
#     STOPS — manual decision required, no automatic retry/uninstall.
#   * If the app is already installed and holds data, requires a backup
#     ZIP on shared storage (or an explicit --no-backup-ok override).
#
# Usage:
#   tool/safe_install.sh [path-to.apk] [--no-backup-ok] [--allow-downgrade]
#
# Default APK: build/app/outputs/flutter-apk/app-debug.apk

set -euo pipefail

PKG="com.example.bragmat"
APK="build/app/outputs/flutter-apk/app-debug.apk"
NO_BACKUP_OK=0
ALLOW_DOWNGRADE=0
CHECK_ONLY=0

for arg in "$@"; do
  case "$arg" in
    --no-backup-ok)    NO_BACKUP_OK=1 ;;
    --allow-downgrade) ALLOW_DOWNGRADE=1 ;;
    --check-only)      CHECK_ONLY=1 ;;
    *.apk)             APK="$arg" ;;
    *) echo "unknown arg: $arg" >&2; exit 2 ;;
  esac
done

fail() { echo "ABORT: $*" >&2; exit 1; }

# --- locate Android SDK tools -------------------------------------------
ADB="${ADB:-$LOCALAPPDATA/Android/Sdk/platform-tools/adb.exe}"
command -v "$ADB" >/dev/null 2>&1 || ADB=adb
command -v "$ADB" >/dev/null 2>&1 || fail "adb not found"

AAPT=$(ls -d "$LOCALAPPDATA"/Android/Sdk/build-tools/*/aapt.exe 2>/dev/null | sort -V | tail -1 || true)
APKSIGNER=$(ls -d "$LOCALAPPDATA"/Android/Sdk/build-tools/*/apksigner.bat 2>/dev/null | sort -V | tail -1 || true)

# --- verify APK exists and is the right package --------------------------
[ -f "$APK" ] || fail "APK not found: $APK"

if [ -n "$AAPT" ]; then
  BADGING=$("$AAPT" dump badging "$APK" 2>/dev/null) || fail "aapt could not read $APK"
  APK_PKG=$(echo "$BADGING" | sed -n "s/^package: name='\([^']*\)'.*/\1/p")
  APK_VC=$(echo "$BADGING" | sed -n "s/^package: name='[^']*' versionCode='\([0-9]*\)'.*/\1/p")
  APK_VER=$(echo "$BADGING" | sed -n "s/^package: name='[^']*' versionCode='[0-9]*' versionName='\([^']*\)'.*/\1/p")
  [ "$APK_PKG" = "$PKG" ] || fail "APK package '$APK_PKG' != expected '$PKG'"
else
  fail "aapt not found — cannot verify APK package/version"
fi
if [ -n "$APKSIGNER" ]; then
  # apksigner is a .bat on Windows — invoke via cmd; failure is non-fatal.
  APK_CERT=$(cmd //c "$(cygpath -w "$APKSIGNER")" verify --print-certs "$(cygpath -w "$APK")" 2>/dev/null \
    | sed -n 's/.*SHA-256 digest: *//p' | head -1 | tr -d '\r' || true)
fi

echo "APK:        $APK"
echo "  package:  $APK_PKG"
echo "  version:  $APK_VER (versionCode $APK_VC)"
[ -n "${APK_CERT:-}" ] && echo "  cert:     SHA-256 ${APK_CERT:0:32}..."

# --- verify exactly one device is connected ------------------------------
mapfile -t DEVICES < <("$ADB" devices | awk 'NR>1 && $2=="device" {print $1}')
[ "${#DEVICES[@]}" -eq 0 ] && fail "no device connected"
[ "${#DEVICES[@]}" -gt 1 ] && fail "multiple devices connected: ${DEVICES[*]}"
DEVICE="${DEVICES[0]}"
echo "Device:     $DEVICE ($("$ADB" -s "$DEVICE" shell getprop ro.product.model 2>/dev/null | tr -d '\r'))"

# --- inspect the currently installed app ---------------------------------
INSTALLED_VC=""
if "$ADB" -s "$DEVICE" shell pm list packages "$PKG" | grep -q "$PKG"; then
  DUMP=$("$ADB" -s "$DEVICE" shell dumpsys package "$PKG" 2>/dev/null | tr -d '\r')
  INSTALLED_VC=$(echo "$DUMP" | sed -n 's/.*versionCode=\([0-9]*\).*/\1/p' | head -1)
  INSTALLED_VER=$(echo "$DUMP" | sed -n 's/.*versionName=\([^ ]*\).*/\1/p' | head -1)
  echo "Installed:  version $INSTALLED_VER (versionCode $INSTALLED_VC)"

  if [ -n "$INSTALLED_VC" ] && [ "$APK_VC" -lt "$INSTALLED_VC" ]; then
    [ "$ALLOW_DOWNGRADE" -eq 1 ] || fail "downgrade $INSTALLED_VC -> $APK_VC refused (use --allow-downgrade only if you are certain; uninstall is still never attempted)"
    echo "WARNING: proceeding with downgrade $INSTALLED_VC -> $APK_VC by explicit flag"
  fi

  # --- backup check: existing data must be backed up outside the app ----
  BACKUP_FOUND=$("$ADB" -s "$DEVICE" shell 'find /sdcard/Download /sdcard/Documents -maxdepth 2 -name "bragmat_backup_*.zip" 2>/dev/null | head -1' | tr -d '\r')
  if [ -n "$BACKUP_FOUND" ]; then
    echo "Backup:     $BACKUP_FOUND"
  elif [ "$NO_BACKUP_OK" -eq 1 ]; then
    echo "WARNING:    no bragmat_backup_*.zip on shared storage; proceeding by explicit flag"
  else
    fail "installed app may hold data and no bragmat_backup_*.zip was found on shared storage.
       Export a ZIP backup in the app first, or pass --no-backup-ok to proceed anyway.
       NOTE: with 'adb install -r' data is preserved; this check is for catastrophic-failure safety."
  fi
else
  echo "Installed:  <not installed> — clean install"
fi

if [ "$CHECK_ONLY" -eq 1 ]; then
  echo "CHECK-ONLY: all pre-flight checks passed; no install performed."
  exit 0
fi

# --- install -------------------------------------------------------------
echo "Installing (adb install -r)..."
if ! "$ADB" -s "$DEVICE" install -r "$APK"; then
  fail "adb install -r failed.
       Likely causes: signature mismatch or incompatible update.
       Data on the device is untouched. Do NOT uninstall — investigate the
       signature first (apksigner verify --print-certs on the APK vs the
       installed app's signature via: adb shell pm dump $PKG | grep -i signature)"
fi
echo "OK — installed without uninstalling; app data preserved."
