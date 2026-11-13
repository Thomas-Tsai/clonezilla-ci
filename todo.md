# clonezilla ci and gemini cli 開發整理
default prompt: 這是 clonezilla 準備來開發CI的目錄，裡面討論可以用英文與繁體中文，程式與註解都用英文。大部分用bash script 開發, 請協助我整理目前需要改進的事項，並以checklist 方式列出，完成後不可以打勾，列出完成的項目給開發者驗證。

## Overview
This directory contains scripts and tools for automating Clonezilla operations in a Continuous Integration (CI) environment. The main scripts include `qemu-clonezilla-ci-run.sh`, which is used to run Clonezilla in a QEMU virtual machine, and `clonezilla-zip2qcow.sh`, which converts Clonezilla zip images to QCOW2 format for use in QEMU.

- [ ] 整個專案的readme 文件需要補充
- [x] 整個專案的usage 文件需要補充
- [x] 整個專案需要支援多架構，先處理 riscv-64, arm64 架構支援; 所有script 需要支援多架構
- [x] 相依的套件要補上 qemu-efi-aarch64 qemu-system-arm for usage
- [x] 增加 AMD64 架構下的 EFI 開機備份還原測試支援。
- [ ] 容器化支援, 開發一個 Dockerfile 來建置一個包含所有相依套件的容器映像檔，方便在不同環境中執行這些腳本，要可以支援多架構，與 dev/testData, qemu/cloudimages, isos, zip 等目錄的掛載

## .gitlab-ci.yml 改進事項：
- [x] 目前行為是執行 start.sh 來進行所有的單元測試, 我想改為每一個 script 都自己的單元測試, 並且在 .gitlab-ci.yml 裡面分別執行每一個 script 的單元測試, 這樣可以更清楚知道是哪一個 script 有問題
- [x] 以 .gitlab-ci.yml 來執行所有在 start.sh 內的測試, 並且產生測試報告
- [x] 支援多架構測試, 例如 amd64, arm64, riscv64 等架構的測試 可以搭配不同的pipelines 來執行不同架構的測試
- [x] 支援多架構測試, 例如 amd64, arm64, riscv64 等架構的測試 可以搭配不同的 variables 來執行不同架構的 pipelines 測試
variable arch=amd64 zip=https://.../clonezilla-live-xxxx-amd64.zip
variable arch=riscv64 zip=https://.../clonezilla-live-xxxx-riscv64.zip
variable arch=arm64 zip=https://.../clonezilla-live-xxxx-arm64.zip
- [x] 每一個 script 的測試結果都要產生 並上傳到 gitlab artifacts 裡面, 方便後續下載查看; 目前都會放到 logs/ 目錄裡面, 有些是以檔案形式產生，也一併上傳
- [x] 解決 QEMU port forwarding 衝突問題，在平行 CI jobs 中避免 `tcp::2222-:22` 錯誤。
- [x] .gitlab-ci.yml 中，build job 不再保留舊的 zip 檔案，每次都下載新的 zip 以避免錯誤。
- [x] 修改為可以同時運作
- [x] 讓 .gitlab-ci.yml專注於流程，要測試的部份改用 jobs/ 目錄底下的 script 來執行
- [x] 產生報告，報告內容包含 測試結果、VARIABLES、測試的 ARCH, ZIP  等
- [x] 產生測試報告，報告內容包含測試結果、Pipeline 變數、測試架構 (ARCH) 和使用的 Clonezilla ZIP 檔案。報告中也包含了 Pipeline 啟動時間、總執行時間、每個 Job 的啟動時間與執行時間。
- [x] 報告內容增加 Runner 資訊，詳細顯示每個測試 Job 執行於哪一台 Runner。
- [x] 將 `build_zip` Job 中的下載邏輯與 `download-clonezilla.sh` 腳本整合，支援透過 `ARCH` 和 `TYPE` 變數自動下載，同時保留 `CLONEZILLA_ZIP_URL` 的直接指定功能。
- [x] 修復 `build_zip` Job 中下載邏輯的錯誤，使其在無法找到或下載 zip 檔時能輸出更清晰的錯誤訊息。
- [x] report 網頁分為 history.htm 與 index.htm; index.htm 保留最新50 個測試pipeline 結果; history.html 可以連結到 history-$year-$month.html
- [x] 產生 history-$year-$month.html 當作 archive的概念 不用每次都產生 只產生之前的，如果檢查已經存在則不用產生

### publish_reports.sh
- [x] 修改report dir 為 REPORT_DIR="reports_repo/${ZIP_BASENAME}/pipelineID/"
- [x] 將 results/ 也複製進去 REPORT_DIR
- [x] Pipeline ID 將line 69 追加 顯示 id (iid) ，如： `${CI_PIPELINE_IID}(${CI_PIPELINE_ID})`
- [x] per-run report, REPORT_DIR/index.htm , log 那欄 連結換成 gitlab.com CI_JOB_URL，但是保留 logs/ 資料
- [x] 刪除 ... `click on the link in the 'Log' column or <a href="./log` ...
- [ ] 修復 GitLab Pages 網站停止更新問題：在 test-reports 分支新增 .gitlab-ci.yml 的 pages job，由 publish_reports push 觸發部署（原本 main child pipeline 的 pages job 改名為 publish_reports 後不再部署）(待驗證)
- [x] 發布 report 時於同一 commit 移除 `in-progress.json` 中對應 `<arch>_<type>` 的 claim 狀態，讓 schedule pipeline 知道該版本測試已完成（取消的 pipeline 由 12h TTL 兜底）(待驗證)

### scripts/check-version-update.sh
- [x] 新增 `in-progress.json` claim 機制：偵測到新版本時立即寫回 test-reports branch（`git push -o ci.skip`），後續 schedule 在 TTL（預設 12h）內看到同版本 claim 會輸出 `VERSION_STATUS=in_progress` 跳過測試，避免 release 日多個 pipeline 同時測試同一版本、active jobs 超過 GitLab.com Free tier 500 上限導致 "Project exceeded the allowed number of jobs in active pipelines"。(待驗證)
- [x] claim 寫入採用 fresh clone + push retry（最多 3 次）防止並發搶佔，搶輸時改輸出 in_progress；claim 失敗時仍照常測試（允許重複，不阻塞 CI）。(待驗證)
- [x] 新增 `VERSION_STATUS=mirror_empty`：testing→stable 晉升後 NCHC mirror 的 `testing/`、`alternative/testing/` 目錄會暫時清空（正常狀態），原本視為硬錯誤導致每小時 2 條 pipeline 硬失敗（2026-09-20 09:34Z 起 32 條皆為 check_version script_failure）。現改為 `download-clonezilla.sh` 找不到版本時回傳 exit 3，check_version 映射為 `mirror_empty` 並 exit 0，下游跳過；mirror 發新版後自動恢復測試。

### .gitlab-ci.yml / child-pipeline.yml
- [x] child-pipeline.yml 所有 version gate 支援 `in_progress` 狀態一併跳過（download_zip、build_singularity、update_sif、test_template before_script/script、publish_reports，共 6 處）。(待驗證)
- [x] child-pipeline.yml 所有 version gate（同樣 6 處）加入 `mirror_empty` 一併跳過；cron-report.sh 的 skip 統計亦納入 `in_progress`/`mirror_empty`。
- [x] .gitlab-ci.yml 13 個手動 trigger jobs 限定只在 push/web/api/trigger 來源出現：schedule pipeline 從此只含 trigger:scheduled，狀態即時收斂為 success/failed，不再累積「永遠 manual」的殭屍 pipeline（手動測試請用 Run pipeline 或 push pipeline 頁面按鈕）。(待驗證)
- [x] 移除 `trigger-*-new-vm` 6 個手動 trigger jobs 與 `.trigger_template_new_vm`（runner 驗證完畢）；之後要指定 runner 請在 Run pipeline 時設定 `RUNNER_TAG` 變數。(待驗證)
- [x] update_sif 移出 child-pipeline（2026-11-01：F1 login node 離線時 update_sif 卡 pending 塞爆全部 schedule pipelines，單日 14 條；改為 .gitlab-ci.yml 獨立 daily schedule "update-sif"（SIF_UPDATE_ONLY=true），前置 `f1_probe` job 偵測 f1-ilgn01:22 連線，失敗即 exit 1 → update_sif 因 needs 未滿足被 skip 而非 pending，主測試 flow 從此不碰 build_sif/F1）。(已驗證：2026-11-02 F1 恢復後手動 play schedule id 4526314 → pipeline 3016019719 success，f1_probe 3s、update_sif 76s，SIF 399M 已更新)
- [x] update_sif 改為事件驅動 + skip-if-unchanged：daily 03:35 schedule 保留為備援；`build_singularity` 重建 Docker image 後立即以 CI_JOB_TOKEN 觸發 SIF_UPDATE_ONLY=true + IMAGE_JUST_BUILT=true 的小 pipeline 強制重建 SIF；update_sif 在 SIF 存在且 IMAGE_JUST_BUILT!=true 時跳過（FORCE_SIF_REBUILD=true 可強制）；`.trigger_template` 與 `trigger:scheduled` 均排除 SIF_UPDATE_ONLY，避免殭屍 manual jobs；從此 image 重建當下即補齊 SIF，解決 daily 排程期間 Slurm 測試可能用到舊 image 的問題。(已驗證 2026-11-02：pipeline 3016144280 僅含兩個 SIF jobs 無殭屍 manual jobs，update_sif 正確 skip；3016145207 帶 IMAGE_JUST_BUILT=true 正確強制重建 SIF；build_singularity 的 trigger 路徑待下次真實 image 重建自動驗證)

### Telegram 通知 (scripts/notify-telegram.sh + child-pipeline.yml)
- [x] 新增 `scripts/notify-telegram.sh`：`started`（新版本偵測）與 `finished`（測試完成摘要）兩種模式，使用 Telegram Bot API (`sendMessage`, HTML parse mode)；腳本永不讓 job 失敗（缺 token 或 API 失敗只記 warning 並 exit 0），支援 `--dry-run` 本地驗證。(已於本地 dry-run 驗證)
- [x] 通知過濾：排程 + `VERSION_STATUS=no_change/in_progress/mirror_empty` → 不送；排程 + `new_version` → `check_version` 階段先送「偵測到新版本」、`notify:telegram` 結束再送結果；手動 pipeline（push/web/api/trigger）→ 完成後一律送。(已於本地 dry-run 矩陣驗證 6 種 gate 組合)
- [x] `finished` 摘要從 `results/*.yml` 彙總，缺的 expected jobs results 比照 `publish_reports.sh` 視為失敗（EXPECTED_TEST_JOBS arch-aware）；完全不見 results 時顯示「無測試結果」。
- [x] child-pipeline.yml 新增 `notify:telegram` job（deploy stage, `when: always`, needs 比照 publish_reports），並在 `check_version` script 末端 source `version_check.env` 後呼叫 `started` 模式。
- [x] 在 GitLab project 設定 masked CI/CD variables：`TELEGRAM_BOT_TOKEN`、`TELEGRAM_CHAT_ID`（bot 需加入目標 group）。(已設定；masked、非 protected，feature branch 亦可用)
- [x] 腳本實際發送驗證：以 SELFTEST 資料發送 started/finished 兩則訊息，Telegram group 已確認收到（2026-10-27）。
- [ ] 真實 pipeline 觸發驗證 `notify:telegram` job 行為（手動觸發一次完整測試）。已於 2026-10-27 觸發 child pipeline [#19019](https://gitlab.com/freelabstw/clonezilla-ci/-/pipelines/2993361835)（commit 484a1483，amd64/testing manual run；check_version 正確缺席、notify:telegram 待命），待 suite 完成後確認 Telegram group 收到 finished 摘要訊息。(驗證中)

### generate_report.sh
- [x] reports.json,  generate_report.sh  須增加顯示 CI_PIPELINE_ID 方便與 pipeline 網頁對應
- [x] reports_repo/index.html Pipeline 顯示 ${CI_PIPELINE_IID}(${CI_PIPELINE_ID})
- [x] reports_repo/history-${month}.html  Pipeline 顯示 ${CI_PIPELINE_IID}(${CI_PIPELINE_ID})
- [x] reset data for report repo , reports.json and old data logs/.... // change to append new data


## start.sh 改進事項：
- [x] 開發一個 start.sh 腳本，這個腳本主要用來啟動一個完整的 clonezilla ci 流程, 使用 shunit2 來進行單元測試, 並且產生測試報告
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
- [ ] ubuntu-2404-vm-runner 資源不足（2026-10-23 確診：VM 僅 8C/16GB 且無 nested KVM → TCG 高 CPU 負載；2 個並發 TCG job 尖峰破 12GB → OOM killer 終結 runner/qemu → GitLab 判 no_updates_running，單日 5 次失聯。短期對策：runner config.toml 設 `limit = 1`；長期：擴至 32GB/16C）
- [x] TCG 環境 timeout 調大（2026-10-23：F1/VM runner 皆無 KVM，純 TCG；風暴時單步驟 >90min（7x 惡化）→ TEST_TIMEOUT_SECONDS 6000→10800、job timeout 2h→4h，commit 8e188b14）
- [x] 增加timeout機制（2026-10-22：jobs/test_dev_to_dev.sh 的 QEMU 外層加入 timeout（TEST_TIMEOUT_SECONDS，預設 2700s，針對上游 ocs-sr "Press Enter" hang）；child-pipeline.yml .test_template 全面加入 TEST_TIMEOUT_SECONDS=6000 script 層 timeout，避免 CI 2h job timeout 砍掉導致 logs/results artifacts 無法上傳）
- [x] GitLab Pages 報表不會自動更新（2026-10-23：last deploy 停在 2026-09-15；原因是 CI_JOB_TOKEN 的 git push 不會在 test-reports 分支觸發 pipeline → publish_reports.sh 改用 pipeline trigger API 顯式觸發 pages job；目前 3.3.4-12 / 20261022-tenacious 紀錄已手動補部署上線）
- [x] 測試失敗也要發布 failed report 到 Pages（2026-10-22：publish_reports 改 when: always；publish_reports.sh 對缺失的結果檔以 EXPECTED_TEST_JOBS 合成 "failed (no report)" 列，並用 ZIP_FILE_FROM_BUILD 做全損 fallback；reports.json 因此會記錄失敗版本，止住 version-gate 每 12h 重測壞版本的寄信迴圈。背景：上游 3.3.4-10/3.3.4-12 part-to-part clone regression + ocs-sr batch 模式仍等 Enter 造成 dev_to_dev 掛死）

## jobs/** script 改進事項：
先將 start.sh 裡面的測試拆分成多個不同的 jobs 來執行 ，檔案放 jobs/ 目錄底下
- [x] 產生 jobs 目錄，裡面包含各種不同的 CI jobs 範例，例如 debian.sh, ubuntu.sh, ext4.sh, liteserver-job.sh 等等
- [x] 用 shunit2 來進行單元測試
- [x] 用 common.sh 來放置共用的函式
- [x] 預設需要指定參數 --zip 來指定 clonezilla zip 檔案路徑, --arch 來指定架構 預設為 amd64
- [x] 新增 `download-clonezilla.sh` 腳本，提供自動偵測並下載指定架構及類型 Clonezilla Live zip 檔的功能。
- [x] 將 `jobs/common.sh` 中的自動下載邏輯替換為呼叫 `download-clonezilla.sh` 腳本，並支援 `--type` 參數。
- [x] 更新 `jobs/**` 下所有測試腳本的參數解析，使其支援傳遞 `--type` 參數。
- [x] 在 `jobs/common.sh` 中新增檢查，強制所有測試腳本必須從 `jobs/` 目錄內執行，否則將顯示錯誤並退出。
- [ ] 修復 `jobs/test_sample.sh` 已解析 `--no-ssh-forward` 卻未傳入 qemu-clonezilla-ci-run.sh，導致平行 CI jobs 時 port 2222 衝突。(待驗證)
- [ ] 新增 `jobs/test_dev_to_dev_lvm_thin.sh` 實作本地磁碟 LVM to LVM 對拷測試場景，包含 thin provisioning (thin pool / thin LVs) 建立、ocs-onthefly 複製、來源盤隔離與目標盤完整性驗證。(待驗證)
- [ ] 新增 `jobs/test_lvm_thin_save_restore.sh` 實作 LVM (含 thin provisioning) 儲存映像檔 (savedisk)、清除目標磁碟、並將映像檔還原至目標磁碟 (restoredisk) 的完整測試場景。(待驗證)
- [x] LVM thin 測試版本門檻：`jobs/common.sh` 新增 `skip_unless_clonezilla_version_or_newer`，兩個 LVM thin 測試要求 Clonezilla Live >= 3.3.4-23 / 20261108-*，低於門檻時 exit 0 視為 SKIPPED（fail-safe，不拖垮 pipeline）；無法解析的 zip 檔名 warn 後放行。(已驗證：child pipeline 3043786396 stable track 上 zip 3.3.3-37 時兩 jobs 皆印出 SKIPPED 並 exit 0；testing track 3043735854 正常執行)
- [x] 修復兩個 LVM thin 測試 check_boot 失敗（pipeline 3043241917 根因：mkfs 後立即 mount 競態失敗，資料靜默寫入 RAM rootfs）：**採用 Steven Shiau 的 MR !5**（mkfs 後 sync+settle、`mount_with_retry -t ext4`、setup fail-fast、dmesg 診斷、per-check shunit2 assert）。我方在 bugfix/lvm-thin-mount-race 的重複修正已撤回，僅保留版本門檻。另補 shunit2 assert 取值的 CRLF 剝離修正（d0092fbf）；child pipeline 3043735854 以 `TEST_FILTER=lvm_thin` 選擇性執行驗證通過（兩個 LVM jobs 五項檢查全 SUCCESS）。
- [ ] CI 報表發布問題：GitLab Pages 上檔名含 `:` 的 per-job log（如 `test:dev_to_dev_lvm_thin.log`）404；results yml 的 `job_duration` 顯示為時鐘時間而非 duration。
- [ ] `clonezilla-zip2qcow.sh` 平行不安全性：兩個 CI job 同時解同一 zip 時，共用 output dir 且 `virt-make-fs` 寫入相同路徑，會造成 libguestfs 崩潰或產出毀損的 live media（guest 開機報 "Unable to find a medium containing a live file system"）。需加 lock 機制或 per-job 隔離目錄。（本地驗證時實際觀測到）

## liteserver.sh 改進事項：
開發一個 liteserver.sh 腳本，這個腳本主要用來啟動一個簡易的 clonezilla lite server 來提供 clonezilla server 服務的場景
場景會先跑起一個 clonezilla lite server，以 qemu-clonezilla-ci-run.sh 來啟動 lite server ，須考量增加網卡的需求
然後用 qemu-clonezilla-ci-run.sh 啟動一個client 以網路開機方式 來連接這個 lite server 進行備份還原測試

例如：

client --cmd 參數機本是固定的
server 提供 --cmd, --cmdpath 參數來讓使用者可以自訂 server 的行為 透過 qemu-clonezilla-ci-run.sh 傳入qemu
如：./liteserver.sh --zip clone.zip --disk a.qcow2 --disk b.qcow2 --cmdpath dev/ocscmd/lite-bt-dev.sh --keep-temp

整個flow 為
1. prepare zip
2. prepare restore qcow2 (restore-a.qcow2, restore-b.qcow2)
3. start lite server , 需要複數 --disk 搭配一個以上的qcow2磁碟映像檔案 通常是 qemu/cloudimages 裡面的cloud image
server 啟動：
$ ./qemu-clonezilla-ci-run.sh -i --zip zip/clonezilla-live-3.3.0-33-amd64.zip --disk a.qcow2  --disk  qemu/cloudimages/debian-sid-amd64.qcow2  --no-ssh-forward --qemu-args "-netdev socket,id=net1,listen=127.0.0.1:14321 -device virtio-net-pci,netdev=net1" --cmd "ip route del default ; ip link set ens5 up; ip a add 192.168.0.1/24 dev ens5 ; ip r add default via 192.168.0.1; ocs-live-feed-img -cbm both -dm start-new-dhcpd -lscm massive-deployment -mdst from-image -g auto -e1 auto -e2 -r -x -j2 -k0 -sc0 -p true -md multicast --clients-to-wait 1 start \"debian-13-amd64\" vda"

4. start lite client , 對應 --disk 需要的 restore qcow2 磁碟映像檔案
client 啟動：
$ ./qemu-clonezilla-ci-run.sh -i --zip zip/clonezilla-live-20251124-resolute-amd64.zip --disk restore-a.qcow2  --disk qemu/restore.qcow2 --cmd "dhclient ens5; ocs-live-get-img 192.168.0.1" --no-ssh-forward --qemu-args "-netdev socket,id=net1,connect=127.0.0.1:14321 -device virtio-net-pci,netdev=net1"

5. verify restore qcow2 // 如果多個硬碟 還不確定要怎麼verify ; 先跳過
6. kill server

主意：不需要先做任何備份 // Create Image from Source Disk 是不需要的
不需要 --disk-size 參數
- [x] 主要流程
- [x] LIVE DISK / clonezilla live 同時開會有lock問題. 嘗試 disable lock/ readonly/COW 無效，也許直接備份 clonezilla...qcow2 or zip 比較快, 透過分別指定--serverzip 與 --clientzip 來解決
- [x] --zip A.zip 參數會變成 --serverzip A.zip 與 --clientzip A.zip 兩個參數
- [x] 增加--serverzip 參數，可以指定lite server 使用的 clonezilla zip 檔案, 允許與client 相同得zip 檔案
- [x] 增加--clientzip 參數，可以指定lite client 使用的 clonezilla zip 檔案, 允許與server 相同得zip 檔案
- [x] 以 COW 方式處理 tmpl 取代 copy qcow2 檔案，減少磁碟空間使用量與加快備份還原速度
- [x] client 要 loop 去等server ready//10 times
- [ ] 修復 arm64/riscv64 pipeline 失敗：Clonezilla 3.3.3-32 (forky/sid base) 移除 isc-dhcp-client，ocs_prerun 改為 `dhclient || true`，避免卡在 Press Enter。(待驗證)
- [ ] 等待 image_creation_complete 逾時或 server 異常死亡時，自動印出最新 server QEMU log 的最後 50 行，加速診斷。(待驗證)

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
- [x] 以 COW 方式處理 tmpl 取代 copy qcow2 檔案，減少磁碟空間使用量與加快備份還原速度

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
- [x] 修正 `qemu-clonezilla-ci-run.sh`，針對 `arm64` 架構，在 kernel append arguments 中指定 `console=ttyAMA0,38400n8` 以確保正常運作。
- [x] 支援 NVMe 裝置模擬 (`--disk-driver nvme`)，並可指定 logical/physical block size，用於 4Kn 等進階測試場景。
- [x] `qemu-clonezilla-ci-run.sh` 增加 `--efi` 選項，啟用 AMD64 EFI 開機支援。
- [x] `qemu-clonezilla-ci-run.sh` 增加 `--temp-dir` 選項，用於指定臨時檔案存放目錄，支援 UEFI VARS 檔案清理。
- [x] `qemu-clonezilla-ci-run.sh` 將 UEFI 相關的 `-pflash` 參數改為明確的 `-drive if=pflash,format=raw...` 語法。
- [ ] 修復 SC2199 與 PCI_BUS_NAME 自動調整邏輯：原區塊誤植於 `--disk-driver` 參數解析 case 內（且巢狀結構錯亂），已移出至架構 case 之後執行，`${arr[@]}` 改為 `${arr[*]}` 明確串接，並一併涵蓋 `EXTRA_QEMU_ARGS` 中的 q35 檢查。(待驗證)

## clonezilla-zip2qcow.sh 改進事項：
- [x] 1. 增加參數檢查機制，確保使用者輸入的參數是有效的。例如，檢查檔案是否存在，參數格式是否正確等。
- [x] 2. 增加--help 參數可以讓使用者查詢使用說明
- [x] 3. 參數改為長參數，例如
./clonezilla-zip2qcow.sh --zip clonezilla_image.zip --output outputdir/ --size 10G --force
- [x] 4. 在步驟 Copying Kernel/Initrd files to the target directory，檔案名稱prefix採用clonezilla zip 的base name 來命名，而不是固定用 vmlinuz 與 initrd.img
- [x] 自動下載最新的zip 檔案，當沒有指定 --zip 參數時，自動下載最新的 clonezilla zip 檔案，預設下載stable amd64 版本
- [x] 修改 `clonezilla-zip2qcow.sh` 中的自動下載邏輯，改用 `download-clonezilla.sh` 腳本，並支援 `--type` 參數。

## clonezilla-boot.sh 改進事項：
- [x] rename clonezilla-iso-boot.sh 為 clonezilla-boot.sh
- [x] 1. 增加參數檢查機制，確保使用者輸入的參數是有效的。例如，檢查檔案是否存在，參數格式是否正確等。
- [x] 2. 增加--help 參數可以讓使用者查詢使用說明
- [x] 3. 自動下載 clonezilla iso 檔案，當沒有指定 --iso 參數時，自動下載最新的 clonezilla iso 檔案，預設下載stable amd64 iso 版本
- [x] 增加參數 --zip 行為類似 qemu-clonezilla-ci-run.sh 的用 clonezilla-zip2qcow.sh , 自動解壓縮 zip 檔案取得 vmlinux, initrd.img, clonezilla-live-xxxx.qcow2, 並以qemu開機，用console 顯示。主要用來確認可以用clonezilla iso zip 開機就好，不需要額外指定append args 與 ocs cmd
- [x] --disk 換成optional 參數, 如果有指定就掛載qcow2 磁碟映像檔案, 沒有指定就不掛載
- [x] 修改 `clonezilla-boot.sh` 中的自動下載邏輯，改用 `download-clonezilla.sh` 腳本，並支援 `--type` 參數。
- [x] 修正 `clonezilla-boot.sh`，針對 `arm64` 架構，在 kernel append arguments 中指定 `console=ttyAMA0,38400n8` 以確保正常運作。

## clonezilla-download.sh
- [x] 自動下載 zip
- [x] type for debian / ubuntu basd
- [x] arch : amd64, arm64, riscv64
- [x] --all 下載所有zip
- [x] --all --fry-run 列出所有url
- [x] 找不到任何符合版本（mirror 目錄清空後正常狀態）改回傳獨立 exit code 3，與一般錯誤（exit 1：網路/參數/下載失敗）區分；usage.md 同步記載 exit codes。
- [x] 新增 amd64 `unstable` type（NCHC mirror `clonezilla-live/unstable/`）：download 腳本解析（版本目錄格式同 testing，`archived/` 由 regex 自然排除）、`--all` 組合、check-version usage、`.gitlab-ci.yml` `trigger:amd64-unstable` 手動 job，以及 GitLab schedule `unstable amd64`（cron `5 * * * *`，id 4450955）。mirror 無 `alternative/unstable/`，故無 alternative-unstable。
- [x] 修復 `--all --dry-run` 遇到任一 tree 為空（rc=3）會整個中斷的問題：改為跳過該組合並警告，其餘 URL 照常列出。

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
- [x] 支援 NVMe 裝置模擬 (`--disk-driver nvme`)，並可指定 logical/physical block size，用於 4Kn 等進階測試場景。
- [x] `validate.sh` 增加 `--efi` 選項，啟用 AMD64 EFI 開機支援。
- [x] `validate.sh` 增加 `--temp-dir` 選項，用於指定臨時檔案存放目錄，支援 UEFI VARS 檔案清理。
- [x] `validate.sh` 將 UEFI 相關的 `-pflash` 參數改為明確的 `-drive if=pflash,format=raw...` 語法。
---

## Ubuntu ZFS-on-root 測試（partclone.zfs）

- [x] `build-ubuntu-zfs-image.sh`：全自動建置 Ubuntu 24.04 ZFS-on-root golden image（subiquity autoinstall，免互動；kernel 直開 + NoCloud seed）。
- [x] autoinstall 模板 `dev/cloudinit/autoinstall-zfs/`（UEFI：EFI+/boot ext4+zpool；BIOS：bios_grub+/boot ext4+zpool；含 growpart 替代 fix、zpool cache 清理、serial console）。
- [x] `jobs/test_os_ubuntu_zfs.sh`：使用 `ubuntu-zfs` conf token 發現 image，版本 gate `3.3.4-20` / `20261030`（partclone.zfs 首次進 Live 的版本）。
- [x] `qemu/cloudimages/cloud_images.conf` 補兩行 PLACEHOLDER（uefi / bios），不影響現有 `ubuntu` 測試。
- [x] Dockerfile 補 `ovmf`（amd64 UEFI 建置/驗證需要）。
- [x] BIOS 變體額外開機驗證（curtin `bios_grub` flag 配置正確性；BIOS 還原開機測試通過）。
- [x] 確認 ocs-sr 對 `zfs_member` 分割區自動走 partclone.zfs（Live 20261111-tenacious：vda3 save/restore 皆 `partclone.zfs -a3`，非 dd fallback）。
- [x] 全流程驗證：`test_os_ubuntu_zfs.sh` + clonezilla-live-20261111-tenacious（UEFI+BIOS 兩 image savedisk→restoredisk(80G,-k1)→開機 OK）；舊 zip（3.3.2-16 / 20260403）正確 SKIP。
- [x] 已知陷阱修正：subiquity initramfs 無 IDE/ATA driver（ISO/seed 改掛 virtio-blk）；`updates: "none"` 遭 subiquity 拒絕（改 `security`）；libguestfs list-filesystems 不含 zfs_member（verify 改 `blkid` 逐分割區查 TYPE/LABEL）；smoke test 改 COW overlay 避免弄髒母碟（cloud-init instance-id 固定於 cidata）；`feature@large_dnodes` 遭 installer 環境拒絕（改回 ubiquity 官方 10-feature 清單，無 large_dnodes）。
- [x] 佈局改版：由 cmtops 文章自訂佈局（ext4 /boot + 單 pool）改為 **Ubuntu 官方 ZFS 佈局**（ESP + bpool 2G + swap 2G + rpool；bpool/BOOT/ubuntu、rpool/ROOT/ubuntu 沒有 zsys），涵蓋 GRUB-from-ZFS、雙 zfs_member、swap 還原。UEFI+BIOS 雙變體全流程通過（20261111-tenacious，vda2/vda4 皆 partclone.zfs）。
- [ ] 未來評估：arm64 變體（`qemu-system-aarch64` + QEMU_EFI.fd；TCG 建置慢，腳本保留 `--arch` 擴充點）。
- [ ] 未來評估：`jobs/test_fs_zfs.sh`（data fs 層級 ZFS 測試，需在 guest 內建 zpool，仿 LVM-thin 前例）。
- [ ] 未來評估：於 child-pipeline.yml 註冊 `test:os:ubuntu-zfs` job + publish needs + EXPECTED_TEST_JOBS（等 image 上線 `/data/cloudimages` 後）。

---

## Cloud image 集中化（image repo 架構）

PN42（producer）生產 image → 140.110.240.58（image repo, `cicd@140.110.240.58:3322:/home/cicd/clonezilla-cicd-cloudimages`）→ 各 test runner rsync/ssh pull。架構文件見 usage.md「qemu/cloudimages/ – 雲端映像庫與中央 repo」。

### Phase 1：conf schema v2 + 工具腳本（done, 2026-11-13）
- [x] `cloud_images.conf` schema v2：`OS RELEASE ARCH [FIRMWARE] URL [SHA256]`；檔名契約 `<OS>-<RELEASE>[-<FIRMWARE>]-<ARCH>.qcow2`（通用 image 不加 firmware；zfs/windows 加標）。
- [x] `qemu/cloudimages/image_common.sh`：conf 解析／契約檔名推導（`image_name_from_conf_line`）／prune 共用函式，jobs/common.sh 亦改 source 此檔。
- [x] `download_cloud_images.sh` 重寫：原子下載（`.part`→`mv`）、curl retry/resume、SHA256 驗證、`--check` / `--prune` / `--migrate` / `--yes`、`--force`。
- [x] `sync_images.sh` 新增：`--pull`（runner：對照 MANIFEST.sha256 抓缺漏/過期，`.part`+驗 sha）、`--push`（PN42：rsync 上傳＋遠端重建 MANIFEST.sha256/manifest.tsv）、`--prune`；env：`IMAGE_REPO_HOST`（預設 140.110.240.58）/`IMAGE_REPO_USER`（預設 cicd）/`IMAGE_REPO_DIR`（預設 /home/cicd/clonezilla-cicd-cloudimages）/`IMAGE_REPO_SSH_PORT`（預設 3322）。stub 端到端驗證（push/pull/up-to-date/missing/stale/prune）通過。
- [x] windows image 納入 conf（bios/uefi 兩行 MANUAL 條目）；guestfish 判定 `windows-11-amd64.qcow2`=BIOS、`win11-uefi.qcow2`=UEFI；本機已 `--migrate` 改名為 `windows-11-{bios,uefi}-amd64.qcow2`。
- [x] `test_os_windows.sh` 改為 conf 驅動（bios+uefi 皆測，uefi 檔名自動帶 `--efi`）；`test_os_{debian,ubuntu,fedora,ubuntu_zfs}.sh` 改用契約推導。
- [x] TODO: 注意 windows CI job 現在會連跑 bios+uefi 兩張碟，runner 時間約 2 倍（PN42 有 KVM 應可承受；超時再評估拆分 jobs）。

### Phase 0：repo server 部署（done, 2026-11-13）
- [x] 140.110.240.58 就位：`cicd` 帳號、ssh port 3322、影像目錄 `/home/cicd/clonezilla-cicd-cloudimages`。
- [x] runner 判別：PN42／類似機器 job 以 `gitlab-runner` 執行（`ps`+`builds/` 擁有者驗證）；F1 以 `u1597171` 執行。
- [x] ssh key 部署：三台（PN42、F1、vm-runner）皆有 `clonezilla-imgrepo` ssh config 別名，`ssh clonezilla-imgrepo` 可登入。
- [x] PN42 首次實測通過（2026-11-13）：`/data/cloudimages` chown 給 gitlab-runner + setgid；`--migrate` 改 bios 名；小 push（debian-13-amd64）→ 全量 push（14 張 ~20G，115MB/s）→ remote manifest 重建 → `--pull` 全部 up to date；zfs×2 與 windows-11-uefi 僅存於 debian-lab，如預期顯示 `not on repo yet; skipping`。
- [x] F1 多機取像驗證通過（2026-11-13）：`--migrate` 改 bios 名；`--pull` 偵測 10 張 daily 碟為 stale（兩機群版本漂移，sha256 錨點運作）並重抓、4 張 up to date、3 張 MANUAL skip；`--check` 全綠。
- [ ] （之後）nginx 唯讀 http :80 作為備援取用管道。
- [ ] repo 缺口補齊：`ubuntu-zfs-24.04-{uefi,bios}-amd64.qcow2` 與 `windows-11-uefi-amd64.qcow2` 目前在 debian-lab——補傳（debian-lab 加 ssh key 後 push）或由 PN42 重建（Phase 2/3）。
- [ ] （延後）ssh 強化：test runner key 加 `command="rrsync -ro /home/cicd/clonezilla-cicd-cloudimages"` 唯讀限制（本輪先不鎖）；前置：先將 `--push` 的 manifest 重建從裸 `ssh "cd ... && sha256sum ..."` 改為 **producer 本機產生後隨檔推送**（純 rsync 檔案寫入），之後 PN42 key 也能鎖，server 零 shell。

### Phase 2：CI 接線（done, 2026-11-13；排程建立與驗證待做）
- [x] `.gitlab-ci.yml` 新增 `images:sync`（PN42，tags `clonezilla, windows`）：`--check` → `download_cloud_images.sh`（支援 `IMAGE_SYNC_FORCE=true` 全量重抓）→ `sync_images.sh --push --yes`；schedule `IMAGE_SYNC=true` 時自動跑，web/api 可手動觸發。（待建 GitLab Schedules：daily `IMAGE_SYNC=true`、weekly 加 `IMAGE_SYNC_FORCE=true`）（待驗證）
- [x] 新增 `images:build:zfs`（manual、`allow_failure: true`）：`build-ubuntu-zfs-image.sh --firmware both --output /data/cloudimages` → push。驗證穩定後再考慮週期化。（待驗證）
- [x] `child-pipeline.yml` before_script 自動 `--pull`：共享影像目錄可寫（`/data/cloudimages` 或 F1 fallback）且 `MISSING>0` 才拉（1200s timeout），stale 碟不在 job 內更新（避免 I/O 風暴），失敗退回警告；`IMAGE_PULL=false` 停用。（待驗證）
- [ ] windows 手動匯入流程 runbook（usage.md 補章節；含 checksum 登錄）。

### Phase 3：zfs 測試上線（等 image 上 repo）
- [ ] 解除原 todo: 於 child-pipeline.yml 註冊 `test:os:ubuntu-zfs` job + publish needs + EXPECTED_TEST_JOBS。
