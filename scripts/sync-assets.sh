#!/bin/sh
# 把 assets/ 里的图片和字体同步到 iOS 演示包里。
# 网页版直接读 assets/，iOS 的 .swiftpm 包需要自己带一份资源，所以换图后跑一下这个脚本。
set -e
cd "$(dirname "$0")/.."
DEST=ios/FridgeDemo.swiftpm/Sources/Resources
mkdir -p "$DEST/Fridge/stickers" "$DEST/Fonts"
cp assets/fridge/*.png "$DEST/Fridge/"
cp assets/stickers/*.png "$DEST/Fridge/stickers/"
cp assets/fonts/* "$DEST/Fonts/"
echo "已同步到 $DEST"
