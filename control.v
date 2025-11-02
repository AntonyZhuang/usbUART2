module control
    (input clk,
     input rst_n,
     input [7 : 0] rx_din,
     input rx_vld,
     // 接受信号发送出去的有效标志
     input busy,

     output reg [7 : 0] tx_din,
     output reg tx_vld  //?为什么是reg
    );
  parameter SEND_BYTE = 8;  // FIFO中每存够8字节数据，就连续发送一次
  // 中间信号定义
  reg rdreq_sig;  //?
  wire [7 : 0] data_sig;
  wire wrreq_sig;
  wire empty_sig;
  wire full_sig;
  wire [7 : 0] q_sig;
  wire [7 : 0] usedw_sig;

  reg rdreq_sig_flag;  //?

  // rdreq_sig_flag  读请求标志
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rdreq_sig_flag <= 1'b0;
    end else if (usedw_sig >= SEND_BYTE) begin
      rdreq_sig_flag <= 1'b1;
    end else if (empty_sig) begin
      rdreq_sig_flag <= 1'b0;
    end
  end

  // rdreq_sig  读信号   (随时可以读 ，只要有数据进来且满足对应条件
  // 读请求标志拉高&& 非空 && busy为低电平)
  always @(*) begin
    if (rdreq_sig_flag && empty_sig == 1'b0 && busy == 1'b0) begin
      rdreq_sig <= 1'b1;
    end else begin
      rdreq_sig <= 1'b0;
    end
  end

  // tx_din

  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      tx_din <= 1'b0;
    end else begin
      tx_din <= q_sig;
    end
  end

  // tx_vld
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      tx_vld <= 1'b0;
    end else if (rdreq_sig) begin
      tx_vld <= 1'b1;
    end else begin
      tx_vld <= 1'b0;
    end
  end

  assign wrreq_sig = rx_vld &&
                     full_sig == 1'b0;  // 接受到有效数据的发送请求 && fifo没满
  assign data_sig = rx_din;

  fifo fifo_inst(.aclr(~rst_n),
                 // 高电平有效
                 .clock(clk),
                 .data(data_sig),
                 .rdreq(rdreq_sig),
                 .wrreq(wrreq_sig),
                 .empty(empty_sig),
                 .full(full_sig),
                 .q(q_sig),
                 .usedw(usedw_sig));
endmodule
