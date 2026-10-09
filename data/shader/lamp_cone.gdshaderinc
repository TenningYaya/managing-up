// 吊顶灯的【形状计算】，被 ceiling_lamp（乘法层）和 ceiling_lamp_add（加法层）共用。
//
// 两层必须用完全相同的几何，否则光锥的暗边和亮边会错开一截。
// 所以参数和算法只写一份放在这儿，两个 shader 都 #include 它。
//
// 输出：
//   hits = 这个点被几盏灯照到（0 / 1 / 2…）
//   tube = 是不是落在灯管本体上（0 或 1）

uniform float amount : hint_range(0.0, 1.0, 0.01) = 0.0;  // 0=白天无效果，1=全效果

uniform int lamp_count : hint_range(1, 6) = 2;
uniform float lamp_y : hint_range(-1.0, 1.0, 0.01) = 0.03;      // 灯管高度（0=参考矩形上沿）
uniform float lamp_half_w : hint_range(0.02, 0.5, 0.01) = 0.22; // 灯管半长
uniform float spread : hint_range(0.0, 1.0, 0.01) = 0.16;       // 梯形往下张开多少。0 = 直筒
uniform float cone_len : hint_range(0.1, 20.0, 0.05) = 1.0;     // 光打多远
uniform float tube_h : hint_range(0.0, 0.1, 0.002) = 0.02;      // 灯管半厚
uniform float lamp_pitch : hint_range(0.05, 1.0, 0.01) = 0.5;   // 相邻两盏灯心的距离
uniform float group_x : hint_range(0.0, 1.0, 0.01) = 0.5;       // 整组灯的中心

// 把判定对齐到「大像素」网格。硬边斜线如果按屏幕像素走，台阶会比美术本身的像素还细，
// 看着像锯齿而不像设计。填美术放大倍率；1 = 不对齐。
uniform float block_px : hint_range(1.0, 16.0, 1.0) = 4.0;

// 光的上边界。ruv.y 小于它的地方【一律不受光】，哪怕光锥罩到了。
// 用来挡住窗户：室内的吊灯照不到室外，但遮罩分不清室内室外，
// 不设这条线的话光锥会把窗户"挖个洞"，露出白天的玻璃贴图。
// 0 = 参考矩形的上沿 = 办公室天花板。
uniform float light_top : hint_range(-1.0, 1.0, 0.01) = 0.0;

// 遮罩铺得比办公区大很多（为了盖住整个画面），但灯的位置不该跟着变。
// 这两个描述「办公区参考矩形」在遮罩里占的位置，灯的计算全用换算后的 ruv。
uniform vec2 ref_min = vec2(0.0);
uniform vec2 ref_size = vec2(1.0);

// ── 灯管周围的光晕 ──
// 和光锥是两回事：光锥是"照到哪儿"，光晕是"灯本身在发光"，四面八方都有，
// 离灯管越远越淡。灯管是一条横线段，所以算的是到【线段】的距离，不是到点的距离。
//
// ⚠️ glow_steps 是重点。像素风的光晕是【一圈圈硬边色阶】，不是平滑渐变 ——
//    平滑渐变在像素画里会糊成一团脏东西。2~4 圈最常见。
uniform float glow_radius : hint_range(0.0, 2.0, 0.01) = 0.25;  // 扩散多远（参考矩形高度的倍数）
uniform float glow_power : hint_range(0.5, 4.0, 0.1) = 2.2;     // 衰减曲线。越大越集中在灯管附近
uniform float glow_stretch : hint_range(1.0, 8.0, 0.1) = 1.0;   // >1 = 横向拉长成椭圆
// 0 = 平滑模糊（柔光晕）；≥2 = 量化成那么多圈硬边色阶（像素风的另一种画法）。
// 之前那条莫名其妙的横线就是色阶造成的 —— 灯管是长线段，每一圈在中段都是平的。
uniform float glow_steps : hint_range(0.0, 8.0, 1.0) = 0.0;
uniform float ref_aspect = 1.0;  // 参考矩形的宽高比，用来把光晕修圆（不然会拉成扁椭圆）

void lamp_shape(vec2 uv_in, out float hits, out float tube, out float glow) {
	vec2 node_px = vec2(1.0) / fwidth(uv_in);

	vec2 uv = uv_in;
	if (block_px > 1.5) {
		vec2 cells = max(node_px / block_px, vec2(1.0));
		uv = (floor(uv_in * cells) + 0.5) / cells;
	}

	vec2 ruv = (uv - ref_min) / max(ref_size, vec2(0.0001));

	hits = 0.0;
	tube = 0.0;
	glow = 0.0;
	float n = float(lamp_count);

	// 循环上界写死 6，用 break 控制实际盏数 —— 有些驱动不接受 uniform 当循环上界
	for (int i = 0; i < 6; i++) {
		if (i >= lamp_count) { break; }

		// 以 group_x 为轴左右排开，相邻间距 lamp_pitch。
		// 「几盏灯」和「挨多近」因此是两个独立旋钮，加灯不会把它们撑开。
		float cx = group_x + (float(i) - (n - 1.0) * 0.5) * lamp_pitch;
		float dx = abs(ruv.x - cx);

		// 梯形：t 从灯口 0 到光尽头 1，半宽随 t 线性张开。全程 step，没有过渡带。
		float t = (ruv.y - lamp_y) / cone_len;
		float half_w = lamp_half_w + spread * clamp(t, 0.0, 1.0);
		// 累加而不是取 max：这样才知道被【几盏】灯照到，重叠处才能单独上色
		hits += step(dx, half_w) * step(0.0, t) * step(t, 1.0);

		tube = max(tube, step(abs(ruv.y - lamp_y), tube_h) * step(dx, lamp_half_w));

		// 到灯管这条【线段】的距离：横向先减掉灯管自身长度，超出两端才开始算距离，
		// 这样光晕是个胶囊形（跟着灯管拉长），而不是一个圆点。
		// y 乘 ref_aspect 把坐标修成等比，不然光晕会被办公区的宽高比压成扁椭圆。
		// ref_aspect 把横向修成等比（不然会被办公区的宽高比压扁）；
		// 再除 glow_stretch 把它重新拉长成椭圆 —— 两者是独立的，一个修形一个造型。
		float gdx = max(dx - lamp_half_w, 0.0) * ref_aspect / max(glow_stretch, 0.001);
		float gd = length(vec2(gdx, ruv.y - lamp_y));
		// pow 做平滑衰减：越靠近灯管越浓，没有任何硬边
		float g = pow(clamp(1.0 - gd / max(glow_radius, 0.0001), 0.0, 1.0), glow_power);
		if (glow_steps >= 1.5) {
			g = ceil(g * glow_steps) / glow_steps;   // 想要硬边色阶时才量化
		}
		glow = max(glow, g);
	}

	// 天花板以上一律不受光（窗户在那儿）。灯管本身不受这条线限制 —— 它是实体，不是光。
	hits *= step(light_top, ruv.y);
	glow *= step(light_top, ruv.y);
}
