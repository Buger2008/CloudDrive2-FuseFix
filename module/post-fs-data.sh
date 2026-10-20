#!/system/bin/sh
# CloudDrive2 FUSE 挂载修复
# KernelSU 会自动应用本模块的 sepolicy.rule；这里再用已验证可用的
# `ksud sepolicy apply <文件>` 兜底重放一次（幂等，不会重复加规则）。
MODDIR=${0%/*}
RULE=$MODDIR/sepolicy.rule
LOG=/data/adb/clouddrive2_fusepatch.log

if [ -f "$RULE" ]; then
  /data/adb/ksud sepolicy apply "$RULE" >> "$LOG" 2>&1
  echo "$(date '+%F %T') post-fs-data: selinux=$(getenforce) policy=$(md5sum /sys/fs/selinux/policy 2>/dev/null | cut -d' ' -f1)" >> "$LOG"
fi
