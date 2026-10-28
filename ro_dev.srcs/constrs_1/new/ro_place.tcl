# ============================================================================
# Ring-oscillator placement (unmanaged Tcl constraint file)
#
# Used in IMPLEMENTATION only (used_in_synthesis = false): the cells it refers
# to (gen_ro[i].u_ro/lut_nand, ...) only exist after synthesis.
#
# RO type: the SLICEL of a CLBLM_L tile (2400 sites on xc7a100t). All ROs must
# be of the SAME type, otherwise the captured routes in ro_routes.tcl don't fit.
# List legal sites with:   source scripts/ro_tools.tcl ; ro_sites X0Y2
# ============================================================================

# Instance -> slice. Instance names are the netlist names of the ro_cell
# instances (gen_ro: for i ... generate / u_ro: in top.vhd -> gen_ro[i].u_ro).
set RO_PLACEMENT {
    gen_ro[0].u_ro  SLICE_X39Y100
    gen_ro[1].u_ro  SLICE_X39Y102
    gen_ro[2].u_ro  SLICE_X39Y104
    gen_ro[3].u_ro  SLICE_X39Y106
}

# Cell -> BEL inside the slice, and logical LUT pin -> physical LUT pin
# (LOCK_PINS names the pins A1..A6 for every LUT letter).
# The B LUT holds two functions (B6LUT = NAND, B5LUT = en inverter), so both
# must use pins A1..A5 and share the en pin. Single inverters use A6, the
# fastest LUT input. lut_tog in D6LUT drives DFF.D through the slice directly.
#
# Why B and not A for the NAND: every local path to the slice CLK pin uses the
# switch-matrix wire FAN_ALT5, and from AMUX the SR pin is reachable only via
# FAN_ALT5 too. From BMUX, SR is reached via FAN_ALT1 instead, so the clock
# (ring2) and the clear (en_n) can both stay inside the CLB.
set RO_BELS {
    lut_nand  B6LUT  {I0:A1 I1:A2}
    lut_clr   B5LUT  {I0:A1}
    lut_inv1  A6LUT  {I0:A6}
    lut_inv2  C6LUT  {I0:A6}
    lut_tog   D6LUT  {I0:A6}
    ff        DFF    {}
}

# The RO type: ro_routes.tcl names wires of this tile/slice type only. A RO
# anywhere else can't get its routes (route_design fails with a cryptic
# message, or worse, the router quietly routes it its own way).
set RO_TILE_TYPE CLBLM_L
set RO_SITE_TYPE SLICEL

# Why $site can't hold a RO, or "" if it can.
proc ro_site_problem {site} {
    global RO_TILE_TYPE RO_SITE_TYPE
    set s [get_sites -quiet $site]
    if {[llength $s] == 0} {
        return "there is no site $site on this device"
    }
    set site_type [get_property SITE_TYPE $s]
    set tile_type [get_property TYPE [get_tiles -of_objects $s]]
    if {$site_type ne $RO_SITE_TYPE || $tile_type ne $RO_TILE_TYPE} {
        return "$site is a $site_type in a $tile_type tile, ROs must be on a\
                $RO_SITE_TYPE in a $RO_TILE_TYPE tile (list them with ro_sites)"
    }
    return ""
}

proc ro_place {inst site} {
    global RO_BELS
    foreach {cell bel pins} $RO_BELS {
        set c [get_cells $inst/$cell]
        set_property BEL $bel $c           ;# BEL first, then LOC
        set_property LOC $site $c
        if {$pins ne ""} {
            set_property LOCK_PINS $pins $c
        }
    }
    # The ring is a deliberate combinational loop; without this, DRC LUTLP-1
    # stops write_bitstream.
    set_property ALLOW_COMBINATORIAL_LOOPS TRUE [get_nets $inst/ring*]
}

# A RO with a problem is reported and left completely alone: no placement,
# no fixed route and no ALLOW_COMBINATORIAL_LOOPS. Implementation still runs,
# but write_bitstream stops with DRC LUTLP-1, so a misplaced RO can never
# end up in a bitstream. (An `error` here would only skip the rest of this
# file with a critical warning.)
set ro_used_sites [dict create]
foreach {inst site} $RO_PLACEMENT {
    set problem [ro_site_problem $site]
    if {$problem eq "" && [dict exists $ro_used_sites $site]} {
        set problem "$site is already used by [dict get $ro_used_sites $site]"
    }
    if {$problem eq "" && [llength [get_cells -quiet $inst/ff]] == 0} {
        set problem "no such ro_cell instance in the design"
    }
    if {$problem ne ""} {
        send_msg_id {RO 1-1} {CRITICAL WARNING} "ro_place.tcl: $inst NOT placed: $problem"
        continue
    }
    dict set ro_used_sites $site $inst
    ro_place $inst $site
}

# Every ro_cell must be in RO_PLACEMENT: an unplaced one would get random placement/routing.
foreach inst [get_cells -hierarchical -quiet -filter {ORIG_REF_NAME == ro_cell || REF_NAME == ro_cell}] {
    if {[lsearch -exact $RO_PLACEMENT $inst] < 0} {
        send_msg_id {RO 1-2} {CRITICAL WARNING} "ro_place.tcl: $inst NOT placed: no entry in RO_PLACEMENT"
    }
}
