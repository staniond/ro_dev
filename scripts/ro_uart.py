#!/usr/bin/env python3
"""Control the ring oscillators over the board's UART (see README, "UART protocol").

    ro_uart.py /dev/ttyUSB0 --ro 3 --stages 8    # run RO 3, output /256 on tio_trigger
    ro_uart.py /dev/ttyUSB0 --stop               # stop all ROs (--ro/--stages ignored)

Command: 3 bytes [stages] [id_hi] [id_lo], stages 0..8 (current design) or 0xFF = stop.
Reply:   the same 3 bytes when applied, 0xEE id_hi id_lo when rejected.

Needs pyserial (pip install pyserial).
"""

import argparse
import sys

import serial

STOP = 0xFF
ERROR = 0xEE
MAX_STAGES = 0xEE - 1 # EE and higher reserved for status codes


def send_command(port, stages, ro_id, baud=115200, timeout=1.0):
    """Send one command, return the 3-byte reply (raises on timeout)."""
    cmd = bytes([stages, (ro_id >> 8) & 0xFF, ro_id & 0xFF])
    with serial.Serial(port, baud, timeout=timeout) as ser:
        ser.reset_input_buffer()
        ser.write(cmd)
        reply = ser.read(3)
    if len(reply) != 3:
        raise TimeoutError(f"no complete reply (got {reply.hex(' ') or 'nothing'}), sent {cmd.hex(' ')}")
    return cmd, reply


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("port", help="serial port, e.g. /dev/ttyUSB0")
    p.add_argument("--stop", action="store_true", help="stop all ROs (--ro and --stages are then ignored)")
    p.add_argument("--ro", type=int, help="RO id to enable (0..65535), required unless --stop")
    p.add_argument("--stages", type=int,
                   help=f"prescaler stages 0..{MAX_STAGES}, required unless --stop "
                        "(the board rejects more stages than it has)")
    p.add_argument("--baud", type=int, default=115200)
    a = p.parse_args()

    if a.stop:
        stages, ro_id = STOP, 0
    else:
        missing = [opt for opt, val in (("--ro", a.ro), ("--stages", a.stages)) if val is None]
        if missing:
            p.error(f"{' and '.join(missing)} required (or use --stop)")
        if not 0 <= a.ro <= 0xFFFF:
            p.error("--ro must be 0..65535")
        if not 0 <= a.stages <= MAX_STAGES:
            p.error(f"--stages must be 0..{MAX_STAGES}")
        stages, ro_id = a.stages, a.ro

    cmd, reply = send_command(a.port, stages, ro_id, a.baud)

    if reply == cmd:
        if a.stop:
            print("OK: all ROs stopped")
        else:
            div = 2 * 2 ** stages   # RO toggle FF (/2) and prescaler (/2^stages)
            print(f"OK: RO {ro_id} running, {stages} prescaler stages")
            print(f"    f_RO = {div} x f(tio_trigger)")
        return 0
    if reply[0] == ERROR:
        print(f"REJECTED by the board: {reply.hex(' ')} (RO id out of range or invalid stages)")
        return 1
    print(f"UNEXPECTED reply {reply.hex(' ')} to {cmd.hex(' ')}")
    return 2


if __name__ == "__main__":
    sys.exit(main())
