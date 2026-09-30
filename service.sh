#!/system/bin/sh
MODDIR=${0%/*}
export PATH="/data/adb/ap/bin:/data/adb/ksu/bin:/data/adb/magisk:$PATH"

DATA_DIR="/data/media/0/.syncthing"
BIN="$DATA_DIR/syncthing"
LOGFILE="$DATA_DIR/syncthing.log"
STOPPED_FLAG="$DATA_DIR/.stopped"
BOOTLOG="$MODDIR/service.log"
WATCHDOG_PID_FILE="$MODDIR/watchdog.pid"

log_boot() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$BOOTLOG" 2>/dev/null
}

# 清理可能残留的旧守护进程
if [ -f "$WATCHDOG_PID_FILE" ]; then
    OLD_WD_PID=$(cat "$WATCHDOG_PID_FILE" 2>/dev/null)
    if [ -n "$OLD_WD_PID" ] && kill -0 "$OLD_WD_PID" 2>/dev/null; then
        kill "$OLD_WD_PID" 2>/dev/null
    fi
fi

echo "=== service.sh triggered at $(date '+%Y-%m-%d %H:%M:%S') ===" > "$BOOTLOG" 2>/dev/null

(
    log_boot "daemon started (pid=$$)"

    # 1. 等待系统开机完成 (sys.boot_completed=1)
    while [ "$(getprop sys.boot_completed)" != "1" ]; do
        sleep 2
    done
    log_boot "sys.boot_completed=1"

    # 2. 等待 FBE (文件级加密) 解密完成且 /data/media/0 可读写
    # 注意：在锁屏未解锁前 /data/media/0 目录节点本身已存在，但内部处于 fscrypt 加密状态 (Required key not available)
    until [ -d "/data/media/0/Android" ] && mkdir -p "$DATA_DIR" 2>/dev/null; do
        sleep 3
    done
    log_boot "storage decrypted and $DATA_DIR ready"

    rm -f "$STOPPED_FLAG"

    # 3. 检查并同步可执行文件
    if [ ! -f "$BIN" ] || [ -f "$MODDIR/syncthing" -a "$MODDIR/syncthing" -nt "$BIN" ]; then
        if [ -f "$MODDIR/syncthing" ]; then
            cp -af "$MODDIR/syncthing" "$BIN"
        elif [ -f "$MODDIR/system/bin/syncthing" ]; then
            cp -af "$MODDIR/system/bin/syncthing" "$BIN"
        fi
    fi

    if [ ! -f "$BIN" ]; then
        log_boot "[ERROR] syncthing binary not found at $BIN"
        echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] syncthing binary not found" >> "$LOGFILE"
        exit 1
    fi

    # 确保归属与执行权限
    chown -R 1023:1023 "$DATA_DIR"
    chmod 750 "$DATA_DIR"
    chmod 755 "$BIN"

    SU_OPTS=""
    if su --help 2>&1 | grep -q -- "--no-pty"; then
        SU_OPTS="--no-pty"
    fi

    rotate_log() {
        if [ -f "$LOGFILE" ]; then
            LOGSIZE=$(wc -c < "$LOGFILE" 2>/dev/null || echo 0)
            if [ "$LOGSIZE" -gt 2097152 ]; then
                mv -f "$LOGFILE" "${LOGFILE}.1"
            fi
        fi
        touch "$LOGFILE"
        chown 1023:1023 "$LOGFILE" "${LOGFILE}.1" 2>/dev/null
        chmod 644 "$LOGFILE" "${LOGFILE}.1" 2>/dev/null
    }

    # 启动 Syncthing (保留 1023 media_rw 身份并赋予 inet 3003 网络权限)
    start_syncthing() {
        rotate_log
        log_boot "starting syncthing..."
        su $SU_OPTS -g 1023 -G 3003 1023 -c "export HOME=\"$DATA_DIR\"; exec \"$BIN\" --home=\"$DATA_DIR\" --no-browser" </dev/null >>"$LOGFILE" 2>&1 &
    }

    # 避免重复拉起 (BusyBox pgrep 不支持 -u 参数，使用 ^$BIN 精确匹配进程开头)
    if ! pgrep -f "^$BIN" >/dev/null 2>&1; then
        start_syncthing
    fi

    log_boot "entering watchdog loop"

    # 4. 持续守护进程
    while true; do
        sleep 30
        [ -f "$MODDIR/disable" ] && exit 0
        [ -f "$STOPPED_FLAG" ] && continue

        if ! pgrep -f "^$BIN" >/dev/null 2>&1; then
            log_boot "syncthing not running, restarting..."
            start_syncthing
        fi
    done
) </dev/null >/dev/null 2>&1 &

echo $! > "$WATCHDOG_PID_FILE"
