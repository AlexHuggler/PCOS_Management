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

    @Test("Defaults to subtle when nothing is stored")
    func defaultsToSubtle() {
        #expect(RingMotionStyle.stored(defaults: makeDefaults()) == .subtle)
    }

    @Test("Round-trips through UserDefaults")
    func roundTrips() {
        let defaults = makeDefaults()
        RingMotionStyle.store(.alive, defaults: defaults)
        #expect(RingMotionStyle.stored(defaults: defaults) == .alive)
        #expect(defaults.string(forKey: RingMotionStyle.defaultsKey) == "alive")
    }

    @Test("Invalid stored raw value falls back to subtle")
    func invalidRawFallsBack() {
        let defaults = makeDefaults()
        defaults.set("disco", forKey: RingMotionStyle.defaultsKey)
        #expect(RingMotionStyle.stored(defaults: defaults) == .subtle)
    }

    @Test("Reduce Motion forces off regardless of stored value")
    func reduceMotionWins() {
        let defaults = makeDefaults()
        RingMotionStyle.store(.alive, defaults: defaults)
        #expect(RingMotionStyle.resolved(defaults: defaults, reduceMotion: true) == .off)
        #expect(RingMotionStyle.resolved(defaults: defaults, reduceMotion: false) == .alive)
    }
}
