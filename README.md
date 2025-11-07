# usbUART2 FPGA UART Reference

## JTAG-Based Top-Level for the DE1-SoC Board
Use `jtag_uart_top` as the Quartus top-level when targeting the DE1-SoC (5CSEMA5F31C6N). The module keeps the original `control`
logic but replaces the discrete serial pins with a virtual UART implemented over the USB-Blaster JTAG connection. No external
USB-to-TTL adapter is required on revision G0 boards—the existing USB-Blaster link handles configuration and byte transport.

```
clk      <-- CLOCK_50 (PIN_AF14)
rst_n    <-- KEY0 or another active-low reset source
JTAG     <-> Quartus via USB-Blaster
```

## Files to Add to Your Quartus Project
Add the following sources:

- `control.v`
- `fifo.v`
- `async_fifo.v`
- `jtag_uart_bridge.v`
- `jtag_uart_top.v`

Set the top-level entity to `jtag_uart_top`, assign the clock and reset pins, then compile and program the generated `.sof` via
JTAG as usual.

## How the Virtual UART Works
The bridge exposes a 16-bit data register on the JTAG scan chain. Each scan simultaneously returns FPGA-to-PC data and allows the
host to enqueue new bytes for the FPGA. The bit fields are:

| Bit(s) | Direction | Meaning |
| --- | --- | --- |
| 7:0 | FPGA→PC | Oldest byte waiting for the PC to read. Undefined when `valid` (bit 8) is 0. |
| 8 | FPGA→PC | `valid` – 1 when a byte is available for the PC. Clear it by issuing a read strobe (bit 9). |
| 9 | FPGA→PC | `host_ready` – 1 when the bridge can accept a new byte from the PC. |
| 10 | FPGA→PC | `pc_overflow` – sticky flag set if the PC tried to write while the FIFO was full. Clear with bit 10 in the host command. |
| 11 | FPGA→PC | `fpga_overflow` – sticky flag set if the FPGA tried to write while the return FIFO was full (should not occur when `busy` is observed). Clear with bit 11 in the host command. |
| 15:12 | FPGA→PC | Reserved, reads as 0. |

During the same scan the host shifts the command bits (LSB first):

| Bit(s) | Direction | Purpose |
| --- | --- | --- |
| 7:0 | PC→FPGA | Byte to push into the receive FIFO. Only accepted when bit 8 is 1. |
| 8 | PC→FPGA | `write_strobe` – assert to queue the byte in bits 7:0. |
| 9 | PC→FPGA | `read_strobe` – assert to drop the byte that was reported in the previous scan. |
| 10 | PC→FPGA | `clear_pc_overflow` – write 1 to clear bit 10 of the status word. |
| 11 | PC→FPGA | `clear_fpga_overflow` – write 1 to clear bit 11 of the status word. |
| 15:12 | PC→FPGA | Must be 0. |

The FIFO depth defaults to 64 bytes in each direction (`FIFO_ADDR_WIDTH = 6`) but can be tuned by changing the bridge parameter.

## Quick Start: Quartus Terminal (quartus_stp)
Once the FPGA is configured with `jtag_uart_top`, you can exchange bytes directly from a Quartus command prompt—no external
hardware or Python script required.

1. Open a **Quartus Prime Command Prompt** (Windows) or source the Quartus settings script on Linux so that `quartus_stp` is on
   your `PATH`. On Windows this is **not** the *Nios II Command Shell*—that launcher relies on WSL on recent Intel FPGA
   releases. Instead, search the Start menu for *Quartus Prime 23.x Command Prompt* (or similar) and run it; the prompt sets all
   required environment variables for the Quartus utilities.
2. Run the interactive console provided in this repository:
   ```sh
   quartus_stp -t scripts/jtag_uart_console.tcl
   ```
3. The console connects to the first USB-Blaster it finds and prints a small help menu. Useful commands include:
   - `status` – show the current bridge flags and the last byte returned by the FPGA.
   - `write <value>` – enqueue a byte for the FPGA (hex such as `0x55` or decimal like `85`).
   - `read` – fetch one byte if the FPGA has provided data.
   - `poll` – continuously print bytes as they arrive until you press **Ctrl+C**.
   - `clear` – clear any overflow indicators that may have latched.
   - `quit` – exit the console.

If you prefer to craft your own tooling, the Tcl script is short and demonstrates the scan sequence required by
`jtag_uart_bridge`.

### Windows fallback when the Quartus prompt is unavailable
If you cannot locate the Quartus Prime Command Prompt entry, you can invoke the tool manually from an ordinary Command
Prompt or PowerShell window. Replace `<quartus install>` with the directory where Quartus is installed (e.g.,
`C:\intelFPGA_lite\23.1std\quartus`):

```powershell
"<quartus install>\bin64\quartus_stp.exe" -t "<path to repo>\scripts\jtag_uart_console.tcl"
```

This direct invocation avoids the WSL requirement entirely; only the USB-Blaster driver needs to be installed.

## Example Quartus System Console Session
1. Launch System Console or run `quartus_stp` and open the USB-Blaster connection:
   ```tcl
   package require ::quartus::jtag
   set hw_name [lindex [get_hardware_names] 0]
   set device_name [lindex [get_device_names -hardware_name $hw_name] 0]
   open_device -hardware_name $hw_name -device_name $device_name
   set svc [virtual_jtag::open_service]
   ```
2. Define a helper procedure that performs a 16-bit scan (LSB first) and prints the status:
   ```tcl
   proc uart_scan {svc args} {
       array set opts {write 0 read 0 clear_pc 0 clear_fpga 0 byte 0}
       array set opts $args
       set tdi ""
       set value [expr {$opts(byte) & 0xFF}]
       for {set i 0} {$i < 8} {incr i} {append tdi [expr {($value >> $i) & 1}]}
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
       puts [format "status=0x%04X data=0x%02X valid=%d ready=%d" \
                 $result [expr {$result & 0xFF}] [expr {($result >> 8) & 1}] [expr {($result >> 9) & 1}]]
       return $result
   }
   ```
3. Poll for incoming data and acknowledge it:
   ```tcl
   set status [uart_scan $svc]
   if {[expr {($status >> 8) & 1}]} {
       # Consume the byte that was presented in the last scan
       set status [uart_scan $svc read 1]
   }
   ```
4. Transmit a byte to the FPGA when `ready` (bit 9) is 1:
   ```tcl
   set status [uart_scan $svc]
   if {[expr {($status >> 9) & 1}]} {
       uart_scan $svc write 1 byte 0x55
   }
   ```

You can wrap the helper procedure in a loop to build a small console or integrate it into a custom host tool. Because everything
rides on the USB-Blaster JTAG cable, the design works on revision G0 hardware without any additional serial accessories.
