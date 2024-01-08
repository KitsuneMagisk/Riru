#!/system/bin/sh
MODDIR=${0%/*}
TMP_PATH=/sbin
[ ! -d "$TMP_PATH" ] && TMP_PATH=/debug_ramdisk
TMPPROP="$TMP_PATH/riru.prop"
MIRRORPROP="/data/adb/modules/riru-core/module.prop"
sh -Cc "cat '$MODDIR/module.prop' > '$TMPPROP'"
if [ $? -ne 0 ]; then
  exit
fi
mount --bind "$TMPPROP" "$MIRRORPROP"
if [ "$ZYGISK_ENABLE" = "1" ]; then
    sed -Ei 's/^description=(\[.*][[:space:]]*)?/description=[ ⛔ Riru is not loaded because of Zygisk. ] /g' "$MIRRORPROP"
    exit
fi
sed -Ei 's/^description=(\[.*][[:space:]]*)?/description=[ ⛔ app_process fails to run. ] /g' "$MIRRORPROP"
cd "$MODDIR" || exit
flock "module.prop"
unshare -m sh -c "/system/bin/app_process -Djava.class.path=rirud.apk /system/bin --nice-name=rirud riru.Daemon $(magisk -V) $TMP_PATH $(getprop ro.dalvik.vm.native.bridge)&"

rm -rf "$TMP_PATH/riru"
mkdir "$TMP_PATH/riru"
for libname in riru riruhide riruloader; do
  [ -f "$MODDIR/lib/lib${libname}.so" ] && cp -af "$MODDIR/lib/lib${libname}.so" "$TMP_PATH/riru/${libname}32"
  [ -f "$MODDIR/lib64/lib${libname}.so" ] && cp -af "$MODDIR/lib64/lib${libname}.so" "$TMP_PATH/riru/${libname}64"
done
chmod -R 755 "$TMP_PATH/riru"
  
"$MODDIR/riruloader" "$TMP_PATH" &
