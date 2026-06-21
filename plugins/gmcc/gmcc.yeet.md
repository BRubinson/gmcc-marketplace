**Name** Green Mountain Compiler Collection
**UUID** 00000000-0000-0000-0000-000000000000
**Package** gmcc

# Description

The core GMCC YEETS type definitions. Every other `.yeet.md` file in this
plugin imports from `gmcc`.

The nil UUID above is intentional: the `gmcc` package is the bootstrap
package; its UUID is reserved as the canonical zero value. `/gm_compile`
warns on nil UUIDs in other packages — `gmcc` is the documented exception.

This package defines:

- **Base "boring ass" mixins** (`has_*`) — small composable structs that
  carry one or two fields each. Larger structs use the `unwrap` keyword
  to compose them.
- **Runtime file types** — top-level shapes for the four core ckfs yamls
  (`project_index.gmcc.yaml`, `project_data.gmcc.yaml`,
  `instance_data.gmcc.yaml`, `session_data.gmcc.yaml`).

# Types

## DEFAULT
**section description** Default exports for the `gmcc` package.

### Enums

enums: {}

### Structs

structs:

  # --- Boring ass base mixins ---

  has_serial_id:
    description: |
      Monotonic integer identity within a scope. Not globally unique;
      pair with has_uuid for that.
    fields:
      id: int

  has_code:
    description: |
      Stable kebab/snake-style slug identifier. Human-readable but
      machine-safe. Distinct from has_name (which is display text).
    fields:
      code: string

  has_uuid:
    description: |
      Globally unique v4 UUID. The nil UUID is reserved for the
      bootstrap `gmcc` package only; everywhere else it is a warning.
    fields:
      uuid: uuid

  has_name:
    description: |
      Human-readable display name. May contain spaces, mixed case,
      etc. Use has_code for the slug form.
    fields:
      name: string

  has_description:
    description: |
      Free-text description of what this thing is or does.
    fields:
      description: string

  has_created_time:
    description: |
      Millisecond Unix timestamp of creation. Current ckfs yamls hold
      ISO 8601 strings at the v6.0.x storage layer; YEETS validates
      the field exists but does not yet enforce the numeric form.
    fields:
      created_time: timestamp

  has_updated_time:
    description: |
      Millisecond Unix timestamp of last update. Set equal to
      created_time on creation. ISO 8601 string storage caveat per
      has_created_time applies.
    fields:
      updated_time: timestamp

  has_base_fields:
    description: |
      Standard identity + lifecycle bundle. Most addressable entities
      in GMCC unwrap this.
    fields:
      unwrap_has_serial_id: Unwrap<has_serial_id>
      unwrap_has_code: Unwrap<has_code>
      unwrap_has_uuid: Unwrap<has_uuid>
      unwrap_has_name: Unwrap<has_name>
      unwrap_has_description: Unwrap<has_description>
      unwrap_has_created_time: Unwrap<has_created_time>
      unwrap_has_updated_time: Unwrap<has_updated_time>

  has_gmcc_ckfs_absolute_path:
    description: |
      Absolute path on disk pointing inside the GMCC_CKFS_ROOT tree.
    fields:
      gmcc_ckfs_absolute_path: file_path

  has_gmcc_ckfs_relative_path:
    description: |
      Path relative to GMCC_CKFS_ROOT. Pair with the absolute form for
      portability and human-readable debugging.
    fields:
      gmcc_ckfs_relative_path: file_path

  has_ckfs_paths:
    description: |
      Standard ckfs path bundle. Anything that lives on disk inside
      GMCC_CKFS_ROOT unwraps this.
    fields:
      unwrap_has_gmcc_ckfs_absolute_path: Unwrap<has_gmcc_ckfs_absolute_path>
      unwrap_has_gmcc_ckfs_relative_path: Unwrap<has_gmcc_ckfs_relative_path>

  has_system_path:
    description: |
      Absolute path on the user's system that is NOT inside GMCC_CKFS_ROOT.
      Used for things like an instance's underlying repo checkout.
    fields:
      system_path: file_path

  # --- Core runtime file formats ---
  #
  # The four top-level ckfs yamls. Each file's body conforms to one
  # of these structs (via the yaml's `yeet_type:` key).

  gmcc_project_index_file:
    description: |
      Top-level shape of $GMCC_PROJECTS/project_index.gmcc.yaml.
      A flat registry of every project tracked under this ckfs root.
      Each project entry is a minimal identity stub; the per-project
      instance and session lists live in project_data.gmcc.yaml and
      instance_data.gmcc.yaml respectively.
    fields:
      unwrap_has_base_fields: Unwrap<has_base_fields>
      unwrap_has_ckfs_paths: Unwrap<has_ckfs_paths>
      projects: List<gmcc_project_index_file_project_entry>

  gmcc_project_index_file_project_entry:
    description: |
      One project's entry in the project_index registry. Identity
      only — follow gmcc_ckfs_absolute_path to that project's
      project_data.gmcc.yaml for instances.
    fields:
      unwrap_has_base_fields: Unwrap<has_base_fields>
      unwrap_has_ckfs_paths: Unwrap<has_ckfs_paths>

  gmcc_project_data_file:
    description: |
      Top-level shape of {project}/project_data.gmcc.yaml. Per-project
      identity, repository metadata, and the list of instances for
      this project. Future fields (owners, primary_language,
      kbite_associations) land in v6.2+.
    fields:
      unwrap_has_base_fields: Unwrap<has_base_fields>
      unwrap_has_ckfs_paths: Unwrap<has_ckfs_paths>
      repository_name: string
      http_uri: http_uri?
      ssh_uri: ssh_uri?
      instances: List<gmcc_project_data_file_instance_entry>

  gmcc_project_data_file_instance_entry:
    description: |
      One instance's entry inside a project_data file. An instance is
      a checkout of the project's repo on the user's system, so it
      carries has_system_path in addition to the ckfs paths. Follow
      gmcc_ckfs_absolute_path to that instance's instance_data.gmcc.yaml
      for the session list.
    fields:
      unwrap_has_base_fields: Unwrap<has_base_fields>
      unwrap_has_ckfs_paths: Unwrap<has_ckfs_paths>
      unwrap_has_system_path: Unwrap<has_system_path>

  gmcc_instance_data_file:
    description: |
      Top-level shape of {instance}/instance_data.gmcc.yaml. An instance
      is a unique filesystem path to a repo checkout; it carries both
      the ckfs paths and the repo's system path, a back-reference to
      its project, and the list of its sessions.
    fields:
      unwrap_has_base_fields: Unwrap<has_base_fields>
      unwrap_has_ckfs_paths: Unwrap<has_ckfs_paths>
      unwrap_has_system_path: Unwrap<has_system_path>
      project_uuid: uuid
      sessions: List<gmcc_instance_data_file_session_entry>

  gmcc_instance_data_file_session_entry:
    description: |
      One session's entry inside an instance_data file. A session
      corresponds to a git branch within the instance. Follow
      gmcc_ckfs_absolute_path to that session's session_data.gmcc.yaml
      for its prompts and changed-files history.
    fields:
      unwrap_has_base_fields: Unwrap<has_base_fields>
      unwrap_has_ckfs_paths: Unwrap<has_ckfs_paths>

  gmcc_session_data_file:
    description: |
      Top-level shape of {session}/session_data.gmcc.yaml. A session
      corresponds to a git branch within an instance. Standalone
      (no nested children list) — the prompts and changed_files
      lists are intentionally untyped Lists in v6.1.x; they receive
      proper struct types in v6.2+.
    fields:
      unwrap_has_base_fields: Unwrap<has_base_fields>
      unwrap_has_ckfs_paths: Unwrap<has_ckfs_paths>
      branch: string
      instance_uuid: uuid
      project_uuid: uuid
      prompts: List<string>
      changed_files: List<string>
