"""
Ryzanstein Sync
===============
Sprint 4.1 (Sigma ecosystem federation): syncs written nightly reflections
to the Debian box, where a remote script embeds them via Ryzanstein and
stores them in a dedicated Qdrant collection (xmrig_reflections) for
semantic retrieval.

Ryzanstein (127.0.0.1:8000) and Qdrant (127.0.0.1:6333) are both
deliberately loopback-only on that box for security -- this script never
talks to them directly and never opens that up. It only scp's the already-
written reflection file over SSH (using this ecosystem's established
"sigma-box" SSH config alias) and triggers a remote ingest script that
uses the box's own localhost access.

Runs as its own separate scheduled task, chained after (not merged into)
the existing nightly reflection job -- does not modify nightly_reflect()
or its Windows Task Scheduler entry.

Usage:
    python -m intelligence.ryzanstein_sync

Author: XMRig Automation
License: MIT
"""
import os
import subprocess
import sys

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REFLECTIONS_DIR = os.path.join(REPO_ROOT, "logs", "reflections")
SYNC_MARKER = os.path.join(REPO_ROOT, "logs", ".ryzanstein_synced")

REMOTE_HOST = "sigma-box"
REMOTE_DIR = "/home/stevo/xmrig-sync/reflections"
REMOTE_INGEST_SCRIPT = "/home/stevo/xmrig-sync/ingest_reflection.py"

SSH_TIMEOUT_S = 30
SCP_TIMEOUT_S = 60
INGEST_TIMEOUT_S = 120


def _load_synced() -> set:
    if not os.path.exists(SYNC_MARKER):
        return set()
    with open(SYNC_MARKER, "r", encoding="utf-8") as f:
        return {line.strip() for line in f if line.strip()}


def _mark_synced(filename: str) -> None:
    with open(SYNC_MARKER, "a", encoding="utf-8") as f:
        f.write(filename + "\n")


def sync_new_reflections() -> list:
    """Sync any reflection .md files not yet synced.

    Returns the list of filenames successfully synced. Never raises --
    a sync failure must never be allowed to affect mining or the
    (already-succeeded, already-written) nightly reflection itself. This
    is a best-effort federation step, not part of the core intelligence
    layer's correctness.
    """
    if not os.path.isdir(REFLECTIONS_DIR):
        return []

    synced_already = _load_synced()
    synced_now = []

    for fname in sorted(os.listdir(REFLECTIONS_DIR)):
        if not fname.endswith(".md") or fname in synced_already:
            continue
        local_path = os.path.join(REFLECTIONS_DIR, fname)
        try:
            subprocess.run(
                ["ssh", REMOTE_HOST, f"mkdir -p {REMOTE_DIR}"],
                check=True, capture_output=True, timeout=SSH_TIMEOUT_S,
            )
            subprocess.run(
                ["scp", local_path, f"{REMOTE_HOST}:{REMOTE_DIR}/{fname}"],
                check=True, capture_output=True, timeout=SCP_TIMEOUT_S,
            )
            result = subprocess.run(
                ["ssh", REMOTE_HOST,
                 f"python3 {REMOTE_INGEST_SCRIPT} {REMOTE_DIR}/{fname}"],
                check=True, capture_output=True, timeout=INGEST_TIMEOUT_S,
                text=True,
            )
            print(f"Synced {fname}: {result.stdout.strip()}")
            _mark_synced(fname)
            synced_now.append(fname)
        except subprocess.CalledProcessError as e:
            print(f"FAILED to sync {fname}: {e.stderr}", file=sys.stderr)
        except subprocess.TimeoutExpired:
            print(f"FAILED to sync {fname}: timed out", file=sys.stderr)

    return synced_now


if __name__ == "__main__":
    synced = sync_new_reflections()
    if synced:
        print(f"Synced {len(synced)} reflection(s): {synced}")
    else:
        print("Nothing new to sync.")
