import ArgumentParser
import GMCCDaemonKit

// gm cheatsheet — a compact, full-surface reference compiled into the binary
// so it can never drift from installed capabilities. Pure client-side: no
// daemon socket, works with the daemon down. gmcc_session_startup.sh prints it into
// SessionStart hook stdout; subagent tiers paste it into worker prompts.
// CheatsheetTests walks the GM command tree and refuses to ship a verb
// without a sheet line.
struct Cheatsheet: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Compact full-surface gm reference: one signature line per verb + invariants. Printed into context at SessionStart.")

    static let text: String = """
    GM CHEATSHEET (wire v\(GMCCWireProtocol.version)) — exact signatures. Every command also accepts --json (raw wire response; the form skills/bots should parse).
    CORE
      gm setup [--launchd] [--install-path [--path-dir DIR]]   (--install-path puts the call-time gm resolver shim on your PATH; both flags prod-only, refused under GMCC_ROOT)
      gm doctor   (host-wiring findings: env-vs-db roots, PATH shim, retired zshrc block, daemon health, session dope drift; exit 1 = findings)
      gm status
      gm ping
      gm daemon start · gm daemon stop · gm daemon restart · gm daemon status
      gm backup
      gm events [--kind K] [--subject-uuid U] [--since-id N] [--since-time ISO] [--until-time ISO] [--limit N] [--follow]
      gm paths
      gm config set --key ckfs_root|kbite_root|kbite_open_root|kbite_digested_root --value V
    CONTEXT / BROWSE / SEARCH
      gm context ensure [--no-dope-sync]   (also provisions the ckfs artifact home and runs the dope files -> db boot sync)
      gm context env --plugin-root P [--no-check]   (SessionStart env contract owner: stdout = KEY=VALUE lines for CLAUDE_ENV_FILE, stderr = warnings, ALWAYS exit 0)
      gm context get
      gm project list
      gm project update --project-uuid U --expected-version V [--primary-project-branch B]   (the only project-level mutation; primary_project_branch is BASE_DOPED_BRANCH, default 'main')
      gm instance list [--project-uuid U]
      gm instance current-session --instance-uuid U
      gm session list [--instance-uuid U]
      gm session get [--session-uuid U]
      gm session update [--session-uuid U] --expected-version V [--name N] [--backstory B] [--goal G]
      gm session resolve [--session-uuid U]
      gm catalog search "<query>" [--project-uuid U] [--limit N]
      gm search "<query>" [--all] [--session-uuid U] [--kind prompt|clarification|clarification_summary|architecture_summary|architecture_general_change|architecture_persistence_change|exploration_summary|exploration_key_file|exploration_finding|review_summary|review_finding]... [--limit N]
    PROMPT (lifecycle: draft → clarifying → architecting → implementing → reviewing → done; reviewing skippable)
      gm prompt create --name N [--code C] [--backstory B] [--goal G] [--detail D] [--command CMD] [--uuid U] [--session-uuid U]
      gm prompt list [--session-uuid U] [--all] [--with-reports]
      gm prompt get --prompt-uuid U
      gm prompt update-content --prompt-uuid U --expected-version V [--backstory B] [--goal G] [--detail D]   (draft-only; CONTENT_LOCKED after)
      gm prompt set-status --prompt-uuid U --expected-version V --status clarifying|architecting|implementing|reviewing|done
    CLARIFY (summary: building → answering → complete; reopen: complete → answering)
      gm clarify open --prompt-uuid U
      gm clarify ask --summary-uuid S --category goal|detail --question Q [--answer A] [--source user|bot_inferred]
      gm clarify seal --summary-uuid S --expected-version V
      gm clarify answer --clarification-uuid C --expected-version V [--answer A] [--source user|bot_inferred] [--skip]
      gm clarify reopen --summary-uuid S --expected-version V
      gm clarify finalize --summary-uuid S --expected-version V --refined-goal G --refined-detail D [--backstory-note N]
      gm clarify get --prompt-uuid U
    ARCH (summary: drafting → proposed → approved; revise: proposed → drafting; persistence rows first, always)
      gm arch open --prompt-uuid U
      gm arch summarize --summary-uuid S --expected-version V --body B
      gm arch persist-add --summary-uuid S --class-name C --file-path P --reason R
      gm arch field-add --persistence-uuid PC --field-name F --data-type T --reason R --purpose P --nullable|--no-nullable [--foreign-key --fk-target table.col] [--indexed]
      gm arch general-add --summary-uuid S --file-path P [--class-name C] --reason R --depth pseudo|draft|actual --code CODE
      gm arch propose --summary-uuid S --expected-version V
      gm arch approve --summary-uuid S --expected-version V
      gm arch revise --summary-uuid S --expected-version V
      gm arch get --prompt-uuid U
    EXPLORE (summary: exploring → complete; reopen: complete → exploring; rating 0=critical … 999=ignore, read threshold 100; key-file-add/finding-add/rank require status exploring)
      gm explore open --prompt-uuid U
      gm explore key-file-add --summary-uuid S --file-path P
      gm explore finding-add --summary-uuid S --kind persistence_model|implementation_pattern|existing_functionality|scope_creep_risk|general_relevant_change|other --title T --body B --agent-name A [--rating 0-999]
      gm explore rank --summary-uuid S --rating <finding-uuid>:<0-999> ...   (atomic batch; re-run re-ranks; refused once complete — reopen first)
      gm explore complete --summary-uuid S --expected-version V (--overview TEXT | --overview-file PATH)   (exactly one overview source required; refuses while any finding unranked)
      gm explore reopen --summary-uuid S --expected-version V
      gm explore get --prompt-uuid U [--full | --max-rating N | --rating-range A:B]   (mutually exclusive)
    REVIEW (same shape as explore + resolve/verdict; the fix loop runs AFTER complete)
      gm review open --prompt-uuid U
      gm review finding-add --summary-uuid S --kind correctness_bug|spec_deviation|regression_risk|security|simplification|other --title T --body B [--file-path P] [--line-start N [--line-end N]] --agent-name A [--rating 0-999]
      gm review rank --summary-uuid S --rating <finding-uuid>:<0-999> ...   (same batch contract; refused once complete — reopen first)
      gm review resolve --finding-uuid F --expected-version V --status fixed|accepted|wont_fix   (post-complete; never back to open)
      gm review complete --summary-uuid S --expected-version V (--overview TEXT | --overview-file PATH) --verdict approved|approved_with_nits|changes_requested
      gm review reopen --summary-uuid S --expected-version V
      gm review get --prompt-uuid U [--full | --max-rating N | --rating-range A:B]   (mutually exclusive)
    DOPE (Domain Optimized Project Essence [Driver — the saved .doped.json form]; dope_scope.revision = the whole-tree counter = the .doped.json version field; json refs are dot-path codes, granular verbs take uuids)
      gm dope init --session-uuid U --code C --name N [--prompt-uuid U] [--description D] [--clone-from-session-base]   (idempotent; PROMPT-typed iff --prompt-uuid)
      gm dope list --session-uuid U [--prompt-uuid U]   (scope rows for a picker; SESSION_BASE scopes, or ONLY that prompt's PROMPT scopes with --prompt-uuid — never a union; empty list is normal, unknown uuid is NOT_FOUND)
      gm dope get --session-uuid U [--prompt-uuid U] [--code C] [--resolved]   (SESSION_INSTANCE_ITEM preferred, SESSION_INSTANCE fallback; --code disambiguates; --resolved merges a masking overlay over its same-coded base one tier up and reports provenance + masked-away paths)
      gm dope promote --session-uuid U [--code C] [--dry-run]   (SESSION_INSTANCE -> BASE_PROJECT; primary-branch sessions only, gated on a promoted_from_* high-water so it never ping-pongs between instances or re-fires on an unchanged tree; also runs automatically at boot behind the dope sync)
      gm dope scope-update --uuid U --expected-version V [--code C] [--name N] [--description D]
      gm dope persistence-add · gm dope entity-add · gm dope enum-add · gm dope option-add --parent-uuid U --code C --name N [--description D] [--sort-order N] (entity also: [--entity-type MODEL|JUNCTION|BASE_COMPOSABLE] [--base-composable-uuid U]; entity/enum also: [--repo-representative-file P])
      gm dope property-add --parent-uuid U --code C --name N --data-type enum|relationship|boolean|uuid|int|long|decimal|text|datetime [--nullable|--no-nullable] [--is-unique|--no-is-unique] [--auto-increment|--no-auto-increment] [--text-char-limit N] [--enum-uuid U] [--related-property-uuid U] [--base-origin-uuid U] [--description D] [--sort-order N]
      gm dope persistence-update · gm dope entity-update · gm dope enum-update · gm dope option-update --uuid U --expected-version V [--code C] [--name N] [--description D] [--sort-order N] (entity also: [--entity-type T] [--base-composable-uuid U] [--clear-base-composable]; entity/enum also: [--repo-representative-file P] [--clear-repo-representative-file])
      gm dope property-update --uuid U --expected-version V [--code C] [--name N] [--description D] [--sort-order N] [--data-type T] [--nullable|--no-nullable] [--is-unique|--no-is-unique] [--auto-increment|--no-auto-increment] [--text-char-limit N] [--enum-uuid U] [--related-property-uuid U] [--base-origin-uuid U] [--clear-enum] [--clear-related-property] [--clear-auto-increment] [--clear-text-char-limit] [--clear-base-origin]
      gm dope persistence-delete · gm dope entity-delete · gm dope property-delete · gm dope enum-delete · gm dope option-delete --uuid U --expected-version V [--soft]   (hard: subtree cascades, still-referenced targets refused naming the referrer; --soft: MASKING SCOPES ONLY (PROJECT_ITEM/SESSION_INSTANCE_ITEM) -- stamps deleted_on as a whiteout, no cascade, no referrer guard, reads still return it, and it NEVER reaches the saved .doped.json; scope delete not offered yet)
      gm dope read-repo (--scope-uuid U | --dir-path P)   (parse + validate {instance_root}/.gmcc/dope; never writes; reports drift)
      gm dope write-repo --scope-uuid U [--force]   (db -> files, atomic whole-tree swap; refuses when files are AHEAD of the db unless --force)
      gm dope ingest --scope-uuid U [--dir-path P] [--adopt]   (files -> db whole-tree overwrite, no smart diff, child uuids change; on-disk version must be EXACTLY db revision + 1. --adopt is boot-sync-only: accepts any strictly FORWARD version, discards db-only gap revisions, never moves backward)
      gm dope sync [--session-uuid U]   (files -> db reconcile of the session's SESSION_BASE scope from {instance_root}/.gmcc/dope: seeds a virgin scope, re-adopts when files are ahead, WARNS ONLY when the db is ahead; runs automatically at boot via gm context ensure — run manually after a mid-session branch change)
    DIAGRAM (db-persisted canvases over dope; diagram.revision = whole-tree counter; exactly ONE owner flag picks the tier PROJECT|INSTANCE|SESSION|PROMPT; batch-apply is THE interactive write — the element verbs are one-mutation batches over the same body)
      gm diagram init (--project-uuid U | --instance-uuid U | --session-uuid U | --prompt-uuid U) --code C --name N [--description D] [--gmcc-diagram-path P]   (idempotent per owner+code; path refused at PROJECT tier)
      gm diagram list (--project-uuid U | --instance-uuid U | --session-uuid U | --prompt-uuid U)   (that tier's rows only, never a union; empty is normal, unknown owner NOT_FOUND)
      gm diagram get (--diagram-uuid U | one owner flag: --project-uuid|--instance-uuid|--session-uuid|--prompt-uuid [--code C])   (tree + dope binding resolutions; no cross-tier fallback; pair with gm dope get for bound trees; real owner with none -> SUMMARY_ABSENT)
      gm diagram update --diagram-uuid U --expected-version V [--code C] [--name N] [--description D] [--gmcc-diagram-path P | --clear-gmcc-diagram-path] [--promote-tier T --promote-owner-uuid O]   (promotion re-derives the owner chain; same project always)
      gm diagram element-add --diagram-uuid U (--content JSON | --content-file P) [--parent-element-uuid P] [--code C] [--name N] [--description D] [--sort-order N] [--center-x X] [--center-y Y] [--element-z Z] [--scale S]   (content = {"kind":element_type,"fields":{...}}, vertices ride inside; omitted code/name are minted)
      gm diagram element-update --uuid U --expected-version V [--code C] [--name N] [--description D] [--sort-order N] [--center-x X] [--center-y Y] [--element-z Z] [--scale S] [--parent-element-uuid P] [--content JSON | --content-file P]   (a present content REPLACES the subtype row + vertex set wholesale)
      gm diagram element-delete --uuid U --expected-version V   (subtree CASCADE; no referrer guards in this family)
      gm diagram batch-apply --diagram-uuid U (--mutations JSON | --mutations-file P) [--expected-revision N]   (one txn/revision/event; strict order; clientRef parenting; all-or-nothing; expected-revision = whole-diagram CAS)
      gm diagram screenshot (--diagram-uuid U | one owner flag: --project-uuid|--instance-uuid|--session-uuid|--prompt-uuid [--code C]) [--scheme light|dark] [--scale N] [--out-name N] [--artifact --artifact-prompt-uuid U]   (client-side headless render -> {instance_root}/.gmcc/.screenshots/, self-gitignored; zero db writes)
      gm diagram from-dope --session-uuid U [--prompt-uuid U] [--code C] [--diagram-code C] [--mutations-out P] [--dry-run]   (dope tree -> one atomic regenerate batch; geometry shared with the renderer; replaces the retired python generator)
    ARTIFACT / FILE-CHANGE
      gm artifact add --prompt-uuid U --file-path P [--note N]
      gm artifact list --prompt-uuid U
      gm file-change add --path P [--kind edit|create|delete|rename] [--range start:end]... [--content TEXT] [--prompt-uuid U]   (--content requires exactly one --range)
      gm file-change list [--session-uuid U] [--prompt-uuid U] [--path P] [--limit N] [--all]
    KBITE
      gm kbite list [--scope project|instance|session|prompt] [--owner-uuid U] [--all]
      gm kbite add --code C [--scope S] [--owner-uuid U]
      gm kbite remove --code C [--scope S] [--owner-uuid U]
      gm kbite maw-open --name N [--maw-path P]
      gm kbite digest --code C [--kbite-open-path P]
      gm kbite get --code C
      gm kbite file-get --file-uuid U
      gm kbite search "<query>" [--code C] [--kbite-uuids U ...] [--limit N]   (bm25-ranked stubs with briefs; read briefs, then file-get)
      gm kbite keyword-tag --level kbite|file --target-uuid U --keywords K ... [--detach]
    SANDBOX (local-dev sandbox at {ckfs_root}/development/local_sandbox; prod db touched ONLY by the Online-Backup read; kbites never copied; never gm setup --launchd in a sandbox)
      gm sandbox refresh   (run from the gmcc-marketplace repo root, prod env only — refuses under GMCC_ROOT; quiesce -> gm backup -> OFFLINE retarget of the staged db (config roots + instance identity + storage paths) -> ckfs subtree rsync -> git clone --local / fetch+reset -> binaries+launchers -> atomic db install -> snapshot_meta.json LAST; re-run is always safe recovery)
      gm sandbox status   (generation, instance code, daemon liveness; a metaless sandbox is partial — re-run refresh)
    OTHER
      gm cheatsheet   (this sheet)
    INVARIANTS
      - Thread --expected-version on every mutation; on VERSION_CONFLICT re-run the matching get, take .version, retry.
      - gm prompt set-status is the ONLY door that moves a prompt; clarify/arch/explore/review verbs touch their summary only.
      - Always pass --prompt-uuid on gm file-change add — the implementation-state comparison sees only attributed changes.
      - SUMMARY_ABSENT means the prompt exists but that summary was never opened — open it (gm clarify/arch/explore/review open); for dope it means the session/prompt exists but no scope was ever initialized (gm dope init). Never a file fallback.
      - Dope refs in .doped.json are dot-path codes, never uuids (domain.entity.property / domain.enums.enum_code / domain.entity for base composables); granular dope verbs bump revision by 1 each and leave row versions to --expected-version.
      - Dope boot sync is strictly files -> db and forward-only: context ensure / dope sync never write repo files and never move revision backward; a db AHEAD of the files only warns (publish with gm dope write-repo). Never use --adopt outside that sync path.
      - A base_composable target must be a BASE_COMPOSABLE entity in the same scope; chaining is allowed, cycles are refused, and deleting a still-composed base (or its domain) is refused naming the composer.
      - A materialized property tags its origin (base_origin_ref: domain.entity.property): the origin must live on a base the entity composes and keep its data_type; changing a base that strands a tag, or deleting a tagged origin, is refused naming the referrer.
      - Diagram dope bindings are CODES resolved at read time through the diagram's own session/prompt context (resolved_via surfaced); a dangling code is a LEGAL state rendered as a ghost, never an error — and dope deletes are never blocked by diagrams.
      - Diagram element geometry: center_x/y are parent-space, vertices are element-local, scale composes down the tree, element_z orders siblings only; the element row's version is the lock for the whole element aggregate (subtype + vertices replace wholesale, vertex row uuids are not stable).
      - Values starting with a dash need --flag=value form (e.g. --content="- item").
      - After gm prompt create, mkdir -p $GMCC_CKFS_ROOT/<ckfs_relative_storage_path>/memory verbatim from the response — never re-derive {seq}_{name}.
    RESPONSE NOTES
      - kbite file-get content may be null: the raw source lives on the filesystem (path in the row), not in the db.
      - status table_counts are point-in-time totals, not an event cursor — replay events via gm events --since-id.
    """

    func run() {
        print(Self.text)
    }
}
