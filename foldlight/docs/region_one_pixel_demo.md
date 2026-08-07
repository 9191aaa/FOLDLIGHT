# 区域一高密度像素 Demo

这是与正式战斗隔离的美术演示，用来审阅 FOLDLIGHT「纸礁浅海」的原创高密度像素方向。它借鉴参考图的像素簇、材质层次和俯视可读性，不复刻参考图的题材、物件或布局。

## 地形复现方案

运行时不使用普通房/Boss 房整张截图，而是由三份共享素材实时组成：

- `res://assets/demos/pixel/paper_reef_water_tile.png`：共享水面底图，保持原始比例作居中裁切。
- `res://assets/demos/pixel/paper_reef_terrain_atlas.png`：3×2 地形图集，包含岛礁、浅滩、遗迹、治疗池、危险珊瑚和湿地。
- `res://assets/demos/pixel/paper_reef_actor_atlas.png`：3×2 角色图集，包含玩家、炮塔、灯蟹、苇卫、针舟和 Boss。

普通房和 Boss 房复用同一套六块地形，只改变模块的位置、尺寸和组合顺序。这能直接验证该风格可以扩展到更多房间，而不是只能成立于一张概念图。两张完整概念图只保存在 `artifacts/concepts/pixel_hd/` 供美术对照，不参与运行和导出。

## 操作

- `A` / 左方向键 / 手柄左：普通房。
- `D` / 右方向键 / 手柄右：Boss 房。
- `E` / 空格 / 回车 / 手柄确认键：切换房间。
- `Esc` / 手柄 B 或 Start：退出。
- 无操作时每 9 秒自动轮播；手动选择后停止轮播。

## 运行与导出

直接运行场景：

```powershell
G:\godot\Godot_v4.6.3-stable_win64.exe --path G:\777888\gmae\foldlight res://scenes/demos/region_one_pixel_demo.tscn
```

导出独立 Windows Demo：

```powershell
G:\godot\Godot_v4.6.3-stable_win64_console.exe --headless --path G:\777888\gmae\foldlight --export-release "Pixel Demo Windows"
```

专用导出使用 `pixel_demo` feature，主场景会直接切到 `region_one_pixel_demo.tscn`；正式 Windows preset 不携带该 feature。Demo 只创建窗口，不修改系统显示模式。

## 验证

```powershell
G:\godot\Godot_v4.6.3-stable_win64_console.exe --headless --path G:\777888\gmae\foldlight --script res://tests/integration/test_region_one_pixel_demo.gd
G:\godot\Godot_v4.6.3-stable_win64_console.exe --headless --path G:\777888\gmae\foldlight --script res://tests/integration/test_pixel_demo_hd_art_2_0.gd
```

截图脚本：

```powershell
G:\godot\Godot_v4.6.3-stable_win64_console.exe --path G:\777888\gmae\foldlight --windowed --resolution 1280x720 --script res://tools/capture_region_one_pixel_demo.gd
```
