# FOLDLIGHT 无尽生存：折叠三角洲

## 目标

在 2.0 的“收纳弹幕—追踪返航—持续变强”底子上，增加一个独立、可长期扩展的无尽模式。地图是固定手工关卡，不在运行时随机拼地形；随机性只影响刷怪批次和任务起点，而且所有结果都能由种子复现。

核心节奏有三条彼此独立的进度线：

1. 存活时间只推动敌人进化（密度、生命、弹量、队长比例）。
2. 累计真实吸收的弹幕只推动玩家的“折光进化”。
3. 地图任务提供另一组任务进化选择，不伪造吸收数量，也不提前敌人阶段。

## 场景树

```text
EndlessSurvivalController (Node2D)
├── HandcraftedMap (Node2D)
├── EvolutionDirector (Node)
└── ObjectiveDirector (Node)

EndlessSurvivalSlice (Node2D)
└── Controller (EndlessSurvivalController instance)
    └── SliceRuntime 由根节点驱动的轻量玩家、敌人和弹幕适配层
```

`endless_survival_controller.tscn` 是正式集成入口；`endless_survival_slice.tscn` 是无需主菜单即可启动的可玩垂直切片。

## 节点职责

| 节点 | 单一职责 |
|---|---|
| `FoldlightEndlessHandcraftedMap` | 呈现固定地图、建立墙体碰撞、提供手工刷新位和墙体绕行查询 |
| `FoldlightEndlessEvolutionDirector` | 分别累计存活时间、吸收弹幕和已选择任务进化 |
| `FoldlightEndlessObjectiveDirector` | 按“占点→队长→旗帜”轮换任务并生成奖励选择 |
| `FoldlightEndlessSurvivalController` | 对外 API、刷怪节拍、信号转发和完整快照 |
| `FoldlightEndlessSliceRuntime` | 仅用于独立试玩；把控制器协议接到轻量战斗表现上 |

## 信号图

| 信号 | 来源 | 消费者 | 载荷 |
|---|---|---|---|
| `enemy_wave_requested` | Controller | 主战斗运行时 | 兼容 2.0 敌人 ID 的批次字典 |
| `enemy_evolution_changed` | Evolution | Controller/主 HUD | 阶段与倍率快照 |
| `player_evolution_changed` | Evolution | Controller/玩家构筑 | 吸收阶段与累计奖励快照 |
| `objective_started` | Objective | Controller/主 HUD | 目标、位置、进度和自然语言说明 |
| `mission_reward_offered` | Controller | 主奖励 UI | 三选一任务进化 |
| `mission_reward_claimed` | Controller | 玩家构筑 | 已应用奖励与总加成 |

## 数据流

```text
主会话 start_run(seed)
  -> 固定地图载入（不随机生成地形）
  -> ObjectiveDirector 开启首个任务
  -> 每帧 advance_simulation(delta, player_position)
       -> survival_seconds 跨阈值 -> 敌人进化
       -> spawn_clock 到点 -> enemy_wave_requested
       -> 占点距离/任务计时更新

主战斗捕获弹幕
  -> report_projectiles_absorbed(real_count)
  -> absorbed_total 跨独立阈值
  -> player_evolution_changed

击杀队长 / 摧毁旗帜 / 完成占点
  -> objective_completed
  -> mission_reward_offered
  -> claim_mission_reward(id)
  -> mission_modifiers 更新（不改变时间轴与吸收轴）
```

## 手工地图合同

- 世界尺寸 `6144 × 4096`，玩家出生在中央偏南的折光港。
- 六个命名分区：折光港、破礁西岸、静潮花园、日轮广场、沉钟档案馆、回声南渠。
- 28 组固定墙体/礁体形成掩护、通道、环形据点和侧翼路线。
- 3 个占点、4 面旗帜、6 个队长位、10 个中央火力位、16 个外围近战位。
- `find_cover_route()` 返回绕开固定墙体的短折线路径；墙壁既能挡敌弹，也不会让返航弹持续攻击墙面。

## 对主会话的最小集成 API

```gdscript
controller.enter_mode(seed, player)
controller.advance_simulation(delta, player.global_position)
controller.report_projectiles_absorbed(count)
controller.report_captain_defeated(captain_id)
controller.report_flag_damage(flag_id, damage)
controller.report_flag_destroyed(flag_id)
controller.claim_mission_reward(reward_id)
controller.get_snapshot()
controller.exit_mode(&"return_to_title")
```

安全切换约定：主场景可以长期挂载控制器场景。它在非激活状态自动隐藏，也不会推进计时；进入时调用 `enter_mode(seed, player)`，退出时先让现有战斗 runtime 清理无尽模式生成的实体，再调用 `exit_mode()`。后者会断开外部玩家引用、清空未选择的任务奖励、隐藏大地图并发出 `run_stopped`，不会修改主菜单或经典模式的状态。

主战斗监听 `enemy_wave_requested(request)`，按 `request.entries` 使用现有 `FoldlightRogueEnemyFactory` 生成敌人。条目沿用 2.0 的 `drifter / fan / ram / bloomer / weaver / leech / mirror / rewinder`，系统不复制这些敌人的行为代码。

## 验证门槛

- 地图合同证明地图固定、足够大且包含全部任务设施与掩护。
- 时间跨阈值不会改变吸收总数或玩家吸收阶段。
- 吸收跨阈值不会改变敌人时间阶段。
- 三类任务能连续轮换，每类都能发放合法的三选一奖励。
- 刷怪请求只使用 2.0 敌人 ID，射手优先使用中央火力位。
- 两个 endless 场景可在 Godot 4.6 headless 环境加载和运行。
