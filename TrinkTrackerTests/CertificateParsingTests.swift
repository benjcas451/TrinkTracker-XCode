import Foundation
import Testing
@testable import TrinkTracker

struct CertificateParsingTests {
    @Test func pemBloeckeWerdenGefunden() {
        let pem = """
        -----BEGIN CERTIFICATE-----
        AQID
        -----END CERTIFICATE-----
        -----BEGIN CERTIFICATE-----
        BAUG
        -----END CERTIFICATE-----
        """
        let blocks = PEM.blocks(in: Data(pem.utf8), label: "CERTIFICATE")
        #expect(blocks == [Data([1, 2, 3]), Data([4, 5, 6])])
        #expect(PEM.blocks(in: Data(pem.utf8), label: "PRIVATE KEY").isEmpty)
    }

    @Test func derElementeMitLangerLaenge() throws {
        // SEQUENCE (0x30) mit Langform-Länge 0x81 0x02, Inhalt: INTEGER 5
        let der = Data([0x30, 0x81, 0x03, 0x02, 0x01, 0x05])
        let outer = try DER.elements(der)
        #expect(outer.count == 1)
        #expect(outer[0].tag == 0x30)
        let inner = try DER.elements(outer[0].content)
        #expect(inner[0].tag == 0x02)
        #expect(inner[0].content == Data([5]))
    }

    @Test func pkcs8ErkenntRSA() throws {
        // PrivateKeyInfo { version 0, { OID rsaEncryption, NULL }, OCTET STRING 0xAA }
        let oid: [UInt8] = [0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01]
        let alg: [UInt8] = [0x30, UInt8(oid.count + 2)] + oid + [0x05, 0x00]
        let body: [UInt8] = [0x02, 0x01, 0x00] + alg + [0x04, 0x01, 0xAA]
        let der = Data([0x30, UInt8(body.count)] + body)
        let info = try DER.parsePKCS8(der)
        #expect(info.algorithm == .rsa)
        #expect(info.key == Data([0xAA]))
    }

    @Test func sec1WirdZuX963() throws {
        // ECPrivateKey { version 1, privateKey 0x11 0x22, [1] BIT STRING 00 04 X Y }
        let pub: [UInt8] = [0x03, 0x06, 0x00, 0x04, 0x01, 0x02, 0x03, 0x04] // X=0102, Y=0304
        let ctx: [UInt8] = [0xA1, UInt8(pub.count)] + pub
        let body: [UInt8] = [0x02, 0x01, 0x01, 0x04, 0x02, 0x11, 0x22] + ctx
        let der = Data([0x30, UInt8(body.count)] + body)
        let x963 = try DER.x963(fromSEC1: der)
        #expect(x963 == Data([0x04, 0x01, 0x02, 0x03, 0x04, 0x11, 0x22]))
    }
}
