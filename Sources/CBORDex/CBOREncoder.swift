import Foundation

/// Serialises `CBORValue` instances into their binary representation.
public final class CBOREncoder {
	public struct Options {
		/// Enables canonical map key ordering (RFC 8949 §4.1).
		public var canonicalMapOrdering: Bool = false

		public init() {}
	}

	public var options: Options

	public init(options: Options = Options()) {
		self.options = options
	}

	/// Encodes a value that is already expressed as a `CBORValue` tree.
	public func encode(_ value: CBORValue) throws -> Data {
		var buffer = Data()
		try append(value, canonical: options.canonicalMapOrdering, into: &buffer)
		return buffer
	}

}

private func append(_ value: CBORValue, canonical: Bool, into data: inout Data) throws {
	switch value {
	case .unsigned(let number):
		append(major: 0, argument: number, into: &data)
	case .negative(let magnitude):
		append(major: 1, argument: magnitude, into: &data)
	case .byteString(let bytes):
		append(major: 2, argument: UInt64(bytes.count), into: &data)
		data.append(bytes)
	case .textString(let string):
		let utf8 = Data(string.utf8)
		append(major: 3, argument: UInt64(utf8.count), into: &data)
		data.append(utf8)
	case .array(let items):
		append(major: 4, argument: UInt64(items.count), into: &data)
		for item in items {
			try append(item, canonical: canonical, into: &data)
		}
	case .map(let pairs):
		if canonical {
			let expanded = try pairs.map { pair -> (Data, CBORValue) in
				var keyData = Data()
				try append(pair.0, canonical: true, into: &keyData)
				return (keyData, pair.1)
			}
			let sorted = expanded.sorted { lhs, rhs in
				let leftKey = lhs.0
				let rightKey = rhs.0
				if leftKey == rightKey {
					return false
				}
				return leftKey.lexicographicallyPrecedes(rightKey)
			}
			append(major: 5, argument: UInt64(sorted.count), into: &data)
			for item in sorted {
				data.append(item.0)
				try append(item.1, canonical: canonical, into: &data)
			}
		} else {
			append(major: 5, argument: UInt64(pairs.count), into: &data)
			for (key, value) in pairs {
				try append(key, canonical: canonical, into: &data)
				try append(value, canonical: canonical, into: &data)
			}
		}
	case .tagged(let tag, let wrapped):
		append(major: 6, argument: tag, into: &data)
		try append(wrapped, canonical: canonical, into: &data)
	case .bool(let flag):
		data.append(flag ? 0xF5 : 0xF4)
	case .null:
		data.append(0xF6)
	case .undefined:
		data.append(0xF7)
	case .simple(let simple):
		if simple < 24 {
			data.append(0xE0 | simple)
		} else {
			data.append(0xF8)
			data.append(simple)
		}
	case .half(let bits):
		if canonical {
			let float16 = Float16(bitPattern: bits)
			appendCanonicalFloat(Double(float16), into: &data)
		} else {
			data.append(0xF9)
			appendUInt16(bits, into: &data)
		}
	case .float(let value):
		if canonical {
			appendCanonicalFloat(Double(value), into: &data)
		} else {
			data.append(0xFA)
			appendUInt32(value.bitPattern.bigEndian, into: &data)
		}
	case .double(let value):
		if canonical {
			appendCanonicalFloat(value, into: &data)
		} else {
			data.append(0xFB)
			appendUInt64(value.bitPattern.bigEndian, into: &data)
		}
	}
}

private func append(major: UInt8, argument: UInt64, into data: inout Data) {
	precondition(major <= 7, "Invalid major type")
	if argument < 24 {
		data.append((major << 5) | UInt8(argument))
	} else if argument <= UInt64(UInt8.max) {
		data.append((major << 5) | 24)
		data.append(UInt8(argument))
	} else if argument <= UInt64(UInt16.max) {
		data.append((major << 5) | 25)
		appendUInt16(UInt16(argument), into: &data)
	} else if argument <= UInt64(UInt32.max) {
		data.append((major << 5) | 26)
		appendUInt32(UInt32(argument).bigEndian, into: &data)
	} else {
		data.append((major << 5) | 27)
		appendUInt64(argument.bigEndian, into: &data)
	}
}

@inline(__always)
private func appendUInt16(_ value: UInt16, into data: inout Data) {
	var bigEndian = value.bigEndian
	withUnsafeBytes(of: &bigEndian) { buf in
		data.append(contentsOf: buf)
	}
}

@inline(__always)
private func appendUInt32(_ value: UInt32, into data: inout Data) {
	var bigEndian = value
	withUnsafeBytes(of: &bigEndian) { buf in
		data.append(contentsOf: buf)
	}
}

@inline(__always)
private func appendUInt64(_ value: UInt64, into data: inout Data) {
	var bigEndian = value
	withUnsafeBytes(of: &bigEndian) { buf in
		data.append(contentsOf: buf)
	}
}

private enum CanonicalFloatRepresentation {
	case half(UInt16)
	case single(UInt32)
	case double(UInt64)
}

@inline(__always)
private func canonicalFloatEncoding(for value: Double) -> CanonicalFloatRepresentation {
	if value.isNaN {
		return .half(0x7E00)
	}

	let halfCandidate = Float16(value)
	if Double(halfCandidate).bitPattern == value.bitPattern {
		return .half(halfCandidate.bitPattern)
	}

	let singleCandidate = Float(value)
	if Double(singleCandidate).bitPattern == value.bitPattern {
		return .single(singleCandidate.bitPattern)
	}

	return .double(value.bitPattern)
}

@inline(__always)
private func appendCanonicalFloat(_ value: Double, into data: inout Data) {
	switch canonicalFloatEncoding(for: value) {
	case .half(let bits):
		data.append(0xF9)
		appendUInt16(bits, into: &data)
	case .single(let bits):
		data.append(0xFA)
		appendUInt32(bits.bigEndian, into: &data)
	case .double(let bits):
		data.append(0xFB)
		appendUInt64(bits.bigEndian, into: &data)
	}
}
