module fifo #(
    parameter DATA_WIDTH = 8,
    parameter ADDR_WIDTH = 8
) (
    input wire aclr,
    input wire clock,
    input wire [DATA_WIDTH-1:0] data,
    input wire rdreq,
    input wire wrreq,
    output wire empty,
    output wire full,
    output wire [DATA_WIDTH-1:0] q,
    output wire [ADDR_WIDTH-1:0] usedw
);
  localparam DEPTH = 1 << ADDR_WIDTH;

  reg [DATA_WIDTH-1:0] fifo_mem [0:DEPTH-1];
  reg [ADDR_WIDTH-1:0] rd_ptr;
  reg [ADDR_WIDTH-1:0] wr_ptr;
  reg [ADDR_WIDTH:0] usedw_reg;
  reg [DATA_WIDTH-1:0] q_reg;

  wire read_en = rdreq && (usedw_reg != 0);
  wire write_en = wrreq && (usedw_reg != DEPTH);

  assign empty = (usedw_reg == 0);
  assign full = (usedw_reg == DEPTH);
  assign usedw = usedw_reg[ADDR_WIDTH-1:0];
  assign q = q_reg;

  always @(posedge clock or posedge aclr) begin
    if (aclr) begin
      rd_ptr <= {ADDR_WIDTH{1'b0}};
      wr_ptr <= {ADDR_WIDTH{1'b0}};
      usedw_reg <= {(ADDR_WIDTH+1){1'b0}};
      q_reg <= {DATA_WIDTH{1'b0}};
    end else begin
      if (write_en) begin
        fifo_mem[wr_ptr] <= data;
        wr_ptr <= wr_ptr + 1'b1;
      end
      if (read_en) begin
        q_reg <= fifo_mem[rd_ptr];
        rd_ptr <= rd_ptr + 1'b1;
      end
      case ({write_en, read_en})
        2'b10: usedw_reg <= usedw_reg + 1'b1;
        2'b01: usedw_reg <= usedw_reg - 1'b1;
        default: usedw_reg <= usedw_reg;
      endcase
    end
  end
endmodule
