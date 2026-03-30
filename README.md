# BarKeeper 🍺

> BarKeeper - Use your macOS **Bar** to **Keep** your environments and shortcuts under control.

A lightweight macOS menu bar app for managing cloud resources with one click. Run scripts, monitor the status of applications or spin up and shutdown Cloud Resources — all from your macOS top bar.

<!-- TODO: Add a screenshot of the menu bar popup and settings window here -->

## Features

- **Menu Bar Native** — lives in your macOS menu bar, no Dock icon clutter
- **Toggle Switches** — on/off controls with status monitoring (green/gray/red dots)
- **Action Buttons** — one-click script execution
- **Configurable Polling** — automatic status checks (1 min to 1 hour, or manual only)
- **Settings UI** — add/edit/delete resources with an easy to access UI
- **JSON Import/Export** — share and backup your configuration in common JSON
- **Built-in Azure Fabric Capacity template** — get started instantly

## Requirements

- macOS 15.0+ (Sequoia)
- Xcode 16+ / Swift 6.0+
- (Optional for Sample Config) [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli-macos) (for Azure resources)

## Installation

### Build from Source

```bash
# Clone the repository
git clone https://github.com/abeckDev/BarKeeper.git
cd BarKeeper

# Option 1: Open in Xcode
open BarKeeper.xcodeproj

# Option 2: Build from command line
swift build
# The binary is at .build/debug/BarKeeper
```


## Getting Started

### First Launch

1. Click the BarKeeper icon in your menu bar
2. Click **Settings** → **+** to add a resource
3. Or click **⋯** → **Add Fabric Capacity Example** for a pre-configured Azure template
4. Edit the capacity name and resource group to match your Azure setup
5. Close Settings — your resource appears in the menu bar popup

### Resource Types

BarKeeper supports two resource types:

#### Toggle

A stateful resource with **three scripts**: status, on, and off. BarKeeper periodically runs the status script to determine the current state and shows a colored indicator in the menu bar.

- **Green dot** — resource is ON (status script exited with code `0`)
- **Gray dot** — resource is OFF (status script exited with non-zero code)
- **Red dot** — an error occurred during the last action

Clicking the toggle executes the on or off script based on the current state.

#### Button

A stateless resource with a **single action script**. Clicking it runs the script immediately. Useful for one-off tasks like flushing a cache, deploying a build, or opening a dashboard.

### Script Convention

| Script Type | Exit Code 0 | Non-zero Exit |
|------------|-------------|---------------|
| **Status** | Resource is ON (green) | Resource is OFF (gray) |
| **On/Off/Action** | Success | Error (shown in tooltip) |

## How Scripts Are Executed

Scripts are run using your default login shell (`$SHELL`, typically `/bin/zsh`), invoked as:

```
$SHELL -l -c "<your script>"
```

- The `-l` (login) flag sources your shell profile (`~/.zprofile`, `~/.zshrc`), so Homebrew, `nvm`, `pyenv`, custom `PATH` entries, and tools like `az` CLI are all available.
- Scripts inherit your full user environment.
- stdout and stderr are captured separately and trimmed of whitespace.
- The exit code determines success or failure.

### Writing Your Own Resources

Any shell command or script that follows the exit code convention works. Here are a few ideas:

**Docker container toggle:**
```bash
# Status
docker inspect -f '{{.State.Running}}' my-container 2>/dev/null | grep -q true

# On
docker start my-container

# Off
docker stop my-container
```

**SSH tunnel toggle:**
```bash
# Status
pgrep -f "ssh -N -L 5432:localhost:5432 myserver" > /dev/null

# On
ssh -f -N -L 5432:localhost:5432 myserver

# Off
pkill -f "ssh -N -L 5432:localhost:5432 myserver"
```

**Open a dashboard (button):**
```bash
open "https://portal.azure.com/#view/Dashboard"
```

### Azure Fabric Capacity Example

The built-in template uses these Azure CLI commands:

```bash
# Status check
az fabric capacity show --capacity-name "NAME" --resource-group "RG" \
  --query "state" -o tsv | grep -qi "Active"

# Start (resume)
az fabric capacity resume --capacity-name "NAME" --resource-group "RG"

# Stop (suspend)
az fabric capacity suspend --capacity-name "NAME" --resource-group "RG"
```

> Make sure you're logged in: `az login`

## Configuration

Config is stored at `~/Library/Application Support/BarKeeper/config.json` and managed through the Settings UI. You can also export/import JSON files for backup or sharing.

### JSON Schema

```json
{
  "pollingIntervalSeconds": 3600,
  "resources": [
    {
      "id": "550E8400-E29B-41D4-A716-446655440000",
      "name": "My Toggle",
      "type": "toggle",
      "statusScript": "docker inspect -f '{{.State.Running}}' my-db | grep -q true",
      "onScript": "docker start my-db",
      "offScript": "docker stop my-db",
      "actionScript": null
    },
    {
      "id": "6BA7B810-9DAD-11D1-80B4-00C04FD5B67D",
      "name": "Deploy Staging",
      "type": "button",
      "statusScript": null,
      "onScript": null,
      "offScript": null,
      "actionScript": "./scripts/deploy-staging.sh"
    }
  ]
}
```

| Field | Type | Description |
|-------|------|-------------|
| `pollingIntervalSeconds` | `Int` | How often to run status scripts for toggles. Default: `3600` (1 hour). Set to `0` for manual-only polling. |
| `resources` | `[Resource]` | Ordered array of resources shown in the menu. |
| `id` | `UUID` | Auto-generated unique identifier. |
| `name` | `String` | Display name shown in the menu bar and settings. |
| `type` | `"button"` \| `"toggle"` | Resource type. |
| `statusScript` | `String?` | Toggle only — script to determine on/off state. |
| `onScript` | `String?` | Toggle only — script to turn the resource on. |
| `offScript` | `String?` | Toggle only — script to turn the resource off. |
| `actionScript` | `String?` | Button only — script to run when clicked. |

### Import & Export

- **Export**: Settings → **⋯** → **Export Config** saves a `BarKeeper-config.json` file you can share or back up.
- **Import**: Settings → **⋯** → **Import Config** loads a JSON file. This **replaces** your entire config (it does not merge). All toggle statuses are refreshed immediately after import.

## Architecture

```
Sources/
├── BarKeeperApp.swift           # App entry with MenuBarExtra + Settings scenes
├── Models/
│   ├── Resource.swift           # Resource config model (button/toggle)
│   └── ResourceState.swift      # Runtime state (@Observable)
├── ViewModels/
│   └── ResourceManager.swift    # Config, state, polling, script execution
├── Views/
│   ├── MenuBarView.swift        # Menu bar popup
│   ├── ResourceRowView.swift    # Toggle / button row
│   ├── SettingsView.swift       # Settings window with sidebar
│   └── ResourceEditorView.swift # Resource add/edit form
└── Utilities/
    ├── ShellExecutor.swift      # Async shell command runner
    └── ConfigStore.swift        # JSON persistence
```

## Troubleshooting

| Problem | Solution |
|---------|----------|
| Scripts work in Terminal but not in BarKeeper | Ensure your tool is available in a login shell. Run `$SHELL -l -c "which <tool>"` to verify. |
| `az` commands fail | Run `az login` in your terminal first. BarKeeper inherits your CLI session. |
| Menu bar icon shows an error (❗) | Hover over the resource row to see the error in the tooltip. Fix the script and retry. |
| Status always shows OFF | Make sure your status script exits with code `0` when the resource is on. Test with `<script> && echo ON || echo OFF`. |
| Config file is corrupted | Delete `~/Library/Application Support/BarKeeper/config.json` and relaunch. A fresh default config will be created. |
| Polling feels too frequent/infrequent | Adjust the polling interval in **Settings** → **Polling Interval** (1 min to 1 hour, or manual). |

## Security Considerations

- **Scripts run with your full user privileges** — BarKeeper does not sandbox script execution. Only configure scripts you trust.
- **Config is stored in cleartext** — the JSON file at `~/Library/Application Support/BarKeeper/` is readable by any process running as your user. Avoid storing secrets directly in scripts; use `az login` sessions, keychains, or environment variables instead.
- **App Sandbox is disabled** — this is required for BarKeeper to execute arbitrary shell commands and access your login shell environment.

## Support & Problems

BarKeeper is an open-source project provided **as-is**, without warranty or SLA, under the [MIT License](LICENSE). If you run into issues or have questions:

- **Ask the community** — start a discussion or search existing threads for help.
- **Report a bug** — [Open an Issue](../../issues) to report bugs or request features. Issues serve as our bug tracker.

## Contributing

Contributions are welcome! To get started:

1. Open an Issue
2. Create a feature branch 
3. Push to the branch 
4. Open a Pull Request

Please make sure your code compiles with Swift 6 strict concurrency enabled and that existing functionality still works.

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.