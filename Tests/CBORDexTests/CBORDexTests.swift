import XCTest

@testable import CBORDex

final class CBORCodecTests: XCTestCase {
	func testEncodeSimpleMap() throws {
		let value: CBORValue = .map([
			(.unsigned(1), .textString("a")),
			(.unsigned(2), .bool(true)),
		])
		let encoder = CBOREncoder()
		let data = try encoder.encode(value)
		XCTAssertEqual(Array(data), [0xA2, 0x01, 0x61, 0x61, 0x02, 0xF5])
	}

	func testDecodeIndefiniteByteString() throws {
		let bytes: [UInt8] = [0x5F, 0x42, 0x01, 0x02, 0x41, 0x03, 0xFF]
		let decoder = CBORDecoder()
		let value = try decoder.decode(Data(bytes))
		guard case .byteString(let data) = value else {
			XCTFail("Unexpected type: \(value)")
			return
		}
		XCTAssertEqual(Array(data), [0x01, 0x02, 0x03])
	}

	func testDecodeNegativeInteger() throws {
		let bytes = Data([0x38, 0x63])  // -100
		let decoder = CBORDecoder()
		let value = try decoder.decode(bytes)
		guard case .negative(let magnitude) = value else {
			XCTFail("Expected negative integer")
			return
		}
		XCTAssertEqual(magnitude, 99)  // -1 - 99 = -100
	}

	func testRoundTripArray() throws {
		let original: CBORValue = .array([
			.integer(42),
			.textString("hello"),
			.null,
		])
		let encoder = CBOREncoder()
		let data = try encoder.encode(original)
		let decoder = CBORDecoder()
		let decoded = try decoder.decode(data)
		XCTAssertEqual(decoded, original)
	}

	func testCanonicalMapOrdering() throws {
		let value: CBORValue = .map([
			(.textString("b"), .unsigned(2)),
			(.textString("a"), .unsigned(1)),
		])
		var options = CBOREncoder.Options()
		options.canonicalMapOrdering = true
		let encoder = CBOREncoder(options: options)
		let data = try encoder.encode(value)
		XCTAssertEqual(Array(data), [0xA2, 0x61, 0x61, 0x01, 0x61, 0x62, 0x02])
	}

	func testCanonicalOrderingUsesLexicographicByteComparison() throws {
		let value: CBORValue = .map([
			(.array([.unsigned(1), .unsigned(2)]), .unsigned(12)),
			(.bool(false), .unsigned(34)),
		])
		var options = CBOREncoder.Options()
		options.canonicalMapOrdering = true
		let encoder = CBOREncoder(options: options)
		let data = try encoder.encode(value)
		XCTAssertEqual(Array(data), [0xA2, 0x82, 0x01, 0x02, 0x0C, 0xF4, 0x18, 0x22])
	}

	func testCanonicalFloatDowncastsToHalf() throws {
		let value: CBORValue = .array([
			.double(1.5)
		])
		var options = CBOREncoder.Options()
		options.canonicalMapOrdering = true
		let encoder = CBOREncoder(options: options)
		let data = try encoder.encode(value)
		XCTAssertEqual(Array(data), [0x81, 0xF9, 0x3E, 0x00])
	}

	func testCanonicalDoubleNaNUsesPreferredRepresentation() throws {
		let value: CBORValue = .array([
			.double(Double.nan)
		])
		var options = CBOREncoder.Options()
		options.canonicalMapOrdering = true
		let encoder = CBOREncoder(options: options)
		let data = try encoder.encode(value)
		XCTAssertEqual(Array(data), [0x81, 0xF9, 0x7E, 0x00])
	}

	func testTrailingDataIsRejected() throws {
		let bytes: [UInt8] = [0x01, 0x00]
		let decoder = CBORDecoder()
		XCTAssertThrowsError(try decoder.decode(Data(bytes))) { error in
			guard case CBORDecodingError.trailingBytes = error else {
				XCTFail("Unexpected error: \(error)")
				return
			}
		}
	}
}
