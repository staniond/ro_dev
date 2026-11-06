#!/usr/bin/env python3
"""Read measurement P1 (value and statistics) from the LeCroy scope (HDO9404) over USB with pyvisa-py.

    scope.py                 # *IDN? and the current value and statistics of P1
    scope.py -n 10 -i 0.5    # P1 ten times, every 0.5 s

Scope setup (done by hand on the scope, the script doesn't change any settings):
    - P1 set to the measurement to read (Frequency of the channel with tio_trigger)
    - statistics on (Measure -> Statistics On; app.Measure.StatsOn), so that P1 provides
      mean, min, max, sdev and num besides the last value

Needs pyvisa + pyvisa-py + pyusb, and write access to the scope's USB device (udev rule):
    SUBSYSTEM=="usb", ATTR{idVendor}=="05ff", MODE="0660", GROUP="plugdev"
"""

import argparse
import sys
import time

import pyvisa
import usb.core
from pyvisa_py.protocols import usbtmc

LECROY_VID = 0x05FF

# The scope advertises USB488 REN_CONTROL but stalls the request (USBError: Pipe error), which
# makes pyvisa-py's open fail. Remote enable isn't needed, so ignore the stall.
_enable_remote_control = usbtmc.USBTMC._enable_remote_control


def _enable_remote_control_tolerant(self):
    try:
        _enable_remote_control(self)
    except usb.core.USBError:
        pass


usbtmc.USBTMC._enable_remote_control = _enable_remote_control_tolerant


def open_scope(resource=None):
    rm = pyvisa.ResourceManager("@py")
    if resource is None:
        # LeCroy vendor id 0x05FF; pyvisa-py lists it in decimal (USB0::1535::...)
        found = [r for r in rm.list_resources("USB?*")
                 if int(r.split("::")[1], 0) == LECROY_VID]
        if not found:
            raise RuntimeError("no LeCroy scope found on USB")
        resource = found[0]
    scope = rm.open_resource(resource, timeout=5000)
    scope.write("COMM_HEADER OFF")   # replies without the command header
    return scope


def clear_stats(scope):
    """Restart the measurement statistics (num -> 0); returns when the scope has done it."""
    scope.write("VBS 'app.ClearSweeps'")
    scope.query("*OPC?")


def trigger_mode(scope, mode=None):
    """Return the trigger mode ('Auto', 'Normal', 'Single', 'Stopped'), or set it if mode is given."""
    if mode is not None:
        scope.write(f"VBS 'app.Acquisition.TriggerMode = \"{mode}\"'")
        scope.query("*OPC?")
    return scope.query("VBS? 'return=app.Acquisition.TriggerMode'").strip()


def acquire_single(scope, timeout=2.0):
    """Take one acquisition (scope in Stopped mode) and wait until its measurements are
    computed. True if it triggered; False if it didn't trigger within timeout seconds, then
    there is no new acquisition. (Not forced: Acquire(t, True) returns True even when forced.)"""
    triggered = scope.query(f"VBS? 'return=app.Acquisition.Acquire({timeout}, False)'").strip()
    scope.query("VBS? 'return=app.WaitUntilIdle(5)'")
    return triggered not in ("0", "False")


STATS = ("last", "mean", "min", "max", "sdev", "num")


def read_p1(scope):
    """P1 statistics in one query (one consistent snapshot, full double precision):
    dict with last, mean, min, max, sdev (float, nan if not numeric), num (int),
    status (int bit field) and status_desc (e.g. 'Valid.', 'Too little data.').
    With no valid measurement, the statistics are nan and num is 0.
    """
    p = "app.Measure.P1."
    exprs = [f"{p}{st}.Result.Value" for st in STATS]
    exprs += [f"{p}Out.Result.Status", f"{p}Out.Result.StatusDescription"]
    # Reading a value with no data raises a VBScript error ('No Data Available') that would
    # abort the whole query, so read each field separately, keeping "nan" if it fails.
    script = 'On Error Resume Next : r = ""'
    for e in exprs:
        script += f' : v = "nan" : v = {e} : r = r & v & ";"'
    reply = scope.query(f"VBS? '{script} : return = r'")
    fields = reply.strip().removeprefix("VBS").strip().split(";")[:-1]
    if len(fields) != len(exprs):
        raise ValueError(f"unexpected reply to P1 query: {reply!r}")

    r = {}
    for name, val in zip(STATS, fields):
        try:
            r[name] = float(val)
        except ValueError:
            r[name] = float("nan")
    r["num"] = int(r["num"]) if r["num"] == r["num"] else 0
    if r["num"] == 0:   # the scope reports 0 for mean etc. when it has no data
        for name in STATS[:5]:
            r[name] = float("nan")
    # Status is a 64-bit int that VBScript returns as Currency, i.e. scaled by 1e-4
    try:
        r["status"] = round(float(fields[6]) * 10000)
    except ValueError:
        r["status"] = None
    r["status_desc"] = fields[7]
    return r


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--resource", help="VISA resource (default: first LeCroy on USB)")
    p.add_argument("-n", "--count", type=int, default=1, help="number of readings")
    p.add_argument("-i", "--interval", type=float, default=1.0, help="seconds between readings")
    a = p.parse_args()

    scope = open_scope(a.resource)
    print(f"{scope.resource_name}: {scope.query('*IDN?').strip()}")
    for i in range(a.count):
        if i:
            time.sleep(a.interval)
        r = read_p1(scope)
        print(f"P1: last {r['last']:.9g}  mean {r['mean']:.9g}  min {r['min']:.9g}  max {r['max']:.9g}"
              f"  sdev {r['sdev']:.6g}  num {r['num']}"
              f"  status {'?' if r['status'] is None else hex(r['status'])} {r['status_desc']}")
    scope.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
