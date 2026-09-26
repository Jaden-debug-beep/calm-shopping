# iPhone 版构建说明

当前 iOS 工程沿用 Flutter 3.47.5 的标准模板，最低支持 iOS 15。应用显示名为“冷静购物”，包标识暂定 `app.calmshopping.personal`，版本号从 `pubspec.yaml` 读取。仓库中的 `.github/workflows/ios.yml` 会在 GitHub 的 macOS 运行器上生成未签名的 iPhone 构建产物，可用于检查苹果端编译是否通过。未签名文件不能直接安装到 iPhone。

购物清单、月度统计和本地 Hive 数据与 Android 共用同一份 Dart 代码。相册选图使用系统照片选择器；完整备份通过系统“文件”界面导出和导入 JSON。图片仅保存在本机账本与用户主动导出的备份中。iOS 的系统设备备份行为仍取决于用户的设备设置。

## 在 Mac 上运行

安装当前稳定版 Flutter、Xcode 和 CocoaPods。打开终端，进入项目目录：

```sh
flutter pub get
flutter run -d <iPhone或模拟器ID>
```

第一次在自己的 iPhone 上运行时，在 Xcode 打开 `ios/Runner.xcworkspace`，选择 Runner target，设置自己的 Team 与签名。若 `app.calmshopping.personal` 已被占用，改为自己 Apple 开发团队可用的唯一 Bundle Identifier。模拟器不需要真实设备签名。

通过 Xcode 完成设备签名后，可以运行 `flutter build ipa` 生成正式归档。将应用发给其他人之前，还需要相应的 Apple 分发资格、签名和 TestFlight 或 App Store 配置。

## 需要在 iPhone 上检查

1. 首次打开、新增和编辑记录、退出后重开数据是否仍在。
2. 从相册选择商品图片，拒绝权限后能否正常继续使用。
3. 导出包含图片的备份到“文件”，再导入并确认覆盖。
4. 日期选择、月报、跨月处理及小屏幕布局。

Windows 不能运行 Xcode，因此本机无法生成经苹果签名、可直接安装到 iPhone 的 IPA，也无法代替真机验证。
