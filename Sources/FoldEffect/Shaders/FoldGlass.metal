//
//  FoldGlass.metal
//  DeviceToolbox
//
//  折叠玻璃窗效果 shader:把整块界面视为一片固定在世界中的 UI 平面,
//  设备绕竖直轴倾斜时,屏幕像一块磨砂玻璃窗绕"远离观察者一侧的铰链边"
//  旋转,透过它看界面:透视重投影 + 按玻璃与界面间隙模糊变暗,射线打
//  不到界面的区域为纯黑。
//
//  设计借鉴 elijah-semyonov/DuoLikeAnimation (MIT License),此处重新实现。
//  原项目作者: Elijah Semyonov。物理模型推导见该仓库 README。
//

#include <metal_stdlib>
#include <SwiftUI/SwiftUI.h>
using namespace metal;

constant int   kMaxBlurTaps   = 32;
constant float kGoldenAngle   = 2.39996322972865332;   // Vogel 螺旋盘角间距(弧度)
constant float kTwoPi         = 6.28318530717958648;

/// 逐像素 hash:让每个像素的采样盘独立旋转,把模糊条纹带打散成磨砂颗粒。
static float hash21(float2 p) {
    return fract(sin(dot(p, float2(12.9898, 78.233))) * 43758.5453);
}

/// layerEffect 的 layer 是预乘 alpha;这里丢到 alpha=1,等价于在黑色背景上合成。
static half4 toOpaque(half4 premultiplied) {
    return half4(premultiplied.rgb, 1.0h);
}

/// - position:    被着色像素(视图坐标,点)。
/// - bounds:      视图边界 (x, y, width, height)。
/// - angle:       绕屏幕空间 Y 轴的有符号倾角(弧度)。
///                正:右缘远离观察者,铰链在右;负:铰链在左。
/// - eyeDistance: 观察者眼睛到 UI 平面的距离(点),位于屏幕中心法线上。
/// - blurSpread:  玻璃-界面每 1pt 间隙增加的模糊半径。
/// - darkening:   每 1pt 模糊半径损失的透光比例。
[[ stitchable ]] half4 glassFold(float2 position,
                                  SwiftUI::Layer layer,
                                  float4 bounds,
                                  float angle,
                                  float eyeDistance,
                                  float blurSpread,
                                  float darkening)
{
    const float2 size = bounds.zw;
    const float2 p    = position - bounds.xy;
    const float  tilt = abs(angle);

    // 零倾角直通,避免无谓采样。
    if (tilt < 1e-5) {
        return toOpaque(layer.sample(position));
    }

    // 铰链:远离观察者的一侧边缘,留在 UI 平面内不动。
    const bool  hingeRight = angle > 0.0;
    const float hingeX     = hingeRight ? size.x : 0.0;
    const float side        = hingeRight ? -1.0 : 1.0;   // 从铰链横穿屏幕的方向
    const float d           = abs(p.x - hingeX);          // 该像素离铰链的沿玻璃距离

    // 玻璃绕铰链线旋转 tilt,整片向观察者抬起。
    const float3 glass = float3(hingeX + side * d * cos(tilt), p.y, d * sin(tilt));
    const float3 eye   = float3(size * 0.5, eyeDistance);

    // 眼 -> 玻璃像素 射线延长到 UI 平面 z = 0。
    const float depth = eye.z - glass.z;
    if (depth <= 1e-3) {
        return half4(0.0h, 0.0h, 0.0h, 1.0h);
    }
    const float  t   = eye.z / depth;
    const float2 hit = eye.xy + (glass.xy - eye.xy) * t;

    // 该像素玻璃面与 UI 平面的间隙决定模糊半径。
    const float gap    = glass.z;
    const float radius = blurSpread * gap;

    // 整个模糊核都落在界面之外:黑。
    if (any(hit < -radius) || any(hit > size + radius)) {
        return half4(0.0h, 0.0h, 0.0h, 1.0h);
    }

    // 磨砂玻璃同时吸收光线:按模糊半径成比例变暗。
    const half attenuation = half(max(1.0 - darkening * radius, 0.0));

    // 间隙极小(铰链附近)时单样本即可。
    if (radius < 0.5) {
        return toOpaque(layer.sample(bounds.xy + hit) * attenuation);
    }

    // Vogel 盘螺旋采样。tap 数随半径自适应:小核少采样,控制整帧成本;
    // 每像素独立旋转采样盘,把条纹带打散成颗粒感。
    const int   taps     = clamp(int(radius * 2.0), 6, kMaxBlurTaps);
    const float rotation = hash21(position) * kTwoPi;
    half3 sum = half3(0.0h);
    for (int i = 0; i < taps; ++i) {
        const float r = radius * sqrt((float(i) + 0.5) / float(taps));
        const float a = float(i) * kGoldenAngle + rotation;
        const float2 offset = r * float2(cos(a), sin(a));
        sum += layer.sample(bounds.xy + hit + offset).rgb;
    }
    return half4(sum / half(taps) * attenuation, 1.0h);
}
