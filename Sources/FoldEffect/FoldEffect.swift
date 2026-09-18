//
//  FoldEffect.swift
//  DeviceToolbox
//
//  `.glassFold(angle:)` 视图扩展:把子树渲染成透过一块按 angle 倾斜的
//  磨砂玻璃窗观察的样子。
//  设计借鉴 elijah-semyonov/DuoLikeAnimation (MIT License),此处重新实现。
//

import SwiftUI
import Foundation

/// 折叠玻璃效果的物理参数。
struct GlassFoldParameters: Equatable {
    /// 观察者眼睛到未倾斜屏幕的距离(毫米)。手持阅读距离典型值约 30cm。
    var eyeDistanceMillimeters: CGFloat = 320
    /// 当前 iPhone 面板上 SwiftUI 点的大致密度(约 6 点/毫米)。
    var pointsPerMillimeter: CGFloat = 6
    /// 玻璃与界面每 1pt 间隙增加的模糊半径(散射半角的正切)。
    var blurSpread: CGFloat = 0.12
    /// 每 1pt 模糊半径损失的透光比例(玻璃越磨砂越暗)。
    var darkening: CGFloat = 0.015

    var eyeDistancePoints: CGFloat { eyeDistanceMillimeters * pointsPerMillimeter }

    /// shader 采样盒上界:与 `FoldGlass.metal` 采样公式逐式复刻,求「最远采样点
    /// 偏离被着色像素的最大 (x,y) 距离」(点),外加 2pt 守卫余量。
    ///
    /// 为什么必须是动态的(而非 v1.0.7 写死的 40pt):
    /// shader 有两段位移——透视重投影(`hit` 偏离当前像素,45° 时水平 ~134pt /
    /// 垂直 ~104pt)+ Vogel 模糊盘(半径 ~33pt)。`layerEffect` 要求所有采样都落在
    /// 被着色像素的 `maxSampleOffset` 盒内,**越界采样是未定义行为**:真机 GPU 上
    /// 表现为鬼影(相邻内存像素被放大铺满全屏,曾出现「整屏黄底 + 巨型红禁止圈」
    /// 渲染残破),而模拟器 GPU 越界时恰好钳成黑,所以模拟器里测不出来。
    /// 40pt 只够 10° 以内;15° 起就越界。v1.0.7 提交记的「render corruption
    /// (黄色图标感观)」即此根因,此处按实际角度 + 视图尺寸精确计算,越界归零。
    ///
    /// 17×17 像素网格 × 左右两铰链,O(578) 次闭式运算/帧,可忽略。
    /// 结果只随 (angle, size) 变,配合 `currentAngle` 的 1° 量化,整页重建频率极低。
    static func maxSampleOffset(
        width: CGFloat,
        height: CGFloat,
        angle: Double,
        parameters: GlassFoldParameters = GlassFoldParameters()
    ) -> CGSize {
        let tilt = abs(angle)
        guard tilt > 1e-5 else { return .zero }
        // 几何未就绪(首次布局前 size=0)时的兜底:iPhone 全系上限(480×1000pt),
        // 同角度下兜底值恒 ≥ 任何真机值,采样盒宁大勿小。
        let w = width > 0 ? width : 480
        let h = height > 0 ? height : 1000
        let eyeZ = parameters.eyeDistancePoints
        let eyeX = w * 0.5
        let eyeY = h * 0.5
        let cosT = CGFloat(cos(tilt))
        let sinT = CGFloat(sin(tilt))
        let blur = parameters.blurSpread
        var maxDX: CGFloat = 0
        var maxDY: CGFloat = 0
        for hingeRight in [true, false] {
            let hingeX: CGFloat = hingeRight ? w : 0
            let side: CGFloat = hingeRight ? -1 : 1
            for iy in 0..<17 {
                let py = h * CGFloat(iy) / 16
                for ix in 0..<17 {
                    let px = w * CGFloat(ix) / 16
                    let d = abs(px - hingeX)
                    let glassX = hingeX + side * d * cosT
                    let glassZ = d * sinT
                    let depth = eyeZ - glassZ
                    guard depth > 1e-3 else { continue }
                    let t = eyeZ / depth
                    let hitX = eyeX + (glassX - eyeX) * t
                    let hitY = eyeY + (py - eyeY) * t
                    let discR = blur * glassZ
                    maxDX = max(maxDX, abs(hitX - px) + discR)
                    maxDY = max(maxDY, abs(hitY - py) + discR)
                }
            }
        }
        return CGSize(width: (maxDX + 2).rounded(.up), height: (maxDY + 2).rounded(.up))
    }
}

extension View {
    /// 渲染效果:透过一块绕屏幕空间 Y 轴按 `angle`(弧度)倾斜的玻璃窗
    /// 观察该视图,铰链在远离观察者的一侧边缘。
    func glassFold(angle: Double, parameters: GlassFoldParameters = GlassFoldParameters()) -> some View {
        modifier(GlassFoldModifier(angle: angle, parameters: parameters))
    }
}

private struct GlassFoldModifier: ViewModifier {
    let angle: Double
    let parameters: GlassFoldParameters

    /// 关闭态(angle≈0)返回**原生内容**,不套 compositingGroup:
    /// 即便 shader 自禁用,压平栅格化仍会污染页面元素的命中测试/AX 树
    /// (UI 测试实测:套在 Tab 页内容上后,页内元素 tap 报 "Not hittable")。
    @ViewBuilder
    func body(content: Content) -> some View {
        if abs(angle) > 1e-4 {
            // 必须先压平整棵子树;否则 SwiftUI 给每个叶子各自开透明层,
            // shader 看到的就不是组合后的界面。
            content
                .compositingGroup()
                .visualEffect { [angle, parameters] content, proxy in
                    content.layerEffect(
                        ShaderLibrary.glassFold(
                            .boundingRect,
                            .float(angle),
                            .float(parameters.eyeDistancePoints),
                            .float(parameters.blurSpread),
                            .float(parameters.darkening)
                        ),
                        // 采样盒上界必须 ≥「最远采样点偏离被着色像素的距离」,
                        // 否则越界采样是未定义行为(真机 GPU 渲染残破,模拟器恰好
                        // 钳成黑测不出)。按实际角度 + 当前视图尺寸精确计算(闭式上界,
                        // 越界归零);45° 时可达水平 ~136pt / 垂直 ~106pt,旧版写死的
                        // 40pt 从 15° 起就越界 —— 即 v1.0.7「render corruption」。
                        maxSampleOffset: GlassFoldParameters.maxSampleOffset(
                            width: proxy.size.width,
                            height: proxy.size.height,
                            angle: angle,
                            parameters: parameters
                        ),
                        isEnabled: abs(angle) > 1e-4
                    )
                }
        } else {
            content
        }
    }
}
