#!/usr/bin/env python3
"""Collect incident diagnostics into a bundle directory and tar.gz archive."""

from __future__ import annotations

import argparse
import json
import re
import shlex
import socket
import subprocess
import tarfile
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Sequence


@dataclass
class CmdResult:
    name: str
    command: str
    returncode: int
    stdout: str
    stderr: str
    duration_ms: int

    @property
    def ok(self) -> bool:
        return self.returncode == 0


def as_text(value: str | bytes | None) -> str:
    if value is None:
        return ""
    if isinstance(value, bytes):
        return value.decode("utf-8", errors="replace")
    if isinstance(value, str):
        return value
    return str(value)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Collect incident diagnostics locally or over SSH."
    )
    parser.add_argument("--mode", choices=("local", "ssh"), default="local")
    parser.add_argument("--host", help="Remote host for --mode ssh")
    parser.add_argument("--user", help="SSH user for --mode ssh")
    parser.add_argument("--port-ssh", type=int, default=22, help="SSH port")
    parser.add_argument("--identity", help="SSH private key path")
    parser.add_argument("--service", default="")
    parser.add_argument("--since", default="2h", help='journalctl period, e.g. "2h"')
    parser.add_argument("--out", default="./bundles", help="Output directory")
    parser.add_argument(
        "--include",
        default="",
        help="Comma-separated list of extra files to collect",
    )
    return parser.parse_args()


def now_iso() -> str:
    return datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds")


def timestamp_slug() -> str:
    return datetime.now(timezone.utc).astimezone().strftime("%Y%m%d_%H%M%S")


def sanitize_target(raw: str) -> str:
    return re.sub(r"[^A-Za-z0-9_.-]+", "_", raw).strip("_") or "target"


def build_ssh_base(args: argparse.Namespace) -> list[str]:
    target = args.host
    if args.user:
        target = f"{args.user}@{args.host}"

    cmd = [
        "ssh",
        "-o",
        "BatchMode=yes",
        "-o",
        "ConnectTimeout=5",
        "-p",
        str(args.port_ssh),
    ]
    if args.identity:
        cmd.extend(["-i", args.identity])
    cmd.append(target)
    return cmd


def run_target(
    args: argparse.Namespace, command: str, timeout: int = 60
) -> CmdResult:
    started = time.monotonic()
    if args.mode == "local":
        full_cmd: Sequence[str] = ["bash", "-lc", command]
    else:
        full_cmd = [*build_ssh_base(args), "bash", "-lc", command]

    try:
        proc = subprocess.run(
            full_cmd,
            capture_output=True,
            text=True,
            timeout=timeout,
            check=False,
        )
        rc = proc.returncode
        stdout = proc.stdout
        stderr = proc.stderr
    except subprocess.TimeoutExpired as exc:
        rc = 124
        stdout = as_text(exc.stdout)
        stderr = as_text(exc.stderr) + f"\nTimed out after {timeout}s"

    duration_ms = int((time.monotonic() - started) * 1000)
    return CmdResult(
        name="",
        command=command,
        returncode=rc,
        stdout=stdout,
        stderr=stderr,
        duration_ms=duration_ms,
    )


def write_command_log(path: Path, result: CmdResult) -> None:
    payload = [
        f"# command: {result.command}",
        f"# returncode: {result.returncode}",
        f"# duration_ms: {result.duration_ms}",
        "",
        "## stdout",
        result.stdout.rstrip(),
        "",
        "## stderr",
        result.stderr.rstrip(),
        "",
    ]
    path.write_text("\n".join(payload), encoding="utf-8")


def include_paths(raw: str) -> list[str]:
    values = [item.strip() for item in raw.split(",")]
    return [item for item in values if item]


def safe_file_name(src_path: str) -> str:
    cleaned = src_path.strip().lstrip("/")
    cleaned = cleaned.replace("/", "__")
    cleaned = re.sub(r"[^A-Za-z0-9_.-]+", "_", cleaned)
    return cleaned or "unknown_path"


def check_ssh_connectivity(args: argparse.Namespace) -> tuple[bool, str]:
    test_cmd = [*build_ssh_base(args), "true"]
    try:
        proc = subprocess.run(test_cmd, capture_output=True, text=True, timeout=10)
    except (subprocess.TimeoutExpired, OSError) as exc:
        return False, str(exc)
    if proc.returncode != 0:
        msg = (proc.stderr or proc.stdout or "ssh failed").strip()
        return False, msg
    return True, ""


def build_commands(service: str, since: str) -> list[tuple[str, str]]:
    q_since = shlex.quote(since)
    commands = [
        ("hostnamectl", "hostnamectl"),
        ("date_iso", "date -Is"),
        ("uptime", "uptime"),
        ("journal_errors", f"journalctl -p err --since {q_since} --no-pager"),
        ("dmesg_tail", "dmesg -T | tail -n 400"),
        ("ss_tulpen", "ss -tulpen"),
        ("df_h", "df -h"),
        ("df_i", "df -i"),
        ("free_m", "free -m"),
    ]
    if service:
        q_service = shlex.quote(service)
        commands.extend(
            [
                (
                    "journal_service",
                    f"journalctl -u {q_service} --since {q_since} --no-pager",
                ),
                ("systemctl_status", f"systemctl status {q_service} --no-pager"),
                (
                    "systemctl_show",
                    f"systemctl show {q_service} "
                    "-p ActiveState,SubState,ExecMainStatus,ExecMainStartTimestamp",
                ),
            ]
        )
    return commands


def make_bundle_layout(out_dir: Path, target: str) -> tuple[Path, Path, Path]:
    ts = timestamp_slug()
    bundle_dir = out_dir / f"incident_{target}_{ts}"
    commands_dir = bundle_dir / "commands"
    files_dir = bundle_dir / "files"
    commands_dir.mkdir(parents=True, exist_ok=False)
    files_dir.mkdir(parents=True, exist_ok=False)
    return bundle_dir, commands_dir, files_dir


def collect_bundle(args: argparse.Namespace) -> int:
    started_iso = now_iso()
    started = time.monotonic()

    if args.mode == "ssh" and not args.host:
        print("ERROR: --host is required in ssh mode")
        return 2

    target_display = "local" if args.mode == "local" else (args.host or "unknown")
    if args.mode == "ssh":
        ok, msg = check_ssh_connectivity(args)
        if not ok:
            print(f"ERROR: SSH connectivity check failed: {msg}")
            return 2

    out_dir = Path(args.out).expanduser()
    out_dir.mkdir(parents=True, exist_ok=True)

    target_slug = sanitize_target(target_display)
    try:
        bundle_dir, commands_dir, files_dir = make_bundle_layout(out_dir, target_slug)
    except FileExistsError:
        print("ERROR: bundle directory already exists, try again in a second")
        return 2
    except OSError as exc:
        print(f"ERROR: cannot create bundle directories: {exc}")
        return 2

    command_results: list[dict[str, object]] = []
    include_results: list[dict[str, object]] = []
    any_failures = False

    for name, cmd in build_commands(args.service, args.since):
        result = run_target(args, cmd)
        result.name = name
        write_command_log(commands_dir / f"{name}.log", result)
        if not result.ok:
            any_failures = True
        command_results.append(
            {
                "name": name,
                "command": cmd,
                "returncode": result.returncode,
                "duration_ms": result.duration_ms,
                "stdout_bytes": len(result.stdout.encode("utf-8")),
                "stderr_bytes": len(result.stderr.encode("utf-8")),
            }
        )

    for file_path in include_paths(args.include):
        q = shlex.quote(file_path)
        check_cmd = (
            f"if [ -e {q} ]; then "
            f"if [ -r {q} ]; then echo READABLE; else echo UNREADABLE; fi; "
            "else echo MISSING; fi"
        )
        check_res = run_target(args, check_cmd, timeout=20)
        state = (check_res.stdout.strip() or "UNKNOWN").splitlines()[0]

        include_item = {
            "path": file_path,
            "collected": False,
            "reason": "",
        }

        if check_res.returncode != 0 or state == "UNKNOWN":
            any_failures = True
            include_item["reason"] = (check_res.stderr.strip() or "cannot inspect file")
            include_results.append(include_item)
            continue

        if state != "READABLE":
            any_failures = True
            include_item["reason"] = state.lower()
            include_results.append(include_item)
            continue

        cat_res = run_target(args, f"cat {q}", timeout=30)
        if cat_res.returncode != 0:
            any_failures = True
            include_item["reason"] = cat_res.stderr.strip() or "cat failed"
            include_results.append(include_item)
            continue

        output_name = safe_file_name(file_path) + ".txt"
        (files_dir / output_name).write_text(cat_res.stdout, encoding="utf-8")
        include_item["collected"] = True
        include_item["reason"] = ""
        include_results.append(include_item)

    finished_iso = now_iso()
    duration_ms = int((time.monotonic() - started) * 1000)

    overall_status = "partial" if any_failures else "ok"
    manifest = {
        "target": target_display,
        "mode": args.mode,
        "service": args.service or None,
        "since": args.since,
        "started_at": started_iso,
        "finished_at": finished_iso,
        "duration_ms": duration_ms,
        "command_results": command_results,
        "included_files": include_results,
        "overall_status": overall_status,
        "collector_host": socket.gethostname(),
    }
    (bundle_dir / "manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8"
    )

    archive_path = out_dir / f"{bundle_dir.name}.tar.gz"
    try:
        with tarfile.open(archive_path, "w:gz") as tar:
            tar.add(bundle_dir, arcname=bundle_dir.name)
    except OSError as exc:
        print(f"ERROR: failed to create archive: {exc}")
        manifest["overall_status"] = "error"
        (bundle_dir / "manifest.json").write_text(
            json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8"
        )
        return 2

    print(f"Bundle directory: {bundle_dir}")
    print(f"Bundle archive:   {archive_path}")
    print(f"Overall status:   {manifest['overall_status']}")

    return 1 if any_failures else 0


def main() -> int:
    args = parse_args()
    if args.port_ssh < 1 or args.port_ssh > 65535:
        print("ERROR: --port-ssh must be between 1 and 65535")
        return 2
    return collect_bundle(args)


if __name__ == "__main__":
    raise SystemExit(main())
