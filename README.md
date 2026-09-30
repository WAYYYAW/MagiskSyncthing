# Syncthing (media_rw) for Magisk / KernelSU / APatch

以 Android 原生 `media_rw (UID 1023)` 身份与 `inet (GID 3003)` 网络权限组在后台运行 [Syncthing](https://syncthing.net/)，**直接读写底层 `/data/media/0` 文件系统**，彻底告别 Android FUSE 层性能损耗、实时同步丢事件与 Scoped Storage 权限限制。

---

## 核心特性

- **分架构独立打包（瘦身极致）**
  - 不再将全架构二进制塞入单个模块包，CI 自动按 `arm64-v8a`、`armeabi-v7a`、`x86_64`、`x86` 独立构建分包，单包体积仅约 10MB。
- **安装阶段联网检查更新与音量键选择**
  - 刷入模块时，安装脚本会自动匹配当前设备架构向 GitHub 查询官方最新正式版；
  - 提供音量键交互选择：**音量+** 确认在线下载最新版并替换，**音量-**（或超时 15 秒）跳过并使用内置版本；
  - 具备完善的容错提示机制：若无网络、超时或校验未通过，会明确告警并自动安全回退至内置版本继续安装。
- **原生 `media_rw (1023)` 身份直通 `/data/media/0`**
  - 绕过 `/storage/emulated/0` FUSE 挂载层开销，直享底层 `f2fs` / `ext4` 原生读写与哈希性能（实测哈希速度达 `1000+ MB/s`）。
  - 同步写入的所有文件归属自动保持为 `media_rw:media_rw (1023:1023)`，与 Android `MediaProvider` 及各类普通应用（Obsidian、输入法词库、图库等）完全兼容，无只读或无法删除权限问题。
  - 支持文件系统底层 `inotify`，文件修改毫秒级触发增量同步。
- **FBE（文件级加密）锁屏解密感知自启**
  - 开机后自动等待 `sys.boot_completed=1` **以及用户首次解锁屏幕完成 FBE (`fscrypt`) 解密**（检测 `/data/media/0/Android` 与数据目录就绪）后再拉起 Syncthing，避免锁屏状态下提前启动导致同步文件夹报错 `Folder path missing`。
- **Action（操作）按钮防闪退与动态状态显示**
  - 在 Magisk / KernelSU / APatch 管理器中点击操作按钮时，操作完成后自动等待 5 秒再关闭窗口，方便查看 PID、控制台地址和 Wi-Fi IP；
  - 无论通过开机自启、后台守护重拉，还是点击 Action 启停，都会实时同步更新 `module.prop` 描述信息：
    - `[🟢 正在运行中 | PID: 1234 1235] ...`
    - `[🔴 已停止] ...`
- **无损挂载 `/system/etc/resolv.conf`**
  - 解决官方静态编译 Go 二进制在 Android 上缺少 `/etc/resolv.conf` 导致无法解析全局发现服务器（`discovery.syncthing.net`）与中继服务器域名的问题。

---

## 目录与文件路径说明

| 路径 | 说明 |
| :--- | :--- |
| `/data/adb/modules/syncthing_media_rw/` | 模块安装目录（含 `service.sh`、`action.sh`、`uninstall.sh` 等） |
| `/data/adb/modules/syncthing_media_rw/service.log` | 开机自启与 FBE 解密等待诊断日志（位于 DE 存储区，锁屏前即可记录） |
| `/data/media/0/.syncthing/` | Syncthing 数据与配置主目录（`--home`），模块升级或卸载均保留 |
| `/data/media/0/.syncthing/config.xml` | Syncthing 配置文件 |
| `/data/media/0/.syncthing/syncthing.log` | Syncthing 运行日志（超 2MB 自动轮转为 `syncthing.log.1`） |
| `/data/media/0/.syncthing/.stopped` | 手动停止标记文件（点击 Action 停止时生成，重启或再次点击时清除） |

---

## 安装与使用

1. 前往 [Releases](https://github.com/WAYYYAW/MagiskSyncthing/releases) 页面，根据设备架构下载对应的安装包：
   - 大多数现代手机选择 **`syncthing_media_rw-v*-arm64-v8a.zip`**
2. 在 **Magisk** / **KernelSU** / **APatch** 中选择从本地安装；
3. 安装过程中会联网检查官方最新版，可按 **音量+** 升级或 **音量-** 跳过；
4. 安装完成后重启设备，首次解锁屏幕后后台自动运行；
5. 在手机浏览器打开 **`http://127.0.0.1:8384`** 访问控制台（建议首次进入后在设置中设置 GUI 用户名和密码）；
6. 添加同步文件夹时，路径填写 `/data/media/0/...` 即可获得最快性能体验。

---

## 自动构建与发布（GitHub Actions）

本项目已配置 [`.github/workflows/build.yml`](.github/workflows/build.yml)：
- **推送到 `main` / `master` 分支**：自动拉取上游最新版，独立构建 4 个架构的安装包并自动发布 GitHub Release；
- **推送 `v*` Tag**：发布对应版本的正式 Release；
- **手动触发 (`workflow_dispatch`)**：支持手动指定 Syncthing 版本进行构建。
