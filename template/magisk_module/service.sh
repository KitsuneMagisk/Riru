#!/system/bin/sh
MODDIR=${0%/*}
TMP_PATH=/sbin
[ ! -d "$TMP_PATH" ] && TMP_PATH=/debug_ramdisk
TMPPROP="$TMP_PATH/riru.prop"
MIRRORPROP="/data/adb/modules/riru-core/module.prop"
sh -Cc "cat '$MODDIR/module.prop' > '$TMPPROP'"
if [ $? -eq 0 ]; then
  mount --bind "$TMPPROP" "$MIRRORPROP"
  sed -Ei 's/^description=(\[.*][[:space:]]*)?/description=[ ⛔ post-fs-data.sh fails to run. Magisk is broken on this device. ] /g' "$MODDIR/module.prop"
  exit
fi

