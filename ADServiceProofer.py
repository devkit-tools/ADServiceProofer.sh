#!/usr/bin/env python3
"""ADUser Service Proofer v2.1 - Python Edition.

Interactive, sequential NetExec credential validation for authorized environments.
Requirements: Python 3.9+ and NetExec (`nxc`) on PATH.
"""

from __future__ import annotations

import getpass
import os
import re
import shutil
import subprocess
import sys
from dataclasses import dataclass


AVAILABLE_SERVICES = ("smb", "winrm", "rdp", "mssql", "wmi", "ssh", "ftp")
NON_DOMAIN_SERVICES = {"ssh", "ftp"}
PATTERNS = {
    "target": re.compile(r"^[A-Za-z0-9:][A-Za-z0-9_.:%-]*$"),
    "domain": re.compile(r"^[A-Za-z0-9][A-Za-z0-9.-]*$"),
    "user": re.compile(r"^[A-Za-z0-9_@.\\$-]+$"),
}


class Color:
    enabled = sys.stdout.isatty() and not os.environ.get("NO_COLOR")
    green = "\033[1;32m" if enabled else ""
    cyan = "\033[1;36m" if enabled else ""
    yellow = "\033[1;33m" if enabled else ""
    red = "\033[1;31m" if enabled else ""
    dim = "\033[2m" if enabled else ""
    reset = "\033[0m" if enabled else ""


def banner() -> None:
    art = r"""         _____    ____  __  __                _____                 _
        /  _  |  / __ \/ / / /_______  _____/ ___/___  ______   __(_)_______
       / /_| | / / / / / / / ___/ _ \/ ___/\__ \/ _ \/ ___/ | / / / ___/ _ \
      / ___  |/ /_/ / /_/ (__  )  __/ /   ___/ /  __/ /   | |/ / / /__/  __/
     /_/  |_//_____/\____/____/\___/_/   /____/\___/_/    |___/_/\___/\___/"""
    print(f"{Color.green}{art}{Color.reset}")
    print(f"{Color.cyan}                       [ ADUser Service Proofer v2.1 ]{Color.reset}")
    print(f"{Color.dim}      +-- Interactive NetExec Authentication Console --+{Color.reset}\n")


def info(message: str) -> None:
    print(f"{Color.cyan}[*]{Color.reset} {message}")


def warn(message: str) -> None:
    print(f"{Color.yellow}[!]{Color.reset} {message}")


def error(message: str) -> None:
    print(f"{Color.red}[-]{Color.reset} {message}", file=sys.stderr)


def prompt(label: str) -> str:
    return input(f"{Color.green}aduser>{Color.reset} {label}: ").strip()


def read_list(label: str, kind: str, *, optional: bool = False) -> list[str]:
    """Read a comma/space-separated list and preserve order without duplicates."""
    while True:
        raw = prompt(label)
        items = raw.replace(",", " ").split()
        if not items:
            if optional:
                return []
            error("At least one value is required.")
            continue

        validated = []
        for item in items:
            if kind == "service":
                item = item.lower()
                valid = item in AVAILABLE_SERVICES
            else:
                valid = bool(PATTERNS[kind].fullmatch(item))
            if not valid:
                error(f"Invalid {kind}: {item}")
                break
            if item not in validated:
                validated.append(item)
        else:
            return validated


def prompt_password(username: str) -> str:
    while True:
        password = getpass.getpass(f"{Color.green}aduser>{Color.reset} Password for {username}: ")
        if password:
            return password
        error("Password cannot be empty.")


@dataclass
class Account:
    username: str
    password: str


def read_users() -> list[Account]:
    usernames = read_list("Usernames (comma/space-separated)", "user")
    return [Account(username, prompt_password(username)) for username in usernames]


def user_index(users: list[Account], label: str) -> int | None:
    choice = input(f"{label}: ").strip()
    if not choice.isdecimal() or not 1 <= int(choice) <= len(users):
        error("Invalid user number.")
        return None
    return int(choice) - 1


def manage_users(users: list[Account]) -> list[Account]:
    while True:
        print(f"\n{Color.cyan}User accounts:{Color.reset}")
        for number, account in enumerate(users, 1):
            print(f"  {number}) {account.username}  [password set]")
        print("  a) Add user\n  e) Edit user / password\n  r) Remove user\n  x) Replace entire list\n  b) Back")
        choice = prompt("Choice").lower()

        if choice == "a":
            name = prompt("New username")
            if not PATTERNS["user"].fullmatch(name):
                error("Invalid username.")
            elif any(account.username == name for account in users):
                error("User already listed.")
            else:
                users.append(Account(name, prompt_password(name)))

        elif choice == "e":
            index = user_index(users, "User number to edit")
            if index is None:
                continue
            current = users[index]
            name = input(f"New username [{current.username}] (Enter = keep): ").strip()
            if name:
                if not PATTERNS["user"].fullmatch(name):
                    error("Invalid username.")
                    continue
                if any(other.username == name for i, other in enumerate(users) if i != index):
                    error("User already listed.")
                    continue
                current.username = name
            if input("Change password? [y/N]: ").strip().lower() in ("y", "yes"):
                current.password = prompt_password(current.username)

        elif choice == "r":
            if len(users) == 1:
                error("Keep at least one user.")
                continue
            index = user_index(users, "User number to remove")
            if index is not None:
                del users[index]

        elif choice == "x":
            users = read_users()
        elif choice in ("b", ""):
            return users
        else:
            error("Unknown choice.")


@dataclass
class Configuration:
    targets: list[str]
    domains: list[str]
    users: list[Account]
    services: list[str]

    def attempt_count(self) -> int:
        domain_count = max(1, len(self.domains))
        return sum(
            len(self.targets) * len(self.users) * (1 if service in NON_DOMAIN_SERVICES else domain_count)
            for service in self.services
        )


def review(config: Configuration) -> None:
    print(f"\n{Color.green}+------------------- Configuration Review -------------------+{Color.reset}")
    print(" Targets:")
    for target in config.targets:
        print(f"   {target}")
    print(" Domains:")
    for domain in config.domains or ["(none / default authentication context)"]:
        print(f"   {domain}")
    print(" Users:")
    for account in config.users:
        print(f"   {account.username:<25} [password set]")
    print(f" Services: {' '.join(config.services)}")
    print(f" Total authentication checks: {config.attempt_count()}")
    print(f"{Color.green}+------------------------------------------------------------+{Color.reset}")
    warn("Every check is a login attempt. Account lockout policies may apply.")
    if len(config.domains) > 1:
        warn("Each username is tested in EVERY listed domain on each target.")
    warn("SSH/FTP do not accept -d in NetExec, so domain entries are not used for them.")


def checks(config: Configuration):
    """Generate each command as a list to avoid shell interpretation of passwords."""
    for target in config.targets:
        for service in config.services:
            domains = [""] if service in NON_DOMAIN_SERVICES else (config.domains or [""])
            for domain in domains:
                for account in config.users:
                    args = ["nxc", service, target]
                    if domain:
                        args.extend(["-d", domain])
                    args.extend(["-u", account.username, "-p", account.password])
                    yield service, target, domain, account.username, args


def run_checks(config: Configuration) -> None:
    total = config.attempt_count()
    info("Starting checks...")
    completed = 0
    for number, (service, target, domain, user, command) in enumerate(checks(config), 1):
        context = f"{service.upper()} | {target} | "
        if service not in NON_DOMAIN_SERVICES:
            context += f"{domain or 'NO DOMAIN'} | "
        print(f"\n{Color.cyan}========== [{number}/{total}] {context}{user} =========={Color.reset}", flush=True)
        try:
            outcome = subprocess.run(command, check=False)  # no shell=True
            if outcome.returncode:
                warn(f"NetExec returned exit code {outcome.returncode} ({service} / {target} / {user}).")
        except OSError as exc:
            error(f"Could not launch NetExec: {exc}")
            return
        completed += 1
    print(f"\n{Color.green}[+] Completed {completed} authentication checks.{Color.reset}")


def main() -> int:
    if len(sys.argv) > 1:
        if sys.argv[1] in ("-h", "--help"):
            print(f"Usage: {sys.argv[0]}\nInteractive NetExec checks. Requires Python 3.9+ and nxc.")
            return 0
        error("Unknown argument. Try --help.")
        return 2

    banner()
    config = Configuration(
        targets=read_list("Target IPs / hostnames (comma/space-separated)", "target"),
        domains=read_list("AD domains (optional; Enter = none)", "domain", optional=True),
        users=read_users(),
        services=[],
    )
    info(f"Available services: {' '.join(AVAILABLE_SERVICES)}")
    config.services = read_list("Services (Enter = all; comma/space-separated)", "service", optional=True) or list(AVAILABLE_SERVICES)

    while True:
        review(config)
        print(f"\n{Color.cyan}ServiceProofer menu:{Color.reset}\n")
        print(f"  {Color.green}x) [START]{Color.reset}\n")
        print("  1) Edit target IP\n  2) Edit domains\n  3) Manage users / passwords\n  4) Edit services\n  5) Exit")
        choice = input(f"{Color.green}serviceproofer>{Color.reset} Select: ").strip().lower()

        if choice == "1":
            config.targets = read_list("Target IPs / hostnames", "target")
        elif choice == "2":
            config.domains = read_list("AD domains (optional; Enter = none)", "domain", optional=True)
        elif choice == "3":
            config.users = manage_users(config.users)
        elif choice == "4":
            info(f"Available services: {' '.join(AVAILABLE_SERVICES)}")
            config.services = read_list("Services (Enter = all)", "service", optional=True) or list(AVAILABLE_SERVICES)
        elif choice == "x":
            if not shutil.which("nxc"):
                error("NetExec (nxc) not found in PATH.")
                continue
            if input("Type START to confirm all checks: ").strip() != "START":
                warn("Cancelled. You can still edit the configuration.")
                continue
            run_checks(config)
            return 0
        elif choice == "5":
            info("Exiting without running checks.")
            return 0
        else:
            error("Unknown choice.")


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (KeyboardInterrupt, EOFError):
        print("\n[*] Interrupted. Exiting.")
        raise SystemExit(130)
