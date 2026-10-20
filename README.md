# CloudDrive2 FUSE 挂载修复

修复 **CloudDrive2（`com.clouddrive2.CloudDrive2`）在安卓上挂载网盘时提示 `IO Permission denied error 13`** 的问题。
只放行一条 SELinux 规则，**保持 SELinux 强制（Enforcing）**，不使用宽容模式，因此不会触发银行类 App 的 root / SELinux 检测。

- 模块 ID：`clouddrive2_fuse_fix`
- 当前版本：V1.1（versionCode 2）
- 作者：Buger

## 适用环境

| 项目 | 值 |
|---|---|
| 机型 | PMG110（OPPO / ColorOS 16） |
| Android | 16（SDK 36） |
| Root | KernelSU（`kernelsu` 为 LKM，Magica late-load 临时 root 亦可） |
| SELinux | Enforcing |
| CloudDrive2 | 1.1.3（versionCode 346） |

理论上同样适用于其它「App 挂载 FUSE 被 SELinux 拦截」的场景，但只在上述环境验证过。

## 原理

CloudDrive2 挂载时需要 App 进程（SELinux 域 `untrusted_app`）对 `/dev/fuse` 做 read/write，而系统策略里没有对应规则，内核直接拒绝：

```
avc: denied { read write } for comm="cloudapi-worker" path="/dev/fuse"
  scontext=u:r:untrusted_app:s0:c135,c257,c512,c768
  tcontext=u:object_r:fuse_device:s0 tclass=chr_file permissive=0
  app=com.clouddrive2.CloudDrive2
```

于是 `read()/write()` 返回 `EACCES(13)`，CloudDrive2 日志表现为：

```
ERROR cloudapi::fuse::linux_fuse3_raw: unprivileged mount also failed
      Io(Os { code: 13, kind: PermissionDenied, message: "Permission denied" })
```

CloudDrive2 自身会用 `magiskpolicy` 热补丁策略来自救，但在 ColorOS 上该路径被系统加固拦截（`magiskpolicy --live` 报 `Out of memory`，dmesg 出现
`[secureguard][secure_harden]oplus_sepolicy_reload: Detected illegal porcess reload policy`）。

本模块把这条规则交给 KernelSU 应用：

```selinux
allow untrusted_app fuse_device chr_file { read write }
```

`/dev/fuse` 的文件权限保持原始 `crw------- root root`，**不需要** `chmod`，也**不需要**关闭 SELinux。

## 安装

### KernelSU 管理器

1. 下载 `clouddrive2_fuse_fix-2-V1.1.zip`
2. KernelSU 管理器 → 模块 → 从本地安装
3. 按你的环境重启，或直接重载 root

### 手动解压

```bash
adb push module /data/local/tmp/
adb shell su -c 'mkdir -p /data/adb/modules/clouddrive2_fuse_fix && \
  cp /data/local/tmp/module/* /data/adb/modules/clouddrive2_fuse_fix/ && \
  chown -R 0:0 /data/adb/modules/clouddrive2_fuse_fix && \
  chmod 644 /data/adb/modules/clouddrive2_fuse_fix/module.prop \
            /data/adb/modules/clouddrive2_fuse_fix/sepolicy.rule \
            /data/adb/modules/clouddrive2_fuse_fix/skip_mount && \
  chmod 755 /data/adb/modules/clouddrive2_fuse_fix/post-fs-data.sh \
            /data/adb/modules/clouddrive2_fuse_fix/service.sh'
```

### 立即生效（不必重启）

```bash
adb shell su -c 'ksud sepolicy apply /data/adb/modules/clouddrive2_fuse_fix/sepolicy.rule'
```

> 注意：`ksud sepolicy patch '<语句>'` 在本环境返回成功但**策略没有任何变化**（假成功）。
> 必须用 `ksud sepolicy apply <文件>`，可用 `md5sum /sys/fs/selinux/policy` 前后对比确认。

## 文件说明

| 文件 | 作用 |
|---|---|
| `module.prop` | 模块信息 |
| `sepolicy.rule` | 核心规则，KernelSU 在 post-fs-data / late-load 阶段自动加载 |
| `post-fs-data.sh` | 标准启动模式下用 `ksud sepolicy apply` 兜底重放并记录策略 md5 |
| `service.sh` | 只记录状态（SELinux 状态、策略 md5、是否已挂载）到 `/data/adb/clouddrive2_fusepatch.log` |
| `skip_mount` | 声明本模块不挂载任何 `/system` 内容 |

### 关于 late-load 模式

在 **late-load**（LKM 临时 root）模式下，KernelSU 用 `late-load` 阶段替代 `post-fs-data`：
会加载模块的 `sepolicy.rule`、执行 `service.sh`，但**不执行** `post-fs-data.sh`。
本模块的核心生效路径是 `sepolicy.rule`，因此在标准启动与 late-load 两种模式下都有效。

## 验证

```bash
# 1. 必须仍是 Enforcing
adb shell su -c getenforce

# 2. 策略已变化
adb shell su -c 'md5sum /sys/fs/selinux/policy'

# 3. 挂载成功
adb shell su -c 'grep -i cloudfs /proc/mounts'

# 4. 不应再有 /dev/fuse 的 AVC 拒绝
adb shell su -c "dmesg | grep -i avc | grep -i fuse_device"
```

实测：连续重建挂载均成功，`/dev/fuse` 相关 AVC 拒绝 0 条，应用日志无新增 error 13。

## 卸载

```bash
adb shell su -c 'rm -rf /data/adb/modules/clouddrive2_fuse_fix'
```

之后重启或重载 root，让 SELinux 策略恢复原状（`sepolicy.rule` 只增不减，删除模块不会回退已加载的规则）。

## 已知限制（与本问题无关）

挂载点父目录 `/mnt/runtime/default/emulated` 是 `0700 root:root`，且该 FUSE 挂载未指定 `context=`，SELinux 类型为 `fuse`。
因此**只有 root 能访问挂载出来的目录**，普通 App 与 `adb shell` 会 `Permission denied`，`/storage/emulated/0/CloudDrive` 也不存在。
若需要让其它 App 读取网盘内容，需要另行处理挂载点位置或 bind mount + 重新打标签。

## 更新日志

### V1.1（versionCode 2）

- 放行 `allow untrusted_app fuse_device chr_file { read write }`
- `post-fs-data.sh` 增加 `ksud sepolicy apply` 兜底与策略 md5 记录
- `service.sh` 输出状态日志
