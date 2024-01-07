#!/system/bin/sh
MODDIR=${0%/*}
TMPPROP="$(magisk --path)/riru.prop"
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
unshare -m sh -c "/system/bin/app_process -Djava.class.path=rirud.apk /system/bin --nice-name=rirud riru.Daemon $(magisk -V) $(magisk --path) $(getprop ro.dalvik.vm.native.bridge)&"

rm -rf "$(magisk --path)/riru"
mkdir "$(magisk --path)/riru"
for libname in riru riruhide riruloader; do
  [ -f "$MODDIR/lib/lib${libname}.so" ] && cp -af "$MODDIR/lib/lib${libname}.so" "$(magisk --path)/riru/${libname}32"
  [ -f "$MODDIR/lib64/lib${libname}.so" ] && cp -af "$MODDIR/lib64/lib${libname}.so" "$(magisk --path)/riru/${libname}64"
done
chmod -R 755 "$(magisk --path)/riru"
  
"$MODDIR/riruloader" "$(magisk --path)" &
