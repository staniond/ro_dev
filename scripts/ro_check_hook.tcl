# ============================================================================
# impl_1 hook: STEPS.WRITE_BITSTREAM.TCL.PRE
#
# Runs automatically right before write_bitstream, on the routed design.
# Refuses to write a bitstream unless every RO is placed, has fixed routes
# that stay inside its CLB + switch matrix, and is routed identically to the
# others (see ro_check in ro_tools.tcl). Unlike an error in a constraint file,
# an error in a hook fails the run step.
# ============================================================================

source [file join [file dirname [info script]] ro_tools.tcl]

if {[ro_check] > 0} {
    error "ro_check_hook.tcl: ro_check found RO problems (table above in this log), no bitstream written"
}
