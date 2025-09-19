# Repository Guidelines

## Project Structure & Module Organization
This Swift Package exposes the `CBORDex` library defined in `Package.swift`. Library sources live under `Sources/CBORDex/`, with dedicated files for encoding (`CBOREncoder.swift`), decoding (`CBORDecoder.swift`), value modelling (`CBORValue.swift`), and shared helpers. XCTest suites reside in `Tests/CBORDexTests/`, mirroring module names. Add new modules by updating `Package.swift` and placing code in a matching `Sources/<target>/` directory so SwiftPM auto-discovers it.

## Build, Test, and Development Commands
Use `swift build` to compile the library; include `-c release` when benchmarking encoder throughput. Run all tests with `swift test`; target a case with `swift test --filter CBORCodecTests/testDecodeNegativeInteger`. Generate coverage locally via `swift test --enable-code-coverage` and inspect results with `llvm-cov export`. During iteration, `swift package describe` is handy to confirm target graphs after edits to `Package.swift`.

## Coding Style & Naming Conventions
Follow idiomatic Swift 6 style with tab-based indentation (see `.swift-format`), braces on the same line, and meaningful `guard` statements for early exits. Types and protocols use `UpperCamelCase`; methods, properties, and enum cases use `lowerCamelCase`. Keep CBOR-focused enums and helpers in `CBORValue.swift` unless a new domain warrants a separate file. Document public APIs with `///` doc comments that explain CBOR semantics. Run `swift format --configuration .swift-format --in-place --recursive Sources Tests` before sending a patch to normalize whitespace and trailing commas.

## Testing Guidelines
Extend the existing XCTest suites, naming methods `test…` and grouping by behavior (e.g., `testDecode…`, `testEncode…`). Provide fixtures that cover canonical ordering, indefinite-length containers, and error paths such as `invalidAdditionalInfo`. When adding new decoding features, include both round-trip and failure expectations so future refactors preserve behavior. Aim to maintain or improve coverage reported by `llvm-cov`; investigate any drop before merging.

## Commit & Pull Request Guidelines
There is no history yet, so adopt a clear, imperative tense commit style such as `Encode floating-point NaN payloads` and squash unrelated fixes. Each pull request should summarize motivation, list major code paths touched, and link any tracking issue. Include test evidence (`swift test`) in the description, and attach sample CBOR payloads or dumps when they help reviewers validate decoder changes quickly.
