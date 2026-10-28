# ============================================================================
# Generated clocks for every ro_prescaler instance (unmanaged Tcl constraint
# file, implementation only).
#
# A ro_prescaler is a ripple divider: stage i is clocked by the output of
# stage i-1, stage 0 by clk_in. Vivado only propagates clocks through
# combinational logic, not through a flip-flop, so every clock pin fed by a
# flip-flop output needs a generated clock; otherwise check_timing reports
# no_clock there.
#
# The generated clocks go on the stage CLOCK PINS (C), not on the Q outputs:
# a clock defined on a Q pin turns that pin into a clock source, and the
# flip-flop's own toggle path (Q -> LUT -> D) would then be timed against the
# wrong clock edge.
#
# Clock names, for instance u_ro_prescaler:
#   u_ro_prescaler_in      at stage 0 (= clk_in, only if clk_in comes from a ro_cell)
#   u_ro_prescaler_div2    at stage 1 (= clk_in / 2)
#   u_ro_prescaler_div4    at stage 2 ...
# ============================================================================

foreach inst [get_cells -hierarchical -quiet -filter {ORIG_REF_NAME == ro_prescaler || REF_NAME == ro_prescaler}] {
    set base [regsub -all {[^A-Za-z0-9]+} $inst _]
    set ffs {}
    for {set i 0} {[llength [get_cells -quiet "$inst/gen_stage\[$i\].stage_reg\[$i\]"]] > 0} {incr i} {
        lappend ffs [get_cells "$inst/gen_stage\[$i\].stage_reg\[$i\]"]
    }
    if {[llength $ffs] == 0} {
        send_msg_id {RO 2-1} {CRITICAL WARNING} "ro_prescaler.tcl: $inst: no gen_stage\[*\].stage_reg\[*\] flip-flops found, no clocks created"
        continue
    }

    # Stage 0: what drives clk_in? A ro_cell's toggle FF (ro_out) divides the
    # RO clock by 2, so declare that on stage 0's clock pin. A real clock (port,
    # MMCM, ...) already propagates there by itself.
    set c0  [get_pins [lindex $ffs 0]/C]
    set drv [get_cells -of_objects [get_pins -leaf -of_objects [get_nets -of_objects $c0] -filter {DIRECTION == OUT}]]
    set drv_parent [get_cells -quiet [get_property PARENT $drv]]
    if {[llength $drv_parent] && "ro_cell" in [list [get_property ORIG_REF_NAME $drv_parent] [get_property REF_NAME $drv_parent]]} {
        create_generated_clock -name ${base}_in -source [get_pins $drv/C] -divide_by 2 $c0
    } elseif {[get_property IS_SEQUENTIAL $drv]} {
        send_msg_id {RO 2-2} {CRITICAL WARNING} "ro_prescaler.tcl: $inst: clk_in is driven by flip-flop $drv, which is not a ro_cell; declare a generated clock on $c0 yourself"
    }

    # Stages 1..N-1: each clocked by the previous stage, which divides by 2.
    for {set i 1} {$i < [llength $ffs]} {incr i} {
        create_generated_clock -name ${base}_div[expr {1 << $i}] \
            -source [get_pins [lindex $ffs [expr {$i - 1}]]/C] -divide_by 2 [get_pins [lindex $ffs $i]/C]
    }
}
