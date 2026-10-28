# ro-dev

Ring oscillators (ROs) for an RO-PUF on the CW305 board (Artix-7 `xc7a100tftg256-1`, Vivado 2025.1).
Each RO sits in one slice, at a site you choose, and all ROs have **identical placement and routing**
that never leaves the RO's own CLB and its switch matrix.
The RO architecture is from Hesselbarth et al., *Large Scale RO PUF Analysis over Slice Type,
Evaluation Time and Temperature on 28nm Xilinx FPGAs* (HOST 2018), Fig. 1 (`ro_architecture.png`).

The project still contains the UART echo from the `uart_dev` template (see [UART](#uart) at the end).

## Quick start: reproduce the bitstream

Needs Vivado 2025.1 with Artix-7 support.

1. Clone the repo and open `ro_dev.xpr` in Vivado.
2. Click **Generate Bitstream**. Vivado offers to run synthesis and implementation first; say yes.

That's all, no Tcl needed. The RO placement and fixed routes are constraint files in the project
(applied automatically), and right before writing the bitstream a hook checks every RO. The
bitstream (`ro_dev.runs/impl_1/top.bit`) is only written if all ROs are OK; the check's table is in
`ro_dev.runs/impl_1/runme.log`:

```
gen_ro[0].u_ro   SLICE_X39Y100   CLBLM_L_X24Y100   OK
...
ro_check: 4 RO(s), 0 with problems
```

After opening, `git status` may show `ro_dev.xpr` as modified: Vivado rewrites a few path entries
(`ImportPath`). That's harmless.

The same applies after changing RTL that doesn't touch the ROs: just Generate Bitstream. To add ROs,
see [Adding more ROs](#adding-more-ros). Everything else below, including the Tcl commands, explains
how the flow works and how to inspect it; you don't need it to build.

## How it works

### The RO cell: `ro_dev.srcs/sources_1/new/ro_cell.vhd`

```
            +---------------------------------------------+
            |                                             |
  en --+--[NAND]--ring0--[INV]--ring1--[INV]--ring2--+----+--> FF.C
       |   B6LUT          A6LUT         C6LUT
       +--[INV]--en_n--> FF.CLR      (held in reset while en = '0')
           B5LUT
                      q --[INV]--d--> FF.D     ro_out = q = f_RO / 2
                          D6LUT        DFF
```

- A 3-stage ring: NAND (with enable) and two inverters. Its output clocks a toggle flip-flop, so
  `ro_out` runs at half the RO frequency. While `en = '0'` the FF is held cleared, so every RO
  starts from the same state.
- Every gate is an **instantiated primitive** (`LUT1`, `LUT2`, `FDCE`) with `DONT_TOUCH`, so synthesis
  can't merge the inverters or optimize the loop away. The cell and net names (`lut_nand`, `ring2`, ...)
  stay fixed, and the Tcl scripts rely on them.
- 5 gates in 4 LUTs (as in the paper): the B LUT is split into two 5-input LUTs. B6LUT holds the NAND
  and B5LUT holds the `en` inverter.
- The `sim` architecture (`sim_1/new/ro_cell_sim.vhd`) is the same circuit with `after` delays. The
  real `rtl` one has zero-delay LUTs in a loop, so a behavioral simulation would never advance time.
  `ro_cell_tb.vhd` checks that the RO is quiet when disabled, toggles when enabled, and clears when
  `en` drops. In `top.vhd` the cell is instantiated explicitly as `entity work.ro_cell(rtl)`.

### The Vivado flow and where the scripts fit in

```
 synth_1                 impl_1
 synth_design ──> link_design ──> opt_design ──> place_design ──> route_design ──> write_bitstream
                       ▲
                       │  constrs_1, in this order:
                       ├── cw305_main.xdc : pins, clock
                       ├── ro_place.tcl   : LOC + BEL + LOCK_PINS -> RO cells placed & fixed
                       └── ro_routes.tcl  : FIXED_ROUTE           -> RO nets routed & fixed
                                                                      write_bitstream pre-hook:
                                                                      ro_check_hook.tcl -> no OK, no bitstream
```

| Step | What it does |
|---|---|
| `synth_design` | Turns the VHDL into a netlist: cells and their connections, with no location on the chip yet |
| `link_design` (run step `init_design`) | Loads the netlist for the device and **applies the constraint files** |
| `opt_design` | Logic cleanup: removes unused logic, propagates constants, merges/remaps LUTs. `DONT_TOUCH` keeps it away from the ROs |
| `place_design` | Places **everything else** (UART etc.); the fixed RO cells are obstacles it never moves |
| `route_design` | Routes everything else; the fixed RO wires are never changed. It only adds the `ro_out` branch of `q` |
| `write_bitstream` | First the pre-hook `scripts/ro_check_hook.tcl` (below), then final DRC (e.g. LUTLP-1), then writes `top.bit` |

**When do `ro_place.tcl` and `ro_routes.tcl` run?** Automatically: they are in the project's
constraint set `constrs_1`, marked *used in implementation* but not *used in synthesis* (the cells
they refer to only exist after synthesis). Vivado `source`s them, in the order listed in
`constrs_1`, every time it links a synthesized netlist:

| Action | Constraint files run? |
|---|---|
| Synthesis (`synth_1`) | no |
| Implementation (`impl_1`): its first step, `link_design` (the log says `Sourcing Tcl File [.../ro_place.tcl]`) | **yes** |
| **Open Synthesized Design** (`open_run synth_1`) | **yes** |
| **Open Implemented Design** (`open_run impl_1`) | no: it loads the finished routed checkpoint, where placement and routes are already baked in |

`scripts/ro_tools.tcl` is *not* a constraint file. You `source` it yourself in the Tcl Console,
and the bitstream hook sources it too.

### `scripts/ro_check_hook.tcl` (impl_1 hook, runs automatically)

Set as `impl_1` property `STEPS.WRITE_BITSTREAM.TCL.PRE` (GUI: *Settings -> Implementation ->
Write Bitstream -> tcl.pre*). Right before every `write_bitstream` it runs `ro_check` on the routed
design and **fails the step if any RO isn't OK**. The `ro_check` table is in the run log
(`ro_dev.runs/impl_1/runme.log`).

This is the one gate that covers everything. A Tcl error in `ro_place.tcl` or `ro_routes.tcl` only
becomes a critical warning, and Vivado then skips the rest of that file. For example, if
`ro_routes.tcl` fails, the router routes the ROs its own way, and without the hook the bitstream
would still be written. Unlike in a constraint file, an `error` in a hook does stop the run step.

This is also why **Open Synthesized Design** shows only the ROs placed. That's not a placement step:
opening it runs `link_design`, which applies the constraints, and the ROs are the only cells with a
location. The rest gets placed by `place_design` during implementation (`impl_1`).

### `ro_dev.srcs/constrs_1/new/ro_place.tcl` (constraint, you edit it)

- `RO_PLACEMENT`: the list you maintain, **instance name -> slice**. Instance names come from the
  generate in `top.vhd` (`gen_ro: for i ... generate` / `u_ro:` -> `gen_ro[i].u_ro`).
- `RO_BELS`: which cell goes to which BEL (position inside the slice), and `LOCK_PINS`, which fixes
  the physical LUT input pin for each logical input. Vivado could otherwise swap LUT pins per
  instance, and then the routes would differ.
- For every RO it sets `BEL` + `LOC` on the 6 cells. It also sets `ALLOW_COMBINATORIAL_LOOPS` on the
  ring nets; without it, DRC **LUTLP-1** (an error) stops `write_bitstream`.
- It **checks every entry first**: the site must exist and be the RO type (below), no site may be used
  twice, the instance must exist, and every `ro_cell` must have an entry. A bad entry is reported as
  `CRITICAL WARNING: [RO 1-1] ro_place.tcl: gen_ro[2].u_ro NOT placed: SLICE_X38Y104 is a SLICEM in a
  CLBLM_L tile, ...` (or `[RO 1-2]` for a missing entry). That RO is then left completely alone: no
  placement, no fixed route, no `ALLOW_COMBINATORIAL_LOOPS`. Implementation still runs, but
  `write_bitstream` stops with DRC **LUTLP-1**, so a misplaced RO can never end up in a bitstream.
  Why not just `error`: an error inside a constraint file only becomes a critical warning, Vivado
  skips the *rest of the file*, and the run continues with those ROs placed and routed at random.

Why this check exists: without it, a RO on the wrong slice would get placed and only fail later,
when `ro_routes.tcl` or `route_design` tries to use the fixed route, with messages like these:

| Placed on | What happens without the check |
|---|---|
| SLICEL of a `CLBLM_R` tile (switch matrix on the other side) | `ERROR: [Constraints 18-11693] Did not find node resource, IMUX_L5, downhill from node, INT_R_.../BYP_BOUNCE5`: the route asks for a wire of the left-hand switch matrix, which doesn't exist in an `INT_R` |
| SLICEM of the same `CLBLM_L` tile | Placement is legal (same LUT/FF BELs), but the fixed route ends at the pins of the *other* slice (`CLBLM_L_*` instead of `CLBLM_M_*`) and `route_design` fails: `Net gen_ro[2].u_ro/ring0 is not completely routed` |

**RO type.** All ROs must be the same "type": the same tile type and the same slice within the
tile. `ro_routes.tcl` names wires relative to the tile, so one route only fits tiles that are wired
identically. The type used here is the **SLICEL of a `CLBLM_L` tile**: the most common CLB tile on
this device (2400 of them), and it has exactly one SLICEL.

**Why the NAND is in the B LUT and not the A LUT.** Inside one switch matrix, every local path to
the slice CLK pin goes through the wire `FAN_ALT5`. From the A LUT's second output (AMUX), the SR
(clear) pin is reachable *only* through `FAN_ALT5` too, so the clock and the clear can't both stay
local. From BMUX, SR is reached through `FAN_ALT1` instead.

### `ro_dev.srcs/constrs_1/new/ro_routes.tcl` (constraint, generated)

This file is generated by `ro_make_routes`, so don't edit it by hand. It holds one route string per
RO net and applies it as `FIXED_ROUTE` to every `ro_cell` in the design. A route string lists the
wires a net uses, e.g.

```
ring2  { CLBLM_L_C CLBLM_LOGIC_OUTS10 FAN_ALT5 FAN_BOUNCE5 { CLK_L0 CLBLM_L_CLK } IMUX_L19 CLBLM_L_B2 }
```

C LUT output -> switch matrix -> local clock input of the slice (`CLK_L0`), with a branch (in
braces) back to the NAND input B2. The names have no tile coordinates, which is why the same string
fits every CLBLM_L SLICEL. `q` is fixed only up to the toggle LUT (D6). Its branch to `ro_out`
(your logic outside the RO) is left to the router.

It must be read **after** `ro_place.tcl`, because a route can only be fixed between placed cells.
ROs that `ro_place.tcl` rejected (no `LOC`) are skipped.

### `scripts/ro_tools.tcl` (helper procs for the Tcl console)

| Command                 | What it does                                                                                                                                                                                                                                        | Needs                             |
| ----------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------- |
| `ro_sites ?region?`     | Lists legal RO sites (CLBLM_L SLICELs), optionally only in one clock region, e.g. `ro_sites X0Y2`                                                                                                                                                   | any open design                   |
| `ro_make_routes ?inst?` | Writes `ro_routes.tcl`.<br>For one placed RO (default: the first), searches the routing graph using only the RO's CLB tile and its switch-matrix (INT) tile, net by net (ring nets first), without sharing wires and without passing through a LUT. | synthesized or implemented design |
| `ro_check`              | For every RO and net: routed? fixed? Does the path from driver to each load inside the slice stay in the CLB + INT tile? Same wires as the first RO? Prints `OK` per RO.                                                                            | implemented design                |

Why compute the routes instead of letting the router route one RO and copying it: the router
happily routes `en_n` through the *neighbouring* switch matrices. A computed route is local by
construction.

### Expected DRC warnings

`report_drc` shows 3 warnings per RO. They are **warnings, not errors**: they don't block the
bitstream, and here they describe exactly what was built on purpose.

| Rule | Meaning | Why it's fine here |
|---|---|---|
| LUTLP-2 Combinatorial Loop Allowed | A LUT loop exists and is allowed | The allowed version of the LUTLP-1 error; it's the ring |
| PDRC-153 Gated clock | A FF is clocked by a LUT, not a clock buffer | The toggle FF is clocked by the ring |
| PLHOLDVIO-2 Possible hold violations | A clock comes from general routing, not the clock tree | Timing analysis doesn't apply to an RO |

In a normal synchronous design each of these would be a bug, so check that they only point at
`gen_ro[*].u_ro` cells and nets.

## Walkthrough: the flow step by step

**Not needed to build** (that's just *Generate Bitstream*, see [Quick start](#quick-start-reproduce-the-bitstream)).
These steps run the same flow by hand so you can see what happens at each stage, inspect the
result, and regenerate `ro_routes.tcl` if you ever change `RO_BELS` or `LOCK_PINS`.

Open `ro_dev.xpr` and type the commands into the **Tcl Console** at the bottom of the Vivado window.
All source, simulation and constraint files are already in the project.

**1. Go to the project directory** (relative paths below start there):

```tcl
cd [get_property DIRECTORY [current_project]]
```

**2. Simulate the RO cell** (optional):

```tcl
set_property top ro_cell_tb [get_filesets sim_1]
launch_simulation
run all
```

The console should print `edges in 1 us: 167` and `ro_cell_tb finished`, with no errors. The 167
comes from the guessed 500 ps gate delay, so it is not a frequency prediction.

**3. Synthesize and look at the RO placement:**

```tcl
reset_run synth_1
launch_runs synth_1 -jobs 8
```

When the run finishes:

```tcl
open_run synth_1
get_property LOC [get_cells {gen_ro[0].u_ro/ff}]          ;# -> SLICE_X39Y100
get_property BEL [get_cells {gen_ro[0].u_ro/*}]           ;# the 6 BELs
report_utilization -hierarchical                           ;# each gen_ro: 5 LUTs, 1 FF
select_objects [get_cells {gen_ro[0].u_ro/*}]              ;# see them in the Device window
```

**4. (Re)generate the routes.** `ro_routes.tcl` is in the repo, so this step is only needed after
changing `RO_BELS` or `LOCK_PINS`. Running it again does no harm; the result is deterministic.

```tcl
source scripts/ro_tools.tcl
ro_make_routes             ;# prints the 5 route strings, rewrites ro_routes.tcl
get_files -of [get_filesets constrs_1]   ;# ro_place.tcl must be listed before ro_routes.tcl
close_design
```

If you changed `RO_BELS`, the old `ro_routes.tcl` no longer fits the new placement and won't apply cleanly.
Disable it for this step and enable it again afterwards:

```tcl
set_property is_enabled false [get_files ro_routes.tcl]
open_run synth_1
source scripts/ro_tools.tcl
ro_make_routes
close_design
set_property is_enabled true [get_files ro_routes.tcl]
```

If `ro_routes.tcl` ever ends up before `ro_place.tcl`:

```tcl
reorder_files -fileset constrs_1 -after [get_files ro_place.tcl] [get_files ro_routes.tcl]
```

**5. Implement, check, write the bitstream:**

```tcl
launch_runs impl_1 -to_step write_bitstream -jobs 8
```

When the run finishes:

`ro_check` has already run in the bitstream hook (its table is in `ro_dev.runs/impl_1/runme.log`);
the bitstream exists only if every RO was OK. To look around yourself:

```tcl
open_run impl_1
source scripts/ro_tools.tcl
ro_check                                          ;# same table as in the run log
report_route_status                               ;# 0 nets with routing errors
report_drc                                        ;# only LUTLP-2, PDRC-153, PLHOLDVIO-2
get_property ROUTE [get_nets {gen_ro[1].u_ro/ring2}]
select_objects [get_nets {gen_ro[0].u_ro/*}]      ;# zoom in: wires stay in one CLB + switch matrix
```

The bitstream is `ro_dev.runs/impl_1/top.bit`. On the board, `dip_switch(0)` enables all ROs and
`led2` shows the XOR of their outputs (lit dimly while they run).

## Adding more ROs

**1. Pick sites.** With a synthesized or implemented design open:

```tcl
source scripts/ro_tools.tcl
ro_sites X0Y2                         ;# all CLBLM_L SLICELs in clock region X0Y2
lrange [ro_sites X0Y2] 0 15           ;# just the first 16
llength [ro_sites]                    ;# 2400 on the whole device
```

Use only sites from `ro_sites`, i.e. the same RO type. Any other slice won't fit the routes;
`ro_place.tcl` rejects it (see above).

**2. Instantiate them.** In `top.vhd`, raise `N_RO`:

```vhdl
constant N_RO : integer := 16;
```

**3. Place them.** In `ro_place.tcl`, add one line per RO to `RO_PLACEMENT`:

```tcl
set RO_PLACEMENT {
    gen_ro[0].u_ro  SLICE_X39Y100
    gen_ro[1].u_ro  SLICE_X39Y102
    ...
    gen_ro[15].u_ro SLICE_X43Y110
}
```

For many ROs, generate the list instead of typing it. For example, every second site of a region
(paste the output into `RO_PLACEMENT`):

```tcl
set i 0
foreach site [ro_sites X0Y2] {
    if {$i % 2 == 0} { puts "    gen_ro\[[expr {$i / 2}]\].u_ro  $site" }
    incr i
}
```

**4. Rebuild:** just *Generate Bitstream*. `ro_routes.tcl` stays valid because it is applied to every
`ro_cell` automatically, so step 4 of the walkthrough isn't needed. The bitstream hook runs `ro_check`;
check in the run log that it reports `N_RO` ROs, all `OK`.

If the bitstream step fails, look at **Critical Warnings** (Messages tab) and the `ro_check` table
in the run log. `[RO 1-1]` / `[RO 1-2]` means a RO was not placed (wrong site, duplicate, missing
`RO_PLACEMENT` entry, or renamed instance).

## UART

The UART echo from the template is still in `top.vhd`. Connect the UART and run:
`picocom -b 115200 --omap crlf --imap lfcrlf /dev/ttyUSB0`

- --omap crlf: Enter sends LF, which is the byte the FSM uses as end of line.
- --imap lfcrlf: the LF the FPGA sends is displayed as CR+LF, so each echoed line starts at column 0.
