# Syncthing (media_rw) for Magisk / KernelSU / APatch

以 Android 原生 `media_rw (UID 1023)` 身份与 `inet (GID 3003)` 网络权限组在后台运行 [Syncthing](https://syncthing.net/)，**直接读写底层 `/data/media/0` 文件系统**，绕过 Android FUSE 层性能损耗与 Scoped Storage 权限隔离问题。

---

## 核心特性

- **原生 `media_rw (1023)` 身份直通 `/data/media/0`**
  - 绕过 `/storage/emulated/0` FUSE 挂载层开销，直接获得底层 `f2fs` / `ext4` 原生读写与哈希校验性能（实测哈希校验速度可达 `1000+ MB/s`）。
  - 同步写入的所有文件归属自动保持为 `media_rw:media_rw (1023:1023)`，与 Android `MediaProvider` 及普通应用（如 Obsidian、输入法词库、文件管理器等）完全兼容，不会出现普通应用只读或无法删除同步文件的问题。
  - 原生支持文件系统 `inotify` 实时监听，文件修改可毫秒级触发增量同步。
- **FBE（文件级加密）锁屏解密感知自启**
  - 开机后自动等待 `sys.boot_completed=1` **以及用户首次解锁屏幕完成 FBE (`fscrypt`) 解密**（验证 `/data/media/0/Android` 与数据目录可读写）后再拉起 Syncthing，彻底避免锁屏状态下提前启动导致同步文件夹报错 `Folder path missing` 或模块启动脚本提前退出。
- **全 Root 管理器兼容（Magisk / KernelSU / APatch）**
  - 适配 BusyBox `ASH_STANDALONE=1` 运行环境与 APatch `su --no-pty` 特性，进程脱离伪终端与标准输入/输出句柄，不阻塞启动阶段。
- **内置后台守护进程（Watchdog）与操作（Action）一键启停**
  - 内置 30 秒轮询守护循环，进程意外退出自动重拉；
  - 支持在 Magisk / KernelSU / APatch 管理器中点击 **操作 (Action)** 按钮一键优雅停止或重新启动，停止期间自动写入 `.stopped` 标记暂停守护拉起。
- **无损挂载 `/system/etc/resolv.conf`**
  - 解决官方静态编译 Go 二进制在 Android 上缺少 `/etc/resolv.conf` 导致无法解析全局发现服务器（`discovery.syncthing.net`）与中继服务器域名的问题。
- **GitHub Actions 自动拉取最新官方内核构建与发布**
  - 仓库不直接存储体积庞大的二进制文件，推送代码或打 Tag 时由 GitHub Actions 自动拉取 [syncthing/syncthing](https://github.com/syncthing/syncthing) 最新正式版四架构二进制（`arm64-v8a`、`armeabi-v7a`、`x86_64`、`x86`），打包并自动发布到 GitHub Releases。

---

## 目录与文件路径说明

| 路径 | 说明 |
| :--- | :--- |
| `/data/adb/modules/syncthing_media_rw/` | 模块安装目录（含 `service.sh`、`action.sh`、`uninstall.sh` 等） |
| `/data/adb/modules/syncthing_media_rw/service.log` | 开机自启与 FBE 解密等待诊断日志（位于 DE 存储，锁屏前即可记录） |
| `/data/media/0/.syncthing/` | Syncthing 数据与配置主目录（`--home`），卸载或升级模块均会保留 |
| `/data/media/0/.syncthing/config.xml` | Syncthing 配置文件 |
| `/data/media/0/.syncthing/syncthing.log` | Syncthing 运行日志（超过 2MB 自动轮转为 `syncthing.log.1`） |
| `/data/media/0/.syncthing/.stopped` | 手动停止标记文件（点击模块“操作”按钮停止时生成，重启或再次点击时清除） |

---

## 安装与使用

1. 前往 [Releases](https://github.com/WAYYYAW/MagiskSyncthing/releases) 下载最新构建的 `syncthing_media_rw-v*.zip` 模块包。
2. 在 **Magisk** / **KernelSU** / **APatch** 管理器中选择从本地安装该模块并重启设备。
3. 开机并解锁屏幕后，Syncthing 将自动在后台启动。
4. 在手机浏览器访问 **`http://127.0.0.1:8384`** 进入 WebUI 管理界面：
   - **安全建议**：首次进入后请前往 **操作 -> 设置 -> 图形用户界面** 设置管理用户名和密码。
   - **同步路径建议**：添加同步文件夹时，推荐直接使用 `/data/media/0/...`（例如 `/data/media/0/Documents/Obsidian`）以获得最佳读写性能和实时监听体验。

---

## 自动构建与发布（GitHub Actions）

本项目已配置 [`.github/workflows/build.yml`](.github/workflows/build.yml)：

1. **日常推送自动构建 (`push` to `main`/`master`)**：
   - 自动查询 `syncthing/syncthing` 最新稳定版 Release，下载全架构二进制文件并打包生成模块 zip，自动创建 `v<版本号>-build.<构建号>` Release。
2. **标签发布 (`push` tag `v*`)**：
   - 推送例如 `git tag v2.1.5 && git push origin v2.1.5`，自动打包对应版本并发布正式 GitHub Release。
3. **手动触发 (`workflow_dispatch`)**：
   - 支持在 GitHub Actions 页面手动填入指定 Syncthing 版本号触发构建。
