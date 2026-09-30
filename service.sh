#!/system/bin/sh
MODDIR=${0%/*}
export PATH="/data/adb/ap/bin:/data/adb/ksu/bin:/data/adb/magisk:$PATH"

DATA_DIR="/data/media/0/.syncthing"
BIN="$DATA_DIR/syncthing"
LOGFILE="$DATA_DIR/syncthing.log"
STOPPED_FLAG="$DATA_DIR/.stopped"
BOOTLOG="$MODDIR/service.log"
WATCHDOG_PID_FILE="$MODDIR/watchdog.pid"
PROP_FILE="$MODDIR/module.prop"
BASE_DESC="Run Syncthing natively under media_rw user (UID 1023) to sync /data/media/0 seamlessly. WebUI: http://127.0.0.1:8384."

log_boot() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$BOOTLOG" 2>/dev/null
}

update_description() {
    if [ -f "$PROP_FILE" ]; then
        sed -i "s|^description=.*|description=$1 $BASE_DESC|" "$PROP_FILE" 2>/dev/null
    fi
}

# 清理可能残留的旧守护进程
if [ -f "$WATCHDOG_PID_FILE" ]; then
    OLD_WD_PID=$(cat "$WATCHDOG_PID_FILE" 2>/dev/null)
    if [ -n "$OLD_WD_PID" ] && kill -0 "$OLD_WD_PID" 2>/dev/null; then
        kill "$OLD_WD_PID" 2>/dev/null
    fi
fi

echo "=== service.sh triggered at $(date '+%Y-%m-%d %H:%M:%S') ===" > "$BOOTLOG" 2>/dev/null
update_description "[⏳ 等待启动]"

(
    log_boot "daemon started (pid=$$)"

    # 1. 等待系统开机完成 (sys.boot_completed=1)
    while [ "$(getprop sys.boot_completed)" != "1" ]; do
        sleep 2
    done
    log_boot "sys.boot_completed=1"

    # 2. 等待 FBE 解密完成且 /data/media/0 可读写
    until [ -d "/data/media/0/Android" ] && mkdir -p "$DATA_DIR" 2>/dev/null; do
        sleep 3
    done
    log_boot "storage decrypted and $DATA_DIR ready"

    rm -f "$STOPPED_FLAG"

    # 3. 检查并同步可执行文件
    if [ ! -f "$BIN" ] || [ -f "$MODDIR/syncthing" -a "$MODDIR/syncthing" -nt "$BIN" ]; then
        if [ -f "$MODDIR/syncthing" ]; then
            cp -af "$MODDIR/syncthing" "$BIN"
        fi
    fi

    if [ ! -f "$BIN" ]; then
        log_boot "[ERROR] syncthing binary not found at $BIN"
        update_description "[❌ 缺少二进制]"
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

    start_syncthing() {
        rotate_log
        log_boot "starting syncthing..."
        su $SU_OPTS -g 1023 -G 3003 1023 -c "export HOME=\"$DATA_DIR\"; exec \"$BIN\" --home=\"$DATA_DIR\" --no-browser" </dev/null >>"$LOGFILE" 2>&1 &
        sleep 2
        PIDS=$(pgrep -f "^$BIN" | tr '\n' ' ' | sed 's/ *$//')
        if [ -n "$PIDS" ]; then
            update_description "[🟢 运行中 | PID: $PIDS]"
            log_boot "syncthing started (PID: $PIDS)"
        fi
    }

    if ! pgrep -f "^$BIN" >/dev/null 2>&1; then
        start_syncthing
    fi

    log_boot "entering watchdog loop"

    # 4. 持续守护进程
    while true; do
        sleep 30
        [ -f "$MODDIR/disable" ] && { update_description "[🔴 模块已禁用]"; exit 0; }
        [ -f "$STOPPED_FLAG" ] && continue

        if ! pgrep -f "^$BIN" >/dev/null 2>&1; then
            update_description "[⏳ 正在重启...]"
            log_boot "syncthing not running, restarting..."
            start_syncthing
        fi
    done
) </dev/null >/dev/null 2>&1 &

echo $! > "$WATCHDOG_PID_FILE"
