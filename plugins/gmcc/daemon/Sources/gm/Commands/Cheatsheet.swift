import ArgumentParser
import GMCCDaemonKit

// gm cheatsheet — a compact, full-surface reference compiled into the binary
// so it can never drift from installed capabilities. Pure client-side: no
// daemon socket, works with the daemon down. detect_repo.sh prints it into
// SessionStart hook stdout; subagent tiers paste it into worker prompts.
// CheatsheetTests walks the GM command tree and refuses to ship a verb
// without a sheet line.
struct Cheatsheet: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Compact full-surface gm reference: one signature line per verb + invariants. Printed into context at SessionStart.")

    static let text: String = """
    GM CHEATSHEET (wire v\(GMCCWireProtocol.version)) — exact signatures. Every command also accepts --json (raw wire response; the form skills/bots should parse).
    CORE
      gm setup [--launchd]
      gm status
      gm ping
      gm daemon start · gm daemon stop · gm daemon restart · gm daemon status
      gm backup
      gm events [--kind K] [--subject-uuid U] [--since-id N] [--since-time ISO] [--until-time ISO] [--limit N] [--follow]
      gm paths
      gm config set --key ckfs_root|kbite_root|kbite_open_root|kbite_digested_root --value V
    CONTEXT / BROWSE / SEARCH
      gm context ensure
      gm context get
      gm project list
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
    DOPE (domain modeling; dope_scope.revision = the whole-tree counter = the .doped.json version field; json refs are dot-path codes, granular verbs take uuids)
      gm dope init --session-uuid U --code C --name N [--prompt-uuid U] [--description D] [--clone-from-session-base]   (idempotent; PROMPT-typed iff --prompt-uuid)
      gm dope list --session-uuid U [--prompt-uuid U]   (scope rows for a picker; SESSION_BASE scopes, or ONLY that prompt's PROMPT scopes with --prompt-uuid — never a union; empty list is normal, unknown uuid is NOT_FOUND)
      gm dope get --session-uuid U [--prompt-uuid U] [--code C]   (PROMPT scope preferred, SESSION_BASE fallback; --code disambiguates)
      gm dope scope-update --uuid U --expected-version V [--code C] [--name N] [--description D]
      gm dope domain-add · gm dope entity-add · gm dope enum-add · gm dope option-add --parent-uuid U --code C --name N [--description D] [--sort-order N] (entity also: [--entity-type MODEL|JUNCTION|BASE_COMPOSABLE] [--base-composable-uuid U]; entity/enum also: [--repo-representative-file P])
      gm dope property-add --parent-uuid U --code C --name N --data-type enum|relationship|boolean|uuid|int|long|decimal|text|datetime [--nullable|--no-nullable] [--is-unique|--no-is-unique] [--auto-increment|--no-auto-increment] [--text-char-limit N] [--enum-uuid U] [--related-property-uuid U] [--base-origin-uuid U] [--description D] [--sort-order N]
      gm dope domain-update · gm dope entity-update · gm dope enum-update · gm dope option-update --uuid U --expected-version V [--code C] [--name N] [--description D] [--sort-order N] (entity also: [--entity-type T] [--base-composable-uuid U] [--clear-base-composable]; entity/enum also: [--repo-representative-file P] [--clear-repo-representative-file])
      gm dope property-update --uuid U --expected-version V [--code C] [--name N] [--description D] [--sort-order N] [--data-type T] [--nullable|--no-nullable] [--is-unique|--no-is-unique] [--auto-increment|--no-auto-increment] [--text-char-limit N] [--enum-uuid U] [--related-property-uuid U] [--base-origin-uuid U] [--clear-enum] [--clear-related-property] [--clear-auto-increment] [--clear-text-char-limit] [--clear-base-origin]
      gm dope domain-delete · gm dope entity-delete · gm dope property-delete · gm dope enum-delete · gm dope option-delete --uuid U --expected-version V   (subtree cascades; still-referenced targets refused naming the referrer; scope delete not offered yet)
      gm dope read-repo (--scope-uuid U | --dir-path P)   (parse + validate {instance_root}/.gmcc/dope; never writes; reports drift)
      gm dope write-repo --scope-uuid U [--force]   (db -> files, atomic whole-tree swap; refuses when files are AHEAD of the db unless --force)
      gm dope ingest --scope-uuid U [--dir-path P]   (files -> db whole-tree overwrite, no smart diff, child uuids change; on-disk version must be EXACTLY db revision + 1)
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
    OTHER
      gm cheatsheet   (this sheet)
    INVARIANTS
      - Thread --expected-version on every mutation; on VERSION_CONFLICT re-run the matching get, take .version, retry.
      - gm prompt set-status is the ONLY door that moves a prompt; clarify/arch/explore/review verbs touch their summary only.
      - Always pass --prompt-uuid on gm file-change add — the implementation-state comparison sees only attributed changes.
      - SUMMARY_ABSENT means the prompt exists but that summary was never opened — open it (gm clarify/arch/explore/review open); for dope it means the session/prompt exists but no scope was ever initialized (gm dope init). Never a file fallback.
      - Dope refs in .doped.json are dot-path codes, never uuids (domain.entity.property / domain.enums.enum_code / domain.entity for base composables); granular dope verbs bump revision by 1 each and leave row versions to --expected-version.
      - A base_composable target must be a BASE_COMPOSABLE entity in the same scope; chaining is allowed, cycles are refused, and deleting a still-composed base (or its domain) is refused naming the composer.
      - A materialized property tags its origin (base_origin_ref: domain.entity.property): the origin must live on a base the entity composes and keep its data_type; changing a base that strands a tag, or deleting a tagged origin, is refused naming the referrer.
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
