module jtag_uart_bridge #(
    parameter FIFO_ADDR_WIDTH = 6
) (
    input  wire        clk,
    input  wire        rst_n,
    output reg  [7:0]  rx_din,
    output reg         rx_vld,
    input  wire [7:0]  tx_din,
    input  wire        tx_vld,
    output wire        busy
);
  localparam DR_WIDTH = 16;

  // Bridge FIFOs
  wire [7:0] to_host_dout;
  wire       to_host_full;
  wire       to_host_empty;
  reg        to_host_rd_en;

  wire [7:0] from_host_dout;
  wire       from_host_full;
  wire       from_host_empty;
  reg        from_host_rd_en;

  async_fifo #(
      .DATA_WIDTH(8),
      .ADDR_WIDTH(FIFO_ADDR_WIDTH)
  ) fifo_fpga_to_host (
      .wr_clk(clk),
      .wr_rst_n(rst_n),
      .rd_clk(tck),
      .rd_rst_n(rst_n),
      .din(tx_din),
      .wr_en(tx_vld && !to_host_full),
      .rd_en(to_host_rd_en),
      .dout(to_host_dout),
      .full(to_host_full),
      .empty(to_host_empty)
  );

  async_fifo #(
      .DATA_WIDTH(8),
      .ADDR_WIDTH(FIFO_ADDR_WIDTH)
  ) fifo_host_to_fpga (
      .wr_clk(tck),
      .wr_rst_n(rst_n),
      .rd_clk(clk),
      .rd_rst_n(rst_n),
      .din(from_host_wr_data),
      .wr_en(from_host_wr_en),
      .rd_en(from_host_rd_en),
      .dout(from_host_dout),
      .full(from_host_full),
      .empty(from_host_empty)
  );

  // Busy asserted when FPGA-to-host FIFO is full.
  assign busy = to_host_full;

  // Track overflow on FPGA-to-host writes.
  reg tx_overflow_flag_clk;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      tx_overflow_flag_clk <= 1'b0;
    end else begin
      if (tx_vld && to_host_full) begin
        tx_overflow_flag_clk <= 1'b1;
      end else if (clr_tx_overflow_clk) begin
        tx_overflow_flag_clk <= 1'b0;
      end
    end
  end

  // Synchronize tx_overflow flag into TCK domain and handshake clear requests back to clk domain.
  reg [1:0] tx_overflow_sync_tck;
  always @(posedge tck or negedge rst_n) begin
    if (!rst_n) begin
      tx_overflow_sync_tck <= 2'b00;
    end else begin
      tx_overflow_sync_tck <= {tx_overflow_sync_tck[0], tx_overflow_flag_clk};
    end
  end
  wire tx_overflow_flag_tck = tx_overflow_sync_tck[1];

  reg clr_tx_overflow_toggle_tck;
  reg clr_tx_overflow_toggle_clk_meta;
  reg clr_tx_overflow_toggle_clk;

  wire clr_tx_overflow_clk;

  always @(posedge tck or negedge rst_n) begin
    if (!rst_n) begin
      clr_tx_overflow_toggle_tck <= 1'b0;
    end else if (clr_tx_overflow_pulse) begin
      clr_tx_overflow_toggle_tck <= ~clr_tx_overflow_toggle_tck;
    end
  end

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      {clr_tx_overflow_toggle_clk_meta, clr_tx_overflow_toggle_clk} <= 2'b00;
    end else begin
      clr_tx_overflow_toggle_clk_meta <= clr_tx_overflow_toggle_tck;
      clr_tx_overflow_toggle_clk <= clr_tx_overflow_toggle_clk_meta;
    end
  end
  assign clr_tx_overflow_clk = clr_tx_overflow_toggle_clk ^ clr_tx_overflow_toggle_clk_meta;

  // Host overflow flag lives in TCK domain.
  reg host_overflow_flag;

  // Virtual JTAG wiring
  wire tck;
  wire tdi;
  wire tdo;
  wire vjtag_cdr;
  wire vjtag_sdr;
  wire vjtag_udr;

  sld_virtual_jtag #(
      .sld_auto_instance_index("YES"),
      .sld_instance_index(0),
      .sld_ir_width(1)
  ) virtual_uart (
      .tck(tck),
      .tdi(tdi),
      .tdo(tdo),
      .ir_in(),
      .ir_out(),
      .virtual_state_cdr(vjtag_cdr),
      .virtual_state_sdr(vjtag_sdr),
      .virtual_state_udr(vjtag_udr)
  );

  reg [DR_WIDTH-1:0] dr_shift;
  reg                 tdo_reg;
  reg [7:0]          tx_data_reg;
  reg                tx_data_valid;
  reg                load_pending;

  reg                host_write_pulse;
  reg                host_read_pulse;
  reg                clr_host_overflow_pulse;
  reg                clr_tx_overflow_pulse;
  reg [7:0]          host_write_data;

  reg                from_host_wr_en;
  reg [7:0]          from_host_wr_data;

  wire               host_can_write = ~from_host_full;

  // Capture status for host
  wire [DR_WIDTH-1:0] capture_value = {4'd0, tx_overflow_flag_tck, host_overflow_flag, host_can_write, tx_data_valid, tx_data_reg};

  // Shift register handling
  always @(posedge tck or negedge rst_n) begin
    if (!rst_n) begin
      dr_shift <= {DR_WIDTH{1'b0}};
      tdo_reg  <= 1'b0;
    end else begin
      if (vjtag_cdr) begin
        dr_shift <= capture_value;
        tdo_reg  <= capture_value[0];
      end else if (vjtag_sdr) begin
        tdo_reg  <= dr_shift[0];
        dr_shift <= {tdi, dr_shift[DR_WIDTH-1:1]};
      end
    end
  end
  assign tdo = tdo_reg;

  // Decode Update-DR contents
  always @(posedge tck or negedge rst_n) begin
    if (!rst_n) begin
      host_write_pulse       <= 1'b0;
      host_read_pulse        <= 1'b0;
      clr_host_overflow_pulse <= 1'b0;
      clr_tx_overflow_pulse  <= 1'b0;
      host_write_data        <= 8'h00;
    end else begin
      host_write_pulse        <= 1'b0;
      host_read_pulse         <= 1'b0;
      clr_host_overflow_pulse <= 1'b0;
      clr_tx_overflow_pulse   <= 1'b0;
      if (vjtag_udr) begin
        host_write_pulse        <= dr_shift[8];
        host_read_pulse         <= dr_shift[9];
        clr_host_overflow_pulse <= dr_shift[10];
        clr_tx_overflow_pulse   <= dr_shift[11];
        host_write_data         <= dr_shift[7:0];
      end
    end
  end

  // Manage host-to-FPGA FIFO writes and overflow reporting
  always @(posedge tck or negedge rst_n) begin
    if (!rst_n) begin
      from_host_wr_en  <= 1'b0;
      from_host_wr_data <= 8'h00;
      host_overflow_flag <= 1'b0;
    end else begin
      from_host_wr_en <= 1'b0;
      if (host_write_pulse) begin
        if (!from_host_full) begin
          from_host_wr_en  <= 1'b1;
          from_host_wr_data <= host_write_data;
        end else begin
          host_overflow_flag <= 1'b1;
        end
      end
      if (clr_host_overflow_pulse) begin
        host_overflow_flag <= 1'b0;
      end
    end
  end

  // Manage FPGA-to-host FIFO reads
  always @(posedge tck or negedge rst_n) begin
    if (!rst_n) begin
      to_host_rd_en <= 1'b0;
      load_pending  <= 1'b0;
      tx_data_valid <= 1'b0;
      tx_data_reg   <= 8'h00;
    end else begin
      to_host_rd_en <= 1'b0;
      if (host_read_pulse && tx_data_valid) begin
        tx_data_valid <= 1'b0;
      end
      if (!tx_data_valid && !load_pending && !to_host_empty) begin
        to_host_rd_en <= 1'b1;
        load_pending  <= 1'b1;
      end else if (load_pending) begin
        tx_data_reg   <= to_host_dout;
        tx_data_valid <= 1'b1;
        load_pending  <= 1'b0;
      end
    end
  end

  // Bring host read request into clock domain to pop bytes for the control block
  reg from_host_rd_en_d;
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      from_host_rd_en   <= 1'b0;
      from_host_rd_en_d <= 1'b0;
      rx_vld            <= 1'b0;
      rx_din            <= 8'h00;
    end else begin
      from_host_rd_en_d <= from_host_rd_en;
      rx_vld            <= 1'b0;
      if (!from_host_rd_en && !from_host_empty) begin
        from_host_rd_en <= 1'b1;
      end else begin
        from_host_rd_en <= 1'b0;
      end
      if (from_host_rd_en_d) begin
        rx_din <= from_host_dout;
        rx_vld <= 1'b1;
      end
    end
  end
endmodule
