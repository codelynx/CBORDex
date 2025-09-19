# CBORDex

## Overview
`CBORDex` is a Swift Package that provides a lightweight CBOR encoder/decoder pair. It focuses on ergonomics for app and service code that needs to produce deterministic, standards-aligned CBOR for tasks such as signing, transport framing, or diagnostic tooling. The implementation follows [RFC 8949](https://www.rfc-editor.org/rfc/rfc8949) and offers an opt-in canonical mode for lexicographic map ordering and preferred floating-point encodings.

## Setup
Add the package to your `Package.swift` manifest:

```swift
.package(url: "https://github.com/codelynx/CBORDex.git", from: "0.1.0")
```

Then depend on `CBORDex` in your target:

```swift
.target(
    name: "App",
    dependencies: ["CBORDex"]
)
```

## Programming Guide
Start by constructing a `CBORValue` tree and using `CBOREncoder` to serialise it:

```swift
let value: CBORValue = .map([
    (.textString("device"), .unsigned(42)),
    (.textString("ok"), .bool(true))
])

var options = CBOREncoder.Options()
options.canonicalMapOrdering = true
let encoder = CBOREncoder(options: options)
let data = try encoder.encode(value)
// data is ready for transmission or signing
```

To parse binary CBOR, hand the data buffer to `CBORDecoder`:

```swift
let decoder = CBORDecoder()
let decoded = try decoder.decode(data)
```

The resulting `CBORValue` is `Equatable`, making test assertions straightforward. Extend the enum with helpers if you want domain-specific projections.

Canonical mode currently covers map ordering and preferred floating-point forms. Other determinism rules from RFC 8949 (e.g., prohibiting duplicate keys or indefinite-length items) are not enforced yet, so layer additional validation if your protocol demands fully canonical CBOR.

## Internal Architecture
The package is split into three main files under `Sources/CBORDex/`:

- `CBORValue.swift` defines the strongly typed in-memory model for CBOR items.
- `CBOREncoder.swift` walks a `CBORValue` tree and emits RFC 8949-compliant bytes, including optional canonical ordering and preferred floating-point encodings.
- `CBORDecoder.swift` implements a streaming cursor that reconstructs `CBORValue` instances from binary input and surfaces errors such as trailing data or invalid UTF-8.

Tests under `Tests/CBORDexTests/` exercise encoding, decoding, canonical ordering, and error paths via XCTest.

## Standards & Compatibility
- Encoding/decoding semantics are based on RFC 8949.
- Canonical behaviors target RFC 8949 §4.2 (preferred serialization); duplicate-key checks and rejection of indefinite-length items are left to callers for now.
- Streaming (incremental) decoding/encoding is not implemented; all data is materialised as `CBORValue` before processing.

## Environment
- Swift tools version: 6.2
- Minimum supported platforms: macOS 11, iOS 14, tvOS 14, watchOS 7
- No external dependencies beyond Foundation

## License
Distributed under the MIT License. See `LICENSE` for details.
