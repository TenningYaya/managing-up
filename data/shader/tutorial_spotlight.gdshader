shader_type canvas_item;

// 新手教程聚光罩：一张全屏遮罩上挖一个【圆角 + 柔边】的洞，并在洞口外缘加一圈会呼吸的光晕。
// 取代原先"四块 ColorRect 拼一个方洞"的做法：
//   · 圆角柔边，不再是生硬的直角方孔
//   · 洞的位置/尺寸是 uniform，可以 tween，切换目标时平滑滑过去而不是瞬间跳
//   · 单张全屏矩形，没有四块布之间的拼缝亮线问题
// ⚠️ 只负责"看"，不负责"点"。命中判定仍由 tutorial_blocker.gd 的 hole_rect 矩形决定。

uniform vec2 rect_size = vec2(1920.0, 1080.0);   // 本节点的像素尺寸（脚本按视口大小写入）
uniform vec2 hole_position = vec2(0.0);          // 洞的左上角（与 hole_rect 同一坐标系）
uniform vec2 hole_size = vec2(0.0);              // 洞的尺寸；接近 0 = 不挖洞，全屏遮死
uniform float corner_radius : hint_range(0.0, 128.0, 1.0) = 18.0;
uniform float edge_softness : hint_range(0.0, 120.0, 1.0) = 26.0;   // 柔边过渡宽度（像素）

uniform vec4 mask_color : source_color = vec4(0.0, 0.0, 0.0, 0.5);  // 幕布颜色
uniform vec4 glow_color : source_color = vec4(1.0, 0.93, 0.65, 1.0); // 洞口光晕颜色
uniform float glow_width : hint_range(0.0, 120.0, 1.0) = 30.0;       // 光晕向外扩散的宽度
uniform float glow_strength : hint_range(0.0, 2.0, 0.05) = 0.55;     // 光晕最大亮度
uniform float pulse_speed : hint_range(0.0, 8.0, 0.1) = 0.0;         // 呼吸速度；0 = 静态不闪

void fragment() {
	// 尺寸为 0 时不挖洞：整屏遮死（对应教程里传空矩形的情况）
	if (hole_size.x < 1.0 || hole_size.y < 1.0) {
		COLOR = mask_color;
	} else {
		vec2 p = UV * rect_size;

		// 圆角矩形有向距离场：d < 0 在洞内，d > 0 在洞外，d ≈ 0 正好在洞口边缘
		vec2 half_size = hole_size * 0.5;
		float r = min(corner_radius, min(half_size.x, half_size.y));
		vec2 q = abs(p - (hole_position + half_size)) - half_size + r;
		float d = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - r;

		// 柔边：洞内 0（全透）→ 洞外 1（全遮），中间平滑过渡
		float cover = smoothstep(-edge_softness, edge_softness, d);

		// 光晕：只画在洞外，紧贴洞口最亮，向外衰减；再叠一层正弦呼吸
		float glow = (1.0 - smoothstep(0.0, max(glow_width, 0.001), d)) * step(0.0, d);
		float pulse = pulse_speed > 0.0 ? (0.65 + 0.35 * sin(TIME * pulse_speed)) : 1.0;
		glow *= glow_strength * pulse;

		// 先铺幕布，再把光晕叠加上去（叠加混合，所以是"提亮"而不是"盖住"）
		vec3 rgb = mix(glow_color.rgb, mask_color.rgb, cover);
		float a = mask_color.a * cover + glow * glow_color.a;
		COLOR = vec4(rgb, clamp(a, 0.0, 1.0));
	}
}
