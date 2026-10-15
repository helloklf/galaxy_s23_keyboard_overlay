#!/system/bin/sh
# Magisk/KernelSU 刷入时自动执行的安装脚本（MODPATH 由安装器提供）
# 作用：生成 /product/overlay 合并目录、给白名单 XML 打补丁、修权限和 SELinux 上下文

# 兼容没有 ui_print 的环境
command -v ui_print >/dev/null 2>&1 || ui_print() { echo "$1"; }

# 需要解压 files/ 里的 APK
SKIPUNZIP=0

ui_print "-- 清理历史模块（旧 id）"
rm -rf /data/adb/modules/keyboardoverlay

ui_print "-- 生成 /product/overlay 合并目录"
mkdir -p "$MODPATH/product_overlay"
cp -a /product/overlay/* "$MODPATH/product_overlay/"

ui_print "-- 安装 overlay APK"
mkdir -p "$MODPATH/product_overlay/KbdOverlay" \
         "$MODPATH/product_overlay/PillOverlay"
cp "$MODPATH/files/KbdOverlay/KbdOverlay.apk"   "$MODPATH/product_overlay/KbdOverlay/"
cp "$MODPATH/files/PillOverlay/PillOverlay.apk" "$MODPATH/product_overlay/PillOverlay/"
cp "$MODPATH/files/NavigationBarModeGestural/NavigationBarModeGesturalOverlay.apk" \
   "$MODPATH/product_overlay/NavigationBarModeGestural/NavigationBarModeGesturalOverlay.apk"
cp "$MODPATH/files/NavigationBarModeGesturalNoHint/NavigationBarModeGesturalNoHintOverlay.apk" \
   "$MODPATH/product_overlay/NavigationBarModeGesturalNoHint/NavigationBarModeGesturalNoHintOverlay.apk"
rm -rf "$MODPATH/files"

ui_print "-- 给白名单 XML 打补丁"
# allowed-system-preload-apps.xml（三星 PMS overlay 白名单，真正生效的那个）
if grep -q 'com.keyboardoverlay.kbd' /system/etc/sysconfig/allowed-system-preload-apps.xml; then
    cp /system/etc/sysconfig/allowed-system-preload-apps.xml "$MODPATH/allowed-system-preload-apps.xml"
else
    sed '$d' /system/etc/sysconfig/allowed-system-preload-apps.xml > "$MODPATH/allowed-system-preload-apps.xml"
    cat >> "$MODPATH/allowed-system-preload-apps.xml" <<'EOF'
    <allowed-system-preload package="com.keyboardoverlay.kbd"/>
    <allowed-system-preload package="com.keyboardoverlay.pill"/>
</config>
EOF
fi
# preinstalled-packages-platform-overlays.xml（保险起见也加）
if grep -q 'com.keyboardoverlay.kbd' /product/etc/sysconfig/preinstalled-packages-platform-overlays.xml; then
    cp /product/etc/sysconfig/preinstalled-packages-platform-overlays.xml "$MODPATH/preinstalled-packages-platform-overlays.xml"
else
    sed '$d' /product/etc/sysconfig/preinstalled-packages-platform-overlays.xml > "$MODPATH/preinstalled-packages-platform-overlays.xml"
    cat >> "$MODPATH/preinstalled-packages-platform-overlays.xml" <<'EOF'
    <install-in-user-type package="com.keyboardoverlay.kbd">
        <install-in user-type="FULL" />
    </install-in-user-type>
    <install-in-user-type package="com.keyboardoverlay.pill">
        <install-in user-type="FULL" />
    </install-in-user-type>
</config>
EOF
fi

ui_print "-- 修正权限和 SELinux 上下文"
find "$MODPATH/product_overlay" -type d -exec chmod 755 {} +
find "$MODPATH/product_overlay" -type f -exec chmod 644 {} +
chmod 644 "$MODPATH"/*.xml "$MODPATH/module.prop"
chmod 755 "$MODPATH/service.sh"
chcon -R u:object_r:system_file:s0 "$MODPATH/product_overlay" "$MODPATH"/*.xml

ui_print "-- 隐藏手势提示（三星自带开关）"
settings put global navigation_bar_gesture_hint 0

ui_print "-- 完成！重新获取 root（或重启）后生效"
