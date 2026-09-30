#!/system/bin/sh
MODDIR=${0%/*}
export PATH="/data/adb/ap/bin:/data/adb/ksu/bin:/data/adb/magisk:$PATH"

DATA_DIR="/data/media/0/.syncthing"
BIN="$DATA_DIR/syncthing"
LOGFILE="$DATA_DIR/syncthing.log"
STOPPED_FLAG="$DATA_DIR/.stopped"
PROP_FILE="$MODDIR/module.prop"
BASE_DESC="Run Syncthing natively under media_rw user (UID 1023) to sync /data/media/0 seamlessly. WebUI: http://127.0.0.1:8384."

update_description() {
    if [ -f "$PROP_FILE" ]; then
        sed -i "s|^description=.*|description=$1 $BASE_DESC|" "$PROP_FILE" 2>/dev/null
    fi
}

# 检查当前运行状态 (BusyBox pgrep 不支持 -u，使用 ^$BIN 精确匹配)
if pgrep -f "^$BIN" >/dev/null 2>&1; then
    echo "[*] Syncthing 正在运行，准备停止..."
    
    # 设置手动停止标记，避免被 service.sh 守护进程立刻重启
    touch "$STOPPED_FLAG"
    
    # 优雅退出：发送 SIGTERM
    pkill -TERM -f "^$BIN"
    
    # 等待最多 5 秒
    for i in 1 2 3 4 5; do
        if ! pgrep -f "^$BIN" >/dev/null 2>&1; then
            break
        fi
        sleep 1
    done
    
    # 超时未退出则强制 SIGKILL
    if pgrep -f "^$BIN" >/dev/null 2>&1; then
        echo "[!] 超时未退出，发送 SIGKILL 强杀..."
        pkill -KILL -f "^$BIN"
        sleep 1
    fi
    
    if ! pgrep -f "^$BIN" >/dev/null 2>&1; then
        update_description "[🔴 已停止]"
        echo "[-] Syncthing 已成功停止。"
        echo "[i] 已更新模块描述状态为：已停止"
    else
        PIDS=$(pgrep -f "^$BIN" | tr '\n' ' ' | sed 's/ *$//')
        update_description "[🟢 正在运行中 | PID: $PIDS]"
        echo "[!] 停止失败，请手动检查进程 (PID: $PIDS)。"
    fi
else
    echo "[*] 启动 Syncthing (用户: media_rw / 1023, 附加组: inet / 3003)..."
    
    # 清除手动停止标记
    rm -f "$STOPPED_FLAG"
    
    # 检查并恢复二进制
    if [ ! -f "$BIN" ]; then
        if [ -f "$MODDIR/syncthing" ]; then
            echo "[i] 正在从模块目录恢复二进制..."
            mkdir -p "$DATA_DIR"
            cp -af "$MODDIR/syncthing" "$BIN"
        elif [ -f "$MODDIR/system/bin/syncthing" ]; then
            echo "[i] 正在从系统目录恢复二进制..."
            mkdir -p "$DATA_DIR"
            cp -af "$MODDIR/system/bin/syncthing" "$BIN"
        else
            update_description "[❌ 启动失败: 缺少二进制]"
            echo "[!] 错误: 未找到 syncthing 二进制文件！"
            echo ""
            echo "[i] 窗口将在 5 秒后自动关闭..."
            sleep 5
            exit 1
        fi
    fi
    
    # 确保目录和二进制权限
    chown -R 1023:1023 "$DATA_DIR"
    chmod 750 "$DATA_DIR"
    chmod 755 "$BIN"
    
    # 日志轮转检查 (单文件超 2MB 轮转)
    if [ -f "$LOGFILE" ]; then
        LOGSIZE=$(wc -c < "$LOGFILE" 2>/dev/null || stat -c %s "$LOGFILE" 2>/dev/null || echo 0)
        if [ "$LOGSIZE" -gt 2097152 ]; then
            mv -f "$LOGFILE" "${LOGFILE}.1"
        fi
    fi
    touch "$LOGFILE"
    chown 1023:1023 "$LOGFILE" "${LOGFILE}.1" 2>/dev/null
    chmod 644 "$LOGFILE" "${LOGFILE}.1" 2>/dev/null
    
    SU_OPTS=""
    if su --help 2>&1 | grep -q -- "--no-pty"; then
        SU_OPTS="--no-pty"
    fi
    
    # 后台启动 Syncthing (赋予 1023 media_rw 与 3003 inet 权限，避免阻塞前端)
    su $SU_OPTS -g 1023 -G 3003 1023 -c "export HOME=\"$DATA_DIR\"; exec \"$BIN\" --home=\"$DATA_DIR\" --no-browser" </dev/null >>"$LOGFILE" 2>&1 &
    
    # 等待启动并检测状态
    sleep 2
    PIDS=$(pgrep -f "^$BIN" | tr '\n' ' ' | sed 's/ *$//')
    if [ -n "$PIDS" ]; then
        update_description "[🟢 正在运行中 | PID: $PIDS]"
        echo "[+] 启动成功！PID: $PIDS"
        echo "[i] 已更新模块描述状态为：正在运行中"
        echo "[i] 本机控制台: http://127.0.0.1:8384"
        
        # 显示当前 WLAN IP 地址以便局域网访问
        WLAN_IP=$(ip -4 addr show wlan0 2>/dev/null | grep -o 'inet [0-9.]*' | cut -d' ' -f2)
        if [ -n "$WLAN_IP" ]; then
            echo "[i] Wi-Fi IP: $WLAN_IP"
        fi
    else
        update_description "[🔴 启动失败]"
        echo "[!] 启动可能失败，请查看日志: $LOGFILE"
        if [ -f "$LOGFILE" ]; then
            echo "--- 日志末尾 5 行 ---"
            tail -n 5 "$LOGFILE"
        fi
    fi
fi

echo ""
echo "[i] 操作执行完毕，等待 5 秒后自动关闭..."
sleep 5
