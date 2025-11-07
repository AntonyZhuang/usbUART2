# Simple interactive console for the jtag_uart_bridge
# Usage: quartus_stp -t scripts/jtag_uart_console.tcl

package require ::quartus::jtag

proc open_virtual_uart {} {
    set hardware [lindex [get_hardware_names] 0]
    if {$hardware eq ""} {
        error "No USB-Blaster hardware detected. Check cable and drivers."
    }
    set device [lindex [get_device_names -hardware_name $hardware] 0]
    if {$device eq ""} {
        error "No JTAG device found on $hardware. Ensure the FPGA is powered and configured."
    }
    open_device -hardware_name $hardware -device_name $device
    set svc [virtual_jtag::open_service]
    return [list $hardware $device $svc]
}

proc uart_scan {svc args} {
    array set opts {byte 0 write 0 read 0 clear_pc 0 clear_fpga 0}
    array set opts $args

    set value [expr {$opts(byte) & 0xFF}]
    set tdi ""
    for {set i 0} {$i < 8} {incr i} {
        append tdi [expr {($value >> $i) & 1}]
    }
    append tdi [expr {$opts(write) & 1}]
    append tdi [expr {$opts(read) & 1}]
    append tdi [expr {$opts(clear_pc) & 1}]
    append tdi [expr {$opts(clear_fpga) & 1}]
    append tdi "0000"

    set tdo [virtual_jtag::shift_dr -instance_index 0 -length 16 -tdi $tdi]
    set result 0
    for {set i 15} {$i >= 0} {incr i -1} {
        set result [expr {(($result << 1) | ([string index $tdo $i] == "1")) & 0xFFFF}]
    }
    return $result
}

proc decode_status {status} {
    return [dict create \
        byte  [expr {$status & 0xFF}] \
        valid [expr {($status >> 8) & 1}] \
        ready [expr {($status >> 9) & 1}] \
        pc_overflow [expr {($status >> 10) & 1}] \
        fpga_overflow [expr {($status >> 11) & 1}] \
        raw   $status]
}

proc format_status {status} {
    dict with status {
        set msg [format "status=0x%04X data=0x%02X valid=%d ready=%d" $raw $byte $valid $ready]
        if {$pc_overflow} {append msg " pc_overflow"}
        if {$fpga_overflow} {append msg " fpga_overflow"}
        return $msg
    }
}

proc uart_try_read {svc} {
    set status [uart_scan $svc]
    set decoded [decode_status $status]
    if {[dict get $decoded valid]} {
        set byte [dict get $decoded byte]
        set post_status [decode_status [uart_scan $svc read 1]]
        return [list 1 $byte $post_status]
    }
    return [list 0 {} $decoded]
}

proc uart_try_write {svc byte} {
    set status [uart_scan $svc]
    set decoded [decode_status $status]
    if {![dict get $decoded ready]} {
        return [list 0 $decoded]
    }
    set post_status [decode_status [uart_scan $svc write 1 byte $byte]]
    return [list 1 $post_status]
}

proc print_help {} {
    puts "Commands:"
    puts "  status           - show bridge flags and last byte"
    puts "  read             - read one byte if available"
    puts "  write <0xHH|N>   - write a byte (hex or decimal)"
    puts "  poll             - loop, printing bytes as they arrive (Ctrl+C to exit)"
    puts "  clear            - clear overflow flags"
    puts "  help             - print this message"
    puts "  quit             - exit"
}

proc clear_overflow {svc} {
    set status [decode_status [uart_scan $svc clear_pc 1 clear_fpga 1]]
    return $status
}

proc poll_loop {svc} {
    puts "Polling for incoming data. Press Ctrl+C to stop."
    while {1} {
        set result [uart_try_read $svc]
        if {[lindex $result 0]} {
            set byte [lindex $result 1]
            puts [format "RX 0x%02X (%d)" $byte $byte]
        }
        after 50
    }
}

# Main entry point
set svc ""
if {[catch {open_virtual_uart} conn err]} {
    puts stderr $err
    exit 1
}
lassign $conn hardware device svc
puts "Connected to $hardware / $device"
print_help

while {1} {
    puts -nonewline "> "
    flush stdout
    if {[gets stdin line] < 0} {
        break
    }
    set line [string trim $line]
    if {$line eq ""} {
        continue
    }
    set parts [split $line]
    set cmd [string tolower [lindex $parts 0]]
    switch -- $cmd {
        status {
            puts [format_status [decode_status [uart_scan $svc]]]
        }
        read {
            set result [uart_try_read $svc]
            if {[lindex $result 0]} {
                set byte [lindex $result 1]
                puts [format "RX 0x%02X (%d)" $byte $byte]
            } else {
                puts "No data available"
            }
        }
        write {
            if {[llength $parts] < 2} {
                puts "Usage: write <byte>"
                continue
            }
            set value [string tolower [lindex $parts 1]]
            set ok 0
            if {[string match "0x*" $value]} {
                if {[scan $value %x byte] == 1} {set ok 1}
            } else {
                if {[scan $value %d byte] == 1} {set ok 1}
            }
            if {!$ok || $byte < 0 || $byte > 255} {
                puts "Byte must be between 0 and 255"
                continue
            }
            set result [uart_try_write $svc $byte]
            if {[lindex $result 0]} {
                puts [format "TX 0x%02X (%d)" $byte $byte]
            } else {
                puts [format "TX FIFO full (%s)" [format_status [lindex $result 1]]]
            }
        }
        poll {
            if {[catch {poll_loop $svc} err]} {
                if {$err ne ""} {
                    puts $err
                }
            }
        }
        clear {
            puts [format_status [clear_overflow $svc]]
        }
        help {
            print_help
        }
        quit - exit {
            break
        }
        default {
            puts "Unknown command '$cmd'. Type 'help'."
        }
    }
}

catch {virtual_jtag::close_service $svc}
catch {close_device}
