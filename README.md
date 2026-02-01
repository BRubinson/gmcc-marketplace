# GMCC Marketplace

Green Mountain Compiler Collection - A Claude Code plugin marketplace for contextual development.

## Installation

### Prerequisites

- [Claude Code](https://claude.ai/code) CLI installed

### Add the Marketplace

1. Open Claude Code
2. Run the `/plugins` command
3. Select **Add Marketplace**
4. Enter: `brubinson/gmcc-marketplace`
5. Confirm the installation

### Install Plugins

After adding the marketplace:

1. Run `/plugins`
2. Select **Install Plugin**
3. Choose from available plugins (e.g., `gmcc`)

## Available Plugins

| Plugin | Description |
|--------|-------------|
| gmcc | GM-CDE plugin for contextual development |

### Installing GMCC and its CKFS

After installing the `gmcc` plugin, you need to initialize the GM-CDE environment and its contextual knowledge file system (ckfs).

#### 1. Initialize GMCC (First Time Setup)

Run this once to set up GMCC globally:

```
/gm_init
```

This creates the global GMCC configuration and ckfs structure in your home directory.

#### 2. Initialize a Repository

Navigate to your project directory and run:

```
/gm_repo_init
```

This sets up the repository-specific ckfs structure for contextual development.

#### 3. Load Branch Context

When starting work on a branch, load or create the branch's FAM (Feature Access Memory):

```
/gm_load_branch
```

Or specify a branch name:

```
/gm_load_branch <branch-name>
```

This loads existing contextual knowledge for the branch or creates a new FAM if one doesn't exist. Once loaded, you're ready to start development with `/gm_feature_dev` or `/gm_task`.

## Uninstalling

To remove the marketplace:

1. Run `/plugins`
2. Select **Manage Marketplaces**
3. Remove `gmcc-marketplace`

## License

MIT License - see [LICENSE](LICENSE) for details.
