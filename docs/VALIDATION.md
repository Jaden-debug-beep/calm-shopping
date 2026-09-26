# 第一版验证记录

日期：2026-09-26。

- `flutter analyze --no-pub`：No issues found。
- `flutter test --no-pub`：13 项通过。预览截图用例默认跳过，单独运行通过。
- 手机尺寸 390 × 844 的首页及添加页截图已人工查看。
- `flutter build apk --release`：成功，约 52.2 MB。
- `apksigner verify --verbose`：签名验证通过，v2 签名。
- `aapt dump badging`：应用名购物冷静清单，包名 app.calmshopping.personal，版本 0.1.0；最低 Android API 24（Android 7.0），包含 arm64-v8a、armeabi-v7a、x86_64。
- 合并后的 release manifest：没有 INTERNET、CAMERA 或广泛相册读取权限；关闭 Android 自动备份。

交付 APK：`dist/calm-shopping-0.1.0.apk`。

SHA-256：`DD13E33F52B124CF591919D333D8CD6F8C67EF594CEE7C46525A27CF14FBAEF6`。

## 实际验证边界

构建使用 release 编译与本机 debug 签名，供个人试用，不是应用商店正式发布包。

没有连接 Android 真机或模拟器。真机首次启动、系统相册选图、系统文件保存/恢复、退出重启仍需设备验证；Hive 数据重开和业务交互已通过自动测试。

Windows 环境准备记录：项目和 SDK 使用英文路径别名，安装完整 Temurin JDK 17，并禁用 Kotlin 的跨盘增量缓存；Android SDK 首次补齐 platform 36、NDK 和 CMake。没有修改全局 PATH。
