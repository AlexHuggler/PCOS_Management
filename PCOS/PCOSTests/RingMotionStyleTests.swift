import Testing
import Foundation
@testable import PCOS

@Suite("Ring Motion Style")
struct RingMotionStyleTests {
    private func makeDefaults() -> UserDefaults {
        let suiteName = "RingMotionStyleTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    @Test("Defaults to the shipped default (alive) when nothing is stored")
    func defaultsToShippedDefault() {
        #expect(RingMotionStyle.shippedDefault == .alive)
        #expect(RingMotionStyle.stored(defaults: makeDefaults()) == .alive)
    }

    @Test("Round-trips through UserDefaults")
    func roundTrips() {
        let defaults = makeDefaults()
        RingMotionStyle.store(.subtle, defaults: defaults)
        #expect(RingMotionStyle.stored(defaults: defaults) == .subtle)
        #expect(defaults.string(forKey: RingMotionStyle.defaultsKey) == "subtle")
    }

    @Test("Invalid stored raw value falls back to the shipped default")
    func invalidRawFallsBack() {
        let defaults = makeDefaults()
        defaults.set("disco", forKey: RingMotionStyle.defaultsKey)
        #expect(RingMotionStyle.stored(defaults: defaults) == RingMotionStyle.shippedDefault)
    }

    @Test("Reduce Motion forces off regardless of stored value")
    func reduceMotionWins() {
        let defaults = makeDefaults()
        RingMotionStyle.store(.alive, defaults: defaults)
        #expect(RingMotionStyle.resolved(defaults: defaults, reduceMotion: true) == .off)
        #expect(RingMotionStyle.resolved(defaults: defaults, reduceMotion: false) == .alive)
    }
}
