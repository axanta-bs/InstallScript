# Windows development setup

`odoo_install_windows.ps1` is a development bootstrap for Windows 10 and 11. It is intentionally not a production service installer: Odoo runs in the foreground with `workers = 0`, and Nginx, Certbot, Linux init scripts, and production hardening are omitted.

## Prerequisites

Install these tools and ensure they are available in a new PowerShell session:

- Git
- Python 3.10 (64-bit)
- PostgreSQL 14
- Node.js LTS/npm
- Windows App Installer (`winget`), only if using `-InstallPrerequisites`

Run PowerShell as a normal user. If script execution is blocked, use `-ExecutionPolicy Bypass` for this invocation only.

## First setup

Download the installer from GitHub and run it in PowerShell:

```powershell
Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/axanta-bs/InstallScript/16.0/odoo_install_windows.ps1' -OutFile '.\odoo_install_windows.ps1'
Set-ExecutionPolicy -Scope Process Bypass
.\odoo_install_windows.ps1 -InstallPrerequisites
```

If the prerequisites are already installed, omit `-InstallPrerequisites`.

```powershell
.\odoo_install_windows.ps1 -NoStart
```

Alternatively, download the script with:

```powershell
curl.exe -L 'https://raw.githubusercontent.com/axanta-bs/InstallScript/16.0/odoo_install_windows.ps1' -o '.\odoo_install_windows.ps1'
```

The prerequisite installation may update PATH only after PowerShell restarts. If the script reports that a command is missing, open a new PowerShell window and run it again without `-InstallPrerequisites`.

For a setup that uses the defaults but does not start Odoo:

```powershell
.\odoo_install_windows.ps1 -NoStart
```

To list all parameters and examples:

```powershell
.\odoo_install_windows.ps1 -Help
```

The default checkout is `$HOME\odoo-dev`. Override it, select Enterprise source, or skip the private/custom repositories as needed:

```powershell
.\odoo_install_windows.ps1 -Root 'D:\src\odoo-dev' -SkipAddonRepos -NoStart
```

Enterprise source is not downloaded by the script. Put an authenticated checkout at `<Root>\enterprise\addons` and run with `-Enterprise`.

## Daily use

```powershell
cd "$HOME\odoo-dev"
.\run-odoo.ps1
```

Open http://localhost:8069. Stop Odoo with Ctrl+C. The generated configuration is `odoo.conf` and the log is `odoo.log` in the root directory.

## Design notes

The Linux installer creates a PostgreSQL superuser named after the Odoo service user. The Windows script creates a local PostgreSQL login with `CREATEDB`, which is sufficient for development and avoids granting a superuser role. If PostgreSQL uses password authentication, create the role in pgAdmin and set `db_password` in the generated config.

The script reuses an existing checkout and fast-forwards it to the configured branch. Review local changes before rerunning; the script never resets or discards them.

If multiple Python versions are installed, the script first tries `py -3.10` and uses that interpreter explicitly. It does not use Python 3.11, 3.12, or another default Python. With `-InstallPrerequisites`, Python 3.10 is installed only when no usable 3.10 interpreter is found.
