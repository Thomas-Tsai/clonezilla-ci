# clonezilla ci and gemini cli 開發整理
default prompt: 這是 clonezilla 準備來開發CI的目錄，裡面討論可以用英文與繁體中文，程式與註解都用英文。大部分用bash script 開發

## Overview
This directory contains scripts and tools for automating Clonezilla operations in a Continuous Integration (CI) environment. The main scripts include `qemu_clonezilla_ci_run.sh`, which is used to run Clonezilla in a QEMU virtual machine, and `clonezilla_zip2qcow.sh`, which converts Clonezilla zip images to QCOW2 format for use in QEMU.

- [x] 整個專案的readme 文件需要補充

## data-clone-restore.sh 改進事項：
- [x] 整個 script flow 需要開發，完整flow, 參數說明
- [x] 增加--help 參數可以讓使用者查詢使用說明
- [x] 參數檢查機制，確保使用者輸入的參數是有效的。例如，檢查檔案是否存在，參數格式是否正確等。
- [x] 增加執行結果回傳值，成功回傳0，失敗回傳1
- [x] 實作主要流程:
    - [x] 1. 使用 clonezilla_zip2qcow.sh 將 clonezilla zip 轉成 qcow2 檔案
    - [x] 2. 備份前準備，將--data 目錄複製到 qcow2 裡面, 需要進行檔案的checksum 記錄供還原時驗證
    - [x] 3. 使用 qemu_clonezilla_ci_run.sh 備份 qcow2 到 partimag/
    - [x] 4. 使用 qemu_clonezilla_ci_run.sh 還原 clonezilla qcow2 到 restore.qcow2
    - [x] 5. 驗證 restore.qcow2 是否能正常還原出正確的檔案內容，與備份前的checksum 進行比對
- [x] 增加參數設定partimag 目錄位置
- [x] 增加參數錯誤時保留temp檔案，方便debug
- [x] 嘗試增加檔案系統類型支援 ext2, ext3, xfs, btrfs, exfat 
- [ ] 嘗試 以其他方式 增加檔案系統類型支援 fat16, fat12, hfs, hfsplus, ufs, reiserfs, jfs, apfs, 需要先確認可行性
- [x] checksum 不要列出所有檔案，只列出有錯誤的部份，所有檔案檢查結果另外存log檔案, 完成, 尚未確認
- [x] 步驟5 驗證方式不要tar/copy 整個目錄，可以直接mount qcow2 檔案然後進行檔案比對
      例如：guestmount -a source.qcow2 -m /dev/sda1 --ro /tmp/XXXX/mnt/ ; md5sum -c ....

## linux-clone-restore.sh 改進事項：
這個程式主要用來進行linux distro 的clonezilla 備份還原，完全非互動方式一次完成備份、還原、還原檢查
提供使用者參數：
1. --zip 指定 clonezilla zip 檔案路徑 
2. --tmpl 設定 linux distro 參數，例: debian-sid-generic-amd64-daily-20250805-2195.qcow2 需支援 cloud init

主要流程
1. 使用 clonezilla_zip2qcow.sh 將 clonezilla zip 轉成 qcow2 檔案
eg: ./clonezilla_zip2qcow.sh --zip isos/clonezilla-live-20251124-resolute-amd64.zip  -o isos/
2. 備份debian-sid-generic-amd64-daily-20250805-2195.qcow2 到 debian-sid-generic-amd64-daily-20250805-2195.sda.qcow2
eg: cp qemu/debian-sid-generic-amd64-daily-20250805-2195.qcow2 qemu/debian-sid-generic-amd64-daily-20250805-2195.sda.qcow2
3. 使用 qemu_clonezilla_ci_run.sh 備份 debian-sid-generic-amd64-daily-20250805-2195.sda.qcow2 到 partimag/ ; 可以直接使用cmdpath  dev/ocscmd/clone-first-disk.sh
eg: ./qemu_clonezilla_ci_run.sh --disk qemu/debian-sid-generic-amd64-daily-20250805-2195.sda.qcow2 --live isos/clonezilla-live-20251124-resolute-amd64/clonezilla-live-20251124-resolute-amd64.qcow2 --kernel isos/clonezilla-live-20251124-resolute-amd64/clonezilla-live-20251124-resolute-amd64-vmlinuz --initrd isos/clonezilla-live-20251124-resolute-amd64/clonezilla-live-20251124-resolute-amd64-initrd.img --cmdpath dev/ocscmd/clone-first-disk.sh  --image ./partimag/
4. 使用 qemu_clonezilla_ci_run.sh 還原 clonezilla qcow2 到 restore.qcow2(需要產生新的30g qcow2) ; 可以直接使用cmdpath  dev/ocscmd/restore-first-disk.sh
eg: qemu-img create -f qemu/qcow2 restore.qcow2 30G
eg: ./qemu_clonezilla_ci_run.sh --disk qemu/restore.qcow2 --live isos/clonezilla-live-20251124-resolute-amd64/clonezilla-live-20251124-resolute-amd64.qcow2 --kernel isos/clonezilla-live-20251124-resolute-amd64/clonezilla-live-20251124-resolute-amd64-vmlinuz --initrd isos/clonezilla-live-20251124-resolute-amd64/clonezilla-live-20251124-resolute-amd64-initrd.img --cmdpath dev/ocscmd/restore-first-disk.sh  --image ./partimag/
5. 使用 validateOS.sh 驗證 restore.qcow2 是否能正常啟動
./validateOS.sh --iso dev/cloudinit/cloud_init_config/cidata.iso --disk qemu/restore.qcow2 --timeout 60 --keeplog

- [x] 整個 script flow 需要開發，完整flow, 參數說明
- [x] 增加--help 參數可以讓使用者查詢使用說明
- [x] 參數檢查機制，確保使用者輸入的參數是有效的。例如，檢查檔案是否存在，參數格式是否正確等。
- [x] 增加執行結果回傳值，成功回傳0，失敗回傳1
- [x] 設定參數 CLONE_IMAGE_NAME 來指定 backup / restore 的 image name; 且要同步到 dev/ocscmd/clone-first-disk.sh 與 dev/ocscmd/restore-first-disk.sh 裡面; 抑或是以hardcode 常數方式寫死在 dev/ocscmd/clone-first-disk.sh 與 dev/ocscmd/restore-first-disk.sh 裡面

## qemu_clonezilla_ci_run.sh 改進事項：
qemu_clonezilla_ci_run.sh 需要修改：
- [x] 1. 以長參數與短參數取代目前依照順序的方式取得使用者參數
Example:
./qemu_clonezilla_ci_run.sh -i restore.qcow2 live.qcow2 ./clonezilla/vmlinuz ./clonezilla/initrd.img "sudo /usr/sbin/ocs-sr -g auto -p poweroff restoredisk ask_user sda" "./partimag"
to

./qemu_clonezilla_ci_run.sh -i --disk restore.qcow2 --disk second.qcow2 --disk third.qcow2  --live live.qcow2  --kernel ./clonezilla/vmlinuz --initrd ./clonezilla/initrd.img --cmd "sudo /usr/sbin/ocs-sr -g auto -p poweroff restoredisk ask_user sda" --image "./partimag"

- [x] 2. 目前APPAND ARGS 是寫死的，需要改成可以由使用者輸入參數來決定要不要加入override APPAND ARGS, 提供一個參數複寫APPAND ARGS
- [x] 3. 增加參數 cmdpath 用來替換 執行 cmd 的方式。目前只能執行簡易指令，我想要執行一個script file, 所以用一個 參數 cmdpath 來指定 script file 的路徑，然後把 script file 複製到 clonezilla live 的 ramdisk 裡面，最後在 cmd 裡面執行這個 script file。
  例如：
  ./qemu_clonezilla_ci_run.sh --disk restore.qcow2 --live live.qcow2  --kernel ./clonezilla/vmlinuz --initrd ./clonezilla/initrd.img --cmdpath "/root/myscript.sh" --image "./partimag"
  裡面的 myscript.sh 內容可以是：
  ```
  #!/bin/bash
  sudo /usr/sbin/ocs-sr -g auto -p poweroff restoredisk ask_user sda
  ```
  然後 qemu_clonezilla_ci_run.sh 裡面會把 myscript.sh 複製到 ramdisk 裡面，然後在 boot 的參數裡面執行 /root/myscript.sh
reference https://clonezilla.nchc.org.tw/clonezilla-live/doc/fine-print.php?path=99_Misc/00_live-boot-parameters.doc#00_live-boot-parameters.doc
- [x] 4. 一樣cmdpath的邏輯，我也想要讓APPAND ARGS 可以從一個檔案讀取進來，而不是只能用參數帶進來
- [x] 5. 發現沒有--help 參數可以讓使用者查詢使用說明，請加上--help 參數; 且參數錯誤也沒有充分說明錯誤原因，請補上錯誤訊息說明
example:
$ ./qemu_clonezilla_ci_run.sh 
Error: Missing command. Please provide either --cmd or --cmdpath.
- [x] 6. 目前的程式碼沒有檢查參數的有效性，請加上參數檢查機制，確保使用者輸入的參數是有效的。例如，檢查檔案是否存在，參數格式是否正確等。
- [x] 7. 發現 partimage 有殘留的 md_script_1764665091_12358  cmd_script_1764665393_8800 , 應該於執行完成之後刪除。

## clonezilla_zip2qcow.sh 改進事項：
- [x] 1. 增加參數檢查機制，確保使用者輸入的參數是有效的。例如，檢查檔案是否存在，參數格式是否正確等。
- [x] 2. 增加--help 參數可以讓使用者查詢使用說明
- [x] 3. 參數改為長參數，例如
./clonezilla_zip2qcow.sh --zip clonezilla_image.zip --output outputdir/ --size 10G --force
- [x] 4. 在步驟 Copying Kernel/Initrd files to the target directory，檔案名稱prefix採用clonezilla zip 的base name 來命名，而不是固定用 vmlinuz 與 initrd.img

## clonezilla-boot.sh 改進事項：
- [x] rename clonezilla-iso-boot.sh 為 clonezilla-boot.sh
- [x] 1. 增加參數檢查機制，確保使用者輸入的參數是有效的。例如，檢查檔案是否存在，參數格式是否正確等。
- [x] 2. 增加--help 參數可以讓使用者查詢使用說明
- [x] 3. 自動下載 clonezilla iso 檔案，當沒有指定 --iso 參數時，自動下載最新的 clonezilla iso 檔案，預設下載stable amd64 iso 版本

## debian-install.sh 改進事項：
- [x] 1. 增加參數檢查機制，確保使用者輸入的參數是有效的。例如，檢查檔案是否存在，參數格式是否正確等。
- [x] 2. 增加--help 參數可以讓使用者查詢使用說明
- [x] 3. 自動下載 debian netinst iso 檔案，當沒有指定 --iso 參數時，自動下載最新的 debian netinst iso 檔案

## boot.sh 改進事項：
- [x] rename boot-qemu-image.sh 為 boot.sh
- [x] 1. 增加參數檢查機制，確保使用者輸入的參數是有效的。例如，檢查檔案是否存在，參數格式是否正確等。
- [x] 2. 增加--help 參數可以讓使用者查詢使用說明

## validateOS.sh 改進事項：
validateOS.sh 主要功能是當clonezilla 還原成功之後，驗證作業系統是否能正常啟動。驗證方式是利用cloud init 方式進行驗證
cloud init 已經完成於 dev/cloudinit/prepareiso.sh 會產生 dev/cloudinit/cloud_init_config/cidata.iso
當 cloud init 作用之後會變更使用者密碼最後echo 關鍵字 ReStOrE
程式需要已 auto ci 方式，不提供互動、輸出到log檔, 並檢查關鍵字是否有成功輸出

- [x] 確認/增加參數 --iso 指定 cloud init iso 檔案路徑
- [x] 確認/增加參數 --disk 指定要驗證的 qcow2 磁碟映像檔案
- [x] 增加--help 參數可以讓使用者查詢使用說明
- [x] 參數檢查機制，確保使用者輸入的參數是有效的。例如，檢查檔案是否存在，參數格式是否正確等。
- [x] 執行完成之後，檢查log 檔案是否有 ReStOrE 關鍵字，來確認驗證是否成功
- [x] 執行完成之後，刪除產生的暫存檔案, 用validate_為 prefix 的檔案
- [x] 增加執行timeout 機制，避免無限等待, 等待時間300秒
- [x] 增加執行結果回傳值，成功回傳0，失敗回傳1
- [x] 增加選用參數 --keeplog 來保留log 檔案，預設會刪除log 檔案

## dev/cloudinit/prepareiso.sh 改進事項：
- [x] comment the code in english
