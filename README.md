# usbUART2 FPGA UART Reference

## Quartus Top-Level for the DE1-SoC Board
Use `de1_soc_uart_top` as the top-level entity when targeting the DE1-SoC (5CSEMA5F31C6N). It wraps the existing `control`, `uart_rx`, and `uart_tx` modules so the FPGA fabric can drive discrete GPIO pins for a USB-UART dongle.

```
serial_rx  <-- external USB-UART TXD
serial_tx  --> external USB-UART RXD
CLOCK_50   <-- DE1-SoC 50 MHz oscillator
reset_n    <-- push button or GPIO source (active-low)
baud_select[2:0] <-- slide switches to pick baud (000 = 115200)
tx_busy_led --> LED indicator wired to busy output
```

## Required Hardware Change on Revision G0
On the DE1-SoC revision G0 boards the onboard USB UART bridges only to the HPS. The FPGA fabric cannot see traffic that appears on COM3. Attach a USB-to-TTL converter to the GPIO or Arduino header pins you assign to `serial_rx` and `serial_tx` in Pin Planner. Tie the converter ground to the board ground.

Suggested assignments (verify with the DE1-SoC manual):

| Signal | Location | Notes |
| --- | --- | --- |
| `CLOCK_50` | `PIN_AF14` | Fixed 50 MHz clock input |
| `reset_n` | `PIN_AA14` | KEY0 push button, active-low |
| `serial_rx` | `GPIO_0[0]` (e.g., `PIN_AB12`) | Connect to USB-UART TXD |
| `serial_tx` | `GPIO_0[1]` (e.g., `PIN_AA12`) | Connect to USB-UART RXD |
| `baud_select[0]` | `SW0` (`PIN_AB28`) | Optional switch for baud control |
| `baud_select[1]` | `SW1` (`PIN_AC28`) | Optional |
| `baud_select[2]` | `SW2` (`PIN_AD28`) | Optional |
| `tx_busy_led` | `LED0` (`PIN_V16`) | Shows transmitter activity |

## Programming Flow
1. Add `control.v`, `fifo.v`, `uart_rx.v`, `uart_tx.v`, and `de1_soc_uart_top.v` to the Quartus project.
2. Set the top-level entity to `de1_soc_uart_top`.
3. Assign pins per the table above or your preferred wiring.
4. Compile and program via JTAG (.sof) using the USB-Blaster.
5. Connect the external USB-UART dongle to your PC and open the matching COM port at the baud rate selected on the board switches.

This setup bypasses the HPS-connected USB UART and lets the FPGA logic exchange serial data directly with the PC.
