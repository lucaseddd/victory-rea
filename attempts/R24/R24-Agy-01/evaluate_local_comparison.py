"""Run R24 v2 scorer across local Candidate 4 vs Candidate 5 runs and local capture sample."""
from __future__ import annotations

import csv
import json
from pathlib import Path

from score_v2 import RunMetadata, compare_runs_v2, evaluate_frames_gates, score_run

WORKSPACE = Path(__file__).resolve().parents[4]


def main() -> int:
    cand4_log = (
        WORKSPACE
        / "fxceless-f6a09d3b-cand4-run"
        / "rapido-series-s-fila0-worker0-mips1-pisopadrao-discopadrao-1280x720-20261126-081659-513.stderr"
    )
    cand5_log = (
        WORKSPACE
        / "victory-pipeline"
        / "rodadas"
        / "v002-cand5-cena-preta-db827d45-rapido-20261126-084154.stderr"
    )
    out_dir = Path(__file__).resolve().parent

    cand4 = score_run(
        cand4_log,
        RunMetadata(
            exe_name="victory.exe",
            exe_sha256="2ffd8cb5f3e66c16e6cec8005e778a76692a337fd1075cc3d3cd72991ff41973",
            pdb_guid="079087F6D20D457980A62BC749D33EE3",
            pdb_age=1,
            console="series-s",
            display_mode="1280x720",
            render_scale=1.0,
            frame_generation=False,
            cache_state="warm",
            checkpoint="C1",
            profile_name="Cand4-rapido",
        ),
        first_frame_s=11.5,
        enter_accepted_s=610.3,
        first_3d_scene_s=612.5,
        save_events_s=[612.6],
        scene_measured_ok=False,
    )

    cand5 = score_run(
        cand5_log,
        RunMetadata(
            exe_name="victory.exe",
            exe_sha256="db827d457c47c607489dba29bcfe4a85d8e0bba3f149111bb911553f6bd7fbe9",
            pdb_guid="12F63D85330944469A11A69A686708C8",
            pdb_age=1,
            console="series-s",
            display_mode="1280x720",
            render_scale=1.0,
            frame_generation=False,
            cache_state="warm",
            checkpoint="C1",
            profile_name="Cand5-v002-rapido",
        ),
        first_frame_s=18.0,
        enter_accepted_s=125.6,
        first_3d_scene_s=394.0,
        save_events_s=[18.8],
        scene_measured_ok=False,
    )

    cmp = compare_runs_v2(cand5, cand4)

    # Also test visual/ground gate evaluator on local non-empty capture slice
    cap_dir = WORKSPACE / "cutscene-lab" / "capture-20261125-181538-671"
    sample_pngs = [
        cap_dir / "frame-7952.png",
        cap_dir / "frame-15952.png",
        cap_dir / "frame-30439.png",
    ]
    cap_eval = (
        evaluate_frames_gates([p for p in sample_pngs if p.is_file()])
        if all(p.is_file() for p in sample_pngs)
        else None
    )

    rows = []
    for tag, r in [("cand4-2ffd8cb5", cand4), ("cand5-db827d45", cand5)]:
        rows.append(
            {
                "candidate": tag,
                "exe_sha256": r["build"]["exe_sha256"],
                "pdb_guid": r["build"]["pdb_guid"],
                "console": r["environment"]["console"],
                "display_mode": r["environment"]["display_mode"],
                "cache_state": r["environment"]["cache_state"],
                "pure_world_frames": r["timing"]["pure_world_frames"],
                "mixed_frames": r["timing"]["mixed_frames"],
                "rendered_fps": r["timing"]["rendered_fps"],
                "median_ms": r["timing"]["median_ms"],
                "p95_ms": r["timing"]["p95_ms"],
                "pct_over_33_33ms": r["timing"]["pct_over_33_33ms"],
                "hitches_1s": r["timing"]["hitches_1s"],
                "typical_vram_mb": r["vram"]["typical_mb"],
                "peak_vram_mb": r["vram"]["peak_mb"],
                "shared_peak_mb": r["vram"]["shared_peak_mb"],
                "shader_coverage_pct": r["shaders"]["coverage_pct"],
                "workload_gate": r["gates"]["workload_and_render"]["status"],
                "image_gate": r["gates"]["image_and_geometry"]["status"],
                "ground_gate": r["gates"]["ground_coverage_and_contact"]["status"],
                "facial_gate": r["gates"]["facial_motion"]["status"],
                "qualified_for_release": r["qualified_for_release"],
                "score_total": r["score_total"],
            }
        )

    csv_path = out_dir / "candidate_comparison.csv"
    with csv_path.open("w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=list(rows[0].keys()))
        w.writeheader()
        w.writerows(rows)

    print("Comparison verdict:", cmp["verdict"])
    for f in cmp["findings"]:
        print(" ", f)
    print("CSV written:", csv_path.name)
    for row in rows:
        print(json.dumps(row))
    if cap_eval:
        print("Local capture slice gate check (aggregate only):", json.dumps(cap_eval))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
