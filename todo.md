# clonezilla ci and gemini cli 開發整理
default prompt: 這是 clonezilla 準備來開發CI的目錄，裡面討論可以用英文與繁體中文，程式與註解都用英文。大部分用bash script 開發, 請協助我整理目前需要改進的事項，並以checklist 方式列出，完成後不可以打勾，列出完成的項目給開發者驗證。

## Overview
This directory contains scripts and tools for automating Clonezilla operations in a Continuous Integration (CI) environment. The main scripts include `qemu-clonezilla-ci-run.sh`, which is used to run Clonezilla in a QEMU virtual machine, and `clonezilla-zip2qcow.sh`, which converts Clonezilla zip images to QCOW2 format for use in QEMU.

- [x] 整個專案的readme 文件需要補充
- [x] 整個專案的usage 文件需要補充
- [x] 整個專案需要支援多架構，先處理 riscv-64, arm64 架構支援; 所有script 需要支援多架構
- [x] 相依的套件要補上 qemu-efi-aarch64 qemu-system-arm for usage
- [ ] 容器化支援, 開發一個 Dockerfile 來建置一個包含所有相依套件的容器映像檔，方便在不同環境中執行這些腳本，要可以支援多架構，與 dev/testData, qemu/cloudimages, isos, zip 等目錄的掛載

## .gitlab-ci.yml 改進事項：
- [x] 目前行為是執行 start.sh 來進行所有的單元測試, 我想改為每一個 script 都有自己的單元測試, 並且在 .gitlab-ci.yml 裡面分別執行每一個 script 的單元測試, 這樣可以更清楚知道是哪一個 script 有問題
- [x] 以 .gitlab-ci.yml 來執行所有在 start.sh 內的測試, 並且產生測試報告
- [x] 支援多架構測試, 例如 amd64, arm64, riscv64 等架構的測試 可以搭配不同的pipelines 來執行不同架構的測試
- [ ] 支援多架構測試, 例如 amd64, arm64, riscv64 等架構的測試 可以搭配不同的 variables 來執行不同架構的 pipelines 測試
      variable arch=amd64 zip=https://.../clonezilla-live-xxxx-amd64.zip
      variable arch=riscv64 zip=https://.../clonezilla-live-xxxx-riscv64.zip
      variable arch=arm64 zip=https://.../clonezilla-live-xxxx-arm64.zip
- [ ] 每一個 script 的測試結果都要產生 並上傳到 gitlab artifacts 裡面, 方便後續下載查看; 目前都會放到 logs/ 目錄裡面, 有些是以檔案形式產生，也一併上傳


## start.sh 改進事項：
開發一個 start.sh 腳本，這個腳本主要用來啟動一個完整的 clonezilla ci 流程, 使用 shunit2 來進行單元測試, 並且產生測試報告
- [x] check shunit2 並提示安裝 (done)
- [x] 實做單元測試，主要包含兩種類型 (done)
    - [x] 作業系統測試，利用 os-clone-restore.sh 以不同的 linux distro 進行 clonezilla 備份還原測試 (done)
    - [x] 檔案系統測試，利用 data-clone-restore.sh 以不同的檔案系統類型進行 clonezilla 備份還原測試 (done)
    - [x] zip檔不要寫死在程式碼裡面，可以在檔案前面進行定義 也可以用參數帶入 (done)
    - [x] 每一個測試的log 檔案要分開存放到 /log/XXX，方便debug (done)
    - [x] 我加了SHUNIT_TIMER=1 # Enable test timing 希望可以在log 裡面看到每一個測試花費的時間, 但目前沒有看到相關資訊, 需要修正
    - [x] 支援 --arch 參數，並從 qemu/cloudimages/cloud_images.conf 讀取對應架構的 cloud image，如果沒有就忽略 (done)
    - [x] 移除作業系統測試中 hardcode 的 release version，改為測試所有支援的 release (done)
    - [x] 提供 --help 參數 (done)
    - [x] os_clone_restore 與 data_clone_restore 兩個 使用 tee 來同時輸出到螢幕與log 檔

## data-clone-restore.sh 改進事項：
- [x] 整個 script flow 需要開發，完整flow, 參數說明
- [x] 增加--help 參數可以讓使用者查詢使用說明
- [x] 參數檢查機制，確保使用者輸入的參數是有效的。例如，檢查檔案是否存在，參數格式是否正確等。
- [x] 增加執行結果回傳值，成功回傳0，失敗回傳1
- [x] 實作主要流程:
    - [x] 1. 使用 clonezilla-zip2qcow.sh 將 clonezilla zip 轉成 qcow2 檔案
    - [x] 2. 備份前準備，將--data 目錄複製到 qcow2 裡面, 需要進行檔案的checksum 記錄供還原時驗證
    - [x] 3. 使用 qemu-clonezilla-ci-run.sh 備份 qcow2 到 partimag/
    - [x] 4. 使用 qemu-clonezilla-ci-run.sh 還原 clonezilla qcow2 到 restore.qcow2    - [x] 5. 驗證 restore.qcow2 是否能正常還原出正確的檔案內容，與備份前的checksum 進行比對
- [x] 增加參數設定partimag 目錄位置
- [x] 增加參數錯誤時保留temp檔案，方便debug
- [x] 嘗試增加檔案系統類型支援 ext2, ext3, xfs, btrfs, exfat 
- [ ] 先忽略 嘗試 以其他方式 增加檔案系統類型支援 fat16, fat12, hfs, hfsplus, ufs, reiserfs, jfs, apfs, 需要先確認可行性
- [x] checksum 不要列出所有檔案，只列出有錯誤的部份，所有檔案檢查結果另外存log檔案, 完成, 尚未確認
- [x] 步驟5 驗證方式不要tar/copy 整個目錄，可以直接mount qcow2 檔案然後進行檔案比對
      例如：guestmount -a source.qcow2 -m /dev/sda1 --ro /tmp/XXXX/mnt/ ; md5sum -c ....
- [x] 指定tmp路徑，預設使用 /tmp/dcr-xxxxxx , 並於完成後刪除; --tmp_path /home/debian/tmp/ 參數指定tmp 路徑
- [x] 檔案的checksum 記錄供還原時驗證, 希望設計為可以保留checksum 檔案, 以便後續可以用來驗證其他 qcow2 檔案，減少步驟2的時間, 可以設定位置於當前目錄下的 dcr_checksums.txt 檔案
- [x] 還原失敗時，保留相關檔案，方便debug
- [x] 檢查還原的檔案系統會直接用 checksum; 希望在這步驟之前設計一個新的檢查，以read-only的方式用fsck檢查檔案系統是否有錯誤(只檢查不修正)，確保還原的檔案系統是健康的，再進行checksum 比對

## os-clone-restore.sh 改進事項：
- [x] linux-clone-restore.sh 更名為 os-clone-restore.sh
這個程式主要用來進行os distro 的clonezilla 備份還原，完全非互動方式一次完成備份、還原、還原檢查
提供使用者參數：
1. --zip 指定 clonezilla zip 檔案路徑 
2. --tmpl 設定 os distro 參數，例: debian-sid-generic-amd64-daily-20250805-2195.qcow2 需支援 cloud init

主要流程
1. 使用 clonezilla-zip2qcow.sh 將 clonezilla zip 轉成 qcow2 檔案
eg: ./clonezilla-zip2qcow.sh --zip isos/clonezilla-live-20251124-resolute-amd64.zip  -o isos/
2. 備份debian-sid-generic-amd64-daily-20250805-2195.qcow2 到 debian-sid-generic-amd64-daily-20250805-2195.sda.qcow2
eg: cp qemu/debian-sid-generic-amd64-daily-20250805-2195.qcow2 qemu/debian-sid-generic-amd64-daily-20250805-2195.sda.qcow2
3. 使用 qemu-clonezilla-ci-run.sh 備份 debian-sid-generic-amd64-daily-20250805-2195.sda.qcow2 到 partimag/ ; 可以直接使用cmdpath  dev/ocscmd/clone-first-disk.sh
eg: ./qemu-clonezilla-ci-run.sh --disk qemu/debian-sid-generic-amd64-daily-20250805-2195.sda.qcow2 --live isos/clonezilla-live-20251124-resolute-amd64/clonezilla-live-20251124-resolute-amd64.qcow2 --kernel isos/clonezilla-live-20251124-resolute-amd64/clonezilla-live-20251124-resolute-amd64-vmlinuz --initrd isos/clonezilla-live-20251124-resolute-amd64/clonezilla-live-20251124-resolute-amd64-initrd.img --cmdpath dev/ocscmd/clone-first-disk.sh  --image ./partimag/
4. 使用 qemu-clonezilla-ci-run.sh 還原 clonezilla qcow2 到 restore.qcow2(需要產生新的30g qcow2) ; 可以直接使用cmdpath  dev/ocscmd/restore-first-disk.sh
eg: qemu-img create -f qemu/qcow2 restore.qcow2 30G
eg: ./qemu-clonezilla-ci-run.sh --disk qemu/restore.qcow2 --live isos/clonezilla-live-20251124-resolute-amd64/clonezilla-live-20251124-resolute-amd64.qcow2 --kernel isos/clonezilla-live-20251124-resolute-amd64/clonezilla-live-20251124-resolute-amd64-vmlinuz --initrd isos/clonezilla-live-20251124-resolute-amd64/clonezilla-live-20251124-resolute-amd64-initrd.img --cmdpath dev/ocscmd/restore-first-disk.sh  --image ./partimag/
5. 使用 validate.sh 驗證 restore.qcow2 是否能正常啟動
./validate.sh --iso dev/cloudinit/cloud_init_config/cidata.iso --disk qemu/restore.qcow2 --timeout 60 --keeplog

- [x] 整個 script flow 需要開發，完整flow, 參數說明
- [x] 增加--help 參數可以讓使用者查詢使用說明
- [x] 參數檢查機制，確保使用者輸入的參數是有效的。例如，檢查檔案是否存在，參數格式是否正確等。
- [x] 增加執行結果回傳值，成功回傳0，失敗回傳1
- [x] 設定參數 CLONE_IMAGE_NAME 來指定 backup / restore 的 image name; 且要同步到 dev/ocscmd/clone-first-disk.sh 與 dev/ocscmd/restore-first-disk.sh 裡面; 抑或是以hardcode 常數方式寫死在 dev/ocscmd/clone-first-disk.sh 與 dev/ocscmd/restore-first-disk.sh 裡面
- [x] 增加參數 --keep-temp 當失敗時，保留中間產生的所有檔案，方便debug
- [x] image name 如果沒有參數指定，目前預設是固定字串； 建議改成以 os distro 名稱來命名，例如 debian-sid-generic-amd64-daily-20250805-2195.qcow2 就會是 debian-sid-generic-amd64-daily-20250805-2195/

## qemu-clonezilla-ci-run.sh 改進事項：
qemu-clonezilla-ci-run.sh 需要修改：
- [x] 1. 以長參數與短參數取代目前依照順序的方式取得使用者參數
Example:
./qemu-clonezilla-ci-run.sh -i restore.qcow2 live.qcow2 ./clonezilla/vmlinuz ./clonezilla/initrd.img "sudo /usr/sbin/ocs-sr -g auto -p poweroff restoredisk ask_user sda" "./partimag"
to

./qemu-clonezilla-ci-run.sh -i --disk restore.qcow2 --disk second.qcow2 --disk third.qcow2  --live live.qcow2  --kernel ./clonezilla/vmlinuz --initrd ./clonezilla/initrd.img --cmd "sudo /usr/sbin/ocs-sr -g auto -p poweroff restoredisk ask_user sda" --image "./partimag"

- [x] 2. 目前APPAND ARGS 是寫死的，需要改成可以由使用者輸入參數來決定要不要加入override APPAND ARGS, 提供一個參數複寫APPAND ARGS
- [x] 3. 增加參數 cmdpath 用來替換 執行 cmd 的方式。目前只能執行簡易指令，我想要執行一個script file, 所以用一個 參數 cmdpath 來指定 script file 的路徑，然後把 script file 複製到 clonezilla live 的 ramdisk 裡面，最後在 cmd 裡面執行這個 script file。
  例如：
  ./qemu-clonezilla-ci-run.sh --disk restore.qcow2 --live live.qcow2  --kernel ./clonezilla/vmlinuz --initrd ./clonezilla/initrd.img --cmdpath "/root/myscript.sh" --image "./partimag"
  裡面的 myscript.sh 內容可以是：
  ```
  #!/bin/bash
  sudo /usr/sbin/ocs-sr -g auto -p poweroff restoredisk ask_user sda
  ```
  然後 qemu-clonezilla-ci-run.sh 裡面會把 myscript.sh 複製到 ramdisk 裡面，然後在 boot 的參數裡面執行 /root/myscript.sh
reference https://clonezilla.nchc.org.tw/clonezilla-live/doc/fine-print.php?path=99_Misc/00_live-boot-parameters.doc#00_live-boot-parameters.doc
- [x] 4. 一樣cmdpath的邏輯，我也想要讓APPAND ARGS 可以從一個檔案讀取進來，而不是只能用參數帶進來
- [x] 5. 發現沒有--help 參數可以讓使用者查詢使用說明，請加上--help 參數; 且參數錯誤也沒有充分說明錯誤原因，請補上錯誤訊息說明
example:
$ ./qemu-clonezilla-ci-run.sh 
Error: Missing command. Please provide either --cmd or --cmdpath.
- [x] 6. 目前的程式碼沒有檢查參數的有效性，請加上參數檢查機制，確保使用者輸入的參數是有效的。例如，檢查檔案是否存在，參數格式是否正確等。
- [x] 7. 發現 partimage 有殘留的 md_script_1764665091_12358  cmd_script_1764665393_8800 , 應該於執行完成之後刪除。
- [x] 自動判斷是否 --enable-kvm
- [x] 於完成時間顯示總共花費時間紀錄到log 檔案
- [x] 增加參數設定log目錄，預設為當前目錄下的 logs/ 目錄 (done)
- [x] 增加zip參數，呼叫 clonezilla-zip2qcow.sh 自動轉換zip 為 qcow2; 參數範例 --zip path/to/clonezilla.zip --output zip/ --size 2G
      解壓縮之後會產生需要的檔案 vmlinux initrd.img clonezilla-live-xxxx.qcow2 就是 
      clonezilla-live-xxxx.qcow2,  --live <path>           Path to the Clonezilla live QCOW2 media.
      vmlinux,                     --kernel <path>         Path to the kernel file (e.g., vmlinuz).
      initrd.img,                  --initrd <path>         Path to the initrd file.
      且不要重複進行解壓縮，如果三個檔案都已經存在，就跳過這個步驟
      如果只有部份檔案，就還是需要使用 clonezilla-zip2qcow.sh 來解壓縮 with --force 參數來強制覆蓋
- [x] 增加額外qemu參數，例如要設定mtddevice 等參數，以便支援更多硬體裝置模擬，例如
    -drive file=mtd.img,format=raw,id=mtddev0 \
    -device mtd-ram,id=mtd0,drive=mtddev0,size=0x4000000 \ # Or similar mtd device
    要怎麼安全的合併到 qemu-clonezilla-ci-run.sh

## clonezilla-zip2qcow.sh 改進事項：
- [x] 1. 增加參數檢查機制，確保使用者輸入的參數是有效的。例如，檢查檔案是否存在，參數格式是否正確等。
- [x] 2. 增加--help 參數可以讓使用者查詢使用說明
- [x] 3. 參數改為長參數，例如
./clonezilla-zip2qcow.sh --zip clonezilla_image.zip --output outputdir/ --size 10G --force
- [x] 4. 在步驟 Copying Kernel/Initrd files to the target directory，檔案名稱prefix採用clonezilla zip 的base name 來命名，而不是固定用 vmlinuz 與 initrd.img
- [x] 自動下載最新的zip 檔案，當沒有指定 --zip 參數時，自動下載最新的 clonezilla zip 檔案，預設下載stable amd64 版本

## clonezilla-boot.sh 改進事項：
- [x] rename clonezilla-iso-boot.sh 為 clonezilla-boot.sh
- [x] 1. 增加參數檢查機制，確保使用者輸入的參數是有效的。例如，檢查檔案是否存在，參數格式是否正確等。
- [x] 2. 增加--help 參數可以讓使用者查詢使用說明
- [x] 3. 自動下載 clonezilla iso 檔案，當沒有指定 --iso 參數時，自動下載最新的 clonezilla iso 檔案，預設下載stable amd64 iso 版本
- [x] 增加參數 --zip 行為類似 qemu-clonezilla-ci-run.sh 的用 clonezilla-zip2qcow.sh , 自動解壓縮 zip 檔案取得 vmlinux, initrd.img, clonezilla-live-xxxx.qcow2, 並以qemu開機，用console 顯示。主要用來確認可以用clonezilla iso zip 開機就好，不需要額外指定append args 與 ocs cmd
- [x] --disk 換成optional 參數, 如果有指定就掛載qcow2 磁碟映像檔案, 沒有指定就不掛載

## debian-install.sh 改進事項：
- [x] 1. 增加參數檢查機制，確保使用者輸入的參數是有效的。例如，檢查檔案是否存在，參數格式是否正確等。
- [x] 2. 增加--help 參數可以讓使用者查詢使用說明
- [x] 3. 自動下載 debian netinst iso 檔案，當沒有指定 --iso 參數時，自動下載最新的 debian netinst iso 檔案

## boot.sh 改進事項：
- [x] rename boot-qemu-image.sh 為 boot.sh
- [x] 1. 增加參數檢查機制，確保使用者輸入的參數是有效的。例如，檢查檔案是否存在，參數格式是否正確等。
- [x] 2. 增加--help 參數可以讓使用者查詢使用說明

## validate.sh 改進事項：
validate.sh 主要功能是當clonezilla 還原成功之後，驗證作業系統是否能正常啟動。驗證方式是利用cloud init 方式進行驗證
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
- [x] 自動判斷是否 --enable-kvm

## dev/cloudinit/prepareiso.sh 改進事項：
- [x] comment the code in english
