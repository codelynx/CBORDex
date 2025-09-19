import Foundation

public enum CBORDecodingError: Error, CustomStringConvertible {
	case unexpectedEndOfData
	case invalidAdditionalInfo(UInt8)
	case unexpectedBreak
	case invalidInitialByte(UInt8)
	case invalidUTF8(Data)
	case excessiveNesting
	case trailingBytes
	case invalidMapStructure
	case invalidChunkType(expected: String)
	case lengthOutOfRange

	public var description: String {
		switch self {
		case .unexpectedEndOfData:
			return "Unexpected end of CBOR data"
		case .invalidAdditionalInfo(let info):
			return "Invalid additional information field: \(info)"
		case .unexpectedBreak:
			return "Encountered a break byte outside of an indefinite-length container"
		case .invalidInitialByte(let byte):
			return "Invalid CBOR initial byte: 0x\(String(byte, radix: 16))"
		case .invalidUTF8(let data):
			return "Invalid UTF-8 data of length \(data.count)"
		case .excessiveNesting:
			return "CBOR nesting depth exceeded the configured limit"
		case .trailingBytes:
			return "Trailing data encountered after decoding the top-level item"
		case .invalidMapStructure:
			return "Map must contain an even number of elements"
		case .invalidChunkType(let expected):
			return "Invalid chunk type encountered; expected \(expected)"
		case .lengthOutOfRange:
			return "Length value exceeds supported range"
		}
	}
}

/// Parses binary CBOR into `CBORValue` trees or strongly typed models.
public final class CBORDecoder {
	public struct Options {
		/// Maximum container nesting depth allowed during decoding.
		public var maximumNestingDepth: Int = 256
		/// Whether to tolerate trailing bytes after the first top-level item.
		public var allowTrailingData: Bool = false

		public init() {}
	}

	public var options: Options

	public init(options: Options = Options()) {
		self.options = options
	}

	public func decode(_ data: Data) throws -> CBORValue {
		var cursor = Cursor(data: data)
		let value = try decodeValue(cursor: &cursor, depth: 0)
		if !options.allowTrailingData && !cursor.isAtEnd {
			throw CBORDecodingError.trailingBytes
		}
		return value
	}

	// MARK: - Core decoding

	private func decodeValue(cursor: inout Cursor, depth: Int) throws -> CBORValue {
		guard depth <= options.maximumNestingDepth else {
			throw CBORDecodingError.excessiveNesting
		}
		let initial = try cursor.readByte()
		if initial == 0xFF {
			throw CBORDecodingError.unexpectedBreak
		}

		let major = initial >> 5
		let info = initial & 0x1F

		switch major {
		case 0:
			guard let length = try readLength(info, cursor: &cursor) else {
				throw CBORDecodingError.invalidAdditionalInfo(info)
			}
			return .unsigned(length)
		case 1:
			guard let length = try readLength(info, cursor: &cursor) else {
				throw CBORDecodingError.invalidAdditionalInfo(info)
			}
			return .negative(length)
		case 2:
			let result = try decodeByteString(
				cursor: &cursor, additionalInfo: info, depth: depth)
			return .byteString(result)
		case 3:
			let result = try decodeTextString(
				cursor: &cursor, additionalInfo: info, depth: depth)
			return .textString(result)
		case 4:
			return try decodeArray(cursor: &cursor, additionalInfo: info, depth: depth)
		case 5:
			return try decodeMap(cursor: &cursor, additionalInfo: info, depth: depth)
		case 6:
			guard let tag = try readLength(info, cursor: &cursor) else {
				throw CBORDecodingError.invalidAdditionalInfo(info)
			}
			let wrapped = try decodeValue(cursor: &cursor, depth: depth + 1)
			return .tagged(tag, wrapped)
		case 7:
			return try decodeSimpleOrFloat(cursor: &cursor, additionalInfo: info)
		default:
			throw CBORDecodingError.invalidInitialByte(initial)
		}
	}

	private func decodeByteString(cursor: inout Cursor, additionalInfo: UInt8, depth: Int)
		throws
		-> Data
	{
		guard let length = try readLength(additionalInfo, cursor: &cursor) else {
			// Indefinite length
			var chunks = Data()
			while true {
				let next = try cursor.peekByte()
				if next == 0xFF {
					cursor.advance()
					break
				}
				let value = try decodeValue(cursor: &cursor, depth: depth + 1)
				guard case .byteString(let data) = value else {
					throw CBORDecodingError.invalidChunkType(
						expected: "byte string chunk")
				}
				chunks.append(data)
			}
			return chunks
		}
		guard length <= UInt64(Int.max) else {
			throw CBORDecodingError.lengthOutOfRange
		}
		let bytes = try cursor.read(count: Int(length))
		return bytes
	}

	private func decodeTextString(cursor: inout Cursor, additionalInfo: UInt8, depth: Int)
		throws
		-> String
	{
		if let length = try readLength(additionalInfo, cursor: &cursor) {
			guard length <= UInt64(Int.max) else {
				throw CBORDecodingError.lengthOutOfRange
			}
			let bytes = try cursor.read(count: Int(length))
			guard let text = String(data: bytes, encoding: .utf8) else {
				throw CBORDecodingError.invalidUTF8(bytes)
			}
			return text
		}

		// Indefinite length text string
		var buffer = Data()
		while true {
			let next = try cursor.peekByte()
			if next == 0xFF {
				cursor.advance()
				break
			}
			let chunk = try decodeValue(cursor: &cursor, depth: depth + 1)
			guard case .textString(let string) = chunk else {
				throw CBORDecodingError.invalidChunkType(
					expected: "text string chunk")
			}
			buffer.append(contentsOf: string.utf8)
		}
		guard let text = String(data: buffer, encoding: .utf8) else {
			throw CBORDecodingError.invalidUTF8(buffer)
		}
		return text
	}

	private func decodeArray(cursor: inout Cursor, additionalInfo: UInt8, depth: Int) throws
		-> CBORValue
	{
		if let length = try readLength(additionalInfo, cursor: &cursor) {
			guard length <= UInt64(Int.max) else {
				throw CBORDecodingError.lengthOutOfRange
			}
			var items: [CBORValue] = []
			items.reserveCapacity(Int(length))
			for _ in 0..<length {
				let element = try decodeValue(cursor: &cursor, depth: depth + 1)
				items.append(element)
			}
			return .array(items)
		}

		var items: [CBORValue] = []
		while true {
			let next = try cursor.peekByte()
			if next == 0xFF {
				cursor.advance()
				break
			}
			let element = try decodeValue(cursor: &cursor, depth: depth + 1)
			items.append(element)
		}
		return .array(items)
	}

	private func decodeMap(cursor: inout Cursor, additionalInfo: UInt8, depth: Int) throws
		-> CBORValue
	{
		if let length = try readLength(additionalInfo, cursor: &cursor) {
			guard length <= UInt64(Int.max) else {
				throw CBORDecodingError.lengthOutOfRange
			}
			var pairs: [(CBORValue, CBORValue)] = []
			pairs.reserveCapacity(Int(length))
			for _ in 0..<length {
				let key = try decodeValue(cursor: &cursor, depth: depth + 1)
				let value = try decodeValue(cursor: &cursor, depth: depth + 1)
				pairs.append((key, value))
			}
			return .map(pairs)
		}

		var pairs: [(CBORValue, CBORValue)] = []
		while true {
			let next = try cursor.peekByte()
			if next == 0xFF {
				cursor.advance()
				break
			}
			let key = try decodeValue(cursor: &cursor, depth: depth + 1)
			let value = try decodeValue(cursor: &cursor, depth: depth + 1)
			pairs.append((key, value))
		}
		return .map(pairs)
	}

	private func decodeSimpleOrFloat(cursor: inout Cursor, additionalInfo: UInt8) throws
		-> CBORValue
	{
		switch additionalInfo {
		case 20:
			return .bool(false)
		case 21:
			return .bool(true)
		case 22:
			return .null
		case 23:
			return .undefined
		case 24:
			let byte = try cursor.readByte()
			return .simple(byte)
		case 25:
			let bytes = try cursor.read(count: 2)
			let raw = UInt16(bytes[0]) << 8 | UInt16(bytes[1])
			return .half(raw)
		case 26:
			let bytes = try cursor.read(count: 4)
			let raw = bytes.reduce(0) { ($0 << 8) | UInt32($1) }
			return .float(Float(bitPattern: raw))
		case 27:
			let bytes = try cursor.read(count: 8)
			let raw = bytes.reduce(0) { ($0 << 8) | UInt64($1) }
			return .double(Double(bitPattern: raw))
		case 31:
			throw CBORDecodingError.unexpectedBreak
		default:
			if additionalInfo < 24 {
				return .simple(additionalInfo)
			}
			throw CBORDecodingError.invalidAdditionalInfo(additionalInfo)
		}
	}

	private func readLength(_ info: UInt8, cursor: inout Cursor) throws -> UInt64? {
		switch info {
		case 0...23:
			return UInt64(info)
		case 24:
			let byte = try cursor.readByte()
			return UInt64(byte)
		case 25:
			let raw = try cursor.read(count: 2)
			return UInt64(UInt16(raw[0]) << 8 | UInt16(raw[1]))
		case 26:
			let raw = try cursor.read(count: 4)
			return raw.reduce(0) { ($0 << 8) | UInt64($1) }
		case 27:
			let raw = try cursor.read(count: 8)
			return raw.reduce(0) { ($0 << 8) | UInt64($1) }
		case 31:
			return nil
		default:
			throw CBORDecodingError.invalidAdditionalInfo(info)
		}
	}

	// MARK: - Cursor

	private struct Cursor {
		let data: Data
		var index: Data.Index

		init(data: Data) {
			self.data = data
			self.index = data.startIndex
		}

		var isAtEnd: Bool {
			index >= data.endIndex
		}

		mutating func readByte() throws -> UInt8 {
			guard index < data.endIndex else {
				throw CBORDecodingError.unexpectedEndOfData
			}
			let byte = data[index]
			index = data.index(after: index)
			return byte
		}

		mutating func peekByte() throws -> UInt8 {
			guard index < data.endIndex else {
				throw CBORDecodingError.unexpectedEndOfData
			}
			return data[index]
		}

		mutating func advance() {
			index = data.index(after: index)
		}

		mutating func read(count: Int) throws -> Data {
			guard count >= 0 else {
				throw CBORDecodingError.lengthOutOfRange
			}
			guard data.distance(from: index, to: data.endIndex) >= count else {
				throw CBORDecodingError.unexpectedEndOfData
			}
			let end = data.index(index, offsetBy: count)
			let slice = data[index..<end]
			index = end
			return Data(slice)
		}
	}
}
