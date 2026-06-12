# RootfsPatch

已发布 rootfs 的版本化热修补丁。**与 rootfs 分别 release**：patch 发布到固定 tag
`rootfs-patch` 的滚动 Release（资产每次替换、永不标记 latest），与 rootfs 的
`vX.Y.Z-*` 版本系列互不触发、互不干扰。

iSH 在 **Xcode 构建时**从稳定 URL
`releases/download/rootfs-patch/RootfsPatch.tar.gz` 下载补丁，解包成 app 内的
`RootfsPatch.bundle`；应用启动时（`FsApplyOverlay()` in ish 的
`app/CurrentRoot.m`）按 `manifest.plist` 把文件叠加进 guest 文件系统，以 guest 内
`/ish/overlay-version` 的整数版本做幂等门控。

用途：给**已经部署在用户设备上**的 rootfs 打小补丁，无需重新导入 root.tar.gz。
仅在明确需要热修时才更新——日常的 rootfs 改进直接改 `build/`，走 rootfs 发版，
**不放进 patch**。

## 目录结构

```
patch/
├── VERSION        ← 自增整数。改了 files/ 必须 +1，CI 会强制检查
└── files/         ← 以 guest 绝对路径为根的文件树
    └── etc/profile.d/foo.sh   → 叠加为 guest 的 /etc/profile.d/foo.sh
```

`manifest.plist` 不手写：发布时由 `build/gen_patch_manifest.py` 从 `VERSION` +
`files/` 树自动生成（`src = files/<rel>`，`dst = /<rel>`），杜绝清单与文件漂移。

## 发版流程

1. 把文件按 guest 绝对路径放进 `files/`
2. `VERSION` +1（每次更新必须递增）
3. 提交并推送 main —— `patch-release.yml`（按 `patch/**` 路径触发）打包
   `RootfsPatch.tar.gz`（+`.sha256`），更新 `rootfs-patch` 滚动 Release；
   iSH 下次构建自动拉到

CI 守门：如果 `files/` 内容相对已发布资产变了而 `VERSION` 没有增大，发布失败。
本地打包/检查：`./build/package_patch.sh`（产物在 `dist/`）。

## 与 rootfs 本体的关系

- `build/inside.sh` 会把 `patch/files/` 同样叠加进新构建的 rootfs，并把
  `/ish/overlay-version` 写成当前 `VERSION` —— 新导入的 rootfs 自带补丁内容，
  首次启动直接跳过 overlay。
- 因此补丁内容只需要维护一份；rootfs 重新发版时自然吸收全部补丁。
  补丁在 rootfs 侧的长期归宿应是 `build/inside.sh`/`packages.txt`：
  下次大版本时把成熟的补丁内容移进构建脚本，然后清空 `files/`（`VERSION` 继续递增，不回退）。

## 注意事项

- `dst` 即 guest 绝对路径，父目录由 iSH 自动创建，写入会覆盖已有文件
- 单文件控制在几 MB 内（iSH 整读进内存）
- 不要与 ish 侧 `GuestRuntime.bundle` 的 `dst` 路径重叠（见 ish 的
  `docs/ssh-key-management.md`）
