// Asynchronous FIFO with parameterizable width and depth.
module async_fifo #(
    parameter DATA_WIDTH = 8,
    parameter ADDR_WIDTH = 4
) (
    input  wire                  wr_clk,
    input  wire                  wr_rst_n,
    input  wire                  rd_clk,
    input  wire                  rd_rst_n,
    input  wire [DATA_WIDTH-1:0] din,
    input  wire                  wr_en,
    input  wire                  rd_en,
    output reg  [DATA_WIDTH-1:0] dout,
    output wire                  full,
    output wire                  empty
);
  localparam DEPTH = 1 << ADDR_WIDTH;

  reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];

  reg [ADDR_WIDTH:0] wr_ptr_bin;
  reg [ADDR_WIDTH:0] rd_ptr_bin;
  reg [ADDR_WIDTH:0] wr_ptr_gray;
  reg [ADDR_WIDTH:0] rd_ptr_gray;

  reg [ADDR_WIDTH:0] wr_ptr_gray_sync_rd[1:0];
  reg [ADDR_WIDTH:0] rd_ptr_gray_sync_wr[1:0];

  wire [ADDR_WIDTH:0] wr_ptr_bin_next;
  wire [ADDR_WIDTH:0] rd_ptr_bin_next;
  wire [ADDR_WIDTH:0] wr_ptr_gray_next;
  wire [ADDR_WIDTH:0] rd_ptr_gray_next;

  function [ADDR_WIDTH:0] bin_to_gray(input [ADDR_WIDTH:0] value);
    bin_to_gray = (value >> 1) ^ value;
  endfunction

  assign wr_ptr_bin_next = wr_ptr_bin + ((wr_en && !full) ? 1'b1 : 1'b0);
  assign rd_ptr_bin_next = rd_ptr_bin + ((rd_en && !empty) ? 1'b1 : 1'b0);

  assign wr_ptr_gray_next = bin_to_gray(wr_ptr_bin_next);
  assign rd_ptr_gray_next = bin_to_gray(rd_ptr_bin_next);

  // Write-side pointer and memory updates
  always @(posedge wr_clk or negedge wr_rst_n) begin
    if (!wr_rst_n) begin
      wr_ptr_bin  <= {ADDR_WIDTH+1{1'b0}};
      wr_ptr_gray <= {ADDR_WIDTH+1{1'b0}};
    end else begin
      if (wr_en && !full) begin
        mem[wr_ptr_bin[ADDR_WIDTH-1:0]] <= din;
        wr_ptr_bin <= wr_ptr_bin_next;
        wr_ptr_gray <= wr_ptr_gray_next;
      end else begin
        wr_ptr_bin <= wr_ptr_bin;
        wr_ptr_gray <= wr_ptr_gray;
      end
    end
  end

  // Read-side pointer and data output
  always @(posedge rd_clk or negedge rd_rst_n) begin
    if (!rd_rst_n) begin
      rd_ptr_bin  <= {ADDR_WIDTH+1{1'b0}};
      rd_ptr_gray <= {ADDR_WIDTH+1{1'b0}};
      dout <= {DATA_WIDTH{1'b0}};
    end else begin
      if (rd_en && !empty) begin
        rd_ptr_bin <= rd_ptr_bin_next;
        rd_ptr_gray <= rd_ptr_gray_next;
        dout <= mem[rd_ptr_bin_next[ADDR_WIDTH-1:0]];
      end
    end
  end

  // Pointer synchronization
  integer i;
  always @(posedge rd_clk or negedge rd_rst_n) begin
    if (!rd_rst_n) begin
      for (i = 0; i < 2; i = i + 1) begin
        wr_ptr_gray_sync_rd[i] <= {ADDR_WIDTH+1{1'b0}};
      end
    end else begin
      wr_ptr_gray_sync_rd[0] <= wr_ptr_gray;
      wr_ptr_gray_sync_rd[1] <= wr_ptr_gray_sync_rd[0];
    end
  end

  always @(posedge wr_clk or negedge wr_rst_n) begin
    if (!wr_rst_n) begin
      for (i = 0; i < 2; i = i + 1) begin
        rd_ptr_gray_sync_wr[i] <= {ADDR_WIDTH+1{1'b0}};
      end
    end else begin
      rd_ptr_gray_sync_wr[0] <= rd_ptr_gray;
      rd_ptr_gray_sync_wr[1] <= rd_ptr_gray_sync_wr[0];
    end
  end

  // Full and empty detection
  wire [ADDR_WIDTH:0] rd_ptr_gray_sync_wr_inverted =
      {~rd_ptr_gray_sync_wr[1][ADDR_WIDTH:ADDR_WIDTH-1], rd_ptr_gray_sync_wr[1][ADDR_WIDTH-2:0]};

  assign full  = (wr_ptr_gray_next == rd_ptr_gray_sync_wr_inverted);
  assign empty = (wr_ptr_gray_sync_rd[1] == rd_ptr_gray);
endmodule
