#!/usr/bin/env python3
"""Aggregate world-data, on-demand tile, and page-write coherence metrics from local VIctory stderr logs."""

from __future__ import annotations

import argparse
import csv
import pathlib
import re
from dataclasses import dataclass

TILES_RE = re.compile(
    r"textures with levels on demand:\s*(\d+) alive \((\d+) made so far\), "
    r"(\d+) MB of the card given to (\d+) levels in all,\s*(\d+) MB of the card not allocated"
)
CENSUS_RE = re.compile(
    r"placed texture slots picked by index, by what the host slot shows:\s*"
    r"(\d+) slots; (\d+) shown with their contents; (\d+) shown from a copy made level by level"
)
NO_LEVEL_HELD_RE = re.compile(
    r"of the slots that read zeros,\s*(\d+) show a copy with no level judged"
)
PAGE_WRITES_RE = re.compile(
    r"writes behind the guards, since the start:\s*(\d+) DirectStorage writes into physical pages.*?"
    r"\((\d+) MB\);\s*(\d+) guarded 64 KiB blocks.*?;\s*(\d+) reads to plain addresses finished \(([^)]+)\);\s*"
    r"(\d+) ranges under texture views kept.*?;\s*(\d+) slots of placed textures held their bytes,\s*"
    r"(\d+) of them uploaded before the write \(([^)]+)\)"
)
TEXBACK_RE = re.compile(r"texture readback landed")


@dataclass
class RunMetrics:
    run: str
    log_lines: int
    first_tiles: str
    last_tiles_alive: int
    last_tiles_made: int
    last_tile_levels: int
    last_tile_mb: int
    census_total_slots: int
    census_shown_ok: int
    census_blank_on_demand: int
    census_blank_no_held_level: str
    phys_page_writes: int
    phys_page_mb: int
    guarded_blocks_opened: int
    plain_addr_reads: int
    plain_addr_action: str
    placed_slots_touched: int
    placed_slots_uploaded_stale: int
    placed_slots_action: str
    tex_changed_warns: int
    texback_landed_logs: int


def parse_log(name: str, path: pathlib.Path) -> RunMetrics:
    lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    tiles_matches: list[tuple[int, int, int, int, int]] = []
    census_lines: list[str] = []
    pw_lines: list[str] = []
    tex_changed_warns = 0
    texback_landed = 0

    for line in lines:
        if "textures with levels on demand:" in line:
            m = TILES_RE.search(line)
            if m:
                tiles_matches.append(tuple(int(m.group(i)) for i in (1, 2, 4, 3, 5)))
        if "placed texture slots picked by index," in line:
            census_lines.append(line)
        if "writes behind the guards, since the start:" in line:
            pw_lines.append(line)
        if "a texture picked by index changed after its upload" in line:
            tex_changed_warns += 1
        if TEXBACK_RE.search(line):
            texback_landed += 1

    if tiles_matches:
        f_alive, f_made, f_lv, f_mb, _ = tiles_matches[0]
        first_tiles = f"{f_alive}/{f_made}/{f_lv}lv/{f_mb}MB"
        l_alive, l_made, l_lv, l_mb, _ = tiles_matches[-1]
    else:
        first_tiles = "none"
        l_alive = l_made = l_lv = l_mb = 0

    c_total = c_ok = c_blank = 0
    c_no_held = "N/A"
    if census_lines:
        last_c = census_lines[-1]
        m = CENSUS_RE.search(last_c)
        if m:
            c_total, c_ok, c_blank = int(m.group(1)), int(m.group(2)), int(m.group(3))
        m2 = NO_LEVEL_HELD_RE.search(last_c)
        if m2:
            c_no_held = m2.group(1)

    pw_phys = pw_mb = pw_blocks = pw_plain = pw_slots = pw_stale = 0
    pw_plain_act = pw_slots_act = "none"
    if pw_lines:
        last_pw = re.sub(r"\s+", " ", pw_lines[-1])
        m = PAGE_WRITES_RE.search(last_pw)
        if m:
            pw_phys = int(m.group(1))
            pw_mb = int(m.group(2))
            pw_blocks = int(m.group(3))
            pw_plain = int(m.group(4))
            pw_plain_act = m.group(5)
            pw_slots = int(m.group(7))
            pw_stale = int(m.group(8))
            pw_slots_act = m.group(9)

    return RunMetrics(
        run=name,
        log_lines=len(lines),
        first_tiles=first_tiles,
        last_tiles_alive=l_alive,
        last_tiles_made=l_made,
        last_tile_levels=l_lv,
        last_tile_mb=l_mb,
        census_total_slots=c_total,
        census_shown_ok=c_ok,
        census_blank_on_demand=c_blank,
        census_blank_no_held_level=c_no_held,
        phys_page_writes=pw_phys,
        phys_page_mb=pw_mb,
        guarded_blocks_opened=pw_blocks,
        plain_addr_reads=pw_plain,
        plain_addr_action=pw_plain_act,
        placed_slots_touched=pw_slots,
        placed_slots_uploaded_stale=pw_stale,
        placed_slots_action=pw_slots_act,
        tex_changed_warns=tex_changed_warns,
        texback_landed_logs=texback_landed,
    )


DEFAULT_RUNS = [
    ("cand4_HW0", "fxceless-f6a09d3b-cand4-run/rapido-series-s-fila0-worker0-mips1-pisopadrao-discopadrao-1280x720-20261126-081659-513.stderr"),
    ("cand5_v002_HW0", "victory-pipeline/rodadas/v002-cand5-cena-preta-db827d45-rapido-20261126-084154.stderr"),
    ("next_rea_BuffersVRAM", "build-next-rea/run/BuffersVRAM-20261126-094849-762.stderr"),
    ("next_rea_Integrado", "build-next-rea/run/Integrado-20261126-091241-832.stderr"),
    ("r27_mouth_Integrado", "build-rea-r27-mouth/run/Integrado-20261126-120934-601.stderr"),
    ("r27_perf_Fluidez", "build-rea-r27-perf/run/Fluidez-20261126-125649-227.stderr"),
]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--workspace", type=pathlib.Path, default=pathlib.Path("."))
    parser.add_argument("--out", type=pathlib.Path, default=pathlib.Path("coherence_summary.csv"))
    args = parser.parse_args()

    rows: list[RunMetrics] = []
    for name, rel in DEFAULT_RUNS:
        p = args.workspace / rel
        if p.exists():
            rows.append(parse_log(name, p))

    if not rows:
        raise SystemExit("no matching local stderr logs found under workspace")

    fieldnames = list(RunMetrics.__dataclass_fields__.keys())
    with args.out.open("w", newline="", encoding="utf-8") as fh:
        writer = csv.DictWriter(fh, fieldnames=fieldnames)
        writer.writeheader()
        for r in rows:
            writer.writerow(r.__dict__)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
