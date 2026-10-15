# KeyboardOverlay — 三星 Android 16 (One UI 8) 键盘贴底 + 隐藏手势提示线

设备：SM-S9110 (Galaxy S23 国行)，Android 16，KernelSU 越狱模式（重启后 root 失效，需手动获取）。

目标：
1. 去掉手势导航下键盘底部的抬高（键盘贴近屏幕底边）
2. 隐藏手势提示线（小横条）

约束：不能改系统分区，只能用 root + `mount --bind` 等方式。

## 最终方案

用 RRO（Runtime Resource Overlay）APK，通过 bind mount 注入 `/product/overlay`，并 bind mount 两个白名单 XML 让三星 PMS 接受注册。全部文件在设备 `/data/adb/modules/keyboardoverlay/`（仅作存储，越狱模式 KernelSU 不会自动挂载模块）。

四个 overlay 包（源码在同名目录，编译产物在 `dist/`）：

| 包名 | 目标 | 作用 |
|---|---|---|
| `com.keyboardoverlay.kbd` | `android` | `navigation_bar_*` / `navigation_bar_gesture_*` 高度全部归零（含 gesture_larger_height） |
| `com.keyboardoverlay.pill` | `com.android.systemui` | `navigation_handle_radius` / `navigation_home_handle_width` / `navigation_handle_bottom` 归零，隐藏小横条 |
| `com.android.internal.systemui.navbar.gestural` | `android` | **替换**系统自带的 NavigationBarModeGestural overlay：所有值与原版一致，仅把 `navigation_bar_height`、`navigation_bar_height_landscape`、`navigation_bar_frame_height` 改为 0dp；`navigation_bar_gesture_height` 保留 20dp |
| `com.android.internal.systemui.navbar.gestural_no_hint` | `android` | 同上，替换 NoHint 变体（防止设置里切换手势提示开关后高度复活） |

**注意：`navigation_bar_gesture_height` 不能归零**——它是底部上滑手势的触摸感应区高度，归 0 后上滑回桌面完全失效。三星官方 NoHint overlay 的写法就是 `navigation_bar_height=0`（贴底）+ `gesture_height=20dp`（保留触摸区），我们照抄这个组合。kbd 包里的 `navigation_bar_gesture_larger_height` 同理保留 20dp（category 内启用的 gestural overlay 优先级是 INT_MAX，`gesture_height` 以它为准，kbd 里那项 0dp 实际不生效）。

另外顺手执行了 `settings put global navigation_bar_gesture_hint 0`（三星自带的"手势提示"开关，持久保存在系统设置里）。

## 关键坑（三星 + Android 16 特有）

1. **FRRO 在 Android 16 被封**：`cmd overlay fabricate` 只允许注入 int/bool/color（dataType 0x10–0x1F），dimen (0x05) 报 `dataType is out of range`。HideNavBar 模块在 Android 12+ 用的 FRRO 方案在 16 上不可用，必须编译真正的 RRO APK。
2. **越狱模式 KernelSU 不做 magic mount**：`/data/adb/modules/<id>/system/` 不会挂载到系统，只能手动 bind mount。`/product` 是独立 erofs 分区（`/system/product` 是指向它的符号链接），只读，无法直接创建文件。
3. **三星 PMS 有 overlay 白名单**：`/product/overlay` 里的新 APK 即使被扫描到，也会报 `Package is not in allowed list : <包名>` 而拒绝注册。白名单是 `/system/etc/sysconfig/allowed-system-preload-apps.xml`（注意不是 `preinstalled-packages-platform-overlays.xml`，那个加了没用，但为保险也加了）。把包名以 `<allowed-system-preload package="..."/>` 格式加入即可。
4. **互斥 category 的优先级碾压**：处于启用状态的导航模式 overlay（category `com.android.internal.navigation_bar_mode`）在 OverlayManager 里优先级是 `Integer.MAX_VALUE`，任何普通 overlay（priority 最多几百）都无法覆盖它定义的 `navigation_bar_height` 等资源。唯一办法是**同包名替换它的 APK**——启用状态按包名记在 overlays.xml 里，替换后自动保持启用并保持最高优先级。
5. **SELinux 上下文**：bind mount 源文件必须 `chcon u:object_r:system_file:s0`，否则 system_server 读不到。
6. **目录可执行位**：`/product/overlay` 下的 overlay 很多在**子目录**里（如 NavigationBarModeGestural/）。对合并目录递归 `chmod -R 644` 会把目录的 +x 剥掉，非 root 进程无法穿越目录 → 子目录里的 overlay 全部静默消失（症状：只有顶层 APK 注册成功）。必须目录 755 / 文件 644，用 `find -type d/-type f` 分开处理。
7. **toybox 不是 GNU coreutils**：Android 上的 `head` 不支持 `-n -1`（删最后一行），要用 `sed '$d'`。写错会把白名单 XML 截断成残件，PMS 读到残件会引发整机重启（本方案因此自我验证过：挂载不持久，崩了自动回原生，无变砖风险）。
8. **生效方式**：静态 overlay 由 PackageManager 在 system_server 启动时扫描注册，所以每次改完需要热重启：`su -c 'setprop ctl.restart zygote'`（不需要完整重启）。另外 overlay 包一旦在某次开机时"不存在"，OMS 会把它在 overlays.xml 里的启用状态清掉，所以 service.sh 里要幂等地 `cmd overlay enable` 自愈。

## 设备端部署结构

```
/data/adb/modules/keyboardoverlay/               # 标准 KernelSU 模块
├── module.prop                                  # 模块元信息
├── service.sh                                   # 三条 mount --bind + 自愈（enable gestural overlay、隐藏手势提示设置）；获取 root 后由 KSU 自动执行
├── product_overlay/                             # /product/overlay 的完整合并副本，bind mount 到 /product/overlay
│   ├── ...（原有全部文件）
│   ├── KbdOverlay/KbdOverlay.apk                # 键盘高度归零
│   ├── PillOverlay/PillOverlay.apk              # 隐藏小横条
│   ├── NavigationBarModeGestural/NavigationBarModeGesturalOverlay.apk        # 已替换
│   └── NavigationBarModeGesturalNoHint/NavigationBarModeGesturalNoHintOverlay.apk  # 已替换
├── preinstalled-packages-platform-overlays.xml  # bind mount 到 /product/etc/sysconfig/ 同名文件
└── allowed-system-preload-apps.xml              # bind mount 到 /system/etc/sysconfig/ 同名文件
```

## 一键构建与部署

```bash
./build.sh     # 编译 4 个 overlay -> dist/，组装 module/ 并打包 keyboardoverlay-module.zip
./deploy.sh    # 推送到手机并安装（需 adb 连接 + 已手动获取 root），装完自动热重启
```

仓库结构：

```
build.sh           # PC 端：一键编译 + 打包
deploy.sh          # PC 端：adb 推送 + 调用设备端安装器（不进模块包）
deploy-device.sh   # 设备端安装器，由 deploy.sh 推送到 /data/local/tmp 执行（不进模块包）
module/            # 纯模块包：module.prop + service.sh + files/（就是 zip 的内容）
kbd/ pill/ gestural/ gestural_nohint/   # 四个 overlay 的源码
dist/              # 编译产物
```

- `build.sh`：aapt2 编译 + zipalign + apksigner（密钥 `overlay.jks`，没有会自动生成），可用 `SDK_DIR` 环境变量覆盖 SDK 路径
- `deploy-device.sh`（设备端）：卸载旧挂载 → 从当前系统重新复制 `/product/overlay` 生成合并目录（OTA 后也安全）→ 安装 4 个 APK → 动态给两个白名单 XML 打补丁（幂等，基于设备当前文件生成，不会用过期副本）→ 安装 `module.prop` / `service.sh` → 修 SELinux 上下文和权限 → 本次手动执行一次 `service.sh` 并热重启立即可见效果

## 每次完全重启后

无需任何手动操作。越狱模式下重启后 root 和 bind mount 都会消失（系统完全恢复原样，无变砖风险）；在 KernelSU 里手动获取 root 后，KSU 会自动执行模块的 `service.sh` 完成三条 bind mount，并自动热重启让 PMS 重新扫描 overlay。

## 验证命令

```
cmd overlay list android                 # 应看到 [x] com.keyboardoverlay.kbd 和 [x] ...navbar.gestural
cmd overlay list com.android.systemui    # 应看到 [x] com.keyboardoverlay.pill
dumpsys window displays | grep "navigationBars frame"   # 应为 frame=[0,0][0,0]
```

## 手动重新构建（调数值时）

改对应目录下 `res/values/dimens.xml` 后跑 `./build.sh` 即可；想手动单编一个：

```bash
AAPT2=/d/Android/SDK/build-tools/36.0.0/aapt2.exe
BT=/d/Android/SDK/build-tools/36.0.0

$AAPT2 compile --dir <源码目录>/res -o out.zip
$AAPT2 link -o unsigned.apk -I /d/Android/SDK/platforms/android-36/android.jar \
    --manifest <源码目录>/AndroidManifest.xml out.zip
$BT/zipalign.exe -f 4 unsigned.apk aligned.apk
$BT/apksigner.bat sign --ks overlay.jks --ks-pass pass:android \
    --ks-key-alias overlay --key-pass pass:android --out dist/<名字>.apk aligned.apk
```

签名密钥是本目录的 `overlay.jks`（密码 `android`）；分区 overlay 对签名无要求，随便签。

推送替换（以 gestural 为例）：

```bash
adb push dist/GesturalOverlay.apk //data/local/tmp/
adb shell "su -c '
cp /data/local/tmp/GesturalOverlay.apk /data/adb/modules/keyboardoverlay/product_overlay/NavigationBarModeGestural/NavigationBarModeGesturalOverlay.apk
chcon u:object_r:system_file:s0 /data/adb/modules/keyboardoverlay/product_overlay/NavigationBarModeGestural/NavigationBarModeGesturalOverlay.apk
setprop ctl.restart zygote'"
```

## 卸载 / 回滚

重启手机即可完全恢复原样（bind mount 不持久）。想永久移除：删掉 `/data/adb/modules/keyboardoverlay/`，并恢复手势提示设置 `settings put global navigation_bar_gesture_hint 1`。

## 备注

- 如果键盘底部仍有一条小区域，那是输入法自身的 padding（如三星键盘的工具条、Gboard 的 `ro.com.google.ime.kb_pad_port_b` 属性），与系统 overlay 无关。
- 三星设置里的导航模式/手势提示开关会切换 `gestural` / `gestural_no_hint` overlay，两个都已替换为零高度版本；但 `sec_gestural` 系列（三星备用 overlay）未动，目前未被启用。
- 三星键盘"隐藏键盘按钮"由 `settings get global navigation_bar_button_to_hide_keyboard` 控制（当前为 1）。
