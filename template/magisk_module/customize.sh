SKIPUNZIP=1

RIRU_API="@RIRU_API@"
RIRU_VERSION_CODE="@RIRU_VERSION_CODE@"
RIRU_VERSION_NAME="@RIRU_VERSION_NAME@"

if $BOOTMODE; then
  ui_print "- Installing from Magisk app"
else
  ui_print "*********************************************************"
  ui_print "! Install from recovery is NOT supported"
  ui_print "! Some recovery has broken implementations, install with such recovery will finally cause Riru or Riru modules not working"
  ui_print "! Please install from Magisk app"
  abort "*********************************************************"
fi

ui_print "- Installing Riru $RIRU_VERSION_NAME (Riru API $RIRU_API)"

# check Magisk
ui_print "- Magisk version: $MAGISK_VER ($MAGISK_VER_CODE)"

if [ "$MAGISK_VER_CODE" -lt 25200 ]; then
  abort "! Please install Magisk v25200+"
fi

# check android
if [ "$API" -lt 23 ]; then
  ui_print "! Unsupported sdk: $API"
  abort "! Minimal supported sdk is 23 (Android 6.0)"
else
  ui_print "- Device sdk: $API"
fi

# check architecture
if [ "$ARCH" != "arm" ] && [ "$ARCH" != "arm64" ] && [ "$ARCH" != "x86" ] && [ "$ARCH" != "x64" ]; then
  abort "! Unsupported platform: $ARCH"
else
  ui_print "- Device platform: $ARCH"
fi

unzip -o "$ZIPFILE" 'verify.sh' -d "$TMPDIR" >&2
if [ ! -f "$TMPDIR/verify.sh" ]; then
  ui_print "*********************************************************"
  ui_print "! Unable to extract verify.sh!"
  ui_print "! This zip may be corrupted, please try downloading again"
  abort "*********************************************************"
fi
. $TMPDIR/verify.sh

extract "$ZIPFILE" 'customize.sh' "$TMPDIR/.vunzip"
extract "$ZIPFILE" 'verify.sh' "$TMPDIR/.vunzip"

ui_print "- Extracting Magisk files"

MAGISK_CURRENT_MODULE_PATH=/data/adb/modules/riru-core

extract "$ZIPFILE" 'module.prop' "$MODPATH"
cp "$MODPATH/module.prop" "$MODPATH/module.prop.bk"
extract "$ZIPFILE" 'post-fs-data.sh' "$MODPATH"
extract "$ZIPFILE" 'util_functions.sh' "$MODPATH"
extract "$ZIPFILE" 'sepolicy.rule' "$MODPATH"
extract "$ZIPFILE" 'uninstall.sh' "$MODPATH"

mkdir $MAGISK_CURRENT_MODULE_PATH
rm "$MAGISK_CURRENT_MODULE_PATH"/util_functions.sh
cp "$MODPATH"/util_functions.sh "$MAGISK_CURRENT_MODULE_PATH"/util_functions.sh

mkdir "$MODPATH/lib"
mkdir "$MODPATH/lib64"
[ "$IS64BIT" = true ] && mkdir "$MODPATH/system/lib64"

if [ "$ARCH" = "x86" ] || [ "$ARCH" = "x64" ]; then
  ui_print "- Extracting x86 libraries"
  extract "$ZIPFILE" 'lib/x86/libriru.so' "$MODPATH/lib" true
  extract "$ZIPFILE" 'lib/x86/libriruloader.so' "$MODPATH/lib" true

  if [ "$IS64BIT" = true ]; then
    ui_print "- Extracting x64 libraries"
    extract "$ZIPFILE" 'lib/x86_64/libriru.so' "$MODPATH/lib64" true
    extract "$ZIPFILE" 'lib/x86_64/libriruloader.so' "$MODPATH/lib64" true
  fi
else
  ui_print "- Extracting arm libraries"
  extract "$ZIPFILE" 'lib/armeabi-v7a/libriru.so' "$MODPATH/lib" true
  extract "$ZIPFILE" 'lib/armeabi-v7a/libriruloader.so' "$MODPATH/lib" true

  if [ "$IS64BIT" = true ]; then
    ui_print "- Extracting arm64 libraries"
    extract "$ZIPFILE" 'lib/arm64-v8a/libriru.so' "$MODPATH/lib64" true
    extract "$ZIPFILE" 'lib/arm64-v8a/libriruloader.so' "$MODPATH/lib64" true
  fi
fi

ui_print "- Setting permissions"
set_perm_recursive "$MODPATH" 0 0 0755 0644

if [ "$IS64BIT" = true ]; then
  ln -s ./lib64/libriruloader.so "$MODPATH/riruloader"
else
  ln -s ./lib/libriruloader.so "$MODPATH/riruloader"
fi

chmod 755 "$MODPATH/lib"*"/libriruloader.so"

ui_print "- Extracting rirud"
extract "$ZIPFILE" "rirud.apk" "$MODPATH"
set_perm "$MODPATH/rirud.apk" 0 0 0600

ui_print "- Checking if your ROM has incorrect SELinux rules"
/system/bin/app_process -Djava.class.path="$MODPATH/rirud.apk" /system/bin --nice-name=riru_installer riru.Installer --check-selinux

ui_print "- Removing old files"
rm -rf /data/adb/riru/bin
rm /data/adb/riru/native_bridge
rm /data/adb/riru/api_version.new
rm /data/adb/riru/version_code.new
rm /data/adb/riru/version_name.new
rm /data/adb/riru/enable_hide
rm /data/adb/riru/api_version
rm /data/adb/riru/util_functions.sh
rm /data/misc/riru/api_version
rm /data/misc/riru/version_code
rm /data/misc/riru/version_name

# If Huawei's Maple is enabled, system_server is created with a special way which is out of Riru's control
HUAWEI_MAPLE_ENABLED=$(grep_prop ro.maple.enable)
if [ $HUAWEI_MAPLE_ENABLED == "1" ]; then
  ui_print "- Add ro.maple.enable=0"
  echo "ro.maple.enable=0" >> "$MODPATH/system.prop"
fi
