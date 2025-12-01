#!/bin/bash

# ----------------------------------------------------------------------
# 執行 Clonezilla QEMU CI 測試腳本
# 此腳本用於以純 Console 模式啟動 QEMU，執行 Clonezilla 自動化任務，並在完成後自動關機。
# ----------------------------------------------------------------------

# 預設值
INTERACTIVE_MODE=0
PARTIMAG_PATH="./partimag"
ARGS=()

# 參數解析：處理旗標和其他位置參數
# 允許 -i/--interactive 旗標在任何位置
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        -i|--interactive)
            INTERACTIVE_MODE=1
            shift # 消耗旗標
            ;;
        *)
            ARGS+=("$1") # 儲存位置參數
            shift
            ;;
    esac
done

# 檢查所需位置參數的數量
if [ "${#ARGS[@]}" -lt 5 ]; then
    echo "錯誤：參數數量不足。"
    echo "用法：$0 [選項] <RestoreDisk> <LiveDisk> <KernelPath> <InitrdPath> \"<OCS_Live_Run_Command>\" [Optional_Image_Path]"
    echo ""
    echo "選項："
    echo "  -i, --interactive: 啟用互動模式 (輸出導向終端機，不寫入日誌檔)。"
    echo ""
    echo "範例："
    echo "$0 -i restore.qcow2 live.qcow2 ./clonezilla/vmlinuz ./clonezilla/initrd.img \"sudo /usr/sbin/ocs-sr -g auto -p poweroff restoredisk ask_user sda\" \"/path/to/my/images\""
    echo "  * 若省略 [Optional_Image_Path]，預設為 './partimag'。"
    exit 1
fi

# 重新賦值位置參數
RESTORE_DISK="${ARGS[0]}"  # 1. 目的硬碟 (hda)
LIVE_DISK="${ARGS[1]}"     # 2. Live 媒體碟 (hdb)
KERNEL_PATH="${ARGS[2]}"   # 3. 核心檔案路徑
INITRD_PATH="${ARGS[3]}"   # 4. Initrd 檔案路徑
OCS_COMMAND="${ARGS[4]}"   # 5. OCS_Live_Run 完整指令

# 6. 映像檔儲存目錄 (Host) - 如果提供了第 6 個參數，則使用它
if [ "${#ARGS[@]}" -ge 6 ]; then
    PARTIMAG_PATH="${ARGS[5]}"
fi
# 否則使用預設值 "./partimag" (已在開頭設定)

# 設定日誌檔名稱 (只有在非互動模式下才需要)
if [ "$INTERACTIVE_MODE" -eq 0 ]; then
    LOG_FILE="./clonezilla_ci_$(date +%Y%m%d_%H%M%S).log"
fi

# 檢查檔案是否存在 (檢查邏輯不變)
if [ ! -f "$RESTORE_DISK" ]; then
    echo "錯誤：找不到目的硬碟檔案: $RESTORE_DISK"
    exit 1
fi
if [ ! -f "$LIVE_DISK" ]; then
    echo "錯誤：找不到 Live 媒體碟檔案: $LIVE_DISK"
    exit 1
fi
if [ ! -f "$KERNEL_PATH" ]; then
    echo "錯誤：找不到核心檔案: $KERNEL_PATH"
    exit 1
fi
if [ ! -f "$INITRD_PATH" ]; then
    echo "錯誤：找不到 Initrd 檔案: $INITRD_PATH"
    exit 1
fi
if [ ! -d "$PARTIMAG_PATH" ]; then
    echo "錯誤：找不到映像檔儲存目錄: $PARTIMAG_PATH"
    echo "請確保該目錄存在，或使用第六個參數指定正確路徑。"
    exit 1
fi

echo "--- 啟動 QEMU 進行 CI 測試 ---"

# 確定輸出重定向方式
if [ "$INTERACTIVE_MODE" -eq 0 ]; then
    echo "模式：自動化 CI 模式 (輸出寫入日誌檔)"
    echo "所有輸出將儲存至日誌檔: $LOG_FILE"
    # 設定重定向字串
    REDIRECTION="> \"$LOG_FILE\" 2>&1"
else
    echo "模式：互動除錯模式 (輸出直接導向終端機)"
    # 不設定重定向字串
    REDIRECTION=""
fi
echo "-------------------------------------"

# 關鍵修正：將所有 -append 參數內容組合成單一字串
# 內部使用雙引號 (") 來包裹包含空格的參數值，如 ocs_prerun1 和 ocs_live_run。
# 外部的單引號 (見 QEMU_CMD) 將確保此字串完整傳遞。
#APPEND_ARGS="boot=live config union=overlay noswap edd=on nomodeset noninteractive locales=en_US.UTF-8 keyboard-layouts=us live-getty console=ttyS0,38400n81 live-media=/dev/sdb1 live-media-path=/live toram ocs_prerun=\"dhclient\" ocs_prerun1=\"mkdir -p /home/partimag\" ocs_prerun2=\"mount -t 9p -o trans=virtio,version=9p2000.L hostshare /home/partimag\" ocs_daemonon=\"ssh\" ocs_live_run=\"$OCS_COMMAND\" noeject noprompt"
APPEND_ARGS="boot=live config union=overlay noswap edd=on nomodeset noninteractive locales=en_US.UTF-8 keyboard-layouts=us live-getty console=ttyS0,38400n81 live-media=/dev/sdb1 live-media-path=/live toram ocs_prerun=\"dhclient\" ocs_prerun1=\"mkdir -p /home/partimag\" ocs_prerun2=\"mount -t 9p -o trans=virtio,version=9p2000.L hostshare /home/partimag\" ocs_daemonon=\"ssh\" ocs_live_run=\"$OCS_COMMAND\" ocs_postrun=\"sudo poweroff\" noeject noprompt"

# QEMU 啟動指令 (構建命令字串)
# 使用 eval 執行命令以正確處理引號和重定向
# 修正：將 -append 參數外部的雙引號改為單引號 ('), 以避免 eval 破壞內部的引號結構。
QEMU_CMD="qemu-system-x86_64 \
    -enable-kvm \
    -m 2048 \
    -smp 2 \
    -nographic \
    -kernel \"$KERNEL_PATH\" \
    -initrd \"$INITRD_PATH\" \
    -hda \"$RESTORE_DISK\" \
    -hdb \"$LIVE_DISK\" \
    -device virtio-net-pci,netdev=net0 \
    -netdev user,id=net0,hostfwd=tcp::2222-:22 \
    -fsdev local,id=hostshare,path=\"$PARTIMAG_PATH\",security_model=mapped-xattr \
    -device virtio-9p-pci,fsdev=hostshare,mount_tag=hostshare \
    -append '$APPEND_ARGS' \
    ${REDIRECTION}"

# 執行 QEMU 命令
eval $QEMU_CMD

# 檢查 QEMU 退出狀態碼
QEMU_EXIT_CODE=$?
if [ $QEMU_EXIT_CODE -eq 0 ]; then
    echo "QEMU 執行成功並乾淨退出 (可能由 poweroff 觸發)。"
    if [ "$INTERACTIVE_MODE" -eq 0 ]; then
        echo "完整日誌檔案位於: $LOG_FILE"
    fi
else
    echo "QEMU 執行異常終止。請檢查錯誤訊息。"
    if [ "$INTERACTIVE_MODE" -eq 0 ]; then
        echo "詳細日誌檔案位於: $LOG_FILE"
    fi
fi
