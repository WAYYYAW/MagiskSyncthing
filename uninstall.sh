#!/system/bin/sh
MODDIR=${0%/*}
DATA_DIR="/data/media/0/.syncthing"
BIN="$DATA_DIR/syncthing"
WATCHDOG_PID_FILE="$MODDIR/watchdog.pid"

# 终止守护进程
if [ -f "$WATCHDOG_PID_FILE" ]; then
    WD_PID=$(cat "$WATCHDOG_PID_FILE" 2>/dev/null)
    [ -n "$WD_PID" ] && kill -KILL "$WD_PID" >/dev/null 2>&1
    rm -f "$WATCHDOG_PID_FILE"
fi

# 终止正在运行的 Syncthing 进程 (兼容 BusyBox pkill)
pkill -KILL -f "^$BIN" >/dev/null 2>&1

# 移除标记文件
rm -f "$DATA_DIR/.stopped"

# 提示：为防止数据丢失，保留用户配置和同步数据 (/data/media/0/.syncthing)
