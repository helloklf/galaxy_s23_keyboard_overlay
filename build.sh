#!/usr/bin/env bash
# 一键编译 4 个 overlay APK 并打包模块（Git Bash 下运行）
# 用法: ./build.sh            编译 + 打包 module/ 和 keyboardoverlay-module.zip
# 环境变量: SDK_DIR 可覆盖 SDK 路径（默认 /d/Android/SDK）
set -euo pipefail
cd "$(dirname "$0")"

SDK_DIR="${SDK_DIR:-/d/Android/SDK}"
BT="$SDK_DIR/build-tools/36.0.0"
PLATFORM="$SDK_DIR/platforms/android-36/android.jar"
KS=overlay.jks
KSPASS=android

for f in "$BT/aapt2.exe" "$BT/zipalign.exe" "$BT/apksigner.bat" "$PLATFORM"; do
    [ -f "$f" ] || { echo "缺少文件: $f （可用 SDK_DIR 环境变量指定 SDK 路径）"; exit 1; }
done

if [ ! -f "$KS" ]; then
    echo "== 生成签名密钥 $KS"
    keytool -genkeypair -keystore "$KS" -alias overlay -keyalg RSA -keysize 2048 \
        -validity 10000 -storepass "$KSPASS" -keypass "$KSPASS" -dname "CN=Overlay"
fi

# 源码目录 -> 输出 APK 名 -> 模块内路径
build_one() {
    local src="$1" apk="$2"
    echo "== 编译 $src -> dist/$apk"
    "$BT/aapt2.exe" compile --dir "$src/res" -o "dist/$src.zip"
    "$BT/aapt2.exe" link -o "dist/$src-unsigned.apk" -I "$PLATFORM" \
        --manifest "$src/AndroidManifest.xml" "dist/$src.zip"
    "$BT/zipalign.exe" -f 4 "dist/$src-unsigned.apk" "dist/$src-aligned.apk"
    "$BT/apksigner.bat" sign --ks "$KS" --ks-pass pass:$KSPASS \
        --ks-key-alias overlay --key-pass pass:$KSPASS \
        --out "dist/$apk" "dist/$src-aligned.apk"
    rm -f "dist/$src.zip" "dist/$src-unsigned.apk" "dist/$src-aligned.apk" "dist/$apk.idsig"
}

mkdir -p dist
build_one kbd             KbdOverlay.apk
build_one pill            PillOverlay.apk
build_one gestural        GesturalOverlay.apk
build_one gestural_nohint GesturalNoHintOverlay.apk

echo "== 组装 module/（纯模块内容：module.prop + service.sh + files/）"
PKG=module
rm -rf "$PKG" keyboardoverlay-module.zip
mkdir -p "$PKG/files/KbdOverlay" \
         "$PKG/files/PillOverlay" \
         "$PKG/files/NavigationBarModeGestural" \
         "$PKG/files/NavigationBarModeGesturalNoHint"
cp dist/KbdOverlay.apk             "$PKG/files/KbdOverlay/"
cp dist/PillOverlay.apk            "$PKG/files/PillOverlay/"
cp dist/GesturalOverlay.apk        "$PKG/files/NavigationBarModeGestural/NavigationBarModeGesturalOverlay.apk"
cp dist/GesturalNoHintOverlay.apk  "$PKG/files/NavigationBarModeGesturalNoHint/NavigationBarModeGesturalNoHintOverlay.apk"
cp module.prop service.sh "$PKG/"

echo "== 打包 keyboardoverlay-module.zip"
powershell -NoProfile -Command "Compress-Archive -Path '$PKG/*' -DestinationPath keyboardoverlay-module.zip -Force"

echo "完成: dist/ 四个 APK + keyboardoverlay-module.zip"
echo "部署到手机: ./deploy.sh   （需要已连 adb 且已手动获取 root）"
