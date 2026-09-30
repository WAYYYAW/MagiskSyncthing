#!/system/bin/sh
# Magisk / KernelSU / APatch module installation script

DATA_DIR="/data/media/0/.syncthing"

ui_print "=========================================="
ui_print "       Syncthing (media_rw) Installer     "
ui_print "=========================================="
ui_print "- 运行身份: media_rw (UID 1023) + inet (GID 3003)"
ui_print "- 数据目录: $DATA_DIR"
ui_print "- 管理面板: http://127.0.0.1:8384"
ui_print "------------------------------------------"

# 1. 架构检测
ABI=$(getprop ro.product.cpu.abi)
ABILIST=$(getprop ro.product.cpu.abilist)
ARCH=""
ST_ARCH=""

for a in "$ABI" $(echo "$ABILIST" | tr ',' ' '); do
    case "$a" in
        arm64-v8a)
            ARCH="arm64-v8a"
            ST_ARCH="linux-arm64"
            break
            ;;
        armeabi-v7a|armeabi)
            ARCH="armeabi-v7a"
            ST_ARCH="linux-arm"
            break
            ;;
        x86_64)
            ARCH="x86_64"
            ST_ARCH="linux-amd64"
            break
            ;;
        x86)
            ARCH="x86"
            ST_ARCH="linux-386"
            break
            ;;
    esac
done

if [ -z "$ARCH" ] || [ -z "$ST_ARCH" ]; then
    abort "[!] 不支持的 CPU 架构: $ABI"
fi
ui_print "- 设备目标架构: $ARCH ($ST_ARCH)"

# 2. 检查安装包内二进制
# 兼容单独架构包 ($MODPATH/syncthing) 与多架构暂存包 ($MODPATH/bin/$ARCH/syncthing)
if [ -d "$MODPATH/bin" ]; then
    if [ -f "$MODPATH/bin/$ARCH/syncthing" ]; then
        mv -f "$MODPATH/bin/$ARCH/syncthing" "$MODPATH/syncthing"
    fi
    rm -rf "$MODPATH/bin"
fi

if [ -f "$MODPATH/syncthing" ]; then
    chmod 0755 "$MODPATH/syncthing"
    LOCAL_VER=$("$MODPATH/syncthing" --version 2>/dev/null | awk '{print $2}')
else
    LOCAL_VER=""
fi

ui_print "- 模块内置版本: ${LOCAL_VER:-未知}"

# 3. 音量键检测函数 (超时 15 秒，默认选择音量-)
choose_vol_key() {
    # 0 = 音量+ (更新), 1 = 音量- (跳过)
    local deadline=$(( $(date +%s) + 15 ))
    while [ "$(date +%s)" -lt "$deadline" ]; do
        local events=$(/system/bin/timeout 1 /system/bin/getevent -qlc 1 2>/dev/null)
        case "$events" in
            *KEY_VOLUMEUP*DOWN*)
                # 等待释放
                while true; do
                    local r=$(/system/bin/timeout 1 /system/bin/getevent -qlc 1 2>/dev/null)
                    case "$r" in *KEY_VOLUMEUP*UP*|"") break ;; esac
                done
                return 0
                ;;
            *KEY_VOLUMEDOWN*DOWN*)
                while true; do
                    local r=$(/system/bin/timeout 1 /system/bin/getevent -qlc 1 2>/dev/null)
                    case "$r" in *KEY_VOLUMEDOWN*UP*|"") break ;; esac
                done
                return 1
                ;;
        esac
    done
    return 1
}

# 4. 在线检查更新
ui_print "- 正在联网检查 Syncthing 官方最新版本..."
LATEST_VER=""
API_URL="https://api.github.com/repos/syncthing/syncthing/releases/latest"

if command -v curl >/dev/null 2>&1; then
    LATEST_JSON=$(curl -kfsSL --connect-timeout 6 -m 12 "$API_URL" 2>/dev/null)
elif command -v wget >/dev/null 2>&1; then
    LATEST_JSON=$(wget -qO- --no-check-certificate -T 12 "$API_URL" 2>/dev/null)
else
    LATEST_JSON=""
fi

if [ -n "$LATEST_JSON" ]; then
    LATEST_VER=$(echo "$LATEST_JSON" | grep -m1 '"tag_name"' | sed -E 's/.*"tag_name": *"([^"]+)".*/\1/')
fi

DO_UPDATE=0

if [ -n "$LATEST_VER" ]; then
    ui_print "- 官方最新版本: $LATEST_VER"
    if [ "$LATEST_VER" != "$LOCAL_VER" ]; then
        ui_print "------------------------------------------"
        ui_print "[!] 发现官方新版本: $LATEST_VER (当前内置: ${LOCAL_VER:-无})"
        ui_print "    请按音量键进行选择："
        ui_print "    🔊 [音量+] ：在线下载并更新至 $LATEST_VER"
        ui_print "    🔉 [音量-] ：跳过，使用模块内置版本"
        ui_print "    (15秒内无操作将自动跳过更新)"
        ui_print "------------------------------------------"
        if choose_vol_key; then
            DO_UPDATE=1
        else
            ui_print "[-] 已跳过在线更新。"
        fi
    else
        ui_print "[i] 当前模块内置版本已是最新正式版 ($LOCAL_VER)。"
        ui_print "    如需强制重新下载，请按音量键选择："
        ui_print "    🔊 [音量+] ：重新下载最新版"
        ui_print "    🔉 [音量-] ：直接使用内置版本"
        ui_print "    (15秒内无操作默认跳过)"
        if choose_vol_key; then
            DO_UPDATE=1
        else
            ui_print "[-] 保持使用内置版本。"
        fi
    fi
else
    ui_print "[!] 检查更新失败：无法连接至 GitHub，将使用模块内置版本。"
fi

# 5. 执行更新下载与替换
if [ "$DO_UPDATE" -eq 1 ]; then
    TAR_NAME="syncthing-${ST_ARCH}-${LATEST_VER}.tar.gz"
    DL_URL="https://github.com/syncthing/syncthing/releases/download/${LATEST_VER}/${TAR_NAME}"
    TMP_DL="$TMPDIR/syncthing_update.tar.gz"
    TMP_EXTRACT="$TMPDIR/syncthing_extract"
    rm -rf "$TMP_DL" "$TMP_EXTRACT"
    mkdir -p "$TMP_EXTRACT"

    ui_print "[*] 正在下载 $TAR_NAME ..."
    DOWNLOAD_OK=0

    if command -v curl >/dev/null 2>&1; then
        curl -kfsSL --connect-timeout 10 --retry 2 -o "$TMP_DL" "$DL_URL" && DOWNLOAD_OK=1
    fi
    if [ "$DOWNLOAD_OK" -ne 1 ] && command -v wget >/dev/null 2>&1; then
        wget -q --no-check-certificate -O "$TMP_DL" "$DL_URL" && DOWNLOAD_OK=1
    fi

    if [ "$DOWNLOAD_OK" -eq 1 ] && [ -f "$TMP_DL" ]; then
        ui_print "[*] 下载成功，正在解压与校验..."
        tar -xzf "$TMP_DL" -C "$TMP_EXTRACT" 2>/dev/null
        EXTRACTED_BIN=$(find "$TMP_EXTRACT" -name "syncthing" -type f 2>/dev/null | head -n1)

        if [ -n "$EXTRACTED_BIN" ] && [ -f "$EXTRACTED_BIN" ]; then
            chmod 0755 "$EXTRACTED_BIN"
            CHECK_VER=$("$EXTRACTED_BIN" --version 2>/dev/null | awk '{print $2}')
            if [ -n "$CHECK_VER" ]; then
                cp -af "$EXTRACTED_BIN" "$MODPATH/syncthing"
                chmod 0755 "$MODPATH/syncthing"
                LOCAL_VER="$CHECK_VER"
                sed -i "s/^version=.*/version=${CHECK_VER}/" "$MODPATH/module.prop" 2>/dev/null
                ui_print "[+] 在线更新成功！当前版本: $CHECK_VER"
            else
                ui_print "**********************************************"
                ui_print "[!] 警告: 下载的二进制文件校验执行失败！"
                ui_print "[!] 已自动回退使用模块内置版本。"
                ui_print "**********************************************"
            fi
        else
            ui_print "**********************************************"
            ui_print "[!] 警告: 解压未找到 syncthing 文件！"
            ui_print "[!] 已自动回退使用模块内置版本。"
            ui_print "**********************************************"
        fi
    else
        ui_print "**********************************************"
        ui_print "[!] 警告: 下载最新版本失败（网络超时或无法访问）！"
        ui_print "[!] 已自动回退使用模块内置版本。"
        ui_print "**********************************************"
    fi
    rm -rf "$TMP_DL" "$TMP_EXTRACT"
fi

if [ ! -f "$MODPATH/syncthing" ]; then
    abort "[!] 错误: 未找到可用的 syncthing 可执行文件，安装中止！"
fi

# 6. 设置权限
set_perm_recursive "$MODPATH" 0 0 0755 0644
set_perm "$MODPATH/syncthing" 0 0 0755
set_perm "$MODPATH/service.sh" 0 0 0755
set_perm "$MODPATH/action.sh" 0 0 0755
set_perm "$MODPATH/uninstall.sh" 0 0 0755

# 7. 若当前存储已解密，同步部署至工作目录
if [ -d "/data/media/0/Android" ] && mkdir -p "$DATA_DIR" 2>/dev/null; then
    ui_print "- 正在同步二进制文件至 $DATA_DIR/syncthing ..."
    cp -af "$MODPATH/syncthing" "$DATA_DIR/syncthing" 2>/dev/null
    chown -R 1023:1023 "$DATA_DIR" 2>/dev/null
    chmod 750 "$DATA_DIR" 2>/dev/null
    chmod 755 "$DATA_DIR/syncthing" 2>/dev/null
fi

ui_print "- 安装完成！重启设备后将自动在后台启动（支持点击操作按钮启停）。"
ui_print "=========================================="
