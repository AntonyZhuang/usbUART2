module jtag_uart_top (
    input wire clk,
    input wire rst_n
);
  wire [7:0] rx_din;
  wire       rx_vld;
  wire [7:0] tx_din;
  wire       tx_vld;
  wire       busy;

  jtag_uart_bridge #(
      .FIFO_ADDR_WIDTH(6)
  ) bridge (
      .clk(clk),
      .rst_n(rst_n),
      .rx_din(rx_din),
      .rx_vld(rx_vld),
      .tx_din(tx_din),
      .tx_vld(tx_vld),
      .busy(busy)
  );

  control u_control (
      .clk(clk),
      .rst_n(rst_n),
      .rx_din(rx_din),
      .rx_vld(rx_vld),
      .busy(busy),
      .tx_din(tx_din),
      .tx_vld(tx_vld)
  );
endmodule
