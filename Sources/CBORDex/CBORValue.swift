import Foundation

/// An in-memory representation of a CBOR data item.
public indirect enum CBORValue: Equatable {
	case unsigned(UInt64)
	case negative(UInt64)  // Stores the CBOR argument; actual value is -1 - n
	case byteString(Data)
	case textString(String)
	case array([CBORValue])
	case map([(CBORValue, CBORValue)])
	case tagged(UInt64, CBORValue)
	case simple(UInt8)
	case bool(Bool)
	case null
	case undefined
	case half(UInt16)
	case float(Float)
	case double(Double)

	/// Convenience helper for integer literals.
	public static func integer(_ value: Int64) -> CBORValue {
		if value >= 0 {
			return .unsigned(UInt64(value))
		} else {
			return .negative(UInt64(bitPattern: ~value))
		}
	}
}

extension CBORValue {
	/// Returns true when the value is representable as a finite number.
	public var isNumeric: Bool {
		switch self {
		case .unsigned, .negative, .half, .float, .double:
			return true
		default:
			return false
		}
	}

	/// Attempts to expose the numeric value as a signed 128-bit integer represented by sign and magnitude.
	public var integerComponents: (sign: Int, magnitude: UInt64)? {
		switch self {
		case .unsigned(let value):
			return (1, value)
		case .negative(let value):
			return (-1, value)
		default:
			return nil
		}
	}
}

extension CBORValue {
	public static func == (lhs: CBORValue, rhs: CBORValue) -> Bool {
		switch (lhs, rhs) {
		case (.unsigned(let lhs), .unsigned(let rhs)):
			return lhs == rhs
		case (.negative(let lhs), .negative(let rhs)):
			return lhs == rhs
		case (.byteString(let lhs), .byteString(let rhs)):
			return lhs == rhs
		case (.textString(let lhs), .textString(let rhs)):
			return lhs == rhs
		case (.array(let lhs), .array(let rhs)):
			guard lhs.count == rhs.count else { return false }
			for (left, right) in zip(lhs, rhs) {
				if left != right { return false }
			}
			return true
		case (.map(let lhs), .map(let rhs)):
			guard lhs.count == rhs.count else { return false }
			for ((lKey, lValue), (rKey, rValue)) in zip(lhs, rhs) {
				if lKey != rKey || lValue != rValue { return false }
			}
			return true
		case (.tagged(let ltag, let lvalue), .tagged(let rtag, let rvalue)):
			return ltag == rtag && lvalue == rvalue
		case (.simple(let lhs), .simple(let rhs)):
			return lhs == rhs
		case (.bool(let lhs), .bool(let rhs)):
			return lhs == rhs
		case (.null, .null):
			return true
		case (.undefined, .undefined):
			return true
		case (.half(let lhs), .half(let rhs)):
			return lhs == rhs
		case (.float(let lhs), .float(let rhs)):
			return lhs.bitPattern == rhs.bitPattern
		case (.double(let lhs), .double(let rhs)):
			return lhs.bitPattern == rhs.bitPattern
		default:
			return false
		}
	}
}
