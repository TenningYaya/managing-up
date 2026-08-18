shader_type canvas_item;

// 像素风圆角：把四角按【贴图自身的像素网格】切掉，圆角边缘是方块台阶而不是抗锯齿的平滑弧线，
// 和像素美术的硬边风格统一。（若想要平滑抗锯齿的圆角，用 resume_cards.gdshader 那个即可。）
//
// 与 resume_cards.gdshader 的区别：
//   · 那个用 fwidth(UV) 取【屏幕】像素尺寸 → 半径按屏幕像素算、边缘 smoothstep 抗锯齿
//   · 本shader 用 TEXTURE_PIXEL_SIZE 取【贴图】像素尺寸 → 半径按美术像素算、硬切不羽化，
//     贴图放大几倍，圆角台阶也跟着放大几倍，始终是整齐的像素块

// 圆角半径，单位 = 贴图的像素（不是屏幕像素）。比如贴图 32x32、半径 4 = 切掉 4 个美术像素
uniform float corner_radius : hint_range(0.0, 64.0, 1.0) = 4.0;

// 描边：沿圆角矩形边缘【向内】画一圈，单位同样是贴图像素。0 = 不描边（默认关闭）。
// 画在形状内侧而不是外侧，这样不会被节点矩形裁掉。悬停时由脚本把宽度调上去。
uniform float outline_width : hint_range(0.0, 16.0, 1.0) = 0.0;
uniform vec4 outline_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void fragment() {
	// 1. 贴图的原始像素尺寸（TEXTURE_PIXEL_SIZE = 1/尺寸，取倒数还原）
	vec2 tex_size = vec2(1.0) / TEXTURE_PIXEL_SIZE;

	// 2. 当前点在贴图里的像素坐标，并对齐到像素中心（floor + 0.5）。
	//    这一步是"像素感"的关键：同一个美术像素内的所有采样点算出同样的结果，
	//    于是要么整块保留、要么整块切掉，绝不会出现半透明的过渡像素。
	vec2 pixel_pos = floor(UV * tex_size) + 0.5;

	// 3. 半径夹取：不能超过短边的一半，否则形状会翻转出错
	float r = min(corner_radius, min(tex_size.x, tex_size.y) * 0.5);

	// 4. 圆角矩形的有向距离场（SDF）：dist > 0 = 在圆角之外
	vec2 half_size = tex_size * 0.5;
	vec2 q = abs(pixel_pos - half_size) - half_size + r;
	float dist = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - r;

	// 5. 硬切：不做 smoothstep，圆角外的整个像素直接透明
	float mask = dist <= 0.0 ? 1.0 : 0.0;

	vec4 tex_color = texture(TEXTURE, UV);
	vec3 rgb = tex_color.rgb;
	float a = tex_color.a;

	// 6. 描边：距离边缘 outline_width 以内的像素换成描边色（同样是硬边，无羽化）
	if (outline_width > 0.0 && dist > -outline_width) {
		rgb = outline_color.rgb;
		a = outline_color.a;
	}

	COLOR = vec4(rgb, a * mask);
}
