// Top-level wrapper that routes the UART handshake logic into
// FPGA-accessible GPIO pins on the DE1-SoC board. The board's
// integrated USB-UART interface is connected to the HPS core on
// revision G0, so the FPGA fabric cannot see COM3 directly.  Use
// an external USB-to-UART dongle wired to the GPIO header pins
// assigned to serial_rx and serial_tx when compiling this design.
module de1_soc_uart_top (
    input  wire        CLOCK_50,
    input  wire        reset_n,
    input  wire        serial_rx,
    output wire        serial_tx,
    input  wire [2:0]  baud_select,
    output wire        tx_busy_led
);
  wire [7:0] rx_byte;
  wire       rx_byte_valid;
  wire [7:0] tx_byte;
  wire       tx_byte_valid;
  wire       tx_busy;

  uart_rx uart_rx_inst (
      .clk(CLOCK_50),
      .rst_n(reset_n),
      .baud_set(baud_select),
      .din(serial_rx),
      .rx_dout(rx_byte),
      .rx_vld(rx_byte_valid)
  );

  control control_inst (
      .clk(CLOCK_50),
      .rst_n(reset_n),
      .rx_din(rx_byte),
      .rx_vld(rx_byte_valid),
      .busy(tx_busy),
      .tx_din(tx_byte),
      .tx_vld(tx_byte_valid)
  );

  uart_tx uart_tx_inst (
      .clk(CLOCK_50),
      .rst_n(reset_n),
      .baud_set(baud_select),
      .tx_din(tx_byte),
      .tx_vld(tx_byte_valid),
      .tx_dout(serial_tx),
      .busy(tx_busy)
  );

  assign tx_busy_led = tx_busy;
endmodule
