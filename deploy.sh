#!/usr/bin/env bash
# PC 端部署脚本（Git Bash，仓库根目录运行）：把模块推送到手机并执行设备安装
# 前提：adb 已连接，且已在 KernelSU 里手动获取 root
set -euo pipefail
cd "$(dirname "$0")"

[ -d module/files ] || { echo "module/ 不存在，先运行 ./build.sh"; exit 1; }

adb wait-for-device
adb shell "su -c 'id'" >/dev/null 2>&1 || { echo "root 不可用，请先在 KernelSU 里手动获取 root"; exit 1; }

echo "== 推送模块文件"
adb shell "rm -rf /data/local/tmp/kbo; mkdir -p /data/local/tmp/kbo"
adb push ./module/files ./module/module.prop ./module/service.sh ./deploy-device.sh //data/local/tmp/kbo/ >/dev/null

echo "== 设备端安装（结束后会热重启，屏幕会闪一下）"
adb shell "su -c 'sh /data/local/tmp/kbo/deploy-device.sh'"

adb shell "rm -rf /data/local/tmp/kbo"
echo "完成。验证: adb shell \"dumpsys window displays | grep 'navigationBars frame'\" 应为 [0,0][0,0]"
