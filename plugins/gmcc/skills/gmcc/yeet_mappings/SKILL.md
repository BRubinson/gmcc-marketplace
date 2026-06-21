---
name: yeet_mappings
description: YEETS-to-language compilation mappings. Defines how YEETS primary types, parametric collections, nullability, enums, and structs lower into idiomatic constructs in concrete target languages (Swift today; Kotlin, TypeScript, and Python+mypy planned). Activate when generating, reviewing, or hand-translating code from a `.yeet.yaml` package or inline `<YEET>` block into a target language, or when extending YEETS with a new compilation target.
user-invocable: false
---

# YEETS Mappings

This skill is the home for **per-target compilation templates** that describe how YEETS lowers into concrete programming languages. YEETS is intentionally close to the typed cores of Kotlin / Swift / TypeScript / Python+mypy (see the `## YEETS` section of `skills/gmcc/SKILL.md` for the authoritative grammar), so each mapping is short — it just pins down the one-true-spelling per target.

---

## Why mappings live in their own files

YEETS is one grammar; targets are many. Keeping the mapping for each language in a sibling `{language}.yeet_template.md` file lets:

- A YEETS author look up "what does `Map<string, decimal?>` become in Swift?" without scanning unrelated guidance.
- A new target be added by writing one new file — no changes to the core spec.
- Code generators consume a single template per target rather than parsing the full grammar doc.

The grammar itself never lives in these files. They are **mappings only** — the source of truth for what types exist is `skills/gmcc/SKILL.md`.

---

## Template file shape

Every `{language}.yeet_template.md` in this directory follows the same outline:

1. **Front matter** — target language + version, identifier-casing rule, file-layout rule (one YEETS package → one target module / file / namespace).
2. **Primary type table** — every YEETS primary type (`string`, `character`, `decimal`, `int`, `timestamp`, `datetime`) on a row, with the target spelling.
3. **Nullability rule** — how the `?` suffix lowers.
4. **Parametric collections** — `Map<K, V>`, `List<T>`, `Set<T>` with the target spelling, including how nullability inside the parameters interacts with the target's null model.
5. **Enum lowering** — including the backing-type variants (`string`, `int`, `character`).
6. **Struct lowering** — field forms (compact + expanded), required vs nullable fields, recursive references.
7. **Mapping functions** — the pure-function constraint from the YEETS grammar, and how it shows up in the target.
8. **Worked example** — one enum + one struct end-to-end, lowered side-by-side with the YEETS source.
9. **Open questions** — anything the YEETS grammar does not yet pin down for this target (e.g., serializer choice, package-system mapping). Each entry is a note, not a blocker.

A reader who knows YEETS should be able to write valid target-language code after reading one of these files end-to-end.

---

## Available targets

| Target | File | Status |
|--------|------|--------|
| Swift | [`swift.yeet_template.md`](./swift.yeet_template.md) | Live |
| Kotlin | — | Planned |
| TypeScript | — | Planned |
| Python (+ mypy / pydantic) | — | Planned |

The four planned targets mirror the language list named in `skills/gmcc/SKILL.md` ("maps 1:1 to most strongly-typed languages — Kotlin/Swift/TypeScript/Python+mypy"). Add a new target by dropping a new `{language}.yeet_template.md` file in this folder, following the shape above, and appending a row to this table.

---

## When to read a specific template

- Generating or hand-writing target code from a YEETS source: read the matching template before producing code, and re-read it whenever you touch a primary type, nullability, or a collection.
- Reviewing target code for YEETS conformance: walk the template's tables and confirm every type spelling matches.
- Adding a feature to YEETS: every mapping file may need a new row. Open an entry in each template's "Open questions" section if the lowering is ambiguous.

This skill itself never generates code — it points to the right per-language file.
