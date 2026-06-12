# alpine-rootfs

自定义 Alpine rootfs 的构建与发布。
产物是干净的根文件系统压缩归档（`tar.gz`），不是带 layer 元数据的容器镜像归档。

## 产物

- 架构：`aarch64`（ARM64）。结构上为后续扩展其它架构留位，本期只交付 ARM64。
- 文件：`alpine-aarch64-rootfs.tar.gz` 与 `alpine-aarch64-rootfs.tar.gz.sha256`。
- 基线：固定版本的 Alpine miniroot（参见 [`build/build.sh`](build/build.sh) 中的 `ALPINE_VERSION`），不使用 `latest`/`edge` 之类浮动标签。
- 预装：`nano`、`vim`、`git`、`curl`、`openssh-client`、`ca-certificates`、`tzdata` 等常用工具。完整清单见 [`build/packages.txt`](build/packages.txt)。
- 不启用任何系统服务（无真实 init 环境）。
- `/proc`、`/sys`、`/dev` 目录保留为空，不包含运行时动态内容。
- 内置默认环境变量（`SSL_CERT_FILE`、`TERM`、`EDITOR`/`VISUAL`、`HOME`），全部为守护式兜底——spawner 传入的值优先；`PATH` 会前置 `~/.bun/bin`、`~/.local/bin`（目录存在时）。脚本装在 `/etc/profile.d/`（login shell）与 `/etc/bash/`（交互式非 login bash）两处；非交互执行（`sh -c`）不经过任何 rc 文件，消费方应以 login shell（`-l`）启动，或自行传入所需环境。
- root 的登录 shell 为 bash，并附带交互默认值（history 行为、`ll`/`la` 别名、彩色提示符——root 红色、普通用户绿色）。
- 内嵌当前 [`patch/`](patch/) 的全部内容并写入 `/ish/overlay-version`，新导入的 rootfs 首次启动无需再叠加补丁。

## RootfsPatch（独立发布）

针对已部署 rootfs 的版本化热补丁，源在 [`patch/`](patch/)，发布到固定 tag `rootfs-patch` 的滚动 Release（与 rootfs 发版互不触发）。iSH 构建时从以下稳定 URL 下载：

```
https://github.com/ViSH-App/alpine-rootfs/releases/download/rootfs-patch/RootfsPatch.tar.gz
```

仅在明确需要热修时更新，更新必须递增 `patch/VERSION`（CI 强制）。详见 [`patch/README.md`](patch/README.md)。

## 下载

下游永远使用「指向最新版本」的稳定 URL，不需要硬编码 tag：

```
https://github.com/ViSH-App/alpine-rootfs/releases/latest/download/alpine-aarch64-rootfs.tar.gz
https://github.com/ViSH-App/alpine-rootfs/releases/latest/download/alpine-aarch64-rootfs.tar.gz.sha256
```

历史版本通过具体 tag 锁定：

```
https://github.com/ViSH-App/alpine-rootfs/releases/download/<TAG>/alpine-aarch64-rootfs.tar.gz
```

发布列表见 [Releases](../../releases) 页面。

校验示例：

```sh
curl -fsSLO https://github.com/ViSH-App/alpine-rootfs/releases/latest/download/alpine-aarch64-rootfs.tar.gz
curl -fsSLO https://github.com/ViSH-App/alpine-rootfs/releases/latest/download/alpine-aarch64-rootfs.tar.gz.sha256
shasum -a 256 -c alpine-aarch64-rootfs.tar.gz.sha256
```

## 本地构建

依赖：

- Docker（macOS 上 Docker Desktop 自带 QEMU；Linux 上需启用 binfmt，例如 `docker run --privileged --rm tonistiigi/binfmt --install arm64`）。
- Bash。

复现 CI 产物：

```sh
./build/build.sh
```

可覆写默认值：

```sh
ALPINE_VERSION=3.23.3 ARCH=aarch64 ./build/build.sh
```

产物会写入仓库根的 `dist/` 目录：

```
dist/alpine-aarch64-rootfs.tar.gz
dist/alpine-aarch64-rootfs.tar.gz.sha256
```

CI 与本地共用同一入口（`build/build.sh` → 在 aarch64 alpine 容器里跑 `build/inside.sh`），同一 `ALPINE_VERSION` + 同一 `packages.txt` 应得到等价产物。

## 发布

GitHub Actions workflow：[`.github/workflows/release.yml`](.github/workflows/release.yml)

- 手动触发：仓库 → Actions → "Build & release rootfs" → Run workflow，可选填 `alpine_version`。
- 定期触发：每周一 06:17 UTC 自动跑一次，跟随 Alpine 上游修补。
- 每次成功构建会创建一个新的 Release（tag 形如 `v3.23.3-YYYYMMDD-HHMM`），并标记为 `latest`，于是 `releases/latest/download/...` 自动指向新版本。
- Release 中附带产物本体与 `.sha256` 校验文件。

## 不在范围内

- 下游消费方的改动。
- 首次运行引导、UI、用户/dotfiles/主题等深度定制。
- ARM64 之外的架构（仅保留扩展可能性）。
