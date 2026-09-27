# 0.1.4 更新说明

- 点顶部日历按钮或月份文字可选日期，清单和月报按所选日期的月份显示；左右箭头仍可逐月切换。
- 选择其他月份后，消费概览、消费上限和月报标题显示对应月份，不再误称“本月”。历史月报不再混入当前月待处理计划。
- 新增或补记往月记录后，清单自动切换到该记录所在月份。
- 修改已消费记录时，实付金额会带出原值；新记录仍不会把预计价格当成实付金额。
- 应用图标保持原版。

验证：`flutter analyze --no-pub` 无问题；`flutter test --no-pub` 通过；Android 通用、ARM64、ARM32 release APK 构建通过。与 0.1.3 使用相同的应用 ID 与签名，可覆盖安装。

| 安装包 | SHA-256 |
| --- | --- |
| `calm-shopping-0.1.4-arm64.apk` | `EA0D606D8D06DA3353E2D31E9314A6994BFC8CA497D758E1CE74E3EAFCBE67A4` |
| `calm-shopping-0.1.4-arm32.apk` | `EE9FAB5EC44A7E33B085A82CBB839E9D031F33AD24B3D938C6093AE31EC88894` |
| `calm-shopping-0.1.4.apk` | `21292932F13FC2309ACAEE0279FA8AD7CCB42838C8414A4B31CAFDE9DAF434D7` |
