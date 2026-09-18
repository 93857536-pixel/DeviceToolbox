import XCTest
@testable import DeviceToolbox

/// `GlassFoldParameters.maxSampleOffset` 的数学单测:
/// 锁定 layerEffect 采样盒上界 ≥ 最远采样点偏离被着色像素的距离(闭式上界),
/// 杜绝 v1.0.7「整屏黄底 + 巨型红禁止圈」渲染残破(layerEffect 越界采样 UB)。
final class GlassFoldOffsetTests: XCTestCase {

    private func offset(
        _ w: CGFloat, _ h: CGFloat, _ degrees: Double,
        _ p: GlassFoldParameters = GlassFoldParameters()
    ) -> CGSize {
        GlassFoldParameters.maxSampleOffset(
            width: w, height: h,
            angle: degrees * .pi / 180,
            parameters: p
        )
    }

    /// 零倾角直通:shader 不采样,采样盒必须为 .zero(压平零成本)。
    func testZeroAngleYieldsZeroOffset() {
        XCTAssertEqual(offset(390, 844, 0), .zero)
        XCTAssertEqual(offset(390, 844, -0.0001), .zero)
    }

    /// 上界随倾角单调不减(更大角度采样走得更远)。
    func testMonotonicInAngle() {
        for (w, h) in [(CGFloat(390), CGFloat(844)), (CGFloat(430), CGFloat(932)), (CGFloat(440), CGFloat(956))] {
            let a15 = offset(w, h, 15)
            let a30 = offset(w, h, 30)
            let a45 = offset(w, h, 45)
            XCTAssertLessThanOrEqual(a15.width, a30.width, "\(w)×\(h) 15°→30° 应不减")
            XCTAssertLessThanOrEqual(a30.width, a45.width, "\(w)×\(h) 30°→45° 应不减")
            XCTAssertLessThanOrEqual(a15.height, a45.height)
            XCTAssertGreaterThan(a30.width, 40, "\(w)×\(h) 30° 采样盒必须远超旧版写死的 40pt")
        }
    }

    /// 45° 关键回归值:真机最大倾斜度下的采样盒上界,必须远超旧版写死的 40pt。
    /// 用区间断言(模拟器 32-bit CGFloat 下 rounding 在边界可能有 ±1pt 漂移):
    /// 离线 64-bit 对照 390×844 @45° ≈ (136, 106)、440×956 @45° ≈ (151, 132)。
    func testFortyFiveDegreesBounds() {
        let std = offset(390, 844, 45)
        XCTAssertTrue((130...142).contains(std.width), "390×844 @45° 横向 ≈136, 实得 \(std.width)")
        XCTAssertTrue((100...112).contains(std.height), "390×844 @45° 纵向 ≈106, 实得 \(std.height)")
        let proMax = offset(440, 956, 45)
        XCTAssertTrue((145...157).contains(proMax.width), "440×956 @45° 横向 ≈151, 实得 \(proMax.width)")
        XCTAssertTrue((126...138).contains(proMax.height), "440×956 @45° 纵向 ≈132, 实得 \(proMax.height)")
    }

    /// 几何未就绪(size=0)的兜底盒必须 ≥ 所有真机同角度盒(宁大勿小,采样仍不越界)。
    func testZeroSizeFallbackDominates() {
        let fallback = offset(0, 0, 45)
        for (w, h) in [(CGFloat(375), CGFloat(812)), (CGFloat(390), CGFloat(844)),
                       (CGFloat(430), CGFloat(932)), (CGFloat(440), CGFloat(956))] {
            let real = offset(w, h, 45)
            XCTAssertGreaterThanOrEqual(fallback.width, real.width, "兜底 < \(w)×\(h)")
            XCTAssertGreaterThanOrEqual(fallback.height, real.height)
        }
    }

    /// 负角度(左铰链)与正角度对称:采样盒大小一致。
    func testSymmetricForNegativeAngle() {
        XCTAssertEqual(offset(390, 844, 30), offset(390, 844, -30))
    }

    /// 自定义参数:眼距变化必须被采样盒捕捉(长基线透视 → 眼距越远投影位移越大)。
    /// 160mm(贴近) vs 480mm(抬远)实测:480mm 盒更大,旧写死 40pt 两档都远超。
    func testParametersScaleTheBound() {
        var near = GlassFoldParameters()
        near.eyeDistanceMillimeters = 160   // 贴近脸
        var far = GlassFoldParameters()
        far.eyeDistanceMillimeters = 480    // 抬远
        let nearBox = offset(390, 844, 45, near)
        let farBox = offset(390, 844, 45, far)
        XCTAssertGreaterThan(farBox.width, nearBox.width, "眼距越远投影位移越大,采样盒应更大")
    }
}
