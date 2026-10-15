#!/system/bin/sh
# 设备端安装脚本（root 运行）：重建 /product/overlay 合并目录、打白名单补丁、安装标准模块文件
# 由 PC 端 deploy.sh 推送到 /data/local/tmp/kbo/ 后执行；也可用于 OTA 后重装
PKG=/data/local/tmp/kbo
MODID=$(grep -m1 '^id=' "$PKG/module.prop" | cut -d= -f2 | tr -d ' \r')
MOD=/data/adb/modules/${MODID:-s23_keyboardoverlay}

echo "-- 清理历史模块（旧 id）"
[ "$MODID" != "keyboardoverlay" ] && rm -rf /data/adb/modules/keyboardoverlay

echo "-- 卸载旧的 bind mount（忽略错误）"
umount -l /product/overlay 2>/dev/null
umount -l /product/etc/sysconfig/preinstalled-packages-platform-overlays.xml 2>/dev/null
umount -l /system/etc/sysconfig/allowed-system-preload-apps.xml 2>/dev/null

echo "-- 重建合并目录 $MOD/product_overlay"
mkdir -p "$MOD"
rm -rf "$MOD/product_overlay"
mkdir -p "$MOD/product_overlay"
cp -a /product/overlay/* "$MOD/product_overlay/"

echo "-- 安装 overlay APK"
mkdir -p "$MOD/product_overlay/KbdOverlay" \
         "$MOD/product_overlay/PillOverlay"
cp "$PKG/files/KbdOverlay/KbdOverlay.apk"            "$MOD/product_overlay/KbdOverlay/"
cp "$PKG/files/PillOverlay/PillOverlay.apk"          "$MOD/product_overlay/PillOverlay/"
cp "$PKG/files/NavigationBarModeGestural/NavigationBarModeGesturalOverlay.apk" \
   "$MOD/product_overlay/NavigationBarModeGestural/NavigationBarModeGesturalOverlay.apk"
cp "$PKG/files/NavigationBarModeGesturalNoHint/NavigationBarModeGesturalNoHintOverlay.apk" \
   "$MOD/product_overlay/NavigationBarModeGesturalNoHint/NavigationBarModeGesturalNoHintOverlay.apk"

echo "-- 生成打过补丁的白名单 XML"
# allowed-system-preload-apps.xml（三星 PMS overlay 白名单，真正生效的那个）
if grep -q 'com.keyboardoverlay.kbd' /system/etc/sysconfig/allowed-system-preload-apps.xml; then
    cp /system/etc/sysconfig/allowed-system-preload-apps.xml "$MOD/allowed-system-preload-apps.xml"
else
    sed '$d' /system/etc/sysconfig/allowed-system-preload-apps.xml > "$MOD/allowed-system-preload-apps.xml"
    cat >> "$MOD/allowed-system-preload-apps.xml" <<'EOF'
    <allowed-system-preload package="com.keyboardoverlay.kbd"/>
    <allowed-system-preload package="com.keyboardoverlay.pill"/>
</config>
EOF
fi
# preinstalled-packages-platform-overlays.xml（保险起见也加）
if grep -q 'com.keyboardoverlay.kbd' /product/etc/sysconfig/preinstalled-packages-platform-overlays.xml; then
    cp /product/etc/sysconfig/preinstalled-packages-platform-overlays.xml "$MOD/preinstalled-packages-platform-overlays.xml"
else
    sed '$d' /product/etc/sysconfig/preinstalled-packages-platform-overlays.xml > "$MOD/preinstalled-packages-platform-overlays.xml"
    cat >> "$MOD/preinstalled-packages-platform-overlays.xml" <<'EOF'
    <install-in-user-type package="com.keyboardoverlay.kbd">
        <install-in user-type="FULL" />
    </install-in-user-type>
    <install-in-user-type package="com.keyboardoverlay.pill">
        <install-in user-type="FULL" />
    </install-in-user-type>
</config>
EOF
fi

echo "-- 安装模块文件"
cp "$PKG/module.prop" "$PKG/service.sh" "$MOD/"
chmod 644 "$MOD/module.prop"
chmod 755 "$MOD/service.sh"

echo "-- 修正权限和 SELinux 上下文"
find "$MOD/product_overlay" -type d -exec chmod 755 {} +
find "$MOD/product_overlay" -type f -exec chmod 644 {} +
chmod 644 "$MOD"/*.xml
chcon -R u:object_r:system_file:s0 "$MOD/product_overlay" "$MOD"/*.xml

echo "-- 隐藏手势提示设置（三星自带开关，持久保存）"
settings put global navigation_bar_gesture_hint 0

echo "-- 本次立即生效：执行一次 service.sh 并热重启（以后由 KSU 自动完成）"
sh "$MOD/service.sh"
setprop ctl.restart zygote
