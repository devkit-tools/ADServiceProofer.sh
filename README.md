# ADUser Service Proofer v2.1

```bash
bash ADServiceProofer.sh
```

**A lightweight, interactive multi-protocol authentication checker powered by [NetExec (nxc)](https://github.com/Pennyw0rth/NetExec).**

ADUser Service Proofer helps penetration testers validate supplied credentials across **multiple hosts, domains, users, and services** from one Bash interface. No need to manually type the same NetExec commands repeatedly.

> [!IMPORTANT]
> This project is an independent Bash wrapper around **NetExec**. NetExec is required and is **not** bundled with this script. This tool is not an official NetExec project.

## Terminal banner

The following is the **original banner printed by v2.1** (shown without ANSI color codes):

```text
         _____    ____  __  __                _____                 _
        /  _  |  / __ \/ / / /_______  _____/ ___/___  ______   __(_)_______
       / /_| | / / / / / / / ___/ _ \/ ___/\__ \/ _ \/ ___/ | / / / ___/ _ \
      / ___  |/ /_/ / /_/ (__  )  __/ /   ___/ /  __/ /   | |/ / / /__/  __/
     /_/  |_//_____/\____/____/\___/_/   /____/\___/_/    |___/_/\___/\___/
                       [ ADUser Service Proofer v2.1 ]
      +-- Interactive NetExec Authentication Console --+
```

## Features

- **Interactive setup:** enter your targets, optional AD domains, usernames, and a **separate password for every user**.
- **Multiple targets:** supply one or more IP addresses or hostnames, separated by spaces or commas.
- **Multiple domains:** supply one or more AD domains; leave blank if you do not need one.
- **Seven protocols:** SMB, WinRM, RDP, MSSQL, WMI, SSH, and FTP.
- **Hidden password entry:** passwords are not echoed while typing.
- **Review before running:** check all settings and fix typos through an editable menu.
- **Explicit confirmation:** authentication checks begin only after choosing **`x`** and typing **`START`**.
- **Progress display:** shows the current check and total planned checks.

## Requirements

- Linux (e.g. Kali Linux, Parrot Security OS, or HTB Pwnbox)
- **Bash 4.3+**
- **[NetExec](https://github.com/Pennyw0rth/NetExec)** installed and available through the `nxc` command
- Network connectivity to the targets you are authorized to test

## Step 1 — Install NetExec (nxc)

### Option A: Kali Linux / Parrot Security OS (easiest)

```bash
sudo apt update
sudo apt install -y netexec
```

### Option B: Install NetExec with pipx

Useful if `netexec` is not available in your package manager or you prefer an isolated installation:

```bash
sudo apt update
sudo apt install -y pipx git
pipx ensurepath
pipx install git+https://github.com/Pennyw0rth/NetExec
```

Open a **new terminal** after `pipx ensurepath`, if needed. Some dependency builds may also require Rust or Python development headers; consult the official NetExec installation guide below.

### Verify NetExec

```bash
nxc --version
nxc --help
```

If `nxc --version` works, the dependency is ready.

**Official resources:** [NetExec GitHub](https://github.com/Pennyw0rth/NetExec) · [NetExec installation guide](https://www.netexec.wiki/getting-started/installation/installation-on-unix)

## Step 2 — Run ADUser Service Proofer

Place `ADServiceProofer.sh` in your working directory:

```bash
chmod +x ADServiceProofer.sh
./ADServiceProofer.sh.sh
```

Alternatively:

```bash
bash ADServiceProofer.sh.sh
```

To display basic command-line help:

```bash
./ADServiceProofer.sh --help
```

## Step 3 — Enter your configuration

The program asks for:

| Input | Example | Notes |
| --- | --- | --- |
| Target IPs / hostnames | `192.0.2.10, 192.0.2.20` | One or more, separated by spaces or commas |
| AD domains | `lab.example, dev.example` | Optional; press Enter to skip |
| Usernames | `alice, bob` | One or more users |
| Password for `alice` | *(typed invisibly)* | Password is requested separately |
| Password for `bob` | *(typed invisibly)* | Password is requested separately |
| Services | `smb rdp winrm` | Press Enter for all seven |

The passwords above are only placeholders; the interface does not display typed passwords.

## Step 4 — Review and edit your settings

Before running any authentication checks, the following review screen appears:

```text
+------------------- Configuration Review -------------------+
 Targets:
   192.0.2.10
   192.0.2.20
 Domains:
   lab.example
 Users:
   alice                     [password set]
   bob                       [password set]
 Services: smb winrm rdp mssql wmi ssh ftp
 Total authentication checks: 28
+------------------------------------------------------------+
[!] Every check is a login attempt. Account lockout policies may apply.
[!] SSH/FTP do not accept -d in NetExec, so domain entries are not used for them.

ServiceProofer menu:

  x) [START]

  1) Edit target IP
  2) Edit domains
  3) Manage users / passwords
  4) Edit services
  5) Exit

serviceproofer> Select:
```

**Choose `1`–`4` to make corrections.** In **Manage users / passwords**, you can add, edit, remove, or replace users and their associated passwords. Changes are shown in the review before you start.

To run the checks:

1. Enter **`x`** at the menu.
2. Type **`START`** at the confirmation prompt.
3. Read the NetExec results printed for each selected target, service, domain, and user.

To quit without testing, choose **`5`**.

## Understanding the results

NetExec prints one result for each attempted service authentication. Typical outcomes include:

| Result | Meaning |
| --- | --- |
| `[+]` | Authentication accepted by the service |
| `[-]` | Authentication failed or access was denied |
| `(Pwn3d!)` | NetExec detected administrative privileges for that protocol/host |
| No service output | The service may be unavailable or no usable result was returned |

A successful SMB or RDP authentication **does not automatically mean** you have administrator privileges or permission to create an interactive desktop session.

## How multi-target checks work

For SMB, WinRM, RDP, MSSQL, and WMI, the script checks each selected **target × domain × user** combination. When no domain is entered, the domain option is omitted.

For SSH and FTP, the script checks each selected **target × user** combination **without `-d`**, because those NetExec protocol commands do not accept that flag.

**Please note:** this is a credential validation wrapper, not an automatic port scanner. Unavailable services may fail or return no output. When multiple domains are selected, each supplied username is attempted in every selected domain.

## Troubleshooting

| Problem | What to check |
| --- | --- |
| `nxc: command not found` | Install NetExec, run `pipx ensurepath` if relevant, and open a new shell |
| `Permission denied` when launching | Run `chmod +x aduser-service-proofer-v2.1.sh` or start it with `bash` |
| `STATUS_LOGON_FAILURE` | Verify the username/password/domain mapping before another attempt |
| `RPC_S_ACCESS_DENIED` | Authentication and authorization are different; investigate the permissions of the account |
| Blank MSSQL/SSH/FTP section | Confirm the service is listening and reachable, and check the corresponding NetExec module |
| Wrong IP, user, or domain | Return to the review menu and use options `1`–`4` |

## Security notes

> [!WARNING]
> **Use only on systems and accounts you own or are explicitly authorized to assess.** Every attempted login can contribute to Active Directory account-lockout counters. Carefully review the displayed total before choosing START.

- The script **does not save your passwords to a file**; passwords are entered invisibly and shown as `[password set]` in the review.
- Like ordinary `nxc -p ...` commands, the script passes passwords as **process arguments** to NetExec. On shared hosts, these arguments may be visible to other privileged processes or monitoring tools.
- NetExec itself may print usernames and supplied credentials in terminal output. Handle terminal recordings and screenshots as sensitive data.
- The script performs checks sequentially; it **does not** implement account-lockout-aware throttling or automatic service discovery.

## Credits

**Built on [NetExec](https://github.com/Pennyw0rth/NetExec)**, the community-maintained network assessment tool and successor to CrackMapExec. Thanks to the NetExec maintainers and contributors for providing the underlying authentication functionality.

ADUser Service Proofer is a separate interactive Bash utility and is not affiliated with or endorsed by the NetExec project.
