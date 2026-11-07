#!/usr/bin/env python3
"""Графики результатов бенчмарка: benchmarks/results/*.csv -> benchmarks/charts/*.png.
Использование: python3 benchmarks/scripts/plot.py benchmarks/results/<label>.csv
"""
import csv
import sys
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402


def load(csv_path: Path):
    rows = list(csv.DictReader(csv_path.open()))
    ping = [(i, float(r["value"])) for i, r in enumerate(rows) if r["metric"] == "ping_rtt_direct"]
    ttfb = [float(r["value"]) for r in rows if r["metric"] == "ttfb_tunnel" and r["value"] != "fail"]
    return ping, ttfb


def main(csv_path: str) -> None:
    src = Path(csv_path)
    ping, ttfb = load(src)
    out = Path(__file__).resolve().parents[1] / "charts" / f"{src.stem}.png"
    out.parent.mkdir(parents=True, exist_ok=True)

    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(11, 4))
    if ping:
        ax1.plot([p[0] for p in ping], [p[1] for p in ping], marker="o")
        ax1.set_title("RTT до сервера (прямой)")
        ax1.set_xlabel("проба")
        ax1.set_ylabel("мс")
    if ttfb:
        ax2.bar(range(len(ttfb)), ttfb)
        ax2.set_title("TTFB через туннель")
        ax2.set_xlabel("прогон")
        ax2.set_ylabel("с")
    fig.tight_layout()
    fig.savefig(out, dpi=120)
    print(f"OK: {out}")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(sys.argv[1])
