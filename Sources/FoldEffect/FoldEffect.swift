//
//  FoldEffect.swift
//  DeviceToolbox
//
//  `.glassFold(angle:)` 视图扩展:把子树渲染成透过一块按 angle 倾斜的
//  磨砂玻璃窗观察的样子。
//  设计借鉴 elijah-semyonov/DuoLikeAnimation (MIT License),此处重新实现。
//

import SwiftUI

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
                .visualEffect { [angle, parameters] content, _ in
                    content.layerEffect(
                        ShaderLibrary.glassFold(
                            .boundingRect,
                            .float(angle),
                            .float(parameters.eyeDistancePoints),
                            .float(parameters.blurSpread),
                            .float(parameters.darkening)
                        ),
                        // shader 会向远处采样(Vogel 盘模糊核,半径最大约 35pt);
                        // maxSampleOffset 必须覆盖它,否则越界采样行为未定义,
                        // 大倾角时边缘会发黑/断裂(观感像"界面坏了")。
                        maxSampleOffset: CGSize(width: 40, height: 40),
                        isEnabled: abs(angle) > 1e-4
                    )
                }
        } else {
            content
        }
    }
}
