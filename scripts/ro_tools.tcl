# ============================================================================
# Interactive helpers for the ring oscillators. In the Vivado Tcl console:
#
#   cd [get_property DIRECTORY [current_project]]
#   source scripts/ro_tools.tcl
#
#   ro_sites ?clock_region?        list legal RO sites (any open design)
#   ro_placement_list count ?clock_region? ?step?
#                                  print RO_PLACEMENT lines for many ROs
#   ro_make_routes ?inst?          compute local routes for one placed RO and
#                                  write constrs_1/new/ro_routes.tcl
#   ro_check                       per RO: routed, fixed, local, identical?
# ============================================================================

# The RO type: which slice of which tile type every RO uses. Defined only here;
# ro_place.tcl sources this file and checks RO_PLACEMENT against it. All ROs
# must be of one type, because ro_routes.tcl names the wires of that tile type.
set ::RO_TILE_TYPE CLBLM_L
set ::RO_SITE_TYPE SLICEL

# Nets of one ro_cell that leave the slice and therefore need routing, in the
# order they get routing resources (ring first: it sets the frequency).
# (d is slice-internal; en comes from outside the cell and is left to the router.)
set ::RO_NETS {ring0 ring1 ring2 q en_n}

proc ro_instances {} {
    return [get_cells -hierarchical -quiet -filter {ORIG_REF_NAME == ro_cell || REF_NAME == ro_cell}]
}

# All legal RO sites (RO_SITE_TYPE in RO_TILE_TYPE tiles), optionally in one
# clock region (e.g. X0Y2).
proc ro_sites {{clock_region *}} {
    set sites [get_sites -of_objects [get_tiles -filter "TYPE == $::RO_TILE_TYPE"] \
                   -filter "SITE_TYPE == $::RO_SITE_TYPE && CLOCK_REGION =~ $clock_region"]
    # get_property NAME gives a plain Tcl list (collections >500 can't be printed)
    return [lsort -dictionary [get_property NAME $sites]]
}

# Print RO_PLACEMENT lines for `count` ROs named gen_ro[i].u_ro (or $pattern,
# with %d for the index), on every `step`-th legal site of a clock region.
# Paste the output into RO_PLACEMENT in ro_place.tcl. Example:
#   ro_placement_list 64 X0Y2 2
proc ro_placement_list {count {clock_region *} {step 1} {pattern {gen_ro[%d].u_ro}}} {
    set sites [ro_sites $clock_region]
    set avail [expr {([llength $sites] + $step - 1) / $step}]
    if {$count > $avail} {
        error "only $avail sites with step $step in clock region $clock_region, need $count"
    }
    for {set i 0} {$i < $count} {incr i} {
        puts [format "    %-20s %s" [format $pattern $i] [lindex $sites [expr {$i * $step}]]]
    }
}

# Site pins of $net inside $site: driver first, then the loads.
# (q also drives ro_out outside the slice; that load is ignored here.)
proc ro_site_pins {net site} {
    set drv {}
    set loads {}
    foreach sp [get_property NAME [get_site_pins -of_objects $net]] {
        if {![string match "$site/*" $sp]} continue
        if {[get_property DIRECTION [get_site_pins $sp]] eq "OUT"} {
            set drv $sp
        } else {
            lappend loads $sp
        }
    }
    return [list $drv $loads]
}

proc ro_node_of {site_pin} {
    return [get_property NAME [get_nodes -of_objects [get_site_pins $site_pin]]]
}

# The RO's CLB tile and its switch-matrix tile: the only tiles a route may use.
# A CLB tile and its INT tile share coordinates; the _L/_R side matches:
# CLBLM_L_X24Y100 -> INT_L_X24Y100, CLBLL_R_X13Y189 -> INT_R_X13Y189.
proc ro_local_tiles {site} {
    set clb [get_property NAME [get_tiles -of_objects [get_sites $site]]]
    if {![regsub {^CLBL[LM]_([LR])_} $clb {INT_\1_} int]} {
        error "ro_local_tiles: $clb is not a CLB tile"
    }
    return [list $clb $int]
}

proc ro_is_local {node tiles} {
    foreach t [get_property NAME [get_tiles -of_objects [get_nodes $node]]] {
        if {[lsearch -exact $tiles $t] < 0} { return 0 }
    }
    return 1
}

# Breadth-first search through the routing graph from any node of the tree
# (dict node -> parent) to goal, using only local nodes not in $used.
# Returns the tree extended by the path, or "" if no local path exists.
proc ro_bfs {tree goal tiles used} {
    set prev $tree
    set queue [dict keys $tree]
    while {[llength $queue]} {
        set n [lindex $queue 0]
        set queue [lrange $queue 1 end]
        if {$n eq $goal} {
            # copy the new branch (goal back to the tree) into the tree
            while {![dict exists $tree $n]} {
                dict set tree $n [dict get $prev $n]
                set n [dict get $prev $n]
            }
            return $tree
        }
        # don't route through a slice (LUT route-through): a site-pin node is
        # only allowed as the goal, never as an intermediate hop
        if {![dict exists $tree $n] && [llength [get_site_pins -quiet -of_objects [get_nodes $n]]]} continue
        set down [get_nodes -quiet -downhill -of_objects [get_nodes $n]]
        if {[llength $down] == 0} continue
        foreach m [get_property NAME $down] {
            if {[dict exists $prev $m] || [dict exists $used $m]} continue
            if {![ro_is_local $m $tiles]} continue
            dict set prev $m $n
            lappend queue $m
        }
    }
    return ""
}

# Tree (dict node -> parent) to a Vivado ROUTE string. Node names lose their
# tile prefix (INT_L_X24Y100/IMUX_L42 -> IMUX_L42), which is what makes the
# route relocatable. Branches are braced, the last child continues inline:
#   { CLBLM_L_C CLBLM_LOGIC_OUTS10 FAN_ALT5 FAN_BOUNCE5 { CLK_L0 CLBLM_L_CLK } IMUX_L3 CLBLM_L_A2 }
proc ro_route_string {tree node} {
    set s [regsub {^[^/]*/} $node {}]
    set kids {}
    dict for {n p} $tree { if {$p eq $node} { lappend kids $n } }
    set kids [lsort $kids]
    foreach k [lrange $kids 0 end-1] { append s " \{ [ro_route_string $tree $k] \}" }
    if {[llength $kids]} { append s " [ro_route_string $tree [lindex $kids end]]" }
    return $s
}

# Compute routes for one placed RO (default: the first one) that stay inside its
# CLB + INT tile, and write them as constraint file ro_routes.tcl, which applies
# them as FIXED_ROUTE to EVERY RO. Needs a design with ro_place.tcl applied
# (Open Synthesized or Implemented Design); routing is not needed.
proc ro_make_routes {{ref_inst ""}} {
    global RO_NETS
    if {$ref_inst eq ""} { set ref_inst [lindex [ro_instances] 0] }
    set site [get_property LOC [get_cells $ref_inst/ff]]
    if {$site eq ""} { error "$ref_inst is not placed - is ro_place.tcl applied?" }
    set tiles [ro_local_tiles $site]

    set used [dict create]
    set routes {}
    foreach net $RO_NETS {
        lassign [ro_site_pins [get_nets $ref_inst/$net] $site] drv loads
        set root [ro_node_of $drv]
        set tree [dict create $root {}]
        foreach load $loads {
            set tree [ro_bfs $tree [ro_node_of $load] $tiles $used]
            if {$tree eq ""} { error "no local path for $net to $load" }
        }
        foreach n [dict keys $tree] { dict set used $n 1 }
        set route "\{ [ro_route_string $tree $root] \}"
        puts [format "  %-6s %s" $net $route]
        lappend routes $net $route
    }

    set out [file join [get_property DIRECTORY [current_project]] \
                 [current_project].srcs constrs_1 new ro_routes.tcl]
    file mkdir [file dirname $out]
    set f [open $out w]
    puts $f "# Generated by scripts/ro_tools.tcl (ro_make_routes) on [clock format [clock seconds]]"
    puts $f "# Computed for $ref_inst at $site; valid for any $::RO_SITE_TYPE of a $::RO_TILE_TYPE tile."
    puts $f "# Unmanaged constraint file, implementation only, read AFTER ro_place.tcl"
    puts $f "# (FIXED_ROUTE needs the cells already placed)."
    puts $f "# q is fixed only up to D6 (inside the CLB); the ro_out branch to user"
    puts $f "# logic is added by the router."
    puts $f ""
    puts $f "set RO_ROUTES \{"
    foreach {net route} $routes { puts $f "    $net {$route}" }
    puts $f "\}"
    puts $f ""
    puts $f {foreach inst [get_cells -hierarchical -quiet -filter {ORIG_REF_NAME == ro_cell || REF_NAME == ro_cell}] {
    if {[get_property LOC [get_cells $inst/ff]] eq ""} continue   ;# rejected by ro_place.tcl
    foreach {net route} $RO_ROUTES {
        set_property FIXED_ROUTE $route [get_nets $inst/$net]
    }
}}
    close $f
    puts "ro_make_routes: wrote $out"
}

# Path of the ROUTED net from its driver node to $goal, following the net's PIPs.
proc ro_routed_path {net goal} {
    set up [dict create]
    foreach pip [get_pips -quiet -of_objects $net] {
        dict set up [get_property NAME [get_nodes -downhill -of_objects $pip]] \
                    [get_property NAME [get_nodes -uphill -of_objects $pip]]
    }
    set path [list $goal]
    while {[dict exists $up [lindex $path 0]]} {
        set path [linsert $path 0 [dict get $up [lindex $path 0]]]
    }
    return $path
}

# For every RO and net: routed? fixed? path from driver to each load inside the
# slice uses only the RO's CLB + INT tile? same wires as the first RO?
proc ro_check {} {
    global RO_NETS
    set insts [ro_instances]
    if {[llength $insts] == 0} { error "no ro_cell instances in the open design" }
    set ref_sig {}
    set n_bad 0
    puts [format "%-16s %-15s %-17s %s" instance site tile result]
    foreach inst $insts {
        set site  [get_property LOC [get_cells $inst/ff]]
        set tiles [ro_local_tiles $site]
        set problems {}
        set sig {}
        foreach net $RO_NETS {
            set n [get_nets $inst/$net]
            if {[get_property ROUTE_STATUS $n] ne "ROUTED"} { lappend problems "$net [get_property ROUTE_STATUS $n]"; continue }
            if {![get_property IS_ROUTE_FIXED $n]} { lappend problems "$net not fixed" }
            lassign [ro_site_pins $n $site] drv loads
            foreach load $loads {
                set path [ro_routed_path $n [ro_node_of $load]]
                if {[lindex $path 0] ne [ro_node_of $drv]} { lappend problems "$net: no path to $load"; continue }
                foreach node $path {
                    if {![ro_is_local $node $tiles]} { lappend problems "$net leaves CLB via $node" }
                }
                lappend sig [regsub -all {[^ ]*/} $path {}]   ;# wire names only
            }
        }
        if {$ref_sig eq ""} { set ref_sig $sig } elseif {$sig ne $ref_sig} { lappend problems "routing differs from first RO" }
        if {[llength $problems]} { incr n_bad }
        puts [format "%-16s %-15s %-17s %s" $inst $site [lindex $tiles 0] \
                  [expr {[llength $problems] ? [join [lsort -unique $problems] ", "] : "OK"}]]
    }
    puts "ro_check: [llength $insts] RO(s), $n_bad with problems"
    return $n_bad
}
