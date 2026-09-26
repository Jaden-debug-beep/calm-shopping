# GitHub 复用记录

上游：[erdipakrana/expense_app](https://github.com/erdipakrana/expense_app)

基准提交：`28a7334ce5701cfc79f5c781992fbe012260e0ca`。原作者 Dipak Rana，MIT 许可证，完整保留于根目录 LICENSE，并打包到应用许可页。

这是从上游仓库克隆后裁剪、改造的分支。原始 Dart 源码和测试保存在 `upstream_reference/`，不参与编译和静态检查，方便追溯；原说明保存在 `docs/UPSTREAM_README.md`。

## 实际复用

| 上游代码 | 本版本处理 |
| --- | --- |
| Android Flutter 工程、Gradle 包装器及平台启动代码 | 保留；精简 flavor，修改应用标识、图标和显示名，移除识别相关权限 |
| `lib/core/theme/app_theme.dart` | 保留 Material 3 主题、卡片和输入框样式，换为绿色与米色 |
| `lib/core/constants/app_colors.dart`、`app_text_styles.dart` | 调整配色，使用系统字体，移除在线字体请求 |
| `lib/features/transactions/presentation/widgets/month_selector.dart` | 复用月份导航布局，改为中文文案和回调参数 |
| `lib/core/utils/date_utils_extension.dart` | 提取日期键、月份键、按日期分组排序，解除实际交易接口依赖 |
| `lib/features/expenses/data/local/expense_local_data_source.dart` | 复用 Hive 初始化和等待写入的模式，改为完整账本快照；取消上游遇到错误就删库的恢复逻辑 |

继续使用上游已经采用的 Hive、image_picker、uuid；使用 file_picker 的系统文件选择与保存能力做完整备份。没有自行实现图片选择器或文件浏览器。

## 按本产品新增的部分

计划与实际的独立金额、整数分存储、月度计划快照、跨月保留、不买历史、买后备注、手动完整备份及校验、购物清单和月报页面、业务测试。这些与上游记账模型不同，不能直接把收入/支出页面改名替代。

移除运行依赖：OCR、分享导入、Google Fonts、联网检查、生物识别、后台任务、收入、转账、银行账户等。没有登录、服务器或自动图片识别。

## 当前取舍

适合个人少量大额计划。照片压缩到最长边约 1600 像素后随快照保存，备份也包含照片。单图限制 8 MB，账本/备份限制 50 MB，记录数量上限 5000。大量照片场景应改成独立附件存储和增量备份。

备份是明文 JSON，请用户自行选择保管位置。Android 自动云备份关闭。测试 APK 使用本机调试签名，发布应用商店前需要独立正式签名和设备兼容性验证。
