#!/usr/bin/env python3
"""Generate `gm diagram batch-apply` mutations from a dope tree.

Turns the output of `gm dope get --json` into one all-or-nothing batch that
lays the whole domain model out as a canvas: one top-level dope_scope
container plus one dope_entity card per entity, grouped in per-domain
columns. Card geometry mirrors the renderer's real formula
(DiagramRenderEnvironment: width 260, height = header 40 + rows*22 + 8,
rows = own properties + the composed-base chain) so nothing overlaps and
the resolver-drawn FK edges stay legible.

Usage:
  diagram_from_dope.py <dope_get.json> <out_mutations.json> [--existing <diagram_get.json>]

With --existing, the batch is a full regenerate: element_delete mutations
for every current top-level element (subtree CASCADE) precede the adds, so
one batch-apply swaps the canvas atomically under the diagram-revision CAS.
Empty domains are skipped. Output is the bare mutations array for
`gm diagram batch-apply --mutations-file`.
"""
import json
import math
import sys

CARD_W = 260.0
HEADER_H = 40.0
ROW_H = 22.0
CARD_PAD = 8.0
X_PITCH = 310.0
DOMAIN_GAP = 40.0
Y_GAP = 48.0
MAX_CARDS_PER_COLUMN = 5


def main() -> None:
    argv = sys.argv[1:]
    if len(argv) not in (2, 4) or (len(argv) == 4 and argv[2] != "--existing"):
        sys.exit(__doc__.strip())
    dope_path, out_path = argv[0], argv[1]
    existing_path = argv[3] if len(argv) == 4 else None

    tree = json.load(open(dope_path))["tree"]
    domains = {d["code"]: d for d in tree["domains"]}

    def base_chain_rows(ref, seen):
        """Property count contributed by the base_composable_ref chain."""
        if not ref or ref in seen:
            return 0
        seen.add(ref)
        dom_code, ent_code = ref.split(".")
        dom = domains.get(dom_code, {})
        ent = next((e for e in dom.get("entities", []) if e["code"] == ent_code), None)
        if ent is None:
            return 0
        return len(ent.get("properties", [])) + base_chain_rows(
            ent.get("base_composable_ref"), seen)

    def card_height(dom_code, ent):
        rows = max(1, len(ent.get("properties", [])) + base_chain_rows(
            ent.get("base_composable_ref"), {f"{dom_code}.{ent['code']}"}))
        return HEADER_H + rows * ROW_H + CARD_PAD

    mutations = []

    if existing_path:
        for el in json.load(open(existing_path))["tree"]["elements"]:
            mutations.append({
                "kind": "element_delete",
                "fields": {"element_uuid": el["uuid"],
                           "expected_version": el["version"]},
            })

    mutations.append({
        "kind": "element_add",
        "fields": {
            "client_ref": "scope",
            "code": "scope_" + tree["code"],
            "name": tree["name"],
            "center_x": 0, "center_y": 0, "element_z": 0,
            "payload": {"kind": "dope_scope",
                        "fields": {"dope_scope_code": tree["code"]}},
        },
    })

    x_cursor = 0.0
    sort = 0
    for dom in sorted(tree["domains"], key=lambda d: d.get("sort_order", 0)):
        ents = sorted(dom.get("entities", []), key=lambda e: e.get("sort_order", 0))
        if not ents:
            continue
        ncols = math.ceil(len(ents) / MAX_CARDS_PER_COLUMN)
        per_col = math.ceil(len(ents) / ncols)
        for ci in range(ncols):
            col_x = x_cursor + ci * X_PITCH
            y_cursor = 0.0
            for ent in ents[ci * per_col:(ci + 1) * per_col]:
                h = card_height(dom["code"], ent)
                sort += 1
                mutations.append({
                    "kind": "element_add",
                    "fields": {
                        "parent_client_ref": "scope",
                        "code": f"{dom['code']}_{ent['code']}",
                        "name": ent["name"],
                        "sort_order": sort,
                        "center_x": col_x, "center_y": y_cursor + h / 2,
                        "element_z": float(sort),
                        "payload": {
                            "kind": "dope_entity",
                            "fields": {"entity_code": f"{dom['code']}.{ent['code']}"},
                        },
                    },
                })
                y_cursor += h + Y_GAP
        x_cursor += ncols * X_PITCH + DOMAIN_GAP

    json.dump(mutations, open(out_path, "w"), indent=1)
    adds = sum(1 for m in mutations if m["kind"] == "element_add")
    deletes = len(mutations) - adds
    print(f"{len(mutations)} mutations ({deletes} deletes, {adds} adds) -> {out_path}")


if __name__ == "__main__":
    main()
