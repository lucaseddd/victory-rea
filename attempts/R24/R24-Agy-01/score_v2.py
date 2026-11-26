"""R24 correctness-gated automated scoring and regression comparison (schema 2.0.0).

Implements R12-aligned rendered-FPS accounting, pure-world per-frame percentiles
from framelog, C1/M1 checkpoint separation, independent visual/ground/facial
gates with explicit unavailable tracking, and anti-gaming checks.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import re
import statistics
import struct
import zlib
from dataclasses import dataclass
from pathlib import Path
from typing import Any

SCHEMA_VERSION = "2.0.0"
ANSI_RE = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]")
METER_RE = re.compile(
    r"(?P<fps>\d+(?:\.\d+)?) fps, (?P<ms>\d+(?:\.\d+)?) ms/frame "
    r"\((?P<prepare>\d+(?:\.\d+)?) preparing:.*?; (?P<gpu_wait>\d+(?:\.\d+)?) on the GPU; "
    r"(?P<copy_back>\d+(?:\.\d+)?) copying back.*?\),\s*(?P<draws>\d+) draws/frame"
    r"(?:, dropped (?P<dropped>\d+) without a host pipeline \((?P<pending>\d+) being made\) and (?P<indirect>\d+) indirect)?"
)
FRAMELOG_TIMES_RE = re.compile(r"frame times: .*?each: ([0-9 ]+)")
FRAMELOG_KINDS_RE = re.compile(
    r"frames by kind: (?P<world>\d+) of the world .*?; (?P<menu>\d+) menu or loading"
)
VRAM_RE = re.compile(
    r"card's own in use at most (?P<used>\d+) MB, its budget at least (?P<budget>\d+) MB, "
    r"the PC's shared in use at most (?P<shared>\d+) MB"
)
REFUSED_RE = re.compile(r"without a host pipeline: refused \[(\w+) ([0-9a-fA-F]+)\]")
PRESENT_LINE_RE = re.compile(
    r"frame=(\d+) draws=(\d+) drawn=(\d+) dispatches=(\d+) dispatched=(\d+)"
)
GPU_LOST_RE = re.compile(r"device (?:removed|lost|hung)|DEVICE_REMOVED")

WEIGHTS_V2 = {
    "progress": 25,
    "speed": 20,
    "loading": 20,
    "stability": 15,
    "shaders": 10,
    "image": 10,
}


def scorer_sha256() -> str:
    return hashlib.sha256(Path(__file__).read_bytes()).hexdigest()


def percentile(values: list[float], pct: float) -> float | None:
    if not values:
        return None
    s = sorted(values)
    idx = min(len(s) - 1, max(0, math.ceil(len(s) * pct / 100.0) - 1))
    return float(s[idx])


def median_or_none(values: list[float]) -> float | None:
    if not values:
        return None
    return float(statistics.median(values))


def _paeth(a: int, b: int, c: int) -> int:
    p = a + b - c
    pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
    if pa <= pb and pa <= pc:
        return a
    return b if pb <= pc else c


def load_png_rgb(path: Path) -> tuple[int, int, list[tuple[int, int, int]]]:
    """Decode an 8-bit non-interlaced RGB/RGBA/grayscale PNG using stdlib only."""
    data = path.read_bytes()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError(f"Not a PNG file: {path.name}")
    pos = 8
    width = height = bit_depth = color_type = 0
    idat = bytearray()
    while pos + 8 <= len(data):
        length, kind = struct.unpack_from(">I4s", data, pos)
        payload = data[pos + 8 : pos + 8 + length]
        pos += 12 + length
        if kind == b"IHDR":
            width, height, bit_depth, color_type, comp, flt, interlace = struct.unpack(
                ">IIBBBBB", payload
            )
            if bit_depth != 8 or comp != 0 or flt != 0 or interlace != 0:
                raise ValueError(f"Unsupported PNG format in {path.name}")
        elif kind == b"IDAT":
            idat.extend(payload)
        elif kind == b"IEND":
            break
    bpp = {0: 1, 2: 3, 4: 2, 6: 4}.get(color_type)
    if bpp is None or width <= 0 or height <= 0:
        raise ValueError(f"Unsupported PNG color_type={color_type} in {path.name}")
    raw = zlib.decompress(bytes(idat))
    stride = width * bpp
    expected = height * (1 + stride)
    if len(raw) < expected:
        raise ValueError(f"Truncated PNG IDAT in {path.name}")
    prev = bytearray(stride)
    pixels: list[tuple[int, int, int]] = []
    idx = 0
    for _ in range(height):
        ftype = raw[idx]
        idx += 1
        row = bytearray(raw[idx : idx + stride])
        idx += stride
        if ftype == 1:
            for i in range(bpp, stride):
                row[i] = (row[i] + row[i - bpp]) & 0xFF
        elif ftype == 2:
            for i in range(stride):
                row[i] = (row[i] + prev[i]) & 0xFF
        elif ftype == 3:
            for i in range(stride):
                left = row[i - bpp] if i >= bpp else 0
                row[i] = (row[i] + ((left + prev[i]) >> 1)) & 0xFF
        elif ftype == 4:
            for i in range(stride):
                left = row[i - bpp] if i >= bpp else 0
                up = prev[i]
                ul = prev[i - bpp] if i >= bpp else 0
                row[i] = (row[i] + _paeth(left, up, ul)) & 0xFF
        elif ftype != 0:
            raise ValueError(f"Unsupported PNG filter {ftype}")
        prev = row
        for x in range(width):
            off = x * bpp
            if color_type == 0:
                g = row[off]
                pixels.append((g, g, g))
            elif color_type == 4:
                g = row[off]
                pixels.append((g, g, g))
            else:
                pixels.append((row[off], row[off + 1], row[off + 2]))
    return width, height, pixels


def image_luma_grid(width: int, height: int, pixels: list[tuple[int, int, int]]) -> list[float]:
    return [0.2126 * r + 0.7152 * g + 0.0722 * b for r, g, b in pixels]


def region_stats(
    width: int,
    height: int,
    luma: list[float],
    rect: tuple[float, float, float, float] = (0.0, 0.0, 1.0, 1.0),
) -> dict[str, float]:
    rx, ry, rw, rh = rect
    x0 = max(0, min(width - 1, round(rx * width)))
    x1 = max(x0 + 1, min(width, round((rx + rw) * width)))
    y0 = max(0, min(height - 1, round(ry * height)))
    y1 = max(y0 + 1, min(height, round((ry + rh) * height)))
    vals: list[float] = []
    grads: list[float] = []
    edges = 0
    for y in range(y0, y1):
        row_off = y * width
        for x in range(x0, x1):
            v = luma[row_off + x]
            vals.append(v)
            if x + 1 < x1 and y + 1 < y1:
                gx = abs(luma[row_off + x + 1] - v)
                gy = abs(luma[(y + 1) * width + x] - v)
                g = math.hypot(gx, gy)
                grads.append(g)
                if g > 12.0:
                    edges += 1
    mean = sum(vals) / len(vals)
    var = sum((v - mean) ** 2 for v in vals) / len(vals)
    grad_mean = sum(grads) / len(grads) if grads else 0.0
    edge_frac = edges / len(grads) if grads else 0.0
    return {
        "mean_luma": round(mean, 3),
        "std_luma": round(math.sqrt(var), 3),
        "grad_mean": round(grad_mean, 3),
        "edge_frac": round(edge_frac, 4),
    }


def region_mad(
    w: int,
    h: int,
    luma_a: list[float],
    luma_b: list[float],
    rect: tuple[float, float, float, float],
    dx: int = 0,
    dy: int = 0,
) -> float:
    rx, ry, rw, rh = rect
    x0 = max(0, min(w - 1, round(rx * w)))
    x1 = max(x0 + 1, min(w, round((rx + rw) * w)))
    y0 = max(0, min(h - 1, round(ry * h)))
    y1 = max(y0 + 1, min(h, round((ry + rh) * h)))
    total = 0.0
    cnt = 0
    for y in range(y0, y1):
        yb = y - dy
        if not (0 <= yb < h):
            continue
        off_a = y * w
        off_b = yb * w
        for x in range(x0, x1):
            xb = x - dx
            if not (0 <= xb < w):
                continue
            total += abs(luma_a[off_a + x] - luma_b[off_b + xb])
            cnt += 1
    return total / max(1, cnt)


def best_head_shift(
    w: int,
    h: int,
    luma_prev: list[float],
    luma_curr: list[float],
    head_rect: tuple[float, float, float, float],
    max_shift_frac: float = 0.10,
) -> tuple[int, int, float]:
    """Find integer (dx, dy) rigid shift aligning head_rect from prev to curr."""
    max_dx = max(2, min(16, round(w * max_shift_frac)))
    max_dy = max(1, min(8, round(h * max_shift_frac * 0.5)))
    best_dx, best_dy = 0, 0
    best_err = float("inf")
    for dy in range(-max_dy, max_dy + 1):
        for dx in range(-max_dx, max_dx + 1):
            err = region_mad(w, h, luma_curr, luma_prev, head_rect, dx=dx, dy=dy)
            if err < best_err:
                best_err = err
                best_dx, best_dy = dx, dy
    return best_dx, best_dy, best_err


def evaluate_frames_gates(
    frame_paths: list[Path],
    *,
    mouth_roi: tuple[float, float, float, float] | None = None,
    head_roi: tuple[float, float, float, float] | None = None,
    spoken_checkpoint: bool = False,
    silent_control_paths: list[Path] | None = None,
    contact_probe: dict[str, Any] | None = None,
) -> dict[str, Any]:
    """Evaluate image, ground coverage/contact, facial motion, and duplicate frames."""
    if not frame_paths:
        return {
            "frames_analyzed": 0,
            "duplicate_frame_fraction": None,
            "image_and_geometry": {
                "status": "unavailable",
                "reason": "no captured 3D frames supplied",
                "score": None,
            },
            "ground_coverage_and_contact": {
                "status": "unavailable",
                "visual_ground_status": "unavailable",
                "contact_status": "unavailable" if contact_probe is None else "pending",
                "reason": "no captured 3D frames supplied",
            },
            "facial_motion": {
                "status": "unavailable",
                "reason": "no captured 3D frames supplied",
            },
        }

    decoded: list[tuple[int, int, list[float]]] = []
    full_stats: list[dict[str, float]] = []
    ground_stats: list[dict[str, float]] = []
    for p in frame_paths:
        w, h, px = load_png_rgb(p)
        luma = image_luma_grid(w, h, px)
        decoded.append((w, h, luma))
        full_stats.append(region_stats(w, h, luma, (0.0, 0.0, 1.0, 1.0)))
        ground_stats.append(region_stats(w, h, luma, (0.10, 0.65, 0.80, 0.30)))

    # Duplicate frame check (repeated frames masquerading as live rendered FPS)
    dup_pairs = 0
    total_pairs = max(0, len(decoded) - 1)
    for i in range(total_pairs):
        w0, h0, l0 = decoded[i]
        w1, h1, l1 = decoded[i + 1]
        if (w0, h0) == (w1, h1):
            mad = region_mad(w0, h0, l0, l1, (0.0, 0.0, 1.0, 1.0))
            if mad < 1.5:
                dup_pairs += 1
    dup_frac = round(dup_pairs / total_pairs, 4) if total_pairs > 0 else 0.0

    # Image & geometry structure gate (rejects dark frames AND bright flat/empty geometry)
    dark_frames = sum(1 for s in full_stats if s["mean_luma"] < 8.0)
    flat_bright_frames = sum(
        1
        for s in full_stats
        if s["mean_luma"] >= 8.0 and (s["std_luma"] < 12.0 or s["edge_frac"] < 0.03)
    )
    valid_frames = len(full_stats) - dark_frames - flat_bright_frames
    image_score = round(100.0 * valid_frames / len(full_stats), 1)
    img_reasons: list[str] = []
    if dark_frames > 0:
        img_reasons.append(f"{dark_frames}/{len(full_stats)} dark frames (<8/255 luma)")
    if flat_bright_frames > 0:
        img_reasons.append(
            f"{flat_bright_frames}/{len(full_stats)} bright-but-degenerate frames (bright missing geometry)"
        )
    img_status = "pass" if not img_reasons else "fail"

    # Ground coverage and contact gate
    g_mean = statistics.median(s["mean_luma"] for s in ground_stats)
    g_std = statistics.median(s["std_luma"] for s in ground_stats)
    g_grad = statistics.median(s["grad_mean"] for s in ground_stats)
    g_edge = statistics.median(s["edge_frac"] for s in ground_stats)
    vis_ground_ok = g_mean >= 6.0 and g_std >= 10.0 and g_grad >= 2.5 and g_edge >= 0.04
    vis_ground_status = "pass" if vis_ground_ok else "fail"

    if contact_probe is None:
        contact_status = "unavailable"
        contact_reason = "no runtime physics/contact probe supplied"
    else:
        grounded_frac = float(contact_probe.get("grounded_fraction", 0.0))
        tested = int(contact_probe.get("contacts_tested", 0))
        if tested <= 0:
            contact_status = "unavailable"
            contact_reason = "zero contact checks recorded"
        elif grounded_frac >= 0.85:
            contact_status = "pass"
            contact_reason = f"grounded_fraction={grounded_frac:.3f} across {tested} checks"
        else:
            contact_status = "fail"
            contact_reason = f"grounded_fraction={grounded_frac:.3f} < 0.85 ({tested} checks)"

    if vis_ground_status == "fail" or contact_status == "fail":
        ground_overall = "fail"
    elif contact_status == "unavailable":
        ground_overall = "unavailable"
    else:
        ground_overall = "pass"

    # Facial motion gate (head-registered residual mouth motion separates lip motion from head/camera motion)
    if not spoken_checkpoint or mouth_roi is None or head_roi is None or len(decoded) < 2:
        facial_gate: dict[str, Any] = {
            "status": "unavailable",
            "reason": "requires spoken_checkpoint=True with mouth_roi, head_roi, and >=2 frames",
        }
    else:
        raw_mouth_mads: list[float] = []
        head_residual_mads: list[float] = []
        rel_motions: list[float] = []
        for i in range(len(decoded) - 1):
            w0, h0, l0 = decoded[i]
            w1, h1, l1 = decoded[i + 1]
            if (w0, h0) != (w1, h1):
                continue
            dx, dy, head_res = best_head_shift(w0, h0, l0, l1, head_roi)
            raw_m = region_mad(w0, h0, l1, l0, mouth_roi)
            reg_m = region_mad(w0, h0, l1, l0, mouth_roi, dx=dx, dy=dy)
            raw_mouth_mads.append(raw_m)
            head_residual_mads.append(head_res)
            rel_motions.append(max(0.0, reg_m - head_res))
        med_mouth = statistics.median(raw_mouth_mads) if raw_mouth_mads else 0.0
        med_head = statistics.median(head_residual_mads) if head_residual_mads else 0.0
        med_rel = statistics.median(rel_motions) if rel_motions else 0.0
        ratio = (med_rel + med_head) / max(0.5, med_head)
        silent_rel = None
        if silent_control_paths and len(silent_control_paths) >= 2:
            sil_dec = []
            for p in silent_control_paths:
                w, h, px = load_png_rgb(p)
                sil_dec.append((w, h, image_luma_grid(w, h, px)))
            s_rels = []
            for i in range(len(sil_dec) - 1):
                w0, h0, l0 = sil_dec[i]
                w1, h1, l1 = sil_dec[i + 1]
                if (w0, h0) == (w1, h1):
                    dx, dy, head_res = best_head_shift(w0, h0, l0, l1, head_roi)
                    reg_m = region_mad(w0, h0, l1, l0, mouth_roi, dx=dx, dy=dy)
                    s_rels.append(max(0.0, reg_m - head_res))
            if s_rels:
                silent_rel = statistics.median(s_rels)
        spoken_active = med_rel >= 2.5 and ratio >= 1.25
        if silent_rel is not None and med_rel <= silent_rel * 1.25:
            spoken_active = False
        facial_gate = {
            "status": "pass" if spoken_active else "fail",
            "median_raw_mouth_mad": round(med_mouth, 3),
            "median_head_residual_mad": round(med_head, 3),
            "median_relative_mouth_motion": round(med_rel, 3),
            "mouth_to_head_ratio": round(ratio, 3),
            "silent_control_relative_motion": round(silent_rel, 3) if silent_rel is not None else None,
            "reason": (
                "head-registered lip motion exceeds head/camera baseline"
                if spoken_active
                else "static mouth relative to registered head during voiced checkpoint"
            ),
        }

    return {
        "frames_analyzed": len(full_stats),
        "duplicate_frame_fraction": dup_frac,
        "image_and_geometry": {
            "status": img_status,
            "score": image_score,
            "dark_frames": dark_frames,
            "flat_bright_frames": flat_bright_frames,
            "median_luma": round(statistics.median(s["mean_luma"] for s in full_stats), 2),
            "median_std": round(statistics.median(s["std_luma"] for s in full_stats), 2),
            "median_edge_frac": round(statistics.median(s["edge_frac"] for s in full_stats), 4),
            "reason": "; ".join(img_reasons) if img_reasons else "structured non-black frames",
        },
        "ground_coverage_and_contact": {
            "status": ground_overall,
            "visual_ground_status": vis_ground_status,
            "contact_status": contact_status,
            "ground_median_luma": round(g_mean, 2),
            "ground_median_std": round(g_std, 2),
            "ground_median_grad": round(g_grad, 2),
            "ground_median_edge_frac": round(g_edge, 4),
            "reason": (
                "visual ground missing/flat"
                if vis_ground_status == "fail"
                else contact_reason
            ),
        },
        "facial_motion": facial_gate,
    }


@dataclass
class RunMetadata:
    exe_name: str
    exe_sha256: str
    pdb_guid: str
    pdb_age: int
    console: str
    display_mode: str
    render_scale: float
    frame_generation: bool
    cache_state: str
    checkpoint: str
    profile_name: str
    bvh_hold: bool = False
    async_present: bool = False
    present_multiplier: float = 1.0
    world_draws_threshold: int = 1000
    min_expected_world_draws: int = 1500


def parse_display_dims(mode: str) -> tuple[int, int] | None:
    m = re.match(r"^\s*(\d+)x(\d+)\s*$", mode)
    if not m:
        return None
    return int(m.group(1)), int(m.group(2))


def score_run(
    log_path: Path,
    meta: RunMetadata,
    *,
    frame_paths: list[Path] | None = None,
    mouth_roi: tuple[float, float, float, float] | None = None,
    head_roi: tuple[float, float, float, float] | None = None,
    spoken_checkpoint: bool = False,
    silent_control_paths: list[Path] | None = None,
    contact_probe: dict[str, Any] | None = None,
    save_events_s: list[float] | None = None,
    enter_accepted_s: float | None = None,
    first_3d_scene_s: float | None = None,
    scene_measured_ok: bool = False,
    first_frame_s: float | None = None,
) -> dict[str, Any]:
    pure_world_ms: list[float] = []
    mixed_ms: list[float] = []
    pure_menu_ms: list[float] = []
    pure_world_windows = 0
    mixed_windows = 0
    pure_menu_windows = 0
    framelog_world_frames = 0
    framelog_menu_frames = 0

    meter_world_samples: list[dict[str, float]] = []
    meter_menu_samples: list[dict[str, float]] = []
    vram_used: list[int] = []
    vram_budget: list[int] = []
    vram_shared: list[int] = []
    refused_pipelines: set[str] = set()
    shaders_translated = 0
    black_runtime = 0
    gpu_lost = 0
    zero_draw_presents = 0
    total_present_lines = 0

    last_each: list[float] | None = None
    with log_path.open(encoding="utf-8", errors="replace") as fh:
        for raw in fh:
            s = ANSI_RE.sub("", raw)
            mf = FRAMELOG_TIMES_RE.search(s)
            if mf:
                last_each = [float(x) for x in mf.group(1).split()]
                continue
            mk = FRAMELOG_KINDS_RE.search(s)
            if mk and last_each is not None:
                w = int(mk.group("world"))
                m = int(mk.group("menu"))
                framelog_world_frames += w
                framelog_menu_frames += m
                if w > 0 and m == 0:
                    pure_world_windows += 1
                    pure_world_ms.extend(last_each)
                elif w > 0 and m > 0:
                    mixed_windows += 1
                    mixed_ms.extend(last_each)
                elif m > 0:
                    pure_menu_windows += 1
                    pure_menu_ms.extend(last_each)
                last_each = None
                continue
            mm = METER_RE.search(s)
            if mm:
                draws = int(mm.group("draws"))
                dropped = int(mm.group("dropped")) if mm.group("dropped") else 0
                pending = int(mm.group("pending")) if mm.group("pending") else 0
                indirect = int(mm.group("indirect")) if mm.group("indirect") else 0
                row = {
                    "fps": float(mm.group("fps")),
                    "ms": float(mm.group("ms")),
                    "prepare_ms": float(mm.group("prepare")),
                    "gpu_wait_ms": float(mm.group("gpu_wait")),
                    "copy_back_ms": float(mm.group("copy_back")),
                    "draws": float(draws),
                    "dropped": float(dropped),
                    "pending": float(pending),
                    "indirect": float(indirect),
                }
                if draws > meta.world_draws_threshold:
                    meter_world_samples.append(row)
                else:
                    meter_menu_samples.append(row)
                continue
            mv = VRAM_RE.search(s)
            if mv:
                vram_used.append(int(mv.group("used")))
                vram_budget.append(int(mv.group("budget")))
                vram_shared.append(int(mv.group("shared")))
            elif "shader translated" in s:
                shaders_translated += 1
            elif mr := REFUSED_RE.search(s):
                refused_pipelines.add(mr.group(2).lower())
            elif mp := PRESENT_LINE_RE.search(s):
                total_present_lines += 1
                if int(mp.group(3)) == 0 and int(mp.group(5)) == 0:
                    zero_draw_presents += 1
            elif "a black frame after a frame that was not" in s:
                black_runtime += 1
            elif GPU_LOST_RE.search(s):
                gpu_lost += 1

    # Autosave milestone fix: ignore boot/profile writes before world entry & accepted Enter.
    valid_autosave_s = None
    if save_events_s and first_3d_scene_s is not None:
        gate_t = max(first_3d_scene_s, enter_accepted_s or 0.0)
        after = [t for t in save_events_s if t >= gate_t]
        if after:
            valid_autosave_s = round(after[0], 2)

    # Prefer pure-world per-frame framelog timings; fall back to meter_world only if framelog off.
    if pure_world_ms:
        world_med_ms = median_or_none(pure_world_ms)
        world_p95_ms = percentile(pure_world_ms, 95.0)
        pct_over_budget = round(
            100.0 * sum(1 for x in pure_world_ms if x > 33.33) / len(pure_world_ms), 2
        )
        drops_2x_pct = round(
            100.0 * sum(1 for x in pure_world_ms if x > 2.0 * world_med_ms) / len(pure_world_ms),
            2,
        )
        hitches_1s = sum(1 for x in pure_world_ms if x > 1000.0)
        timing_source = "framelog_pure_world_per_frame"
    elif meter_world_samples:
        ms_vals = [r["ms"] for r in meter_world_samples]
        world_med_ms = median_or_none(ms_vals)
        world_p95_ms = percentile(ms_vals, 95.0)
        pct_over_budget = round(
            100.0 * sum(1 for x in ms_vals if x > 33.33) / len(ms_vals), 2
        )
        drops_2x_pct = round(
            100.0 * sum(1 for x in ms_vals if x > 2.0 * world_med_ms) / len(ms_vals), 2
        )
        hitches_1s = sum(1 for x in ms_vals if x > 1000.0)
        timing_source = "meter_world_window_fallback"
    else:
        world_med_ms = world_p95_ms = pct_over_budget = drops_2x_pct = None
        hitches_1s = 0
        timing_source = "unavailable"

    raw_rendered_fps = round(1000.0 / world_med_ms, 2) if world_med_ms and world_med_ms > 0 else None

    # Fixed shader coverage math: drawn / (drawn + dropped)
    shader_cov_vals = []
    for r in meter_world_samples:
        tot = r["draws"] + r["dropped"]
        if tot > 0:
            shader_cov_vals.append(100.0 * r["draws"] / tot)
    shader_cov_pct = round(median_or_none(shader_cov_vals), 2) if shader_cov_vals else None
    med_world_draws = median_or_none([r["draws"] for r in meter_world_samples])
    med_world_dropped = median_or_none([r["dropped"] for r in meter_world_samples])
    med_world_indirect = median_or_none([r["indirect"] for r in meter_world_samples])

    visual_gates = evaluate_frames_gates(
        frame_paths or [],
        mouth_roi=mouth_roi,
        head_roi=head_roi,
        spoken_checkpoint=spoken_checkpoint,
        silent_control_paths=silent_control_paths,
        contact_probe=contact_probe,
    )

    # Anti-gaming and workload gate
    anti_gaming_failures: list[str] = []
    if framelog_world_frames == 0 and not meter_world_samples:
        anti_gaming_failures.append("menu_only_samples: zero world frames detected")
    dims = parse_display_dims(meta.display_mode)
    if dims is None or dims[0] < 1280 or dims[1] < 720:
        anti_gaming_failures.append(f"reduced_workload: display_mode {meta.display_mode!r} < 1280x720")
    if meta.render_scale < 1.0:
        anti_gaming_failures.append(f"reduced_workload: render_scale {meta.render_scale} < 1.0")
    if meta.bvh_hold:
        anti_gaming_failures.append("reduced_workload: VICTORY_BVH_HOLD=1 disables ray/BVH work")
    if med_world_draws is not None and med_world_draws < meta.min_expected_world_draws:
        anti_gaming_failures.append(
            f"reduced_workload: median world draws {med_world_draws:.0f} < {meta.min_expected_world_draws}"
        )
    if shader_cov_pct is not None and shader_cov_pct < 80.0:
        anti_gaming_failures.append(f"reduced_workload: shader coverage {shader_cov_pct:.1f}% < 80.0%")
    if meta.frame_generation:
        anti_gaming_failures.append("repeated_or_generated_frames: frame_generation=True cannot count as rendered")
    if meta.present_multiplier > 1.05:
        anti_gaming_failures.append(
            f"repeated_or_generated_frames: present_multiplier={meta.present_multiplier:.2f} > 1.05"
        )
    if meta.async_present:
        anti_gaming_failures.append("repeated_or_generated_frames: VICTORY_ASYNC_PRESENT=1 decouples FRAMES from host present")
    if total_present_lines >= 4 and zero_draw_presents / total_present_lines > 0.5:
        anti_gaming_failures.append(
            f"repeated_or_generated_frames: {zero_draw_presents}/{total_present_lines} presents had zero draws"
        )
    dup_frac = visual_gates.get("duplicate_frame_fraction")
    if dup_frac is not None and dup_frac >= 0.5:
        anti_gaming_failures.append(
            f"repeated_or_generated_frames: {dup_frac*100:.1f}% consecutive captured 3D frames identical"
        )

    if visual_gates["image_and_geometry"]["status"] == "fail":
        anti_gaming_failures.append(
            f"image_or_geometry: {visual_gates['image_and_geometry']['reason']}"
        )
    if visual_gates["ground_coverage_and_contact"]["status"] == "fail":
        anti_gaming_failures.append(
            f"ground_or_contact: {visual_gates['ground_coverage_and_contact']['reason']}"
        )
    if visual_gates["facial_motion"]["status"] == "fail":
        anti_gaming_failures.append(
            f"facial_motion: {visual_gates['facial_motion']['reason']}"
        )

    workload_gate = {
        "status": "fail" if anti_gaming_failures else "pass",
        "anti_gaming_failures": anti_gaming_failures,
        "framelog_world_frames": framelog_world_frames,
        "framelog_menu_frames": framelog_menu_frames,
        "pure_world_windows": pure_world_windows,
        "mixed_windows": mixed_windows,
        "pure_menu_windows": pure_menu_windows,
        "meter_world_samples": len(meter_world_samples),
        "median_world_draws": med_world_draws,
        "median_world_dropped": med_world_dropped,
        "median_world_indirect": med_world_indirect,
        "zero_draw_presents": zero_draw_presents,
    }

    gates = {
        "workload_and_render": workload_gate,
        "image_and_geometry": visual_gates["image_and_geometry"],
        "ground_coverage_and_contact": visual_gates["ground_coverage_and_contact"],
        "facial_motion": visual_gates["facial_motion"],
    }

    # Component scores (never drop missing components silently from release gating)
    has_world = framelog_world_frames > 0 or len(meter_world_samples) > 0
    progress_score = (
        100.0
        if (scene_measured_ok and has_world and gpu_lost == 0)
        else (50.0 if has_world else (30.0 if enter_accepted_s else (10.0 if first_frame_s else 0.0)))
    )
    effective_fps = (
        0.0
        if any(f.startswith(("menu_only", "repeated_or_generated")) for f in anti_gaming_failures)
        else (raw_rendered_fps or 0.0)
    )
    speed_score = round(min(100.0, effective_fps / 30.0 * 100.0), 1) if has_world else 0.0
    loading_score = (
        round(max(0.0, min(100.0, (1.0 - (first_3d_scene_s - 60.0) / 1140.0) * 100.0)), 1)
        if (first_3d_scene_s is not None and has_world)
        else 0.0
    )
    stability_score = (
        0.0
        if gpu_lost > 0
        else (
            round(max(0.0, 100.0 - 2.0 * drops_2x_pct - 5.0 * hitches_1s), 1)
            if drops_2x_pct is not None
            else None
        )
    )
    shaders_score = round(shader_cov_pct, 1) if shader_cov_pct is not None else None
    image_score = visual_gates["image_and_geometry"]["score"]

    components = {
        "progress": progress_score,
        "speed": speed_score,
        "loading": loading_score,
        "stability": stability_score,
        "shaders": shaders_score,
        "image": image_score,
    }
    unavailable_components = [k for k, v in components.items() if v is None]
    unavailable_gates = [k for k, g in gates.items() if g["status"] == "unavailable"]
    failed_gates = [k for k, g in gates.items() if g["status"] == "fail"]

    # Score total still computes weighted average over present components for diagnostics,
    # BUT marks gated=False and caps release qualification whenever any gate fails or is unavailable.
    w_sum = sum(WEIGHTS_V2[k] for k, v in components.items() if v is not None)
    weighted = (
        round(sum(v * WEIGHTS_V2[k] for k, v in components.items() if v is not None) / w_sum, 1)
        if w_sum > 0
        else 0.0
    )
    if anti_gaming_failures:
        weighted = 0.0

    target_met = (
        not failed_gates
        and not unavailable_gates
        and gpu_lost == 0
        and raw_rendered_fps is not None
        and raw_rendered_fps >= 30.0
        and world_p95_ms is not None
        and world_p95_ms <= 33.33
    )

    return {
        "schema_version": SCHEMA_VERSION,
        "scorer": {"name": Path(__file__).name, "sha256": scorer_sha256()},
        "build": {
            "exe_name": meta.exe_name,
            "exe_sha256": meta.exe_sha256.lower(),
            "pdb_guid": meta.pdb_guid.upper(),
            "pdb_age": meta.pdb_age,
        },
        "environment": {
            "console": meta.console,
            "display_mode": meta.display_mode,
            "render_scale": meta.render_scale,
            "frame_generation": meta.frame_generation,
            "cache_state": meta.cache_state,
            "checkpoint": meta.checkpoint,
            "profile_name": meta.profile_name,
        },
        "score_total": weighted,
        "weights": WEIGHTS_V2,
        "components": components,
        "unavailable_components": unavailable_components,
        "gates": gates,
        "failed_gates": failed_gates,
        "unavailable_gates": unavailable_gates,
        "qualified_for_release": target_met,
        "timing": {
            "source": timing_source,
            "pure_world_frames": len(pure_world_ms),
            "mixed_frames": len(mixed_ms),
            "pure_menu_frames": len(pure_menu_ms),
            "rendered_fps": effective_fps,
            "raw_rendered_fps": raw_rendered_fps,
            "median_ms": round(world_med_ms, 2) if world_med_ms is not None else None,
            "p95_ms": round(world_p95_ms, 2) if world_p95_ms is not None else None,
            "pct_over_33_33ms": pct_over_budget,
            "drops_2x_pct": drops_2x_pct,
            "hitches_1s": hitches_1s,
            "prepare_ms_median": round(median_or_none([r["prepare_ms"] for r in meter_world_samples]), 2)
            if meter_world_samples
            else None,
            "gpu_wait_ms_median": round(median_or_none([r["gpu_wait_ms"] for r in meter_world_samples]), 2)
            if meter_world_samples
            else None,
            "copy_back_ms_median": round(median_or_none([r["copy_back_ms"] for r in meter_world_samples]), 2)
            if meter_world_samples
            else None,
        },
        "vram": {
            "typical_mb": round(median_or_none([float(x) for x in vram_used]), 1) if vram_used else None,
            "peak_mb": max(vram_used) if vram_used else None,
            "min_budget_mb": min(vram_budget) if vram_budget else None,
            "shared_peak_mb": max(vram_shared) if vram_shared else None,
        },
        "milestones_s": {
            "first_frame": first_frame_s,
            "enter_accepted": enter_accepted_s,
            "first_3d_scene": first_3d_scene_s,
            "autosave_after_world": valid_autosave_s,
        },
        "shaders": {
            "translated_in_run": shaders_translated,
            "distinct_refused_pipelines": len(refused_pipelines),
            "coverage_pct": shader_cov_pct,
        },
        "gpu_lost": gpu_lost,
        "runtime_black_frames": black_runtime,
        "log_file_name": log_path.name,
    }


def compare_runs_v2(
    current: dict[str, Any],
    previous: dict[str, Any],
    *,
    allow_mismatch: bool = False,
    fps_drop_pct: float = 10.0,
    p95_worse_pct: float = 15.0,
    over_budget_rise_pp: float = 5.0,
    extra_hitches: int = 1,
) -> dict[str, Any]:
    mismatches: list[str] = []
    for key in ("console", "display_mode", "render_scale", "cache_state", "checkpoint"):
        if current["environment"].get(key) != previous["environment"].get(key):
            mismatches.append(
                f"{key}: {previous['environment'].get(key)} != {current['environment'].get(key)}"
            )
    if mismatches and not allow_mismatch:
        return {
            "verdict": "INVALID_COMPARISON",
            "comparable": False,
            "mismatches": mismatches,
            "findings": [f"uncomparable environments ({'; '.join(mismatches)})"],
        }

    findings: list[str] = []
    regression = False

    if current["failed_gates"]:
        regression = True
        findings.append(f"REGRESSION failed gates: {', '.join(current['failed_gates'])}")

    if current["gpu_lost"] > previous["gpu_lost"]:
        regression = True
        findings.append(f"REGRESSION gpu_lost: {previous['gpu_lost']} -> {current['gpu_lost']}")

    if current["components"]["progress"] < previous["components"]["progress"]:
        regression = True
        findings.append(
            f"REGRESSION progress: {previous['components']['progress']} -> {current['components']['progress']}"
        )

    cur_fps = current["timing"]["rendered_fps"]
    prev_fps = previous["timing"]["rendered_fps"]
    if cur_fps and prev_fps:
        delta = 100.0 * (cur_fps - prev_fps) / prev_fps
        msg = f"rendered FPS: {prev_fps:.2f} -> {cur_fps:.2f} ({delta:+.1f}%)"
        if -delta > fps_drop_pct:
            regression = True
            findings.append("REGRESSION " + msg)
        else:
            findings.append("ok " + msg)

    cur_p95 = current["timing"]["p95_ms"]
    prev_p95 = previous["timing"]["p95_ms"]
    if cur_p95 and prev_p95:
        delta = 100.0 * (cur_p95 - prev_p95) / prev_p95
        msg = f"world p95 ms: {prev_p95:.1f} -> {cur_p95:.1f} ({delta:+.1f}%)"
        if delta > p95_worse_pct:
            regression = True
            findings.append("REGRESSION " + msg)
        else:
            findings.append("ok " + msg)

    cur_over = current["timing"]["pct_over_33_33ms"]
    prev_over = previous["timing"]["pct_over_33_33ms"]
    if cur_over is not None and prev_over is not None:
        diff = cur_over - prev_over
        msg = f"% > 33.33 ms: {prev_over:.1f}% -> {cur_over:.1f}% ({diff:+.1f} pp)"
        if diff > over_budget_rise_pp:
            regression = True
            findings.append("REGRESSION " + msg)
        else:
            findings.append("ok " + msg)

    cur_n = max(1, current["timing"]["pure_world_frames"])
    prev_n = max(1, previous["timing"]["pure_world_frames"])
    hitch_diff = current["timing"]["hitches_1s"] - previous["timing"]["hitches_1s"]
    cur_h_rate = 100.0 * current["timing"]["hitches_1s"] / cur_n
    prev_h_rate = 100.0 * previous["timing"]["hitches_1s"] / prev_n
    rate_diff = cur_h_rate - prev_h_rate
    msg_h = (
        f"hitches > 1 s: {previous['timing']['hitches_1s']}/{prev_n} ({prev_h_rate:.2f}%) "
        f"-> {current['timing']['hitches_1s']}/{cur_n} ({cur_h_rate:.2f}%)"
    )
    # When sample counts are comparable (within 2x), check absolute extra hitches;
    # when sample counts differ >2x, check hitch rate (+2.0 pp threshold).
    sample_ratio = max(cur_n, prev_n) / min(cur_n, prev_n)
    hitch_reg = (rate_diff > 2.0) if sample_ratio > 2.0 else (hitch_diff > extra_hitches)
    if hitch_reg:
        regression = True
        findings.append("REGRESSION " + msg_h)
    else:
        findings.append("ok " + msg_h)

    cur_sh = current["shaders"]["coverage_pct"]
    prev_sh = previous["shaders"]["coverage_pct"]
    if cur_sh is not None and prev_sh is not None:
        diff = cur_sh - prev_sh
        msg = f"shader draw coverage: {prev_sh:.2f}% -> {cur_sh:.2f}% ({diff:+.2f} pp)"
        if diff < -5.0:
            regression = True
            findings.append("REGRESSION " + msg)
        else:
            findings.append("ok " + msg)

    verdict = "REGRESSION" if regression else "OK"
    return {
        "verdict": verdict,
        "comparable": len(mismatches) == 0,
        "mismatches": mismatches,
        "findings": findings,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="R24 correctness-gated scorer v2.0.0")
    sub = parser.add_subparsers(dest="cmd", required=True)

    p_score = sub.add_parser("score")
    p_score.add_argument("--log", type=Path, required=True)
    p_score.add_argument("--exe-name", default="victory.exe")
    p_score.add_argument("--exe-sha256", required=True)
    p_score.add_argument("--pdb-guid", required=True)
    p_score.add_argument("--pdb-age", type=int, default=1)
    p_score.add_argument("--console", default="series-s")
    p_score.add_argument("--display-mode", default="1280x720")
    p_score.add_argument("--render-scale", type=float, default=1.0)
    p_score.add_argument("--frame-generation", action="store_true")
    p_score.add_argument("--cache-state", default="warm")
    p_score.add_argument("--checkpoint", default="C1")
    p_score.add_argument("--profile-name", default="Control")
    p_score.add_argument("--out", type=Path)

    p_cmp = sub.add_parser("compare")
    p_cmp.add_argument("--current", type=Path, required=True)
    p_cmp.add_argument("--previous", type=Path, required=True)
    p_cmp.add_argument("--allow-mismatch", action="store_true")

    args = parser.parse_args()
    if args.cmd == "score":
        meta = RunMetadata(
            exe_name=args.exe_name,
            exe_sha256=args.exe_sha256,
            pdb_guid=args.pdb_guid,
            pdb_age=args.pdb_age,
            console=args.console,
            display_mode=args.display_mode,
            render_scale=args.render_scale,
            frame_generation=args.frame_generation,
            cache_state=args.cache_state,
            checkpoint=args.checkpoint,
            profile_name=args.profile_name,
        )
        res = score_run(args.log, meta)
        payload = json.dumps(res, indent=2)
        if args.out:
            args.out.write_text(payload, encoding="utf-8")
        else:
            print(payload)
        return 0
    cur = json.loads(args.current.read_text(encoding="utf-8"))
    prev = json.loads(args.previous.read_text(encoding="utf-8"))
    res = compare_runs_v2(cur, prev, allow_mismatch=args.allow_mismatch)
    print(json.dumps(res, indent=2))
    return 0 if res["verdict"] == "OK" else 1


if __name__ == "__main__":
    raise SystemExit(main())
