# FOLDLIGHT · 折光

收下光，再还回去。一款以**迷航肉鸽**为主线的纸海弹幕游戏。

![重构版主菜单](screenshots/refactor_title.png)

## 统一的纸海

当前分支是 `3.10.0-dev` 重构预览。自动武器负责开火；你负责移动、冲刺、按住折域收纳弹幕，再松开返光。黑芯金边弹不可反射。

| 入口 | 内容 |
| --- | --- |
| 开始／继续迷航 | 分支房间、局内强化与区域首领；首次进入附操作教学 |
| 故事航路 | 原有三章十二航战役与潮界检查点 |
| 无尽挑战 | 开放纸海、生存进化与任务奖励 |

三个入口共用深海墨、纸白、折光青与旧金的视觉语言。标题纸蛾、玩家、纸礁与灯台采用程序化矢量绘制。像素 Demo 保留在独立场景和导出预设中。

## 运行与构建

使用 **Godot 4.6.3** 打开 `foldlight/project.godot`，按 F5 运行项目，或使用命令行：

```powershell
godot --path ./foldlight
godot --headless --path ./foldlight --export-release "Windows Desktop"
```

Windows 输出为 `foldlight/build/FOLDLIGHT_Refactor_Windows/FOLDLIGHT.exe`。预览导出使用独立的 `FOLDLIGHT Refactor Preview` 存档目录，可与已有版本共存。需要对应版本的导出模板；构建产物不提交到 Git。

## 操作

| 动作 | 键盘 | 手柄 |
| --- | --- | --- |
| 移动 | WASD／方向键 | 左摇杆／十字键 |
| 收纳／返光 | 按住／松开空格或 E | 按住／松开 A |
| 冲刺 | Shift | B |
| 主动道具 | Q | X |
| 暂停／继续 | Esc | Start |

无尽暂停后可继续同一局，或主动结束挑战。故事地图／结算按 Esc 返回主菜单；战斗中先暂停，再按 C／LB 返回，保留最近的潮界存档。

## 开发与验证

```powershell
./foldlight/tools/check_refactor.ps1 -GodotPath 'C:/path/to/godot.exe'
# 扫描全部历史集成测试，包含独立 Demo
./foldlight/tools/check_refactor.ps1 -GodotPath 'C:/path/to/godot.exe' -All
```

每个测试使用独立用户数据目录，不接触玩家存档。日志在 `foldlight/build/refactor-checks/`。

主要职责边界：

- `scripts/ui/foldlight_theme.gd`：共享颜色、字体、控件样式。
- `scripts/roguelite/ui/rogue_title_screen.gd`：主菜单构图与动作信号。
- `scripts/roguelite/rogue_session_controller.gd`：迷航流程与存档协调。
- `scripts/visuals/paper_art.gd`：共用纸蛾和纸海绘制。
- `scripts/campaign/story_content_catalog.gd`：故事文案、教义和敌人说明。
- `scripts/game.gd`：既有故事战斗及与统一主菜单的交接。
- `scripts/endless/endless_slice_runtime.gd`：无尽模式适配，共用玩家和战斗组件。

范围与验证说明见 [重构记录](foldlight/docs/godot-prompter/plans/unified_refactor.md)。修改请提交分支和 PR。MIT 许可证见 [LICENSE](LICENSE)。
