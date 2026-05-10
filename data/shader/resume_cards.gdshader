shader_type canvas_item;

// ——— 可视化编辑器参数 ———

// 在 Inspector 里拖拽调整圆角半径 (像素单位)
//  hint_range(0.0, 200.0, 0.5) 允许 0 到 200 像素，步长为 0.5
uniform float corner_radius : hint_range(0.0, 200.0, 0.5) = 20.0;

// 在 Inspector 里拖拽调整边缘平滑度 (0.0 到 5.0 像素)
// 增加此值可以消除狗牙，使边缘更平滑
uniform float edge_smoothness : hint_range(0.0, 5.0, 0.1) = 1.0;


// ——— 逻辑计算 ———

void fragment() {
    // 1. 🌟 获取节点的当前实际像素尺寸 (防变形核心)
    // fwidth(UV) 获取 UV 坐标的偏导数，换算成像素。
    // 如果纹理显示不正确（被压扁或拉伸），fwidth(UV) 会变小或变大。
    // 我们用 1.0 除以它，就能精确反推出当前节点被渲染出来的像素尺寸。
    vec2 node_size_px = vec2(1.0) / fwidth(UV); 

    // 2. 将当前点从 0~1 的 UV 坐标换算成像素坐标
    vec2 current_pixel_pos = UV * node_size_px;

    // 3. 计算计算到圆角矩形的距离field
    // rounded_box 计算方法，确保不管卡片拉多长，圆角都是完美的正圆角。
    vec2 half_size = node_size_px * 0.5;
    vec2 center_pixel_pos = half_size;
    
    vec2 q = abs(current_pixel_pos - center_pixel_pos) - half_size + corner_radius;
    float dist = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - corner_radius;

    // 4. 应用抗锯齿和裁剪 (平滑边缘)
    // 根据在编辑器里设置的 smooth_smoothness 进行裁剪
    // 这个平滑范围在 -smoothness 到 +smoothness 之间，从而实现抗锯齿。
    float s = max(0.01, edge_smoothness); // 至少保留 0.01 像素，防止除零错误
    float alpha_blend = smoothstep(-s * 0.5, s * 0.5, dist);
    
    // 1.0 - alpha_blend 意味着圆角以外的部分变为透明。
    float final_alpha = 1.0 - alpha_blend;
    
    // 5. 获取原始纹理颜色
    vec4 tex_color = texture(TEXTURE, UV);
    
    // 6. 最终输出颜色 (保留原始纹理颜色的 RGBA 属性，乘以计算好的圆角 Alpha)
    COLOR = vec4(tex_color.rgb, tex_color.a * final_alpha);
}