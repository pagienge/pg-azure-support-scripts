# Azure VM Serial Console Enabler (Linux)

This bash script tests and enables the Azure Serial Console `getty` on Linux VMs. It identifies the guest distribution, reports the current state of the `serial-getty@ttyS0.service` unit, and — if the unit is not already active — unmasks and starts it in the running OS so a login prompt is available on `ttyS0` via the Azure Serial Console.

The script is intentionally **non-persistent**: it does not run `systemctl enable`, so the change does not survive a reboot. This keeps the tool safe for one-shot triage via Azure Run Command without altering the persistent state of the virtual machine.

## How It Works

The script runs 3 phases:

1. **OS identification** — Using standard OS markers such as the /etc/os-release file, determine if the OS is of a known lineage, and report before starting.
2. **Initial state check** — Queries `LoadState`, `ActiveState`, and `UnitFileState` of `serial-getty@ttyS0.service`. If it is already `loaded` + `active`, the script reports the final state and exits without changes
3. **Enable + validation** — Runs `systemctl unmask` then `systemctl start` on the unit, then re-runs the state check and prints a `FINAL STATE:` summary line reflecting the post-enable values

## Systemd Unit

The Azure Serial Console attaches to a known serial port (`ttyS0`). systemd exposes this as a templated getty unit:

```
serial-getty@ttyS0.service
```

> **Note:** The script only starts the unit in the running system (`systemctl start`). It intentionally skips `systemctl enable`, so a reboot will revert to the image's default configuration. Enabling the service in a persistent state is an exercise for the admin to perform once logged in.

## Supported Distributions

The `check_os_family` step recognizes the following IDs from `/etc/os-release` and any distro whose `ID_LIKE` contains `rhel`, `fedora`, or `centos`:

| Family | Recognized `ID` values |
|---|---|
| Red Hat family | `rhel`, `centos`, `rocky`, `almalinux`, `ol`, `oracle` |
| SUSE family | `sles`, `sled`, `opensuse-leap`, `opensuse-tumbleweed` |
| Debian family | `ubuntu`, `debian` |
| Azure Linux / Mariner | `mariner`, `azurelinux` |
| Container Linux | `flatcar` |

Unrecognized distributions produce a warning but the script still attempts the systemd operations, since any systemd-based Linux with a `ttyS0` device should behave identically.

## Prerequisites

- The Azure Agent for Linux, in a 'ready' state.
- Running extensions is enabled in the Azure Agent.
- `systemd` / `systemctl` on the guest
- A `ttyS0` serial device (present on all standard Linux VMs properly prepared for Azure)
- For connecting to the serial console once enabled: Azure Serial Console prerequisites on the VM/subscription (boot diagnostics enabled, subscription setting allowed)

## Usage

Download the script to the local session.  This can be done in `bash` or Powershell, optionally in the [Azure Cloudshell](https://shell.azure.com), or using a web browser to download from the link https://aka.ms/rcl-serial.sh

bash:
```bash
wget https://aka.ms/rcl-serial.sh
```

Powershell
```PowerShell
Invoke-WebRequest `
    -Uri 'https://aka.ms/rcl-serial.sh' `
    -OutFile 'rcl-serial.sh'
```

Run the script via Azure Run Command, in any of the CLI environments:

### Azure CLI

```bash
az vm run-command invoke \
    --resource-group <resource-group> \
    --name <vm-name> \
    --command-id RunShellScript \
    --scripts @rcl-serial.sh
```

The output of the script will be in json format, with embedded formatting strings. To get more readable output including the exit `code` and `displayStatus` alongside the script's log:

```powershell
az vm run-command invoke `
    --resource-group <resource-group> `
    --name <vm-name> `
    --command-id RunShellScript `
    --scripts @rcl-serial.sh `
    --query "value[].[code, displayStatus, message]" -o tsv
```

`-o tsv` renders the embedded `\n` characters in `message` as real newlines, so the phase headings (`=== OS identification ===`, `=== Initial state ===`, etc.) print on their own lines.

## Important: Non-Persistent by Design

The script uses `systemctl start` but **not** `systemctl enable`. This means:

- The serial console getty is available immediately after the script completes
- After the next reboot the unit returns to whatever state the image originally shipped

If you have validated the console works and want the change to survive reboots, run:

```bash
sudo systemctl enable serial-getty@ttyS0.service
```

## Exit Codes

| Code | Meaning |
|---|---|
| `0` | Serial getty is loaded and active (already, or after successful enable) |
| `1` | Unit still not fully active after the enable attempt |
| `2` | No systemd/`systemctl` on the host — script cannot manage the unit |
| other | Exit code from the failing `systemctl` command |

## References

- [Azure Serial Console for Linux](https://learn.microsoft.com/troubleshoot/azure/virtual-machines/linux/serial-console-linux)
- [Enable Serial Console on Azure VMs](https://learn.microsoft.com/azure/virtual-machines/troubleshooting/serial-console-linux)
- [systemd `serial-getty@.service` template](https://www.freedesktop.org/software/systemd/man/systemd-getty-generator.html)
- [Azure Run Command overview](https://learn.microsoft.com/azure/virtual-machines/linux/run-command)

## Liability

As described in the [MIT license](../../../LICENSE.txt), these scripts are provided as-is with no warranty or liability associated with their use.

## Provide Feedback

We value your input. If you encounter problems with the scripts or ideas on how they can be improved please file an issue in the [Issues](https://github.com/Azure/azure-support-scripts/issues) section of the project.

## Known Issues
