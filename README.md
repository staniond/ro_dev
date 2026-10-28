# ro-dev

Ring oscillators (ROs) for an RO-PUF on the CW305 board (Artix-7 `xc7a100tftg256-1`, Vivado 2025.1).
Each RO sits in one slice, at a site you choose, and all ROs have **identical placement and routing**
that never leaves the RO's own CLB and its switch matrix.
The RO architecture is from Hesselbarth et al., *Large Scale RO PUF Analysis over Slice Type,
Evaluation Time and Temperature on 28nm Xilinx FPGAs* (HOST 2018), Fig. 1 (`ro_architecture.png`).

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
ro_check: <N> RO(s), 0 with problems
```

A timing failure would not stop the bitstream (Vivado only gives a critical warning), so glance at
WNS / WHS / TPWS of `impl_1` in the **Design Runs** window: none should be negative.

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
  `en` drops. Because `sim_1` also contains the `sim` architecture, instantiate the cell in your design
  with the architecture named explicitly: `entity work.ro_cell(rtl)`.

### The Vivado flow and where the scripts fit in

```
 synth_1                 impl_1
 synth_design ──> link_design ──> opt_design ──> place_design ──> route_design ──> write_bitstream
                       ▲
                       │  constrs_1, in this order:
                       ├── cw305_main.xdc : board/design constraints (pins, clocks, I/O)
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
| `place_design` | Places **everything else** (your logic); the fixed RO cells are obstacles it never moves |
| `route_design` | Routes everything else; the fixed RO wires are never changed. It only adds the `ro_out` branch of `q` |
| `write_bitstream` | First the pre-hook `scripts/ro_check_hook.tcl` (below), then final DRC (e.g. LUTLP-1), then writes `top.bit` |

**When do `ro_place.tcl` and `ro_routes.tcl` run?** Automatically: they are in the project's
constraint set `constrs_1`, marked *used in implementation* but not *used in synthesis* (the cells
they refer to only exist after synthesis). Vivado `source`s them, in the order listed in
`constrs_1`, every time it links a synthesized netlist:

| Action                                                                                                         | Constraint files run?                                                                        |
| -------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------- |
| Synthesis (`synth_1`)                                                                                          | no                                                                                           |
| Implementation (`impl_1`): its first step, `link_design` (the log says `Sourcing Tcl File [.../ro_place.tcl]`) | **yes**                                                                                      |
| **Open Synthesized Design** (`open_run synth_1`)                                                               | **yes**                                                                                      |
| **Open Implemented Design** (`open_run impl_1`)                                                                | no: it loads the finished routed checkpoint, where placement and routes are already baked in |

This is also why **Open Synthesized Design** shows only the ROs placed. That's not a placement step:
opening it runs `link_design`, which applies the constraints, and the ROs are the only cells with a
location. The rest gets placed by `place_design` during implementation (`impl_1`).

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

### `ro_dev.srcs/constrs_1/new/ro_place.tcl` (constraint, you edit it)

- `RO_PLACEMENT`: the list you maintain, **instance name -> slice**. Instance names are the full
  hierarchical netlist names of your `ro_cell` instances. The examples in this README use
  `gen_ro[i].u_ro`, which is what `gen_ro: for i ... generate` with an instance labelled `u_ro:` in the
  top level gives. If the ROs sit deeper in the hierarchy, the name includes the path
  (e.g. `u_puf/gen_ro[0].u_ro`).
- `RO_BELS`: which cell goes to which BEL (position inside the slice), and `LOCK_PINS`, which fixes
  the physical LUT input pin for each logical input. Vivado could otherwise swap LUT pins per
  instance, and then the routes would differ.
- For every RO it sets `BEL` + `LOC` on the 6 cells. It also sets `ALLOW_COMBINATORIAL_LOOPS` on the
  ring nets; without it, DRC **LUTLP-1** (an error) stops `write_bitstream`.
- For every RO it declares a clock on the ring output (`create_clock` on `lut_inv2/O`, named e.g.
  `ro_clk_gen_ro_0_u_ro`, asynchronous to all other clocks). Without it, `check_timing` reports
  `no_clock` on `gen_ro[*].u_ro/ff/C` and the toggle FF isn't timed. The period `RO_CLK_PERIOD`
  (1.5 ns) only steers the analysis; see [RO timing](#ro-timing-ring-period-and-the-clock-constraint)
  for where it comes from.
- Clocks starting at a LUT trigger `report_methodology` critical warnings TIMING-2 (clock on a
  non-clock pin) and TIMING-14 (LUT on the clock tree). For a RO that is the design, so each RO gets
  a waiver (`create_waiver`) for exactly those objects; the report lists them under *Checks waived*.
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

| Rule                                 | Meaning                                                | Why it's fine here                                                           |
| ------------------------------------ | ------------------------------------------------------ | ---------------------------------------------------------------------------- |
| LUTLP-2 Combinatorial Loop Allowed   | A LUT loop exists and is allowed                       | The allowed version of the LUTLP-1 error; it's the ring                      |
| PDRC-153 Gated clock                 | A FF is clocked by a LUT, not a clock buffer           | The toggle FF is clocked by the ring                                         |
| PLHOLDVIO-2 Possible hold violations | A clock comes from general routing, not the clock tree | The FF's hold is still checked against its `ro_clk_*` clock (slack ~0.21 ns) |

In a normal synchronous design each of these would be a bug, so check that they only point at
`gen_ro[*].u_ro` cells and nets.

What the ROs contribute to the other reports (anything else in them comes from the rest of your
design):

| Report | From the ROs |
|---|---|
| `report_methodology` | 2 checks waived per RO (TIMING-2, TIMING-14: the RO clocks), and one TIMING-23 *Combinational loop found* warning per RO (the ring) |
| `check_timing` | `loops`: one per RO (the ring). `no_clock` must be 0 |
| Timing summary | one `ro_clk_*` clock per RO, each with setup slack ~0.61 ns, hold ~0.21 ns, pulse width 0.25 ns |

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
changing `RO_BELS` or `LOCK_PINS`. Running it again does no harm: the routes come out the same,
only the date in the file's header changes.

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

The file order is stored in `ro_dev.xpr` and is already correct; it only changes if you rearrange
the constraint files (reorder them, or remove one and add it back, which puts it at the end). If
`ro_routes.tcl` ever ends up before `ro_place.tcl`, it finds no placed RO and silently fixes
nothing; the bitstream hook then stops the build with `ro_check ... with problems`. To fix the
order:

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

The bitstream is `ro_dev.runs/impl_1/top.bit`.

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

**2. Instantiate them** in your RTL as `entity work.ro_cell(rtl)`, e.g. by raising the count of the
generate loop that creates them.

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
check in the run log that it reports as many ROs as you instantiated, all `OK`.

If the bitstream step fails, look at **Critical Warnings** (Messages tab) and the `ro_check` table
in the run log. `[RO 1-1]` / `[RO 1-2]` means a RO was not placed (wrong site, duplicate, missing
`RO_PLACEMENT` entry, or renamed instance).

## RO timing: ring period and the clock constraint

`ro_place.tcl` declares a clock on every RO's ring output (`lut_inv2/O`), because that signal
clocks the toggle FF. Its period, `RO_CLK_PERIOD = 1.5 ns`, does **not** change the hardware: the
ring runs at whatever speed the silicon gives it. It only tells timing analysis how fast to assume
the FF is clocked, so it should be at least as fast as the fastest the ring can possibly run.
Otherwise the FF check could pass while the real ring is too fast for the FF.

Vivado can't give that number directly. It cuts every combinational loop at some point for
analysis, so `report_timing` around the ring finds no path. The period has to be added up from
the delays of the individual parts.

### How the period is calculated

The ring has 3 stages (NAND, inverter, inverter), each a LUT followed by a routed net. All three
invert, so an edge that goes once around the loop comes back inverted: one trip around gives half
a period, and a full period is **two trips**, one with each edge direction. Each stage's LUT is
passed once rising and once falling, and each net is passed twice:

```
period = sum over the 3 stages of ( LUT rise + LUT fall + 2 x net delay )
```

### Timing corners

For 7-series, Vivado's timing model has **two corners**, and each gives a **max** and a **min** delay
for every LUT arc and every net. That makes four values, all of which the Tcl below reads:

| Value | Corner | Delay bound | Used by Vivado for |
|---|---|---|---|
| `SLOW_MAX` | Slow: slowest process, highest temperature of the device grade, lowest supply voltage | max | setup checks: **slowest ring** |
| `SLOW_MIN` | Slow | min | hold checks |
| `FAST_MAX` | Fast: fastest process, lowest temperature, highest supply voltage | max | setup checks |
| `FAST_MIN` | Fast | min | hold checks: **fastest ring** |

Each corner is calculated the same way: take that corner's value for every LUT (rise and fall) and
every net, and add them up with the formula above. Results for this design (all ROs are identical,
so `gen_ro[0]` stands for all):

| Value | 3 LUTs (rise + fall) | 3 nets (x 2) | Period | Frequency |
|---|---|---|---|---|
| `SLOW_MAX` | 0.744 ns | 3.838 ns | 4.58 ns | 218 MHz |
| `SLOW_MIN` | 0.600 ns | 3.190 ns | 3.79 ns | 264 MHz |
| `FAST_MAX` | 0.336 ns | 1.550 ns | 1.89 ns | 530 MHz |
| `FAST_MIN` | 0.270 ns | 1.306 ns | **1.58 ns** | **635 MHz** |

**There is no typical corner.** Vivado's 7-series timing data only covers these sign-off bounds.
`set_operating_conditions` (process `typical`, temperature, ...) changes power estimates only; the
timing delays stay exactly the same. A typical value has to come from measurement:

| Typical (measured) | Period | Frequency |
|---|---|---|
| Hesselbarth et al., Table II: same RO architecture, Artix-7 XC7A35T -1, room temperature, mean over 217 boards | ~2.2 ns | **451-457 MHz** |

That is the same architecture and FPGA family, but their own placement and routing, so take it as
the expected ballpark, not a prediction for this design. In the paper, the frequency also varies
about 4.8 % between boards, ROs next to the clock distribution run about 20 MHz slower, and the
frequency changes with temperature (Fig. 6). Measure your own ROs on the board for the real number.

`RO_CLK_PERIOD = 1.5 ns` sits just below the fastest corner (`FAST_MIN`), so the FF check is strict.

### Tcl: get the delays and compute the period

With the implemented design open (`open_run impl_1`), paste into the Tcl Console:

```tcl
set inst {gen_ro[0].u_ro}

# One stage per ring LUT: the LUT, its ring input pin, the net it drives, and the
# next LUT's input pin on the ring (ring2 also goes to ff/C; we want the ring branch).
set stages {
    lut_nand I1 ring0 lut_inv1/I0
    lut_inv1 I0 ring1 lut_inv2/I0
    lut_inv2 I0 ring2 lut_nand/I1
}

foreach corner {SLOW_MAX SLOW_MIN FAST_MAX FAST_MIN} {
    set period 0.0
    puts "$corner:"
    foreach {lut in net next} $stages {
        set arc  [get_timing_arcs -from [get_pins $inst/$lut/$in] -to [get_pins $inst/$lut/O]]
        set rise [get_property DELAY_${corner}_RISE $arc]                  ;# ns
        set fall [get_property DELAY_${corner}_FALL $arc]                  ;# ns
        set nd   [get_net_delays -of_objects [get_nets $inst/$net] -to [get_pins $inst/$next]]
        set net_ns [expr {[get_property $corner $nd] / 1000.0}]            ;# ps -> ns
        puts [format "  %-8s rise %.3f  fall %.3f   %s %.3f ns" $lut $rise $fall $net $net_ns]
        set period [expr {$period + $rise + $fall + 2 * $net_ns}]
    }
    puts [format "  period %.2f ns = %.0f MHz" $period [expr {1000.0 / $period}]]
}
```

Output:

```
SLOW_MAX:
  lut_nand rise 0.124  fall 0.124   ring0 0.532 ns
  lut_inv1 rise 0.124  fall 0.124   ring1 0.520 ns
  lut_inv2 rise 0.124  fall 0.124   ring2 0.867 ns
  period 4.58 ns = 218 MHz
SLOW_MIN:
  lut_nand rise 0.100  fall 0.100   ring0 0.445 ns
  lut_inv1 rise 0.100  fall 0.100   ring1 0.436 ns
  lut_inv2 rise 0.100  fall 0.100   ring2 0.714 ns
  period 3.79 ns = 264 MHz
FAST_MAX:
  lut_nand rise 0.056  fall 0.056   ring0 0.200 ns
  lut_inv1 rise 0.056  fall 0.056   ring1 0.212 ns
  lut_inv2 rise 0.056  fall 0.056   ring2 0.363 ns
  period 1.89 ns = 530 MHz
FAST_MIN:
  lut_nand rise 0.045  fall 0.045   ring0 0.171 ns
  lut_inv1 rise 0.045  fall 0.045   ring1 0.180 ns
  lut_inv2 rise 0.045  fall 0.045   ring2 0.302 ns
  period 1.58 ns = 635 MHz
```

The two commands doing the work:

- `get_timing_arcs -from <LUT input pin> -to <LUT output pin>`: the LUT's timing arc. Its properties
  `DELAY_<corner>_RISE` / `_FALL` are the delays through the LUT for a rising / falling output, in ns.
  The arc depends on the physical LUT pin, which `LOCK_PINS` fixes.
- `get_net_delays -of_objects <net> -to <load pin>`: the routed delay of a net to one load. Its
  properties `SLOW_MAX`, `SLOW_MIN`, `FAST_MAX`, `FAST_MIN` are in **ps**.

### Does the toggle FF keep up? (checked automatically)

Nothing to run by hand: because `ro_place.tcl` declares the `ro_clk_*` clocks, every implementation
run times the toggle FFs together with the rest of the design. The results are in the timing
summary that `route_design` writes (`ro_dev.runs/impl_1/top_timing_summary_routed.rpt`) and in the
**Design Runs** window (WNS / WHS / TPWS of `impl_1`).

Note that a timing failure does **not** stop the bitstream: Vivado only reports
`CRITICAL WARNING: [Timing 38-282] The design failed to meet the timing requirements` and writes
`top.bit` anyway. So check that WNS, WHS and TPWS are not negative. For the ROs this can only
change if `ro_cell` or `RO_BELS` change, since their placement and routes are fixed.

To look at one RO in detail (implemented design open):

```tcl
report_timing -from [get_cells {gen_ro[0].u_ro/ff}] -to [get_cells {gen_ro[0].u_ro/ff}]
report_pulse_width -clocks [get_clocks ro_clk_gen_ro_0_u_ro]
```

| Check | Required | At 1.5 ns | Slack |
|---|---|---|---|
| Setup, path q -> D6LUT -> D | 0.89 ns data delay | 1.5 ns period | 0.61 ns |
| FF minimum clock period (`FDCE/C`) | 1.0 ns | 1.5 ns | 0.50 ns |
| FF minimum high / low pulse | 0.5 ns | 0.75 ns | 0.25 ns |

So the toggle FF can follow the ring even at its fastest corner. The FF itself could toggle at up
to 1 GHz. The full picture for all ROs is in `report_timing_summary` (one `ro_clk_*` per RO).


## UART

The UART echo from the template is still in `top.vhd`. Connect the UART and run:
`picocom -b 115200 --omap crlf --imap lfcrlf /dev/ttyUSB0`

- --omap crlf: Enter sends LF, which is the byte the FSM uses as end of line.
- --imap lfcrlf: the LF the FPGA sends is displayed as CR+LF, so each echoed line starts at column 0.