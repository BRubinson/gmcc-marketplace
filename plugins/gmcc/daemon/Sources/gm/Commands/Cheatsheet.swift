import ArgumentParser
import GMCCDaemonKit

// gm cheatsheet — a compact, full-surface reference compiled into the binary
// so it can never drift from installed capabilities. Pure client-side: no
// daemon socket, works with the daemon down. gmcc_session_startup.sh prints it into
// SessionStart hook stdout; the SubagentStart hook injects the compact core
// into spawned agents. CheatsheetTests walks the GM command tree and refuses
// to ship a verb without a sheet line.
struct Cheatsheet: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Compact full-surface gm reference: one signature line per verb + invariants. Printed into context at SessionStart.")

    static let text: String = """
    GM CHEATSHEET (wire v\(GMCCWireProtocol.version)) — exact signatures. Every command also accepts --json (raw wire response; the form skills/bots should parse).
    CORE
      gm setup [--launchd] [--install-path [--path-dir DIR]]   (--install-path puts the call-time gm resolver shim on your PATH; both flags prod-only, refused under GMCC_ROOT)
      gm doctor   (host-wiring findings: env-vs-db roots, PATH shim, stray zshrc env block, daemon health, session dope drift; exit 1 = findings)
      gm status
      gm ping
      gm daemon start · gm daemon stop · gm daemon restart · gm daemon status
      gm backup
      gm events [--kind K] [--subject-uuid U] [--since-id N] [--since-time ISO] [--until-time ISO] [--limit N] [--follow]
      gm paths
      gm config set --key ckfs_root|kbite_root|kbite_open_root|kbite_digested_root --value V
    CONTEXT / BROWSE / SEARCH
      gm context ensure [--no-dope-sync]   (also provisions the ckfs artifact home and runs the dope files -> db boot sync)
      gm context env --plugin-root P [--no-check]   (SessionStart env contract owner: stdout = export KEY='VALUE' lines for CLAUDE_ENV_FILE, stderr = warnings, ALWAYS exit 0)
      gm context get
      gm project list
      gm project update --project-uuid U --expected-version V [--primary-project-branch B]   (the only project-level mutation; primary_project_branch is BASE_DOPED_BRANCH, default 'main')
      gm instance list [--project-uuid U]
      gm instance current-session --instance-uuid U
      gm session list [--instance-uuid U]
      gm session get [--session-uuid U]
      gm session update [--session-uuid U] --expected-version V [--name N] [--backstory B] [--goal G] [--active-prompt-uuid U | --clear-active-prompt]   (activation claims are PER CLAUDE INSTANCE — several prompts stay active on one session concurrently; set-status implementing normally maintains the claim)
      gm session resolve [--session-uuid U]
      gm catalog search "<query>" [--project-uuid U] [--limit N]
      gm search "<query>" [--all] [--session-uuid U] [--kind prompt|clarification|clarification_summary|architecture_summary|architecture_general_change|architecture_persistence_change|exploration_summary|exploration_key_file|exploration_finding|review_summary|review_finding]... [--limit N]
    PROMPT (lifecycle: draft → clarifying → architecting → implementing → reviewing → done; reviewing skippable)
      gm prompt create --name N [--code C] [--backstory B] [--goal G] [--detail D | --detail-file P] [--command CMD] [--uuid U] [--session-uuid U]
      gm prompt list [--session-uuid U] [--all] [--with-reports]
      gm prompt get --prompt-uuid U
      gm prompt update-content --prompt-uuid U --expected-version V [--backstory B] [--goal G] [--detail D | --detail-file P]   (draft-only; CONTENT_LOCKED after)
      gm prompt set-status --prompt-uuid U --expected-version V --status clarifying|architecting|implementing|reviewing|done
      gm prompt start --prompt-uuid U --variant bot|rpi|team   (enter the workflow machine from draft: creates the active bot_workflow row + claims the activation; task deliberately has NO row)
      gm prompt resume --prompt-uuid U [--variant V]   (fetch-or-create the workflow row; phase recomputed from db evidence, so resume and first run are one path)
    BOT (the daemon-held workflow machine: phase DERIVED from db evidence every next; set-status is the only prompt door; zero-uuid = caller's active workflow -> activation prompt -> session's single workflow; every verb takes --prompt-uuid)
      gm bot next [--prompt-uuid U]   (current phase + compiled-in instructions + uuid bundle + gate blockers)
      gm bot get [--prompt-uuid U]   (the raw workflow row)
      gm bot status [--prompt-uuid U]   (row + derived phase + blockers)
      gm bot current_prompt [--prompt-uuid U]   (the workflow prompt's row — agents read the prompt with zero uuid plumbing)
      gm bot briefing [--prompt-uuid U] [--step S]   (the workflow prompt's briefing — a thin wrapper over the briefing family's get)
      gm bot summary --agent-type T [--agent-id A] [--prompt-uuid U]   (fetch-or-open the caller's per-agent exploration summary — identity is self-reported)
      gm bot reconcile [--prompt-uuid U] [--dry-run]   (completeness channel: tree-diff against the workflow's baseline snapshot — records only PROMPT-ERA hook-invisible writes with real delete/rename kinds, then advances the baseline; pre-existing dirt is excluded; the operator-facing form, run at phase gates)
      gm bot sweep [--prompt-uuid U] [--agent-id I] [--agent-name A]   (the same engine under a hook-safe skin, called from Stop/SubagentStop: --json returns {recorded, phase, blockers[]} so one invocation both records the turn's delta and feeds the status line; ambiguous workflow ownership is REFUSED, never guessed)
    CLARIFY (summary: building → answering → complete; reopen: complete → answering. The family carries user questions + option/selection children, internal notes, and the care package. FINALIZE IS A PURE GATE — nothing ever writes prompt content past draft)
      gm clarify open --prompt-uuid U
      gm clarify question-add --summary-uuid S --question Q [--option TEXT]... [--agent-name A] [--agent-id I]   (building only; options are ordered child rows)
      gm clarify note-add --summary-uuid S (--body B | --body-file P) [--confused-entity-uuid U --confused-entity-type exploration_finding|briefing|question|other] [--weight 0-999] [--question-uuid Q] [--agent-name A] [--agent-id I]   (any state; weight polarity 0=critical)
      gm clarify seal --summary-uuid S --expected-version V
      gm clarify answer --question-uuid Q --expected-version V [--answer A | --answer-file P] [--select OPTION_UUID]... [--skip]   (answering only; --select replaces prior selections — multi-select ready; text and selection may coexist)
      gm clarify reopen --summary-uuid S --expected-version V
      gm clarify finalize --summary-uuid S --expected-version V   (pure gate: every question answered/skipped + care package ready where one exists; NEVER writes prompt.goal)
      gm clarify get --prompt-uuid U   (summary + questions + weighted notes + care package)
      gm clarify package-open --summary-uuid S   (create-or-return; multi-agent flows — bot skips it)
      gm clarify package-add --package-uuid P --kind dope|kbite|exploration [--dope-code C --note N] [--kbite-file-uuid U] [--title T (--body B | --body-file F) --file-path FP --source-finding-uuid U]   (building only; exploration entries are curated COPIES — never re-explore)
      gm clarify package-complete --package-uuid P --expected-version V (--intent TEXT | --intent-file F)   (building -> ready; the clarified intent lives ONLY here)
      gm clarify package-get --prompt-uuid U
    ARCH (summary: drafting → proposed → approved; revise: proposed → drafting; persistence rows first, always)
      gm arch open --prompt-uuid U
      gm arch summarize --summary-uuid S --expected-version V (--body B | --body-file P)
      gm arch persist-add --summary-uuid S --class-name C --file-path P --reason R [--change-kind add|modify|rename|delete] [--dope-ref domain.entity]   (change-kind default modify; dope refs are ghost-legal CODES)
      gm arch field-add --persistence-uuid PC --field-name F --data-type T --reason R --purpose P --nullable|--no-nullable [--foreign-key --fk-target table.col] [--indexed] [--change-kind K] [--renamed-from OLD] [--dope-property-ref domain.entity.property]
      gm arch general-add --summary-uuid S --file-path P [--class-name C] --reason R --depth pseudo|draft|actual (--code CODE | --code-file P)
      gm arch option-add --summary-uuid S --agent-name A [--agent-id I] (--body B | --body-file P)   (the architect pen, team flows: one Option row per methodology; once any option exists, change rows refuse until decide)
      gm arch decide --option-uuid O --expected-version V (--rationale R | --rationale-file P)   (stamps selected + rejects siblings + records why; only the selected option expands into change rows)
      gm arch propose --summary-uuid S --expected-version V
      gm arch approve --summary-uuid S --expected-version V
      gm arch revise --summary-uuid S --expected-version V
      gm arch get --prompt-uuid U
    EXPLORE (literal per-agent summaries keyed (prompt, agent_type); the synthesis-type row is the prompt-level seal; rating 0=critical … 999=ignore, read threshold 100)
      gm explore open --prompt-uuid U [--agent-type aggressive|conservative|pragmatic|alternative|general|synthesis] [--agent-id I]   (default general; idempotent per pair)
      gm explore key-file-add --summary-uuid S --file-path P   (recorded as a finding of kind key_file; deduped per (summary, path))
      gm explore finding-add --summary-uuid S --kind persistence_model|implementation_pattern|existing_functionality|scope_creep_risk|general_relevant_change|key_file|other --title T (--body B | --body-file P) [--file-path FP] --agent-name A [--agent-id I] [--rating 0-999]
      gm explore rank --prompt-uuid U --rating <finding-uuid>:<0-999> ...   (PROMPT-scoped atomic batch across every summary; re-run re-ranks; refused once the synthesis row is complete — reopen it first)
      gm explore complete --summary-uuid S --expected-version V (--overview TEXT | --overview-file PATH)   (per summary; agents seal their OWN row; completing the synthesis row is the prompt-level seal and refuses while anything is unranked)
      gm explore reopen --summary-uuid S --expected-version V
      gm explore get --prompt-uuid U [--agent-type T] [--full | --max-rating N | --rating-range A:B]   (all summaries, synthesis first; key files computed from key_file findings)
    REVIEW (same shape as explore + resolve/verdict; the fix loop runs AFTER complete)
      gm review open --prompt-uuid U
      gm review finding-add --summary-uuid S --kind correctness_bug|spec_deviation|regression_risk|security|simplification|other --title T (--body B | --body-file P) [--file-path P] [--line-start N [--line-end N]] --agent-name A [--agent-id I] [--rating 0-999]
      gm review rank --summary-uuid S --rating <finding-uuid>:<0-999> ...   (same batch contract; refused once complete — reopen first)
      gm review resolve --finding-uuid F --expected-version V --status fixed|accepted|wont_fix   (post-complete; never back to open)
      gm review complete --summary-uuid S --expected-version V (--overview TEXT | --overview-file PATH) --verdict approved|approved_with_nits|changes_requested
      gm review reopen --summary-uuid S --expected-version V
      gm review get --prompt-uuid U [--full | --max-rating N | --rating-range A:B]   (mutually exclusive)
    BRIEFING (the agent-briefing machine: building → ready only; open on an existing (owner, step) RESETS — a step's briefing is always its CURRENT briefing; staleness computed at every read, warns never blocks)
      gm briefing open (--prompt-uuid U | --session-uuid U) --step initial   (exactly one owner; --session-uuid alone = /gm_task-owned)
      gm briefing complete --briefing-uuid B --expected-version V [--dope-ref DOT.PATH]... [--kbite-ref FILE_UUID]... [--file-change-ref UUID]... [--agent-id I]   (an opinion-free ref set, no body; refs become child rows; daemon stamps the dope scope revision itself and denormalizes kbite briefs)
      gm briefing get (--briefing-uuid B | --prompt-uuid U [--step S] | [--session-uuid U] --step S) [--wait [--timeout-seconds N]]   (row + staleness: revision drift + ghost dot-paths. The zero-uuid form `gm briefing get --step S` is DETERMINISTIC: session from cwd, instance from process ancestry, own activation claim -> single session claim -> task row; real owner, no rows -> SUMMARY_ABSENT. --wait polls until status==ready and the output IS the briefing — the primary's post-doper-spawn gate; exit 1 on timeout = treat the doper as dead)
      gm briefing list (--prompt-uuid U | --session-uuid U)   (empty is normal)
      gm briefing stub [--agent-type T]   (the SubagentStart hook's one call: compact plain-text stub ≤2KB with the exact pull command; empty + exit 0 when nothing applies)
    DOPE (Domain Optimized Project Essence [Driver — the saved .doped.json form]; dope_scope.revision = the whole-tree counter = the .doped.json version field; json refs are dot-path codes, granular verbs take uuids)
      gm dope init --session-uuid U --code C --name N [--prompt-uuid U] [--description D] [--clone-from-session-base]   (idempotent; PROMPT-typed iff --prompt-uuid)
      gm dope list [--session-uuid U] [--prompt-uuid U]   (session defaults to the current repo/branch session; SESSION_INSTANCE scopes, or ONLY that prompt's PROMPT scopes with --prompt-uuid — never a union; empty list is normal, unknown uuid is NOT_FOUND)
      gm dope get (--session-uuid U [--prompt-uuid U] | --project-uuid U) [--code C] [--resolved]   (SESSION_INSTANCE_ITEM preferred, SESSION_INSTANCE fallback; --project-uuid reads the project ladder instead — PROJECT_ITEM preferred, then the promoted BASE_PROJECT scope, which is what lets a PROJECT-tier diagram render real cards instead of ghosts; --code disambiguates; --resolved merges a masking overlay over its same-coded base one tier up and reports provenance + masked-away paths)
      gm dope search prompt|session|project "<query>" [--session-uuid U] [--prompt-uuid U] [--project-uuid U] [--only-masks] [--limit N]   (FTS5 over scope/persistence/entity/property/enum/option/cog/cog-element; hits carry the dot-path; --only-masks post-filters on resolver provenance)
      gm dope promote --session-uuid U [--code C] [--dry-run]   (SESSION_INSTANCE -> BASE_PROJECT; primary-branch sessions only, gated on a promoted_from_* high-water so it never ping-pongs between instances or re-fires on an unchanged tree; also runs automatically at boot behind the dope sync)
      gm dope scope-update --uuid U --expected-version V [--code C] [--name N] [--description D]
      gm dope persistence-add · gm dope entity-add · gm dope enum-add · gm dope option-add --parent-uuid U --code C --name N [--description D] [--sort-order N] (entity also: [--entity-type MODEL|JUNCTION|BASE_COMPOSABLE] [--base-composable-uuid U]; entity/enum also: [--repo-representative-file P])
      gm dope property-add --parent-uuid U --code C --name N --data-type enum|relationship|boolean|uuid|int|long|decimal|text|datetime [--nullable|--no-nullable] [--is-unique|--no-is-unique] [--auto-increment|--no-auto-increment] [--text-char-limit N] [--enum-uuid U] [--relationship-target-uuid U] [--base-origin-uuid U] [--description D] [--sort-order N]
      gm dope persistence-update · gm dope entity-update · gm dope enum-update · gm dope option-update --uuid U --expected-version V [--code C] [--name N] [--description D] [--sort-order N] (entity also: [--entity-type T] [--base-composable-uuid U] [--clear-base-composable]; entity/enum also: [--repo-representative-file P] [--clear-repo-representative-file])
      gm dope property-update --uuid U --expected-version V [--code C] [--name N] [--description D] [--sort-order N] [--data-type T] [--nullable|--no-nullable] [--is-unique|--no-is-unique] [--auto-increment|--no-auto-increment] [--text-char-limit N] [--enum-uuid U] [--relationship-target-uuid U] [--base-origin-uuid U] [--clear-enum] [--clear-relationship-target] [--clear-auto-increment] [--clear-text-char-limit] [--clear-base-origin]
      gm dope persistence-delete · gm dope entity-delete · gm dope property-delete · gm dope enum-delete · gm dope option-delete --uuid U --expected-version V [--soft]   (hard: subtree cascades, still-referenced targets refused naming the referrer; --soft: MASKING SCOPES ONLY (PROJECT_ITEM/SESSION_INSTANCE_ITEM) -- stamps deleted_on as a whiteout, no cascade, no referrer guard, reads still return it, and it NEVER reaches the saved .doped.json; scope delete not offered yet)
      gm dope read-repo (--scope-uuid U | --dir-path P)   (parse + validate {instance_root}/.gmcc; never writes; reports drift)
      gm dope write-repo --scope-uuid U [--force]   (db -> files, atomic whole-tree swap; refuses when files are AHEAD of the db unless --force)
      gm dope ingest --scope-uuid U [--dir-path P] [--adopt]   (files -> db whole-tree overwrite, no smart diff, child uuids change; on-disk version must be EXACTLY db revision + 1. --adopt is boot-sync-only: accepts any strictly FORWARD version, discards db-only gap revisions, never moves backward)
      gm dope sync [--session-uuid U]   (files -> db reconcile of the session's SESSION_INSTANCE scope from {instance_root}/.gmcc: seeds a virgin scope, re-adopts when files are ahead, WARNS ONLY when the db is ahead; runs automatically at boot via gm context ensure — run manually after a mid-session branch change)
      gm dope merge-plan --scope-uuid U   (per-element plan of db vs files, judged against the stored merge base in dope_element_provenance; READ-ONLY -- never ingests, never writes files, never blocks. Decisions: takeTheirs / keepOurs / conflict / keepOursLocalAddition / deletedHere)
      gm dope resolve --scope-uuid U --take ours|theirs [--path <dot.path>]   (settle conflicts; omit --path for all. 'theirs' clears the dirty flag so the file wins next sync; 'ours' re-bases onto the file's current hash so the local edit is kept. Either way the conflict is gone on the next plan)
    DIAGRAM (db-persisted canvases over dope; diagram.revision = whole-tree counter; exactly ONE owner flag picks the tier PROJECT|SESSION|PROMPT; batch-apply is THE interactive write — the element verbs are one-mutation batches over the same body. element_type carries NO db CHECK: validity is DiagramElementTypeSpec, so a new type is one registry entry + one subtype table, never a migration)
      gm diagram init (--project-uuid U | --session-uuid U | --prompt-uuid U) --code C --name N [--description D] [--gmcc-diagram-path P] [--dope-scope-code C]   (idempotent per owner+code; gmcc_diagram_path is legal at EVERY tier — it names the directory under the owner's CKFS storage that rendered images land in; dope-scope-code binds the WHOLE canvas to one scope and is restricted on write to the masking tiers PROJECT_ITEM/SESSION_INSTANCE_ITEM — a Swift guard, since a SQLite CHECK cannot reference another table; it coexists with the per-element bindings)
      gm diagram list (--project-uuid U | --session-uuid U | --prompt-uuid U) [--visibility PRIVATE|PUBLIC]   (that tier's rows only, never a union; empty is normal, unknown owner NOT_FOUND)
      gm diagram get (--diagram-uuid U | one owner flag: --project-uuid|--session-uuid|--prompt-uuid [--code C])   (tree + dope binding resolutions + the owner's ckfs storage path; no cross-tier fallback; pair with gm dope get for bound trees; real owner with none -> SUMMARY_ABSENT)
      gm diagram update --diagram-uuid U --expected-version V [--code C] [--name N] [--description D] [--gmcc-diagram-path P | --clear-gmcc-diagram-path] [--promote-tier T --promote-owner-uuid O] [--visibility PRIVATE|PUBLIC]   (promotion re-derives the owner chain, same project always; PUBLIC is SESSION-tier only — demote to PRIVATE before promoting away)
      gm diagram search [query] [--project-uuid U] [--session-uuid U] [--visibility PRIVATE|PUBLIC] [--limit N]   (the cross-tier gallery surface: no query = the project's diagrams by recency, a query = bm25 over the diagram FTS; project defaults from the current repo)
      gm diagram delete --diagram-uuid U [--expected-revision N]   (row delete; elements/FTS/qualified readings cascade; ckfs screenshot removed best-effort; gm backup first for anything precious)
      gm diagram write-repo [--session-uuid U] [--force]   (db -> files: the session's PUBLIC SESSION-tier diagrams into {instance_root}/.gmcc/diagrams/{code}.diagram.doped.json — uuid-free, connector targets as code paths; explicit only, PUBLIC alone never writes; refuses when a file is AHEAD unless --force; prunes demoted/deleted)
      gm diagram ingest [--session-uuid U]   (files -> db, strictly forward-only: a file lands only when its version is ahead of the db revision; PRIVATE collisions skipped; the boot-sync door)
      gm diagram element-add --diagram-uuid U (--content JSON | --content-file P) [--parent-element-uuid P] [--code C] [--name N] [--description D] [--sort-order N] [--center-x X] [--center-y Y] [--element-z Z] [--scale S]   (content = {"kind":element_type,"fields":{...}}, vertices ride inside; omitted code/name are minted)
      gm diagram element-update --uuid U --expected-version V [--code C] [--name N] [--description D] [--sort-order N] [--center-x X] [--center-y Y] [--element-z Z] [--scale S] [--parent-element-uuid P] [--content JSON | --content-file P]   (a present content REPLACES the subtype row + vertex set wholesale)
      gm diagram element-delete --uuid U --expected-version V   (subtree CASCADE; no referrer guards in this family)
      gm diagram batch-apply --diagram-uuid U (--mutations JSON | --mutations-file P) [--expected-revision N]   (one txn/revision/event; strict order; clientRef parenting; all-or-nothing; expected-revision = whole-diagram CAS)
      gm diagram from-dope --session-uuid U [--prompt-uuid U] [--code C] [--diagram-code C] [--mutations-out P] [--dry-run]   (dope tree -> one atomic regenerate batch; geometry shared with the renderer)
    RENDER (bot ingestion: a diagram as an image an agent can read)
      gm render (--diagram-uuid U | one owner flag: --project-uuid|--session-uuid|--prompt-uuid [--code C]) [--scheme light|dark] [--scale N] [--force] [--artifact --artifact-prompt-uuid U]   (client-side headless render, never the daemon; writes ONE mutable file per code to {ckfs_root}/{owner ckfs path}/{gmcc_diagram_path or 'diagrams'}/screenshots/{code}.png and prints the path. Staleness is a FINGERPRINT sidecar beside the PNG, not a timestamp: diagram.revision alone cannot see a bound dope tree changing under the render, so the key is diagram revision + every bound scope revision + scheme + scale + render algo version. Fresh renders re-render nothing; --force overrides. Zero db writes unless --artifact)
    COGS (Coordination Of General Systems; cog rows live in a dope scope and share its revision, tombstone and tier rules. element_type is registry-governed in Swift and carries NO db CHECK, so a new type is one registry entry + one subtype table, never a migration)
      gm cog add --scope-uuid U --code C --name N [--description D] [--sort-order N]
      gm cog update --uuid U --expected-version V [--code C] [--name N] [--description D] [--sort-order N]
      gm cog delete --uuid U --expected-version V [--soft]
      gm cog get --scope-uuid U [--code C]
      gm cog element-add --cog-uuid U --code C --name N [--element-type Hull|PersistenceOwner] [--parent-element-uuid P] [--description D] [--sort-order N] [--dope-scope-code C] [--primary-path P] [--dope-persistence-code C]   (required fields are per-type: Hull needs --primary-path, PersistenceOwner needs --dope-persistence-code and MUST be parented to a Hull. Both dope-scope-code and dope-persistence-code are ghost-tolerant CODES resolved at read time, never uuid FKs)
      gm cog element-update --uuid U --expected-version V [--code C] [--name N] [--description D] [--sort-order N] [--dope-scope-code C | --clear-dope-scope-code] [--primary-path P]
      gm cog element-delete --uuid U --expected-version V [--soft]
    PROMPT-DIAGRAM (a prompt's standing reading of a rendered picture — the image says what the shapes ARE, this says what this prompt concluded they MEAN. One row per (prompt, canvas): no status machine, no findings, no reopen edge — re-qualifying REPLACES. rendered-revision + render-fingerprint are the staleness evidence: pass the sidecar written beside the PNG verbatim, and a later reader can tell whether the reading still describes the picture that exists today)
      gm prompt-diagram qualify --prompt-uuid U --diagram-uuid U --rendered-path P --rendered-revision N (--render-fingerprint JSON | --render-fingerprint-file P) (--qualification TEXT | --qualification-file P)   (upsert on the pair; exactly one source required for each of the fingerprint and the qualification — the file forms exist because a real reading exceeds argv long before the daemon's cap. An unknown prompt or canvas is NOT_FOUND, naming which end was wrong)
      gm prompt-diagram get --prompt-uuid U [--diagram-uuid U]   (omit the uuid only when the prompt has exactly one — several is a refusal naming the count, never an arbitrary pick. Real prompt with none -> SUMMARY_ABSENT)
      gm prompt-diagram list --prompt-uuid U   (everything this prompt has read; empty is normal)
    ARTIFACT / FILE-CHANGE
      gm artifact add --prompt-uuid U --file-path P [--note N]
      gm artifact list --prompt-uuid U
      gm file-change add --path P [--kind edit|create|delete|rename] [--range start:end]... [--content TEXT] [--prompt-uuid U] [--auto-attribute] [--agent-id I] [--agent-name A] [--origin hook|manual|reconcile|turn]   (--content requires exactly one --range; --auto-attribute resolves attribution via the activation registry — this Claude instance's claim first, then the session's single claim, else unattributed — the PostToolUse hook's flag; workflow_phase is stamped daemon-side from the active workflow, never passed)
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
      gm kbite export --code C [--output-dir P]   (single-format gmcc_kbite_{code}_{date}.zip: MANIFEST + db_export.json + root docs + .git-stripped digested sources; paths scrubbed to placeholders)
      gm kbite import --zip-file P [--on-collision skip|overwrite]   (db first then filesystem; skip is the default, overwrite preserves the kbite uuid + registrations; NEVER registers — compose gm kbite add)
      gm kbite delete --code C [--purge-filesystem]   (one cascading db delete incl. registrations, orphan keywords GC'd; purge MOVES the digested tree to _archive/cold_storage/, never rm. CONTENT-DESTRUCTIVE: gm backup or gm kbite export first)
    SANDBOX (local-dev sandbox at {ckfs_root}/development/local_sandbox; prod db touched ONLY by the Online-Backup read; kbites never copied; never gm setup --launchd in a sandbox)
      gm sandbox refresh   (run from the gmcc-marketplace repo root, prod env only — refuses under GMCC_ROOT; quiesce -> gm backup -> OFFLINE retarget of the staged db (config roots + instance identity + storage paths) -> ckfs subtree rsync -> git clone --local / fetch+reset -> binaries+launchers -> atomic db install -> snapshot_meta.json LAST; re-run is always safe recovery)
      gm sandbox status   (generation, instance code, daemon liveness; a metaless sandbox is partial — re-run refresh)
    OTHER
      gm cheatsheet [--full]   (default: the compact core; --full: this complete sheet)
      gm verbs [--writes-only]   (the verb registry as data: every daemon verb's gm invocation, its pen tool where one exists, and who may call it; --writes-only is the deny set — the verbs an agent must not reach through gm. The PreToolUse write guard generates its deny reason from this, so the guard can never drift from the roster)
    INVARIANTS
      - Thread --expected-version on every mutation; on VERSION_CONFLICT re-run the matching get, take .version, retry.
      - gm prompt set-status is the ONLY door that moves a prompt; clarify/arch/explore/review/briefing verbs touch their summary only (set-status implementing claims a prompt_activation row for the calling Claude instance; done releases the prompt's claim — per-instance, never a session-wide pointer).
      - Attribute gm file-change add: pass --prompt-uuid, or --auto-attribute to borrow the session's active prompt — the implementation-state comparison sees only attributed changes.
      - SUMMARY_ABSENT means the prompt exists but that summary was never opened — open it (gm clarify/arch/explore/review/briefing open); for dope it means the session/prompt exists but no scope was ever initialized (gm dope init). Never a file fallback.
      - Dope refs in .doped.json are dot-path codes, never uuids (domain.entity.property / domain.enums.enum_code / domain.entity for base composables); granular dope verbs bump revision by 1 each and leave row versions to --expected-version.
      - Dope boot sync is strictly files -> db and forward-only: context ensure / dope sync never write repo files and never move revision backward; a db AHEAD of the files only warns (publish with gm dope write-repo). Never use --adopt outside that sync path.
      - A base_composable target must be a BASE_COMPOSABLE entity in the same scope; chaining is allowed, cycles are refused, and deleting a still-composed base (or its domain) is refused naming the composer.
      - A materialized property tags its origin (base_origin_ref: domain.entity.property): the origin must live on a base the entity composes and keep its data_type; changing a base that strands a tag, or deleting a tagged origin, is refused naming the referrer.
      - Diagram dope bindings are CODES resolved at read time through the diagram's own session/prompt context (resolved_via surfaced); a dangling code is a LEGAL state rendered as a ghost, never an error — and dope deletes are never blocked by diagrams.
      - Diagram element geometry: center_x/y are parent-space, vertices are element-local, scale composes down the tree, element_z orders siblings only; the element row's version is the lock for the whole element aggregate (subtype + vertices replace wholesale, vertex row uuids are not stable).
      - Values starting with a dash need --flag=value form (e.g. --content="- item").
      - After gm prompt create, mkdir -p $GMCC_CKFS_ROOT/<ckfs_relative_storage_path>/memory verbatim from the response — never re-derive {seq}_{name}.
    RESPONSE NOTES
      - kbite file-get content may be null: the raw source lives on the filesystem under the kbite's digested tree (located by resource/file name — no path column exists), not in the db.
      - status table_counts are point-in-time totals, not an event cursor — replay events via gm events --since-id.
    """

    /// The compact core — what SessionStart and SubagentStart inject (two-tier
    /// diet: a session carries this instead of the full sheet, which is one
    /// command away). One index line per family, the INVARIANTS block verbatim,
    /// and the agent's orientation block. CheatsheetTests holds a size budget on
    /// this so the diet cannot silently regress: it is the per-spawn context
    /// cost, paid by every agent in every booted repo.
    static let coreText: String = {
        let invariants = text.range(of: "INVARIANTS").map { String(text[$0.lowerBound...]) } ?? ""
        // The block carries READ signatures ONLY, and that is the whole point:
        // an agent records through the pen's MCP tools, and the PreToolUse
        // guard refuses every `gm` write verb from a spawned agent. Listing a
        // write signature here would hand every agent, in every booted repo,
        // the exact invocation the door is built to refuse — so the block is
        // held to reads by `testAgentBlockNamesNoGmWriteVerb`.
        //
        // Signatures are EXTRACTED from the full sheet, never hand-copied — a
        // copy drifts silently, because the flag-parity test only walks the
        // full text. A missing prefix surfaces loudly as the sentinel below
        // and fails the parity assertion in CheatsheetTests.
        func fullLine(_ prefix: String) -> String {
            for raw in text.split(separator: "\n") {
                let line = raw.trimmingCharacters(in: .whitespaces)
                if line.hasPrefix(prefix) { return line }
            }
            return "MISSING FULL-SHEET LINE: \(prefix)"
        }
        let readVerbs = [
            "gm bot next",
            "gm dope search",
            "gm kbite search",
            "gm kbite file-get",
        ].map { "  " + fullLine($0) }.joined(separator: "\n")
        return """
        GM CHEATSHEET CORE (wire v\(GMCCWireProtocol.version)) — family index + invariants. FULL signatures: gm cheatsheet --full. Every command accepts --json.
        FAMILIES (one index line each)
          CORE — setup · doctor · status · ping · daemon · backup · events · paths · config
          CONTEXT/BROWSE/SEARCH — context ensure/env/get · project list/update · instance list/current-session · session list/get/update/resolve · catalog search · search
          PROMPT — create · list [--with-reports] · get · update-content · set-status (the ONLY door that moves a prompt) · start · resume (the workflow machine doors)
          BOT — next · get · status · current_prompt · briefing · summary · reconcile · sweep (phase derived from db evidence)
          CLARIFY — open · question-add · note-add · seal · answer · reopen · finalize · get · package-open/add/complete/get
          ARCH — open · summarize · persist-add · field-add · general-add · option-add · decide · propose · approve · revise · get (persistence rows first, always)
          EXPLORE — open (per agent-type) · key-file-add · finding-add · rank (prompt-scoped) · complete (synthesis row = the seal) · reopen · get
          REVIEW — open · finding-add · rank · resolve · complete · reopen · get
          BRIEFING — open · complete · get · list · stub (building → ready; open on existing (owner,step) RESETS; staleness computed at read)
          DOPE — init · list · get · search · promote · scope/persistence/entity/property/enum/option add/update/delete · read-repo · write-repo · ingest · sync · merge-plan · resolve
          DIAGRAM — init · list · get · update · element-add/update/delete · batch-apply · from-dope   RENDER — gm render
          COGS — add · update · delete · get · element-add/update/delete   PROMPT-DIAGRAM — qualify · get · list
          ARTIFACT — add · list   FILE-CHANGE — add · list   KBITE — list · add · remove · maw-open · digest · get · file-get · search · keyword-tag · export · import · delete
          SANDBOX — refresh · status   OTHER — cheatsheet [--full] · verbs
        AGENT PEN — spawned agents record ONLY through the gmcc pen MCP tools (mcp__plugin_gmcc_pen__*, already in your tool list; `gm verbs` prints the gm→pen map). Every gm WRITE verb is refused at PreToolUse, so never reach for one from Bash. The gm READS below are safe, and are the only gm lines this sheet hands you (extracted verbatim from the full sheet).
          gm briefing get --step initial   (zero-uuid deterministic form: session from cwd, instance from process ancestry; uuid/prompt selectors also exist)
        \(readVerbs)
          (self-rate findings 0=critical … 999=ignore, read threshold 100; complete YOUR OWN summary — that seal is yours; NEVER call rank or reopen — those are the primary's)
        \(invariants)
        """
    }()

    @Flag(name: .long, help: "Print the complete sheet (every verb's exact signature) instead of the compact core.")
    var full = false

    func run() {
        print(full ? Self.text : Self.coreText)
    }
}
