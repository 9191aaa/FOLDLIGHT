# Android 构建与验证

Android 与 Windows、网页使用相同游戏场景、任务和战斗规则。原生 Android 启动即使用手机布局，横屏运行；触摸安全区先扣除 16:9 画面的黑边，再移动界面和操作区。系统返回键进入原有返回/暂停流程，不直接退出游戏。单人模式切后台暂停；好友竞赛仍遵守服务端断线与计时规则。

导出预设 `Android` 生成已签名 APK，应用 ID 为 `org.papersea.foldlight`，包含 ARMv7、ARM64 和 x86_64。Godot 4.6.3 官方模板的实际清单为最低 API 24（Android 7），目标 API 36；需要 OpenGL ES 3 支持。x86_64 用于验证同一安装包，不单独交付不同规则的测试版本。

## 本机构建

构建工具放在忽略目录 `build/toolchain/`，包括官方 JDK 17、Android SDK command-line tools、platform-tools、build-tools 35.0.1、platforms/android-35。导出使用 Godot 4.6.3 官方 Android release 模板，不需要 Gradle、NDK 或额外插件。

在项目目录运行：

```powershell
pwsh -File tools/export_android.ps1 -OutputPath build/releases/FOLDLIGHT_Android_3.11.0.apk
```

脚本在隔离的 Godot 编辑器设置中配置工具路径，签名导出并执行 `apksigner verify`。它只在本机缺少签名时生成发布密钥；密码用 Windows 当前用户的 DPAPI 加密保存在 `build/signing/`。整个目录已被 Git 忽略，不能放进 APK、网站资源或公开压缩包。以后更新必须保留同一密钥，否则 Android 无法覆盖安装并保留存档。备份时应保留密钥和受保护密码，跨 Windows 账号迁移需要先在原账号安全导出密码。

## 验证边界

运行 `tests/integration/test_android_safe_area.gd`、已有手机操作/布局测试，再导出正式 APK。检查签名、包名、架构与权限，并将同一 APK 安装到 API 35 Android 模拟器验证启动、触摸、系统返回和前后台恢复。模拟器通过不能替代真实手机的性能、发热、厂商系统和移动网络测试。

2026-10-17 验证了正式 APK 的中文标题、手机战斗 HUD、任务指引、触摸摇杆、返回键暂停、结束航行二次确认，以及切后台后恢复原局并暂停。实际软键盘可输入，联机入口和房间码会滚动至键盘上方，返回键先收起键盘并保留大厅。好友竞赛先使用本机同一 HTTP 服务验证，再通过腾讯海外预览入口执行公网测试：最终 Android APK 与 Windows Godot 引擎加载正式导出的 PCK，完成建房、双方准备、同种子开局、状态同步和弃赛结算。该测试没有覆盖所有大陆运营商或真实手机；Windows 一侧使用原生引擎加载导出包的自动操作脚本，不冒充人工操作 EXE。结算停留超过 30 秒后不应误报断线，有针对性回归和实际 APK 验证覆盖。

本机模拟器使用 API 35 x86_64、WHPX 和 host GLES。SDK/AVD 所在路径包含中文时，模拟器的文件解析失败；验证时用临时 ASCII 盘符映射构建目录解决。SwiftShader 的 GLES uniform 限制会使 Godot 画布着色器失败，应使用 host GLES；这不等于正式 APK 自身闪退。测试完成后停止模拟器并解除临时盘符，不改变用户的系统虚拟化配置。

模拟器即使配置 `hw.keyboard=no`，仍可能枚举内建 AT 键盘。Godot 检测到硬键盘时按设计不弹软键盘；测试需在模拟器内临时解绑该虚拟硬键盘，不能通过改游戏代码强行显示键盘来掩盖测试环境差异。
