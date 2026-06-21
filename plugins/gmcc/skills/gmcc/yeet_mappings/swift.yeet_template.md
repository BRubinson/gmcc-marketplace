# YEETS → Swift Mapping Template

**Target language**: Swift 5.9+
**Target null model**: native `Optional<T>` (sugar: `T?`)
**Identifier casing**: YEETS is `snake_case` everywhere; Swift is `lowerCamelCase` for fields and `UpperCamelCase` for types. The mapping converts at the boundary — see [Naming](#naming) below.
**File layout**: one YEETS package = one Swift module (or one `.swift` file when a module is overkill). Each section under `## DEFAULT` / `## Other` becomes either a nested `enum` namespace or a separate file inside the module — pick per package.

The YEETS grammar lives in `skills/gmcc/SKILL.md ## YEETS`. This file is mapping-only; if a rule conflicts with the grammar, the grammar wins.

---

## Naming

| YEETS identifier | Swift identifier |
|------------------|------------------|
| `payment_status` (enum / struct name) | `PaymentStatus` |
| `display_name` (field) | `displayName` |
| `gmcc`, `ui.graphs.line` (package) | `GMCC`, `UI.Graphs.Line` module name or `GMCC`, `UIGraphsLine` flat module |
| Enum case `pending | PENDING` | `case pending` (case name from the variable side) |

The variable-side identifier is the source of truth. The pipe-RHS string (`PENDING`) is the serialized form — see [Enums](#enums).

Casing drift between a YEETS file and its Swift codegen is a compile error in YEETS (see grammar), even if the lowering is mechanical. Always round-trip through the YEETS spelling, never the Swift spelling.

---

## Primary types

| YEETS | Swift | Notes |
|-------|-------|-------|
| `string` | `String` | |
| `character` | `Character` | Not `Unicode.Scalar`; YEETS `character` is a grapheme cluster, matching Swift's `Character`. |
| `int` | `Int` | Use `Int64` if the package is shared with code that requires fixed width. Default `Int` is fine for in-process use. |
| `decimal` | `Decimal` | From `Foundation`. Do **not** use `Double` — YEETS `decimal` is explicitly high-precision. |
| `timestamp` | `Int64` (ms since epoch) | YEETS `timestamp` is millisecond epoch; keep the integer form on the wire. Convert to `Date` at the UI boundary via `Date(timeIntervalSince1970: TimeInterval(ms) / 1000)`. |

ISO-8601 strings (e.g. `"2026-06-20T23:56:34Z"`) are `String` in YEETS for v6.0.x, so they map to `String` in Swift — not `Date`. Parsing happens at the boundary, not inside the type.

---

## Nullability

YEETS uses `?` as a **type suffix**: `decimal?`, `Map<string, string?>`, `Struct<payee>?`. Swift uses `Optional<T>` with the same `?` sugar, and the mapping is direct.

| YEETS | Swift |
|-------|-------|
| `decimal?` | `Decimal?` |
| `Map<string, string?>` | `[String: String?]` |
| `Map<string, string>?` | `[String: String]?` |
| `Struct<payee>?` | `Payee?` |

Non-nullable YEETS fields map to non-Optional Swift properties. **Do not** use `!` (implicitly unwrapped optionals) — YEETS makes nullability explicit, and so should the Swift surface.

---

## Parametric collections

| YEETS | Swift | Notes |
|-------|-------|-------|
| `List<T>` | `[T]` (aka `Array<T>`) | Ordered. |
| `Set<T>` | `Set<T>` | `T` must be `Hashable` — every YEETS type lowers to a `Hashable` Swift type when you adopt the boilerplate in [Struct conformances](#struct-conformances). |
| `Map<K, V>` | `[K: V]` (aka `Dictionary<K, V>`) | `K` must be `Hashable`. Same note as `Set`. |

Nullability composes through parameters exactly as the YEETS grammar describes. The full table:

| YEETS | Swift |
|-------|-------|
| `List<T>` | `[T]` |
| `List<T?>` | `[T?]` |
| `List<T>?` | `[T]?` |
| `List<T?>?` | `[T?]?` |
| `Set<T>` | `Set<T>` |
| `Map<K, V>` | `[K: V]` |
| `Map<K, V?>` | `[K: V?]` |
| `Map<K, V>?` | `[K: V]?` |

---

## Enums

YEETS enums declare a `type:` (backing type, default `string`) and `values:` (a list of `variable | serialized` rows). Lower to a Swift `enum` with a `RawValue` matching the backing type.

| YEETS backing | Swift `RawValue` |
|---------------|------------------|
| `string` (default) | `String` |
| `int` | `Int` |
| `character` | `Character` |

YEETS source:

```yaml
enums:
  payment_status:
    description: |
      Current status of a payment.
    type: string
    values:
      - draft | DRAFT
      - pending | PENDING
      - disbursed | DISBURSED
      - cashed | CASHED
```

Swift lowering:

```swift
public enum PaymentStatus: String, Codable, Hashable, CaseIterable, Sendable {
    case draft = "DRAFT"
    case pending = "PENDING"
    case disbursed = "DISBURSED"
    case cashed = "CASHED"
}
```

Notes:
- The case identifier comes from the **left** side of the pipe (YEETS variable).
- The `rawValue` comes from the **right** side (serialized form).
- Always conform to `Codable`, `Hashable`, `CaseIterable`, `Sendable`. These four are the boilerplate floor for YEETS-mapped enums.

---

## Structs

YEETS structs have a `description:` (optional) and `fields:` (required). Each field is either a compact `name: type` line or an expanded `name:` map with `type:` + `description:`. Lower to a Swift `struct`.

YEETS source:

```yaml
structs:
  payee:
    description: |
      A payment recipient.
    fields:
      id: string
      display_name: string?
  payment:
    description: |
      A payment record.
    fields:
      status:
        type: Enum<payment_status>
        description: |
          Lifecycle status of the payment.
      amount: decimal
      payee: Struct<payee>
      created_at: timestamp
      disbursed_at: timestamp?
      cashed_at: timestamp?
      reconciled_at: timestamp?
```

Swift lowering:

```swift
public struct Payee: Codable, Hashable, Sendable {
    public let id: String
    public let displayName: String?

    public init(id: String, displayName: String? = nil) {
        self.id = id
        self.displayName = displayName
    }
}

public struct Payment: Codable, Hashable, Sendable {
    /// Lifecycle status of the payment.
    public let status: PaymentStatus
    public let amount: Decimal
    public let payee: Payee
    public let createdAt: Int64
    public let disbursedAt: Int64?
    public let cashedAt: Int64?
    public let reconciledAt: Int64?

    private enum CodingKeys: String, CodingKey {
        case status
        case amount
        case payee
        case createdAt = "created_at"
        case disbursedAt = "disbursed_at"
        case cashedAt = "cashed_at"
        case reconciledAt = "reconciled_at"
    }

    public init(
        status: PaymentStatus,
        amount: Decimal,
        payee: Payee,
        createdAt: Int64,
        disbursedAt: Int64? = nil,
        cashedAt: Int64? = nil,
        reconciledAt: Int64? = nil
    ) {
        self.status = status
        self.amount = amount
        self.payee = payee
        self.createdAt = createdAt
        self.disbursedAt = disbursedAt
        self.cashedAt = cashedAt
        self.reconciledAt = reconciledAt
    }
}
```

### Struct conformances

Every YEETS-mapped struct adopts, at minimum: `Codable, Hashable, Sendable`. Add `Identifiable` whenever the struct has a non-optional `id: string` field — common enough to be worth the convention.

`CodingKeys` is required whenever any field name differs between YEETS (`snake_case`) and Swift (`lowerCamelCase`). Generate it mechanically; do not rely on `JSONDecoder.keyDecodingStrategy = .convertFromSnakeCase` because round-tripping through XML / YAML (also required by the YEETS grammar) breaks that assumption.

### Required vs optional fields

A non-nullable YEETS field has **no default** in the Swift initializer — the caller must pass it. A nullable YEETS field defaults to `nil`. This keeps the wire shape (which `Codable` controls separately) decoupled from the ergonomic surface.

### Recursive references

The YEETS grammar allows recursive struct refs only through nullable fields. In Swift, that means a recursive field is `T?` and the struct stays a value type — no `class` or `indirect` needed unless the recursion is also non-empty at all depths (which YEETS disallows).

---

## Mapping functions

The grammar restricts YEETS-defined functions to **pure mapping functions that return new instances — never mutate in place**. In Swift, lower to free functions, static methods, or instance methods marked with no `mutating` keyword. Prefer instance methods that return `Self`:

```swift
extension Payment {
    public func withStatus(_ status: PaymentStatus) -> Payment {
        Payment(
            status: status,
            amount: amount,
            payee: payee,
            createdAt: createdAt,
            disbursedAt: disbursedAt,
            cashedAt: cashedAt,
            reconciledAt: reconciledAt
        )
    }
}
```

Never expose `var` stored properties on a YEETS-mapped struct — use `let`. Computed `var` properties are fine because they cannot mutate.

---

## Imports / package resolution

YEETS `import {package}` statements lower one-to-one to Swift `import` statements when each YEETS package is its own Swift module. When several YEETS packages share a Swift module (common for small projects), the YEETS imports become documentation only — the types are already in scope.

There is no inheritance in YEETS; do not use Swift `class` or protocol inheritance to model YEETS imports. Composition via `Struct<...>` fields is the only relationship.

---

## Open questions

These items are not yet pinned down by the YEETS grammar; flag the choice at the package level rather than per-struct.

- **Module naming for dotted packages.** `ui.graphs.line` could become a Swift module `UIGraphsLine`, nested types `UI.Graphs.Line`, or a SwiftPM target hierarchy. Pick per project, document in the package's `README` or top of the generated file.
- **`timestamp` ergonomics.** The mapping above keeps `timestamp` as `Int64` to preserve the on-the-wire shape. Some projects will prefer a `Date` property + private `Int64` for `Codable`. The grammar does not forbid this; treat as a project-level choice.
- **Serializer choice.** `Codable` is assumed throughout, but a project using Swift Protobuf or `Sendable`-only IPC may need a parallel conformance set. The YEETS grammar requires JSON / XML / YAML / YEETS serializability, so any Swift representation must round-trip through at least JSON.
- **`Sendable` of mapped types containing reference types.** All primary and parametric types above are `Sendable`. The moment a project adds a non-`Sendable` field through a custom escape hatch, this guarantee breaks — keep YEETS-mapped types pure.
