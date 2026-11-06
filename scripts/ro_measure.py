#!/usr/bin/env python3
"""Measure the frequency of ROs 0..N-1 of one chip and add it as a new run to a shared HDF5 file.

    ro_measure.py /dev/ttyUSB0 --chip chip01 --part xc7a50t --ros 600 --stages 8 -n 10 -o ro_puf.h5
    (swap the board, load its bitstream, check the serial port)
    ro_measure.py /dev/ttyUSB0 --chip chip01 --part xc7a35t --ros 600 --stages 8 -n 10 -o ro_puf.h5

The file is created on the first run and only appended to afterwards; it is open only while
a run measures, so swap boards between runs. Measuring a chip again adds another run to it.

For each RO: start it over the UART (ro_uart.py), wait --settle, then measure it n times.
One measurement = clear the scope's statistics, take ONE acquisition (single trigger), read P1
with its statistics (scope.py). So all values of a measurement come from one trace: num = the
periods P1 found in that trace (set by the scope's timebase). The order is n x RO 0, then
n x RO 1, ... The script sets the scope's trigger mode to Stopped for the run; at the end
(or on Ctrl-C/error) it restores the previous mode and stops all ROs. Every measurement is
written to the file right away, so an aborted run keeps what it measured.

The scope must be set up as in scope.py: P1 = Frequency of the channel with tio_trigger,
statistics on. P1 measures tio_trigger, so f_RO = 2 x 2^stages x P1 (stored as attribute
`divider`). The run doesn't start if statistics are off or P1 isn't Frequency. After
MAX_EMPTY readings in a row without data (num = 0), the run is aborted.

HDF5 file: one group per part, in it one per chip, in it one per run (named by its start time).
A chip is identified by part + name, so chip01 can exist for each part:
    /<part>/<chip>/<start>/    e.g. /xc7a50t/chip01/2026-11-06T12:04:21/
Run attributes: part, chip, settings, scope *IDN?, what P1 measures, rows_done, and the code
version: git_commit (HEAD of this repo), git_dirty (uncommitted changes in scripts/ or
ro_dev.srcs/ at the start of the run) and git_dirty_files (those files, one per line).
Each run holds 1-D datasets, one row per measurement (row = ro * n + rep):
    ro, rep               RO id, repetition 0..n-1
    site, site_x, site_y  the RO's slice ('SLICE_X11Y100') and its X, Y, from the RO_PLACEMENT
                          list in ro_place.tcl (--placement; must match the loaded bitstream)
    time                  Unix time of the reading [s]
    last, mean, min, max, sdev   P1 statistics over one trace [Hz at tio_trigger]
    num                   number of P1 measurements (periods) in the trace
    triggered             1 if the acquisition triggered, 0 if not within TRIGGER_TIMEOUT
                          (then there is no trace: num = 0, statistics nan)
    status, status_desc   P1 status (bit field, -1 if unreadable) and its text ('Valid.')
Rows not measured (aborted run) have ro = -1; attribute `rows_done` counts the written rows.

A crash while the file is open (power cut, killed process) can damage the whole file, i.e. all
chips in it: keep a backup copy of the file.

Needs h5py and numpy, plus what ro_uart.py and scope.py need.
"""

import argparse
import re
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path

import h5py
import numpy as np

from ro_uart import ERROR, STOP, send_command
from scope import STATS, acquire_single, clear_stats, open_scope, read_p1, trigger_mode

PARTS = ("xc7a35t", "xc7a50t", "xc7a100t")
REPO = Path(__file__).resolve().parent.parent
PLACEMENT_FILE = REPO / "ro_dev.srcs/constrs_1/new/ro_place.tcl"
# What the measurement depends on, checked for uncommitted changes. Not ro_dev.xpr: Vivado
# rewrites it on every open, so it would mark every run dirty.
VERSIONED = ("scripts", "ro_dev.srcs")


def git_version():
    """(commit hash of HEAD, files in VERSIONED with uncommitted changes incl. untracked ones)."""
    git = lambda *args: subprocess.run(["git", "-C", str(REPO), *args],
                                       capture_output=True, text=True, check=True).stdout
    commit = git("rev-parse", "HEAD").strip()
    dirty = [line[3:] for line in git("status", "--porcelain", "--", *VERSIONED).splitlines()]
    return commit, dirty


def read_placement(path):
    """RO id -> slice ('SLICE_X11Y100') from the RO_PLACEMENT list in ro_place.tcl.
    As in ro_place.tcl, the first entry of an instance listed twice applies."""
    text = Path(path).read_text()
    block = re.search(r"set\s+RO_PLACEMENT\s*\{(.*?)\}", text, re.S)
    if not block:
        raise ValueError(f"no RO_PLACEMENT list in {path}")
    placement = {}
    for ro_id, site in re.findall(r"gen_ro\[(\d+)\]\.u_ro\s+(SLICE_X\d+Y\d+)", block.group(1)):
        placement.setdefault(int(ro_id), site)
    return placement


MAX_EMPTY = 3      # this many readings in a row without data -> abort the run
TRIGGER_TIMEOUT = 2.0   # s: a reading without a trigger by then has no data


def scope_problems(scope):
    """Why the scope setup can't give measurements (list of strings, empty if OK)."""
    q = lambda e: scope.query(f"VBS? 'return={e}'").strip()
    problems = []
    if q("app.Measure.StatsOn") not in ("-1", "1", "True"):
        problems.append("measurement statistics are off (Measure -> Statistics On)")
    engine = q("app.Measure.P1.ParamEngine")
    if engine != "Frequency":
        problems.append(f"P1 measures {engine}, not Frequency")
    return problems


def measure(scope):
    """Clear the statistics, take one acquisition, read P1: statistics of one trace."""
    clear_stats(scope)
    triggered = acquire_single(scope, TRIGGER_TIMEOUT)
    r = read_p1(scope)
    r["triggered"] = triggered
    return r


def start_ro(port, ro_id, stages):
    cmd, reply = send_command(port, stages, ro_id)
    if reply != cmd:
        what = "rejected (RO id out of range?)" if reply[0] == ERROR else "unexpected reply"
        raise RuntimeError(f"RO {ro_id}: board {what}: {reply.hex(' ')} to {cmd.hex(' ')}")


def stop_ros(port):
    cmd, reply = send_command(port, STOP, 0)
    if reply != cmd:
        raise RuntimeError(f"board didn't confirm the stop: {reply.hex(' ')} to {cmd.hex(' ')}")


def create_datasets(g, rows):
    d = {}
    d["ro"] = g.create_dataset("ro", (rows,), "i4", fillvalue=-1)
    d["rep"] = g.create_dataset("rep", (rows,), "i4", fillvalue=-1)
    d["site"] = g.create_dataset("site", (rows,), h5py.string_dtype())
    d["site_x"] = g.create_dataset("site_x", (rows,), "i4", fillvalue=-1)
    d["site_y"] = g.create_dataset("site_y", (rows,), "i4", fillvalue=-1)
    for name in ("time",) + STATS[:5]:
        d[name] = g.create_dataset(name, (rows,), "f8", fillvalue=np.nan)
    d["num"] = g.create_dataset("num", (rows,), "i8", fillvalue=0)
    d["status"] = g.create_dataset("status", (rows,), "i8", fillvalue=-1)
    d["status_desc"] = g.create_dataset("status_desc", (rows,), h5py.string_dtype())
    d["triggered"] = g.create_dataset("triggered", (rows,), "i1", fillvalue=-1)
    return d


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("port", help="serial port of the board, e.g. /dev/ttyUSB0")
    p.add_argument("--chip", required=True, help="name of the chip/board, e.g. chip01 (unique per part)")
    p.add_argument("--part", required=True, choices=PARTS, help="FPGA of the chip")
    p.add_argument("-o", "--output", required=True, help="HDF5 file, created or appended to")
    p.add_argument("--ros", type=int, required=True, help="measure ROs 0..ROS-1")
    p.add_argument("--stages", type=int, required=True, help="prescaler stages 0..8")
    p.add_argument("-n", "--repeats", type=int, required=True, help="measurements per RO")
    p.add_argument("--settle", type=float, default=0.1,
                   help="seconds to wait after starting a RO, before its first measurement (default 0.1)")
    p.add_argument("--resource", help="VISA resource of the scope (default: first LeCroy on USB)")
    p.add_argument("--placement", default=PLACEMENT_FILE,
                   help="ro_place.tcl with the RO_PLACEMENT list (default: the project's)")
    a = p.parse_args()
    if a.ros < 1 or a.repeats < 1:
        p.error("--ros and -n must be >= 1")
    if not 0 <= a.stages <= 8:
        p.error("--stages must be 0..8")
    if not a.chip or "/" in a.chip or a.chip == ".":
        p.error("--chip must be a name without '/'")

    placement = read_placement(a.placement)
    missing = [i for i in range(a.ros) if i not in placement]
    if missing:
        p.error(f"no RO_PLACEMENT entry in {a.placement} for RO(s) {missing}")

    try:
        commit, dirty = git_version()
    except (OSError, subprocess.CalledProcessError) as e:
        print(f"WARNING: no git version ({e}), stored as 'unknown'")
        commit, dirty = "unknown", []
    print(f"code: {commit}" + (f", uncommitted changes in: {', '.join(dirty)}" if dirty else ""))

    out = a.output
    divider = 2 * 2 ** a.stages   # RO toggle FF (/2) and prescaler (/2^stages)

    with h5py.File(out, "a") as f:
        scope = open_scope(a.resource)
        idn = scope.query("*IDN?").strip()
        p1_param = scope.query("VBS? 'return=app.Measure.P1.ParamEngine'").strip()
        p1_source = scope.query("VBS? 'return=app.Measure.P1.Source1'").strip()
        print(f"scope: {idn}, P1 = {p1_param} of {p1_source}")
        problems = scope_problems(scope)
        if problems:
            scope.close()
            p.error("scope not ready: " + "; ".join(problems))
        hor = scope.query("VBS? 'return=app.Acquisition.Horizontal.HorScale & \";\" &"
                          " app.Acquisition.Horizontal.SampleRate & \";\" &"
                          " app.Acquisition.Horizontal.NumPoints'").strip().split(";")
        old_mode = trigger_mode(scope)
        trigger_mode(scope, "Stopped")

        start = datetime.now().isoformat(timespec="seconds")
        run = f"/{a.part}/{a.chip}/{start}"
        g = f.create_group(run)   # creates /<part>/<chip> too if new
        print(f"chip {a.chip} ({a.part}): ROs 0..{a.ros - 1}, {a.repeats} x each, stages {a.stages}"
              f" (f_RO = {divider} x P1) -> {out}:{run}")
        g.attrs.update({
            "part": a.part,
            "chip": a.chip,
            "start": start,
            "git_commit": commit,
            "git_dirty": bool(dirty),
            "git_dirty_files": "\n".join(dirty),
            "command": " ".join(sys.argv),
            "port": a.port,
            "ros": a.ros,
            "stages": a.stages,
            "repeats": a.repeats,
            "trigger_timeout": TRIGGER_TIMEOUT,
            "hor_scale": float(hor[0]),     # s/div
            "sample_rate": float(hor[1]),   # S/s
            "num_points": int(float(hor[2])),
            "settle": a.settle,
            "divider": divider,
            "scope_idn": idn,
            "p1_param": p1_param,
            "p1_source": p1_source,
            "placement_file": str(Path(a.placement).resolve()),
            "rows_done": 0,
        })
        d = create_datasets(g, a.ros * a.repeats)

        row = 0
        empty = 0   # readings in a row without data
        try:
            for ro_id in range(a.ros):
                start_ro(a.port, ro_id, a.stages)
                time.sleep(a.settle)
                for rep in range(a.repeats):
                    r = measure(scope)
                    t = time.time()

                    d["ro"][row], d["rep"][row], d["time"][row] = ro_id, rep, t
                    site = placement[ro_id]
                    x, y = re.fullmatch(r"SLICE_X(\d+)Y(\d+)", site).groups()
                    d["site"][row], d["site_x"][row], d["site_y"][row] = site, int(x), int(y)
                    for name in STATS:
                        d[name][row] = r[name]
                    d["status"][row] = -1 if r["status"] is None else r["status"]
                    d["status_desc"][row] = r["status_desc"]
                    d["triggered"][row] = r["triggered"]
                    row += 1
                    g.attrs["rows_done"] = row
                    f.flush()

                    problem = ("no trigger" if not r["triggered"] else
                               "no data" if r["num"] == 0 else
                               r["status_desc"] if r["status_desc"] != "Valid." else "")
                    print(f"RO {ro_id:4d} {site:14s} #{rep:<3d} P1 mean {r['mean']:.9g} Hz  sdev {r['sdev']:.4g}"
                          f"  num {r['num']:6d}  f_RO {r['mean'] * divider / 1e6:.4f} MHz"
                          + (f"  !! {problem}" if problem else ""))

                    empty = empty + 1 if r["num"] == 0 else 0
                    if empty >= MAX_EMPTY:
                        raise RuntimeError(f"{MAX_EMPTY} readings in a row without data: no signal on"
                                           " the P1 channel, RO not running, or trigger settings?")
        except KeyboardInterrupt:
            print("interrupted")
        finally:
            # Each step on its own, so a failing one neither skips the others nor hides the
            # error that ended the run
            print(f"{row} of {a.ros * a.repeats} measurements in {out}:{run}")
            try:
                g.attrs["end"] = datetime.now().isoformat(timespec="seconds")
            except Exception as e:
                print(f"WARNING: could not write the end time: {e!r}")
            try:
                stop_ros(a.port)
                print("all ROs stopped")
            except Exception as e:
                print(f"WARNING: could not stop the ROs ({e!r}), stop them with: ro_uart.py {a.port} --stop")
            try:
                trigger_mode(scope, old_mode)
            except Exception as e:
                print(f"WARNING: could not restore the scope trigger mode {old_mode}: {e!r}")
            try:
                scope.close()
            except Exception as e:
                print(f"WARNING: could not close the scope connection: {e!r}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
