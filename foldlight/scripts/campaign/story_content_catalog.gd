class_name FoldlightStoryContentCatalog
extends Resource

## Authored story-mode content. This catalog has no scene-tree dependency;
## runtime controllers own progression and consume fresh presentation snapshots.
## Doctrine resources are shared, read-only definitions; stacks live in the run.

const DOCTRINE_LIBRARY: Array[FoldDoctrine] = [
	preload("res://resources/doctrines/wide_crease.tres"),
	preload("res://resources/doctrines/deep_breath.tres"),
	preload("res://resources/doctrines/lantern_pocket.tres"),
	preload("res://resources/doctrines/still_water.tres"),
	preload("res://resources/doctrines/bright_edge.tres"),
	preload("res://resources/doctrines/swift_return.tres"),
	preload("res://resources/doctrines/chain_bloom.tres"),
	preload("res://resources/doctrines/full_moon.tres"),
	preload("res://resources/doctrines/paper_heart.tres"),
	preload("res://resources/doctrines/slipstream.tres"),
	preload("res://resources/doctrines/mercy_blank.tres"),
	preload("res://resources/doctrines/golden_seam.tres"),
	preload("res://resources/doctrines/quiet_horizon.tres"),
	preload("res://resources/doctrines/ocean_fold.tres"),
	preload("res://resources/doctrines/sunward.tres"),
	preload("res://resources/doctrines/starfall.tres"),
	preload("res://resources/doctrines/afterglow.tres"),
	preload("res://resources/doctrines/dawn_vow.tres"),
]
const DOCTRINE_PATHS: Array = [
	[&"wide_crease", &"deep_breath", &"still_water", &"lantern_pocket", &"quiet_horizon", &"ocean_fold"],
	[&"swift_return", &"bright_edge", &"chain_bloom", &"full_moon", &"sunward", &"starfall"],
	[&"slipstream", &"paper_heart", &"mercy_blank", &"golden_seam", &"afterglow", &"dawn_vow"],
]
const PATH_NAMES: Array[String] = ["折域技艺", "返光技艺", "灯身技艺"]
const NEXT_TIDE_THREATS: Array[String] = [
	"", "基础潮线", "横风与墨覆", "回声与逆折域", "汲光与复合减益", "蓄力冲角与赤轮", "四秒回迹与百折混潮", "墨月三相",
]

const ACT_NAMES: Array[String] = ["", "静水", "纸鸢", "回声", "风眼", "赤轮", "倒流", "墨月"]
const ACT_TITLES: Array[String] = ["", "潮之一 · 静水", "潮之二 · 纸鸢", "潮之三 · 回声", "潮之四 · 风眼", "潮之五 · 赤轮", "潮之六 · 倒流", "终潮 · 墨月"]
const ACT_SUBTITLES: Array[String] = [
	"", "移动 · 按住 · 松开", "迎着扇面去折", "追着旋涡的空隙", "夜色也是你的弹药", "看清金线再横移", "四秒之前也会追上你", "把整轮月亮折回来"
]
const ACT_SCENE_TAGS: Array[String] = [
	"", "镜海微澜", "纸鸢横风", "回声花庭", "无灯风眼", "赤轮苇原", "倒流回廊", "墨月裂相"
]
const ACT_OBJECTIVES: Array[String] = [
	"", "收纳直线花瓣，练习返光", "穿过扇面边缘，辨认封钉", "错开环潮，等青环闭合", "保住折息，逐项洗净墨痕", "看清冲线，横移后收下撞墙震波", "不要贪站位，记住自己四秒前的路径", "读月相裂变，折回整片夜潮"
]

const STORY_BEATS: Dictionary = {
	1: {"id": &"c1_departure", "eyebrow": "第一章 · 残灯渡海", "speaker": "引灯人 · 岑", "title": "纸海没有太阳了", "body": "墨月吞走沿岸的名字，只剩未寄出的灯火漂在潮里。你要做的不是躲开它们——是把它们送回去。"},
	3: {"id": &"c1_echo", "eyebrow": "航行记录 · 回声花庭", "speaker": "折灯人 · 你", "title": "每一枚光都有来处", "body": "花庭里的弹幕正在模仿旧日灯讯。收下它们时，你听见整座港口在纸背面呼吸。"},
	5: {"id": &"c1_red_wheel", "eyebrow": "航行记录 · 赤轮苇原", "speaker": "潮使", "title": "潮水开始记住你的路", "body": "它们不再只追逐此刻。冲角会封住去路，而更深处的东西正沿四秒前的折痕倒流。"},
	7: {"id": &"c1_ink_moon", "eyebrow": "第一章 · 终幕", "speaker": "引灯人 · 岑", "title": "把夜色也折回来", "body": "墨月不是天体，是无数未能返航的愿望。折碎它，让第一束天光重新拥有方向。"},
}


static func enemy_tip(enemy_id: StringName, glyph: int, mission: FoldMissionDefinition = null) -> Dictionary:
	match enemy_id:
		&"drifter":
			return {"id": &"drifter", "eyebrow": "潮兽图鉴 01 / 游移", "title": "漂灯", "body": "缓慢追踪并发射直线花瓣", "counter": "保持移动 · 迎面折走", "accent": Color(0.52, 0.84, 0.82), "glyph": glyph}
		&"fan":
			return {"id": &"fan", "eyebrow": "潮兽图鉴 02 / 扇射", "title": "棱翼", "body": "保持距离，展开五枚扇形花瓣", "counter": "穿过扇缘 · 或迎面收纳", "accent": Color(0.88, 0.36, 0.64), "glyph": glyph}
		&"weaver":
			return {"id": &"weaver", "eyebrow": "潮兽图鉴 03 / 技能", "title": "织潮者", "body": "紫针施加墨覆；蓄力钉下黑金封钉", "counter": "满蓄返还洗净 · 封钉只能躲", "accent": Color(0.68, 0.48, 0.96), "glyph": glyph, "duration": 6.8}
		&"ram":
			return {"id": &"ram", "eyebrow": "潮兽图鉴 04 / 冲撞", "title": "冲角", "body": "金线锁定后沿直线贯穿；冲出后不再转向", "counter": "等导线定向 · 横移一步 · 回身返光", "accent": Color(0.95, 0.36, 0.57), "glyph": glyph}
		&"bloomer":
			return {"id": &"bloomer", "eyebrow": "潮兽图鉴 05 / 环潮", "title": "回声花", "body": "驻留花庭，周期释放整圈慢弹", "counter": "靠近开折 · 一次收下整圈", "accent": Color(0.72, 0.42, 0.91), "glyph": glyph}
		&"leech":
			return {"id": &"leech", "eyebrow": "潮兽图鉴 06 / 汲取", "title": "汲光者", "body": "近身抽走折息，并留下湿墨", "counter": "拉开距离 · 返还 6 光洗净", "accent": Color(0.34, 0.86, 0.84), "glyph": glyph}
		&"mirror":
			return {"id": &"mirror", "eyebrow": "潮兽图鉴 07 / 反制", "title": "逆折者", "body": "青环展开时截获返光并储存", "counter": "先收不放 · 等青环闭合再返还", "accent": Color(0.25, 0.88, 0.84), "glyph": glyph, "duration": 6.8}
		&"rewinder":
			return {"id": &"rewinder", "eyebrow": "潮兽图鉴 08 / 回迹", "title": "回痕兽", "body": "点亮最近四秒的旧路，再沿旧路高速倒冲", "counter": "旧路亮起立即离轨 · 冲完回身返光", "accent": Color(0.96, 0.46, 0.30), "glyph": glyph, "duration": 7.2}
		&"carver":
			return {"id": &"carver", "eyebrow": "潮兽图鉴 09 / 刻线", "title": "刻潮者", "body": "停驻预告后，在纸面刻出短时危险折线", "counter": "看见蓝线就换边 · 线散后贴近收弹", "accent": Color(0.36, 0.70, 0.96), "glyph": glyph, "duration": 6.8}
		&"bell":
			return {"id": &"bell", "eyebrow": "潮兽图鉴 10 / 引潮", "title": "引潮铃", "body": "敲响时牵动附近花瓣，重排成旋转弹带", "counter": "跟着钟弧走半圈 · 收下密集带", "accent": Color(0.82, 0.48, 0.96), "glyph": glyph, "duration": 6.8}
		&"thief":
			return {"id": &"thief", "eyebrow": "潮兽图鉴 11 / 逃逸", "title": "盗名舟", "body": "携带名字横穿战场，只会被返光稳定击破", "counter": "先收弹再追船 · 击破会爆出弹药环", "accent": Color(1.0, 0.63, 0.28), "glyph": glyph, "duration": 6.8}
		&"moth":
			return {"id": &"moth", "eyebrow": "潮兽图鉴 12 / 复唱", "title": "回声蛾", "body": "记住你上一轮返光数量，再复唱同量慢弹", "counter": "上一轮放得越爽 · 下一轮收得越满", "accent": Color(0.44, 0.90, 0.76), "glyph": glyph, "duration": 6.8}
		&"herald":
			return {"id": &"herald", "eyebrow": "潮关 / 本潮终局", "title": "潮使", "body": "驱散杂潮，以高速花瓣守住潮核", "counter": "折返弹幕 · 击破潮核进入下一潮", "accent": Color(1.0, 0.67, 0.28), "glyph": glyph}
		&"boss":
			return {"id": mission.boss_id if mission != null else &"ink_moon", "eyebrow": "终潮 / 多相潮核", "title": mission.boss_title if mission != null else "墨月", "body": "血量降低时裂相并重写弹幕节奏", "counter": "裂相会清场 · 借空窗重新站位", "accent": mission.accent if mission != null else Color(0.96, 0.24, 0.54), "glyph": glyph, "duration": 7.2}
		_:
			return {}



static func effect_tip(effect_id: StringName) -> Dictionary:
	match effect_id:
		&"wet_ink":
			return {"eyebrow": "墨痕 / 折息受阻", "title": "湿墨", "body": "折息恢复速度降低 45%", "counter": "返还 6 光即可洗净", "accent": Color(0.30, 0.78, 0.88), "glyph": 0}
		&"bound_crease":
			return {"eyebrow": "墨痕 / 行动受限", "title": "缚折", "body": "移动速度降低 30%", "counter": "返还 3 光即可挣脱", "accent": Color(0.94, 0.42, 0.56), "glyph": 1}
		&"veiled_fold":
			return {"eyebrow": "墨痕 / 折域受限", "title": "墨覆", "body": "折域最大半径缩小 28%", "counter": "蓄满后返还即可洗去", "accent": Color(0.62, 0.42, 0.90), "glyph": 2}
		&"paper_seal":
			return {"eyebrow": "特殊弹幕 / 黑金十字", "title": "封钉", "body": "穿过折域，不会成为返光弹药", "counter": "折域仍会减速 · 立刻走位避开", "accent": Color(1.0, 0.45, 0.16), "glyph": 3, "duration": 6.4}
		&"crosswind":
			return {"eyebrow": "场景效果 / 纸鸢横风", "title": "横风", "body": "场上敌弹持续向东偏移", "counter": "沿风向预留半个身位", "accent": Color(0.42, 0.66, 0.94), "glyph": 4}
		&"lights_out":
			return {"eyebrow": "场景效果 / 无灯时刻", "title": "风眼熄灯", "body": "纸海压暗，冲角从边缘突入", "counter": "跟随金色导线 · 保留折息", "accent": Color(0.96, 0.32, 0.54), "glyph": 5}
		_:
			return {}

