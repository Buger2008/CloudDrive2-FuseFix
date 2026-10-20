#!/system/bin/sh
# CloudDrive2 FUSE 挂载修复 - 只做状态记录，方便排查
MODDIR=${0%/*}
LOG=/data/adb/clouddrive2_fusepatch.log

(
  i=0
  while [ "$(getprop sys.boot_completed)" != "1" ] && [ $i -lt 60 ]; do
    sleep 5
    i=$((i + 1))
  done
  {
    echo "$(date '+%F %T') service: selinux=$(getenforce) policy=$(md5sum /sys/fs/selinux/policy 2>/dev/null | cut -d' ' -f1)"
    grep -i cloudfs /proc/mounts || echo "$(date '+%F %T') service: 暂无 CloudFS 挂载（打开 CloudDrive2 后会自动挂载）"
  } >> "$LOG"
) &
