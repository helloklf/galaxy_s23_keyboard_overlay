#!/system/bin/sh
# 标准 KernelSU/Magisk 模块 service.sh
# 越狱模式下：手动获取 root 后由 KSU 自动执行，随后 KSU 自动热重启使 overlay 生效
MODDIR=${0%/*}
mount --bind $MODDIR/product_overlay /product/overlay
mount --bind $MODDIR/preinstalled-packages-platform-overlays.xml /product/etc/sysconfig/preinstalled-packages-platform-overlays.xml
mount --bind $MODDIR/allowed-system-preload-apps.xml /system/etc/sysconfig/allowed-system-preload-apps.xml

# 自愈：确保关键状态（曾经因为 overlay 暂时丢失被系统清掉过启用状态）
cmd overlay enable com.android.internal.systemui.navbar.gestural
settings put global navigation_bar_gesture_hint 0
