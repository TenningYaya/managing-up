shader_type canvas_item;
render_mode blend_add;

// 室内"开灯"的光层。加法混合：只会提亮，不会像 modulate 那样把颜色弄脏。
//
// 衰减写在 shader 里而不是靠贴图，这样挂在 ColorRect 上也有层次，不挑节点类型。
//
// 【光心 light_center】决定光从哪儿最浓，纵向 0 = 贴着窗户，1 = 贴着地板：
//     0.00  顶部最亮 —— 像窗外打进来的光（白天用）
//     0.45  中段最亮 —— 桌子和人所在的高度最亮，窗边和地板都暗（夜里开灯，推荐）
//     1.00  底部最亮 —— 像地灯
// 配 light_reach 控制光摊多开。两个一起调，基本能凑出任何"灯在哪"的感觉。
//
// 其余参数由 DayNight 单例每帧写入：
//   light_color = 灯的颜色（偏暖 = 白炽灯）
//   strength    = 光心处叠多少，0 = 关灯
//   compensate  = 1 / CanvasModulate 的颜色，把"天黑"对光层的压暗除掉，
//                 否则越黑越看不见灯，等于白开

uniform vec4 light_color : source_color = vec4(1.0, 0.82, 0.55, 1.0);
uniform float strength : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform float light_center : hint_range(0.0, 1.0, 0.01) = 0.45;
uniform float light_reach : hint_range(0.05, 2.0, 0.05) = 0.75;
uniform float falloff : hint_range(0.2, 6.0, 0.1) = 1.8;
uniform float edge_softness : hint_range(0.0, 0.5, 0.01) = 0.12;
uniform vec3 compensate = vec3(1.0);

void fragment() {
	// 纵向：离光心越远越淡
	float d = abs(UV.y - light_center) / max(light_reach, 0.001);
	float t = pow(clamp(1.0 - d, 0.0, 1.0), falloff);

	// 横向：左右边缘收一下，不然光层的两条竖边会是硬切口
	if (edge_softness > 0.001) {
		t *= smoothstep(0.0, edge_softness, min(UV.x, 1.0 - UV.x));
	}

	COLOR = vec4(light_color.rgb * compensate, t * strength);
}
