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

# 1. 架构识别与二进制部署
ABI=$(getprop ro.product.cpu.abi)
ABILIST=$(getprop ro.product.cpu.abilist)
ARCH=""
for a in "$ABI" $(echo "$ABILIST" | tr ',' ' '); do
    case "$a" in
        arm64-v8a) ARCH="arm64-v8a"; break ;;
        armeabi-v7a|armeabi) ARCH="armeabi-v7a"; break ;;
        x86_64) ARCH="x86_64"; break ;;
        x86) ARCH="x86"; break ;;
    esac
done

if [ -d "$MODPATH/bin" ]; then
    if [ -z "$ARCH" ]; then
        abort "[!] 不支持的 CPU 架构: $ABI"
    fi
    ui_print "- 检测到设备架构: $ARCH"
    if [ ! -f "$MODPATH/bin/$ARCH/syncthing" ]; then
        abort "[!] 未找到对应架构 ($ARCH) 的 syncthing 二进制文件"
    fi
    mv -f "$MODPATH/bin/$ARCH/syncthing" "$MODPATH/syncthing" || abort "[!] 部署 syncthing 二进制失败"
    rm -rf "$MODPATH/bin"
fi

if [ ! -f "$MODPATH/syncthing" ]; then
    abort "[!] 模块包内缺少 syncthing 二进制文件"
fi

# 2. 设置模块文件权限
set_perm_recursive "$MODPATH" 0 0 0755 0644
set_perm "$MODPATH/syncthing" 0 0 0755
set_perm "$MODPATH/service.sh" 0 0 0755
set_perm "$MODPATH/action.sh" 0 0 0755
set_perm "$MODPATH/uninstall.sh" 0 0 0755

# 3. 若当前存储已解密，预同步二进制到数据目录
if [ -d "/data/media/0/Android" ] && mkdir -p "$DATA_DIR" 2>/dev/null; then
    ui_print "- 正在同步二进制文件至 $DATA_DIR/syncthing ..."
    cp -af "$MODPATH/syncthing" "$DATA_DIR/syncthing" 2>/dev/null
    chown -R 1023:1023 "$DATA_DIR" 2>/dev/null
    chmod 750 "$DATA_DIR" 2>/dev/null
    chmod 755 "$DATA_DIR/syncthing" 2>/dev/null
fi

ui_print "- 安装完成！重启设备后将自动在后台启动（支持点击操作按钮启停）。"
ui_print "=========================================="
