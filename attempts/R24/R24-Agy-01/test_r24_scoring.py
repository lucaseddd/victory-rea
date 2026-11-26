"""Unit and anti-gaming fixture tests for R24 correctness-gated scoring (schema 2.0.0)."""
from __future__ import annotations

import struct
import tempfile
import unittest
import zlib
from pathlib import Path

from score_v2 import (
    SCHEMA_VERSION,
    RunMetadata,
    compare_runs_v2,
    score_run,
)


def write_png(path: Path, width: int, height: int, pixel_fn) -> None:
    raw = bytearray()
    for y in range(height):
        raw.append(0)
        for x in range(width):
            r, g, b = pixel_fn(x, y)
            raw.extend((r & 0xFF, g & 0xFF, b & 0xFF))
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)

    def chunk(kind: bytes, data: bytes) -> bytes:
        crc = zlib.crc32(kind + data) & 0xFFFFFFFF
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", crc)

    png = (
        b"\x89PNG\r\n\x1a\n"
        + chunk(b"IHDR", ihdr)
        + chunk(b"IDAT", zlib.compress(bytes(raw)))
        + chunk(b"IEND", b"")
    )
    path.write_bytes(png)


def base_meta(**overrides) -> RunMetadata:
    kwargs = dict(
        exe_name="victory.exe",
        exe_sha256="a" * 64,
        pdb_guid="14F11B44E861429C850B936ADEAF6A88",
        pdb_age=1,
        console="series-s",
        display_mode="1280x720",
        render_scale=1.0,
        frame_generation=False,
        cache_state="warm",
        checkpoint="C1",
        profile_name="Control",
    )
    kwargs.update(overrides)
    return RunMetadata(**kwargs)


VALID_WORLD_LOG = """\
2026-11-26T12:00:00Z INFO victory_gpu::host: card's own in use at most 3200 MB, its budget at least 5100 MB, the PC's shared in use at most 120 MB
2026-11-26T12:00:05Z INFO victory_gpu::host: 30.0 fps, 33.3 ms/frame (2.0 preparing: copies 0.5 ms 1.0 MB, textures 0.5 ms 1.0 MB; 15.0 on the GPU; 0.2 copying back 0.1 MB), 3500 draws/frame, dropped 10 without a host pipeline (0 being made) and 1 indirect
2026-11-26T12:00:05Z INFO victory_gpu::framelog: frame times: 10 frames in 0.3 s: shortest 28 ms, median 31, longest 33; 0 long (over 70 ms, the usual frame of the last 64 being 31); each: 30 31 32 31 29 33 30 31 32 28
2026-11-26T12:00:05Z INFO victory_gpu::framelog: frames by kind: 10 of the world (6 or more host submissions) in 0.3 s: mean 31 ms, 32.57 a second while they ran; 0 menu or loading frames (fewer submissions) in 0.0 s: mean 0 ms
"""


def make_structured_frame(tmp: Path, name: str, mouth_offset: int, pan_x: int = 0) -> Path:
    """Create a 64x36 frame with textured ground, stable head, and movable mouth ROI."""
    p = tmp / name

    def px(x: int, y: int) -> tuple[int, int, int]:
        # Ground band (y >= 23, ~0.65..0.95): textured terrain checkerboard + gradient
        if y >= 23:
            v = 40 + ((x + y * 3) % 5) * 28 + (100 if (x // 3 + y // 2) % 2 == 0 else 0)
            return (v, min(255, v + 10), max(0, v - 15))
        # Head ROI (x in 20..44, y in 4..20)
        hx = x - pan_x
        if 20 <= hx < 44 and 4 <= y < 20:
            # Mouth sub-ROI (x in 26..38, y in 13..18)
            if 26 <= hx < 38 and 13 <= y < 18:
                if mouth_offset > 0 and 14 <= y < 14 + mouth_offset:
                    return (20, 15, 15)
                return (210, 180, 165)
            return (150 + ((hx + y) % 3) * 15, 120, 100)
        # Background sky/building structure
        v = 50 + ((x * 7 + y * 11) % 60)
        return (v, v + 15, v + 25)

    write_png(p, 64, 36, px)
    return p


class R24ScoringTests(unittest.TestCase):
    def test_valid_run_passes_all_gates_and_qualifies(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            tmp = Path(td)
            log = tmp / "valid.stderr"
            log.write_text(VALID_WORLD_LOG, encoding="utf-8")
            frames = [
                make_structured_frame(tmp, "f0.png", mouth_offset=1),
                make_structured_frame(tmp, "f1.png", mouth_offset=3),
                make_structured_frame(tmp, "f2.png", mouth_offset=0),
            ]
            silent = [
                make_structured_frame(tmp, "s0.png", mouth_offset=0),
                make_structured_frame(tmp, "s1.png", mouth_offset=0),
            ]
            res = score_run(
                log,
                base_meta(),
                frame_paths=frames,
                mouth_roi=(26 / 64, 13 / 36, 12 / 64, 5 / 36),
                head_roi=(20 / 64, 4 / 36, 24 / 64, 9 / 36),
                spoken_checkpoint=True,
                silent_control_paths=silent,
                contact_probe={"grounded_fraction": 1.0, "contacts_tested": 12},
                first_frame_s=10.0,
                enter_accepted_s=15.0,
                first_3d_scene_s=60.0,
                scene_measured_ok=True,
            )
            self.assertEqual(res["schema_version"], SCHEMA_VERSION)
            self.assertEqual(len(res["scorer"]["sha256"]), 64)
            self.assertEqual(res["failed_gates"], [])
            self.assertEqual(res["unavailable_gates"], [])
            self.assertTrue(res["qualified_for_release"])
            self.assertGreaterEqual(res["timing"]["rendered_fps"], 30.0)
            self.assertLessEqual(res["timing"]["p95_ms"], 33.33)

    def test_rejects_bright_missing_geometry(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            tmp = Path(td)
            log = tmp / "bright_empty.stderr"
            log.write_text(VALID_WORLD_LOG, encoding="utf-8")
            # Uniform bright sky/clear-color frames (180/255) with zero geometry detail
            frames = []
            for i in range(3):
                p = tmp / f"bright_{i}.png"
                write_png(p, 64, 36, lambda x, y, k=i: (175 + k * 5, 185, 200))
                frames.append(p)
            res = score_run(
                log,
                base_meta(),
                frame_paths=frames,
                contact_probe={"grounded_fraction": 1.0, "contacts_tested": 8},
                first_3d_scene_s=60.0,
                scene_measured_ok=True,
            )
            self.assertIn("image_and_geometry", res["failed_gates"])
            self.assertIn("ground_coverage_and_contact", res["failed_gates"])
            self.assertEqual(res["score_total"], 0.0)
            self.assertFalse(res["qualified_for_release"])

    def test_rejects_static_mouth_even_under_camera_pan(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            tmp = Path(td)
            log = tmp / "static_mouth.stderr"
            log.write_text(VALID_WORLD_LOG, encoding="utf-8")
            # Pan the head horizontally across frames while keeping the mouth completely static!
            frames = [
                make_structured_frame(tmp, "p0.png", mouth_offset=0, pan_x=0),
                make_structured_frame(tmp, "p1.png", mouth_offset=0, pan_x=2),
                make_structured_frame(tmp, "p2.png", mouth_offset=0, pan_x=4),
            ]
            res = score_run(
                log,
                base_meta(),
                frame_paths=frames,
                mouth_roi=(26 / 64, 13 / 36, 12 / 64, 5 / 36),
                head_roi=(20 / 64, 4 / 36, 24 / 64, 9 / 36),
                spoken_checkpoint=True,
                contact_probe={"grounded_fraction": 1.0, "contacts_tested": 10},
                first_3d_scene_s=60.0,
                scene_measured_ok=True,
            )
            self.assertEqual(res["gates"]["facial_motion"]["status"], "fail")
            self.assertIn("facial_motion", res["failed_gates"])
            self.assertFalse(res["qualified_for_release"])

    def test_rejects_menu_only_samples(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            tmp = Path(td)
            log = tmp / "menu_only.stderr"
            log.write_text(
                """\
2026-11-26T12:00:05Z INFO victory_gpu::host: 30.0 fps, 33.3 ms/frame (0.1 preparing: copies 0.0 ms 0.0 MB, textures 0.0 ms 0.0 MB; 0.1 on the GPU; 0.0 copying back 0.0 MB), 13 draws/frame
2026-11-26T12:00:05Z INFO victory_gpu::framelog: frame times: 10 frames in 0.3 s: shortest 33 ms, median 33, longest 34; 0 long (over 73 ms, the usual frame of the last 64 being 33); each: 33 33 33 33 33 33 33 33 33 34
2026-11-26T12:00:05Z INFO victory_gpu::framelog: frames by kind: 0 of the world (6 or more host submissions) in 0.0 s: mean 0 ms, 0.00 a second while they ran; 10 menu or loading frames (fewer submissions) in 0.3 s: mean 33 ms
""",
                encoding="utf-8",
            )
            res = score_run(log, base_meta(), first_frame_s=5.0, enter_accepted_s=10.0)
            self.assertIn("workload_and_render", res["failed_gates"])
            self.assertEqual(res["timing"]["rendered_fps"], 0.0)
            self.assertEqual(res["score_total"], 0.0)
            self.assertFalse(res["qualified_for_release"])

    def test_rejects_reduced_workload(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            tmp = Path(td)
            log = tmp / "reduced.stderr"
            log.write_text(
                VALID_WORLD_LOG.replace("3500 draws/frame, dropped 10", "1100 draws/frame, dropped 600"),
                encoding="utf-8",
            )
            # Reduced render_scale & display_mode & BVH_HOLD & low draws & high shader drops
            res1 = score_run(
                log,
                base_meta(display_mode="640x360", render_scale=0.5, bvh_hold=True),
                first_3d_scene_s=60.0,
            )
            failures = res1["gates"]["workload_and_render"]["anti_gaming_failures"]
            self.assertTrue(any("display_mode" in f for f in failures))
            self.assertTrue(any("render_scale" in f for f in failures))
            self.assertTrue(any("VICTORY_BVH_HOLD" in f for f in failures))
            self.assertTrue(any("median world draws" in f for f in failures))
            self.assertTrue(any("shader coverage" in f for f in failures))
            # Verify fixed shader math: 1100 / (1100 + 600) = 64.71% (NOT negative!)
            self.assertAlmostEqual(res1["shaders"]["coverage_pct"], 64.71, places=1)

    def test_rejects_repeated_and_generated_frames(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            tmp = Path(td)
            log = tmp / "repeated.stderr"
            log.write_text(
                VALID_WORLD_LOG
                + "2026-11-26T12:00:06Z INFO victory_gpu::queue: frame=100 draws=0 drawn=0 dispatches=0 dispatched=0\n"
                * 5,
                encoding="utf-8",
            )
            # Identical consecutive frames
            dup_frames = [
                make_structured_frame(tmp, "d0.png", mouth_offset=1),
                make_structured_frame(tmp, "d1.png", mouth_offset=1),
                make_structured_frame(tmp, "d2.png", mouth_offset=1),
            ]
            res = score_run(
                log,
                base_meta(frame_generation=True, async_present=True, present_multiplier=2.0),
                frame_paths=dup_frames,
                first_3d_scene_s=60.0,
            )
            failures = res["gates"]["workload_and_render"]["anti_gaming_failures"]
            self.assertTrue(any("frame_generation=True" in f for f in failures))
            self.assertTrue(any("present_multiplier" in f for f in failures))
            self.assertTrue(any("VICTORY_ASYNC_PRESENT" in f for f in failures))
            self.assertTrue(any("zero draws" in f for f in failures))
            self.assertTrue(any("consecutive captured 3D frames identical" in f for f in failures))
            self.assertEqual(res["timing"]["rendered_fps"], 0.0)
            self.assertEqual(res["score_total"], 0.0)

    def test_tracks_unavailable_gates_and_ignores_pre_enter_autosave(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            tmp = Path(td)
            log = tmp / "no_captures.stderr"
            log.write_text(VALID_WORLD_LOG, encoding="utf-8")
            res = score_run(
                log,
                base_meta(),
                save_events_s=[18.8, 410.2],
                enter_accepted_s=125.6,
                first_3d_scene_s=380.0,
                scene_measured_ok=True,
            )
            self.assertEqual(res["milestones_s"]["autosave_after_world"], 410.2)
            self.assertIn("image_and_geometry", res["unavailable_gates"])
            self.assertIn("ground_coverage_and_contact", res["unavailable_gates"])
            self.assertIn("facial_motion", res["unavailable_gates"])
            self.assertFalse(res["qualified_for_release"])

    def test_compare_runs_enforces_comparability_and_detects_regression(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            tmp = Path(td)
            log_a = tmp / "a.stderr"
            log_b = tmp / "b.stderr"
            log_a.write_text(VALID_WORLD_LOG, encoding="utf-8")
            log_b.write_text(
                VALID_WORLD_LOG.replace("30 31 32 31 29 33 30 31 32 28", "60 62 61 63 60 61 62 60 61 64"),
                encoding="utf-8",
            )
            a = score_run(log_a, base_meta(checkpoint="C1"))
            b = score_run(log_b, base_meta(checkpoint="C1"))
            cmp_reg = compare_runs_v2(b, a)
            self.assertEqual(cmp_reg["verdict"], "REGRESSION")

            c_mismatch = score_run(log_b, base_meta(checkpoint="M1", cache_state="cold"))
            cmp_inv = compare_runs_v2(c_mismatch, a)
            self.assertEqual(cmp_inv["verdict"], "INVALID_COMPARISON")
            self.assertFalse(cmp_inv["comparable"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
