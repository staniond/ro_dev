# ============================================================================
# Ring-oscillator placement (unmanaged Tcl constraint file)
#
# Used in IMPLEMENTATION only (used_in_synthesis = false): the cells it refers
# to (gen_ro[i].u_ro/lut_nand, ...) only exist after synthesis.
#
# RO type (RO_TILE_TYPE/RO_SITE_TYPE, currently the SLICEL of a CLBLM_L tile)
# is defined in scripts/ro_tools.tcl, which this file sources. All ROs must be
# of the SAME type, otherwise the routes in ro_routes.tcl don't fit.
# List legal sites with:   source scripts/ro_tools.tcl ; ro_sites X0Y2
# ============================================================================

# Shared definitions (RO type) and helpers: scripts/ro_tools.tcl, found
# relative to this file (ro_dev.srcs/constrs_1/new/ -> project dir). Inside an
# implementation run, [info script] points into the run directory, so the path
# of this file is taken from the project's file list (read_xdc registers it).
set ro_place_file [lindex [get_files -quiet -all *ro_place.tcl] 0]
if {$ro_place_file eq ""} { set ro_place_file [file normalize [info script]] }
set ro_tools_file [file normalize [file join [file dirname $ro_place_file] .. .. .. scripts ro_tools.tcl]]
if {[catch {source $ro_tools_file} err]} {
    send_msg_id {RO 1-3} {CRITICAL WARNING} "ro_place.tcl: can't load $ro_tools_file ($err); no RO is placed"
    return
}

# Instance -> slice. Instance names are the netlist names of the ro_cell
# instances (gen_ro: for i ... generate / u_ro: in top.vhd -> gen_ro[i].u_ro).
set RO_PLACEMENT {
    gen_ro[0].u_ro       SLICE_X11Y50
    gen_ro[1].u_ro       SLICE_X11Y51
    gen_ro[2].u_ro       SLICE_X11Y52
    gen_ro[3].u_ro       SLICE_X11Y53
    gen_ro[4].u_ro       SLICE_X11Y54
    gen_ro[5].u_ro       SLICE_X11Y55
    gen_ro[6].u_ro       SLICE_X11Y56
    gen_ro[7].u_ro       SLICE_X11Y57
    gen_ro[8].u_ro       SLICE_X11Y58
    gen_ro[9].u_ro       SLICE_X11Y59
    gen_ro[10].u_ro      SLICE_X11Y60
    gen_ro[11].u_ro      SLICE_X11Y61
    gen_ro[12].u_ro      SLICE_X11Y62
    gen_ro[13].u_ro      SLICE_X11Y63
    gen_ro[14].u_ro      SLICE_X11Y64
    gen_ro[15].u_ro      SLICE_X11Y65
    gen_ro[16].u_ro      SLICE_X11Y66
    gen_ro[17].u_ro      SLICE_X11Y67
    gen_ro[18].u_ro      SLICE_X11Y68
    gen_ro[19].u_ro      SLICE_X11Y69
    gen_ro[20].u_ro      SLICE_X11Y70
    gen_ro[21].u_ro      SLICE_X11Y71
    gen_ro[22].u_ro      SLICE_X11Y72
    gen_ro[23].u_ro      SLICE_X11Y73
    gen_ro[24].u_ro      SLICE_X11Y74
    gen_ro[25].u_ro      SLICE_X11Y75
    gen_ro[26].u_ro      SLICE_X11Y76
    gen_ro[27].u_ro      SLICE_X11Y77
    gen_ro[28].u_ro      SLICE_X11Y78
    gen_ro[29].u_ro      SLICE_X11Y79
    gen_ro[30].u_ro      SLICE_X11Y80
    gen_ro[31].u_ro      SLICE_X11Y81
    gen_ro[32].u_ro      SLICE_X11Y82
    gen_ro[33].u_ro      SLICE_X11Y83
    gen_ro[34].u_ro      SLICE_X11Y84
    gen_ro[35].u_ro      SLICE_X11Y85
    gen_ro[36].u_ro      SLICE_X11Y86
    gen_ro[37].u_ro      SLICE_X11Y87
    gen_ro[38].u_ro      SLICE_X11Y88
    gen_ro[39].u_ro      SLICE_X11Y89
    gen_ro[40].u_ro      SLICE_X11Y90
    gen_ro[41].u_ro      SLICE_X11Y91
    gen_ro[42].u_ro      SLICE_X11Y92
    gen_ro[43].u_ro      SLICE_X11Y93
    gen_ro[44].u_ro      SLICE_X11Y94
    gen_ro[45].u_ro      SLICE_X11Y95
    gen_ro[46].u_ro      SLICE_X11Y96
    gen_ro[47].u_ro      SLICE_X11Y97
    gen_ro[48].u_ro      SLICE_X11Y98
    gen_ro[49].u_ro      SLICE_X11Y99
    gen_ro[50].u_ro      SLICE_X13Y50
    gen_ro[51].u_ro      SLICE_X13Y51
    gen_ro[52].u_ro      SLICE_X13Y52
    gen_ro[53].u_ro      SLICE_X13Y53
    gen_ro[54].u_ro      SLICE_X13Y54
    gen_ro[55].u_ro      SLICE_X13Y55
    gen_ro[56].u_ro      SLICE_X13Y56
    gen_ro[57].u_ro      SLICE_X13Y57
    gen_ro[58].u_ro      SLICE_X13Y58
    gen_ro[59].u_ro      SLICE_X13Y59
    gen_ro[60].u_ro      SLICE_X13Y60
    gen_ro[61].u_ro      SLICE_X13Y61
    gen_ro[62].u_ro      SLICE_X13Y62
    gen_ro[63].u_ro      SLICE_X13Y63
    gen_ro[64].u_ro      SLICE_X13Y64
    gen_ro[65].u_ro      SLICE_X13Y65
    gen_ro[66].u_ro      SLICE_X13Y66
    gen_ro[67].u_ro      SLICE_X13Y67
    gen_ro[68].u_ro      SLICE_X13Y68
    gen_ro[69].u_ro      SLICE_X13Y69
    gen_ro[70].u_ro      SLICE_X13Y70
    gen_ro[71].u_ro      SLICE_X13Y71
    gen_ro[72].u_ro      SLICE_X13Y72
    gen_ro[73].u_ro      SLICE_X13Y73
    gen_ro[74].u_ro      SLICE_X13Y74
    gen_ro[75].u_ro      SLICE_X13Y75
    gen_ro[76].u_ro      SLICE_X13Y76
    gen_ro[77].u_ro      SLICE_X13Y77
    gen_ro[78].u_ro      SLICE_X13Y78
    gen_ro[79].u_ro      SLICE_X13Y79
    gen_ro[80].u_ro      SLICE_X13Y80
    gen_ro[81].u_ro      SLICE_X13Y81
    gen_ro[82].u_ro      SLICE_X13Y82
    gen_ro[83].u_ro      SLICE_X13Y83
    gen_ro[84].u_ro      SLICE_X13Y84
    gen_ro[85].u_ro      SLICE_X13Y85
    gen_ro[86].u_ro      SLICE_X13Y86
    gen_ro[87].u_ro      SLICE_X13Y87
    gen_ro[88].u_ro      SLICE_X13Y88
    gen_ro[89].u_ro      SLICE_X13Y89
    gen_ro[90].u_ro      SLICE_X13Y90
    gen_ro[91].u_ro      SLICE_X13Y91
    gen_ro[92].u_ro      SLICE_X13Y92
    gen_ro[93].u_ro      SLICE_X13Y93
    gen_ro[94].u_ro      SLICE_X13Y94
    gen_ro[95].u_ro      SLICE_X13Y95
    gen_ro[96].u_ro      SLICE_X13Y96
    gen_ro[97].u_ro      SLICE_X13Y97
    gen_ro[98].u_ro      SLICE_X13Y98
    gen_ro[99].u_ro      SLICE_X13Y99
    gen_ro[100].u_ro     SLICE_X31Y50
    gen_ro[101].u_ro     SLICE_X31Y51
    gen_ro[102].u_ro     SLICE_X31Y52
    gen_ro[103].u_ro     SLICE_X31Y53
    gen_ro[104].u_ro     SLICE_X31Y54
    gen_ro[105].u_ro     SLICE_X31Y55
    gen_ro[106].u_ro     SLICE_X31Y56
    gen_ro[107].u_ro     SLICE_X31Y57
    gen_ro[108].u_ro     SLICE_X31Y58
    gen_ro[109].u_ro     SLICE_X31Y59
    gen_ro[110].u_ro     SLICE_X31Y60
    gen_ro[111].u_ro     SLICE_X31Y61
    gen_ro[112].u_ro     SLICE_X31Y62
    gen_ro[113].u_ro     SLICE_X31Y63
    gen_ro[114].u_ro     SLICE_X31Y64
    gen_ro[115].u_ro     SLICE_X31Y65
    gen_ro[116].u_ro     SLICE_X31Y66
    gen_ro[117].u_ro     SLICE_X31Y67
    gen_ro[118].u_ro     SLICE_X31Y68
    gen_ro[119].u_ro     SLICE_X31Y69
    gen_ro[120].u_ro     SLICE_X31Y70
    gen_ro[121].u_ro     SLICE_X31Y71
    gen_ro[122].u_ro     SLICE_X31Y72
    gen_ro[123].u_ro     SLICE_X31Y73
    gen_ro[124].u_ro     SLICE_X31Y74
    gen_ro[125].u_ro     SLICE_X31Y75
    gen_ro[126].u_ro     SLICE_X31Y76
    gen_ro[127].u_ro     SLICE_X31Y77
    gen_ro[128].u_ro     SLICE_X31Y78
    gen_ro[129].u_ro     SLICE_X31Y79
    gen_ro[130].u_ro     SLICE_X31Y80
    gen_ro[131].u_ro     SLICE_X31Y81
    gen_ro[132].u_ro     SLICE_X31Y82
    gen_ro[133].u_ro     SLICE_X31Y83
    gen_ro[134].u_ro     SLICE_X31Y84
    gen_ro[135].u_ro     SLICE_X31Y85
    gen_ro[136].u_ro     SLICE_X31Y86
    gen_ro[137].u_ro     SLICE_X31Y87
    gen_ro[138].u_ro     SLICE_X31Y88
    gen_ro[139].u_ro     SLICE_X31Y89
    gen_ro[140].u_ro     SLICE_X31Y90
    gen_ro[141].u_ro     SLICE_X31Y91
    gen_ro[142].u_ro     SLICE_X31Y92
    gen_ro[143].u_ro     SLICE_X31Y93
    gen_ro[144].u_ro     SLICE_X31Y94
    gen_ro[145].u_ro     SLICE_X31Y95
    gen_ro[146].u_ro     SLICE_X31Y96
    gen_ro[147].u_ro     SLICE_X31Y97
    gen_ro[148].u_ro     SLICE_X31Y98
    gen_ro[149].u_ro     SLICE_X31Y99
    gen_ro[150].u_ro     SLICE_X35Y50
    gen_ro[151].u_ro     SLICE_X35Y51
    gen_ro[152].u_ro     SLICE_X35Y52
    gen_ro[153].u_ro     SLICE_X35Y53
    gen_ro[154].u_ro     SLICE_X35Y54
    gen_ro[155].u_ro     SLICE_X35Y55
    gen_ro[156].u_ro     SLICE_X35Y56
    gen_ro[157].u_ro     SLICE_X35Y57
    gen_ro[158].u_ro     SLICE_X35Y58
    gen_ro[159].u_ro     SLICE_X35Y59
    gen_ro[160].u_ro     SLICE_X35Y60
    gen_ro[161].u_ro     SLICE_X35Y61
    gen_ro[162].u_ro     SLICE_X35Y62
    gen_ro[163].u_ro     SLICE_X35Y63
    gen_ro[164].u_ro     SLICE_X35Y64
    gen_ro[165].u_ro     SLICE_X35Y65
    gen_ro[166].u_ro     SLICE_X35Y66
    gen_ro[167].u_ro     SLICE_X35Y67
    gen_ro[168].u_ro     SLICE_X35Y68
    gen_ro[169].u_ro     SLICE_X35Y69
    gen_ro[170].u_ro     SLICE_X35Y70
    gen_ro[171].u_ro     SLICE_X35Y71
    gen_ro[172].u_ro     SLICE_X35Y72
    gen_ro[173].u_ro     SLICE_X35Y73
    gen_ro[174].u_ro     SLICE_X35Y74
    gen_ro[175].u_ro     SLICE_X35Y75
    gen_ro[176].u_ro     SLICE_X35Y76
    gen_ro[177].u_ro     SLICE_X35Y77
    gen_ro[178].u_ro     SLICE_X35Y78
    gen_ro[179].u_ro     SLICE_X35Y79
    gen_ro[180].u_ro     SLICE_X35Y80
    gen_ro[181].u_ro     SLICE_X35Y81
    gen_ro[182].u_ro     SLICE_X35Y82
    gen_ro[183].u_ro     SLICE_X35Y83
    gen_ro[184].u_ro     SLICE_X35Y84
    gen_ro[185].u_ro     SLICE_X35Y85
    gen_ro[186].u_ro     SLICE_X35Y86
    gen_ro[187].u_ro     SLICE_X35Y87
    gen_ro[188].u_ro     SLICE_X35Y88
    gen_ro[189].u_ro     SLICE_X35Y89
    gen_ro[190].u_ro     SLICE_X35Y90
    gen_ro[191].u_ro     SLICE_X35Y91
    gen_ro[192].u_ro     SLICE_X35Y92
    gen_ro[193].u_ro     SLICE_X35Y93
    gen_ro[194].u_ro     SLICE_X35Y94
    gen_ro[195].u_ro     SLICE_X35Y95
    gen_ro[196].u_ro     SLICE_X35Y96
    gen_ro[197].u_ro     SLICE_X35Y97
    gen_ro[198].u_ro     SLICE_X35Y98
    gen_ro[199].u_ro     SLICE_X35Y99
    gen_ro[200].u_ro     SLICE_X39Y50
    gen_ro[201].u_ro     SLICE_X39Y51
    gen_ro[202].u_ro     SLICE_X39Y52
    gen_ro[203].u_ro     SLICE_X39Y53
    gen_ro[204].u_ro     SLICE_X39Y54
    gen_ro[205].u_ro     SLICE_X39Y55
    gen_ro[206].u_ro     SLICE_X39Y56
    gen_ro[207].u_ro     SLICE_X39Y57
    gen_ro[208].u_ro     SLICE_X39Y58
    gen_ro[209].u_ro     SLICE_X39Y59
    gen_ro[210].u_ro     SLICE_X39Y60
    gen_ro[211].u_ro     SLICE_X39Y61
    gen_ro[212].u_ro     SLICE_X39Y62
    gen_ro[213].u_ro     SLICE_X39Y63
    gen_ro[214].u_ro     SLICE_X39Y64
    gen_ro[215].u_ro     SLICE_X39Y65
    gen_ro[216].u_ro     SLICE_X39Y66
    gen_ro[217].u_ro     SLICE_X39Y67
    gen_ro[218].u_ro     SLICE_X39Y68
    gen_ro[219].u_ro     SLICE_X39Y69
    gen_ro[220].u_ro     SLICE_X39Y70
    gen_ro[221].u_ro     SLICE_X39Y71
    gen_ro[222].u_ro     SLICE_X39Y72
    gen_ro[223].u_ro     SLICE_X39Y73
    gen_ro[224].u_ro     SLICE_X39Y74
    gen_ro[225].u_ro     SLICE_X39Y75
    gen_ro[226].u_ro     SLICE_X39Y76
    gen_ro[227].u_ro     SLICE_X39Y77
    gen_ro[228].u_ro     SLICE_X39Y78
    gen_ro[229].u_ro     SLICE_X39Y79
    gen_ro[230].u_ro     SLICE_X39Y80
    gen_ro[231].u_ro     SLICE_X39Y81
    gen_ro[232].u_ro     SLICE_X39Y82
    gen_ro[233].u_ro     SLICE_X39Y83
    gen_ro[234].u_ro     SLICE_X39Y84
    gen_ro[235].u_ro     SLICE_X39Y85
    gen_ro[236].u_ro     SLICE_X39Y86
    gen_ro[237].u_ro     SLICE_X39Y87
    gen_ro[238].u_ro     SLICE_X39Y88
    gen_ro[239].u_ro     SLICE_X39Y89
    gen_ro[240].u_ro     SLICE_X39Y90
    gen_ro[241].u_ro     SLICE_X39Y91
    gen_ro[242].u_ro     SLICE_X39Y92
    gen_ro[243].u_ro     SLICE_X39Y93
    gen_ro[244].u_ro     SLICE_X39Y94
    gen_ro[245].u_ro     SLICE_X39Y95
    gen_ro[246].u_ro     SLICE_X39Y96
    gen_ro[247].u_ro     SLICE_X39Y97
    gen_ro[248].u_ro     SLICE_X39Y98
    gen_ro[249].u_ro     SLICE_X39Y99
    gen_ro[250].u_ro     SLICE_X43Y50
    gen_ro[251].u_ro     SLICE_X43Y51
    gen_ro[252].u_ro     SLICE_X43Y52
    gen_ro[253].u_ro     SLICE_X43Y53
    gen_ro[254].u_ro     SLICE_X43Y54
    gen_ro[255].u_ro     SLICE_X43Y55
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

# A RO on a site of another type can't get its routes (route_design fails with
# a cryptic message, or worse, the router quietly routes it its own way), so
# every site is checked against the RO type from ro_tools.tcl first.
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

# Clock declared on each RO's ring output (ring2 = lut_inv2/O), which clocks the
# toggle FF. Without it, check_timing reports no_clock on gen_ro[*].u_ro/ff/C and
# the FF isn't timed at all. The period only steers timing analysis, not the
# hardware. Ring period = 2 x (3 LUT arcs + 3 ring nets), from the routed design
# (get_timing_arcs / get_net_delays): 4.58 ns slow corner, 1.58 ns fast corner
# (min delays). 1.5 ns covers the fastest case, so the FF check is strict; the
# FF itself needs >= 1.0 ns period / 0.5 ns pulse width.
# No set_clock_groups here: a group created now would also declare the RO clock
# asynchronous to clocks derived from it later (e.g. by ro_prescaler.tcl), which
# is wrong (methodology TIMING-47). Nothing crosses from a RO clock into another
# clock domain; if you add such logic, constrain that crossing (CDC) there.
set RO_CLK_PERIOD 1.500

proc ro_place {inst site} {
    global RO_BELS RO_CLK_PERIOD
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

    set clk "ro_clk_[regsub -all {[^A-Za-z0-9]+} $inst _]"   ;# gen_ro[0].u_ro -> ro_clk_gen_ro_0_u_ro
    create_clock -name $clk -period $RO_CLK_PERIOD [get_pins $inst/lut_inv2/O]
    # report_methodology flags a clock that starts at / passes through a LUT.
    # For a RO that is the design, so waive exactly these objects.
    create_waiver -type METHODOLOGY -id TIMING-2  -objects [get_pins $inst/lut_inv2/O] \
        -description "RO: ring output is the toggle-FF clock by design"
    create_waiver -type METHODOLOGY -id TIMING-14 -objects [get_cells $inst/lut_inv2] \
        -description "RO: ring LUT drives the toggle-FF clock by design"

    # en comes from control logic in another clock domain and clears the toggle
    # FF asynchronously (and stops the ring). Starting or stopping a RO at an
    # arbitrary moment is harmless, so the path is not timed (otherwise:
    # recovery/removal check from the control clock to ro_clk_*). The only timed
    # endpoint on the en path is the FF's CLR pin. (Not "-through $inst/en":
    # synthesis renames hierarchical ports, e.g. en -> Q[0]; leaf names are kept.)
    set_false_path -to [get_pins $inst/ff/CLR]
    # report_cdc: an asynchronous reset without synchronizer (CDC-7) - intended.
    create_waiver -type CDC -id CDC-7 \
        -from [all_fanin -startpoints_only -flat [get_pins $inst/ff/CLR]] -to [get_pins $inst/ff/CLR] \
        -description "RO: en asynchronously stops the RO and clears its toggle FF by design"
    # report_methodology traces through the en flip-flop and sees the ring clock
    # "downstream" of the control clock (TIMING-4). The ring runs on its own;
    # replacing the upstream clock is the intent.
    create_waiver -type METHODOLOGY -id TIMING-4 -objects [get_clocks $clk] \
        -description "RO: ring clock is independent of the clock that enables it"
}

# A RO with a problem is reported and left completely alone: no placement,
# no fixed route and no ALLOW_COMBINATORIAL_LOOPS. Implementation still runs,
# but write_bitstream stops with DRC LUTLP-1, so a misplaced RO can never
# end up in a bitstream. (An `error` here would only skip the rest of this
# file with a critical warning.)
# Why instance $inst can't be placed (all its RO_BELS cells must exist), or "".
# Checked up front: a missing cell would otherwise raise a Tcl error inside
# ro_place, and Vivado would skip the rest of this file.
proc ro_cell_problem {inst} {
    global RO_BELS
    set missing {}
    foreach {cell bel pins} $RO_BELS {
        if {[llength [get_cells -quiet $inst/$cell]] == 0} { lappend missing $cell }
    }
    if {[llength $missing] == [llength $RO_BELS] / 3} {
        return "no such ro_cell instance in the design"
    } elseif {[llength $missing]} {
        return "cells missing in this ro_cell: [join $missing {, }] (renamed in ro_cell.vhd?)"
    }
    return ""
}

set ro_used_sites [dict create]   ;# site -> instance
set ro_listed     [dict create]   ;# instance -> site (dict: one lookup per RO)
foreach {inst site} $RO_PLACEMENT {
    if {[dict exists $ro_listed $inst]} {
        send_msg_id {RO 1-1} {CRITICAL WARNING} "ro_place.tcl: $inst is listed twice in RO_PLACEMENT:\
            entry $site ignored, the first entry ([dict get $ro_listed $inst]) applies"
        continue
    }
    dict set ro_listed $inst $site
    set problem [ro_site_problem $site]
    if {$problem eq "" && [dict exists $ro_used_sites $site]} {
        set problem "$site is already used by [dict get $ro_used_sites $site]"
    }
    if {$problem eq ""} { set problem [ro_cell_problem $inst] }
    if {$problem ne ""} {
        send_msg_id {RO 1-1} {CRITICAL WARNING} "ro_place.tcl: $inst NOT placed: $problem"
        continue
    }
    dict set ro_used_sites $site $inst
    ro_place $inst $site
}

# Every ro_cell must be in RO_PLACEMENT: an unplaced one would get random placement/routing.
foreach inst [get_cells -hierarchical -quiet -filter {ORIG_REF_NAME == ro_cell || REF_NAME == ro_cell}] {
    if {![dict exists $ro_listed $inst]} {
        send_msg_id {RO 1-2} {CRITICAL WARNING} "ro_place.tcl: $inst NOT placed: no entry in RO_PLACEMENT"
    }
}

# Clock of the selected RO's output: every ro_select instance (OR of all
# ro_out, see ro_select.vhd) ends in the buffer LUT u_root. ro_out comes from a
# flip-flop, and Vivado doesn't propagate clocks through flip-flops, so the
# measurement path (ro_select -> ro_prescaler) has no clock until one is
# declared here. ro_out toggles at half the ring frequency: period 2 x
# RO_CLK_PERIOD. The prescaler stages derive their clocks from this one
# (ro_prescaler.tcl).
foreach inst [get_cells -hierarchical -quiet -filter {ORIG_REF_NAME == ro_select || REF_NAME == ro_select}] {
    set root [get_pins $inst/u_root/O]
    set clk "[regsub -all {[^A-Za-z0-9]+} $inst _]_clk"
    create_clock -name $clk -period [expr {2 * $RO_CLK_PERIOD}] $root
    # TIMING-4: methodology sees this clock "downstream" of every RO clock (through
    # the toggle FFs). It comes from whichever RO is enabled, so it can't be a
    # generated clock of one of them; a new primary clock is the intent.
    create_waiver -type METHODOLOGY -id TIMING-4 -objects [get_clocks $clk] \
        -description "ro_select: output of the enabled RO, independent primary clock by design"
    create_waiver -type METHODOLOGY -id TIMING-2  -objects $root \
        -description "ro_select: selected RO output is the prescaler clock by design"
    create_waiver -type METHODOLOGY -id TIMING-14 -objects [get_cells $inst/u_root] \
        -description "ro_select: LUT drives the prescaler clock by design"
}
