# clonezilla ci and gemini cli 開發整理
default prompt: 這是 clonezilla 準備來開發CI的目錄，裡面討論可以用英文與繁體中文，程式與註解都用英文。大部分用bash script 開發

## Overview
This directory contains scripts and tools for automating Clonezilla operations in a Continuous Integration (CI) environment. The main scripts include `qemu_clonezilla_ci_run.sh`, which is used to run Clonezilla in a QEMU virtual machine, and `clonezilla_zip2qcow.sh`, which converts Clonezilla zip images to QCOW2 format for use in QEMU.

- [x] 整個專案的readme 文件需要補充

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

## boot_qemu_image.sh 改進事項：
- [ ] rename boot-qemu-image.sh 為 boot.sh
- [ ] 1. 增加參數檢查機制，確保使用者輸入的參數是有效的。例如，檢查檔案是否存在，參數格式是否正確等。
- [ ] 2. 增加--help 參數可以讓使用者查詢使用說明
