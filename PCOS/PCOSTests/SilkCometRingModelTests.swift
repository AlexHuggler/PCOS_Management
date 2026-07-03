import Testing
import Foundation
@testable import PCOS

@Suite("Silk Comet Ring Model")
struct SilkCometRingModelTests {
    @Test("Arc end tracks progress within clamp bounds")
    func arcEndTracksProgress() {
        #expect(SilkCometRingModel(progress: 0.5).arcEnd == 0.5)
        // Overdue cycles never close the ring on themselves (spec: clamp 0.98).
        #expect(SilkCometRingModel(progress: 1.4).arcEnd == SilkCometRingModel.maximumArcEnd)
        // Day 1 still shows a sliver so the tip has somewhere to sit.
        #expect(SilkCometRingModel(progress: 0.0).arcEnd == SilkCometRingModel.minimumArcEnd)
    }

    @Test("Gradient stops scale with the arc so the tail is always at day 1")
    func stopsScaleWithArc() {
        let model = SilkCometRingModel(progress: 0.5)
        #expect(model.stops.count == 5)
        #expect(model.stops.first?.position == 0)
        #expect(model.stops.last?.position == 0.5)
        // Positions ascend strictly.
        let positions = model.stops.map(\.position)
        #expect(zip(positions, positions.dropFirst()).allSatisfy { $0 < $1 })
    }

    @Test("Zero fade: tail opacity is exactly zero, tip is full")
    func zeroFadeRecipe() {
        let model = SilkCometRingModel(progress: 0.6)
        #expect(model.stops.first?.opacity == 0)
        #expect(model.stops.last?.opacity == 1)
    }

    @Test("Tail floor lifts every stop below the floor (High Contrast)")
    func tailFloor() {
        let model = SilkCometRingModel(progress: 0.6, tailFloorOpacity: 0.35)
        #expect(model.stops.allSatisfy { $0.opacity >= 0.35 })
        #expect(model.stops.last?.opacity == 1)
    }

    @Test("Welcome state shows the decorative segment without a tip")
    func welcomeState() {
        let model = SilkCometRingModel(progress: 0, isWelcome: true)
        #expect(model.arcEnd == SilkCometRingModel.welcomeArcEnd)
        #expect(model.showsTip == false)
        #expect(SilkCometRingModel(progress: 0.4).showsTip == true)
    }

    @Test("Welcome arc honors the tail floor")
    func welcomeHonorsFloor() {
        let model = SilkCometRingModel(progress: 0, isWelcome: true, tailFloorOpacity: 0.35)
        #expect(model.arcEnd == SilkCometRingModel.welcomeArcEnd)
        #expect(model.stops.allSatisfy { $0.opacity >= 0.35 })
    }

    @Test("NaN progress clamps to the minimum arc")
    func nanProgressClamps() {
        let model = SilkCometRingModel(progress: .nan, isWelcome: false)
        #expect(model.arcEnd == SilkCometRingModel.minimumArcEnd)
    }
}
