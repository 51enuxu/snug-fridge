# FridgeDemo (iOS)

SwiftUI 复古冰箱 demo，Swift Playgrounds「App」包格式，iOS 17+。

## 运行
- Xcode: 直接打开 `FridgeDemo.swiftpm`，选模拟器/真机运行。
- iPad Swift Playgrounds: 把 `FridgeDemo.swiftpm` 拷到 iPad 的 Files，点开即可。
- 命令行:
  `cd ios/FridgeDemo.swiftpm && xcodebuild -scheme FridgeDemo -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath ../../.build-ios build`

## 存储与同步
- 默认纯本机 (UserDefaults)，首次打开是示例冰箱。
- 右上角齿轮 -> 填服务器地址 + token (Bearer) 就同步到 `../server`：每次改动先 GET 最新 -> 套上改动 -> PUT。留空 = 关闭同步。
- 模拟器访问本机服务用 `http://127.0.0.1:8787`；真机用电脑局域网 IP。HTTP 明文在 iOS 上需 ATS 例外，正式使用请走 HTTPS。

## 其它
- 字体: 站酷快乐体 (OFL) 与「我爱万伟伟手写体」随包，启动时用 CTFontManager 注册；文楷拿不到时退回系统字体。
- Debug 构建可用环境变量 `FRIDGE_DEMO_SCENE=open | zone:chillMid | note | magnets | magnets:spread` 直接进入某个画面（截图用）。
