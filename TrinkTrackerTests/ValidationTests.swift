import Foundation
import Testing
@testable import TrinkTracker

struct ValidationTests {
    @Test func getraenkEinsBis60ZeichenGetrimmt() throws {
        #expect(try TrinkValidation.getraenk("  Wasser ") == "Wasser")
        #expect(throws: TrinkError.self) { try TrinkValidation.getraenk("   ") }
        #expect(throws: TrinkError.self) { try TrinkValidation.getraenk(String(repeating: "x", count: 61)) }
    }

    @Test func mengeEinsBis10000() throws {
        #expect(try TrinkValidation.menge(1) == 1)
        #expect(try TrinkValidation.menge(10000) == 10000)
        #expect(throws: TrinkError.self) { try TrinkValidation.menge(0) }
        #expect(throws: TrinkError.self) { try TrinkValidation.menge(10001) }
    }

    @Test func tageszielNullBis20000() throws {
        #expect(try TrinkValidation.tagesziel(0) == 0)
        #expect(try TrinkValidation.tagesziel(20000) == 20000)
        #expect(throws: TrinkError.self) { try TrinkValidation.tagesziel(-1) }
        #expect(throws: TrinkError.self) { try TrinkValidation.tagesziel(20001) }
    }

    @Test func zeitpunktNichtInDerZukunft() throws {
        let now = Date()
        #expect(try TrinkValidation.createTime(now.addingTimeInterval(-3600), now: now) == now.addingTimeInterval(-3600))
        #expect(throws: TrinkError.self) { try TrinkValidation.createTime(now.addingTimeInterval(600), now: now) }
    }

    @Test func fehlerartenSindDauerhaftOderNicht() {
        #expect(TrinkError(.validation, "x").isPermanent)
        #expect(TrinkError(.unsupported, "x").isPermanent)
        #expect(TrinkError(.configuration, "x").isPermanent)
        #expect(!TrinkError(.network, "x").isPermanent)
        #expect(!TrinkError(.auth, "x").isPermanent)
    }
}
