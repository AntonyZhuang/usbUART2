module uart_rx( 
   input                clk,
   input                rst_n,
   input  [2:0]         baud_set,
   input                din, //串行的输入数据

   output  reg [7:0]    rx_dout,   //8bit接收数据输出
   output  reg          rx_vld    //接收数据输出有效

);		

//参数定义 每个波特率下计数器最大计数值
localparam  BPS_115200 = 434,
            BPS_57600  = 868,
            BPS_38400  = 1302,
            BPS_19200  = 2604,
            BPS_9600   = 5208;
//中间信号    

reg   [12:0]      cnt_bps;
wire              add_cnt_bps;
wire              end_cnt_bps;

reg   [9:0]       cnt_bit;
wire              add_cnt_bit;
wire              end_cnt_bit;

reg  [12:0]       rx_bps;   //

reg  [9:0]       rx_data_r;   //接受一帧数据（起始位，数据位，停止位）

reg               din_r0; //同步
reg               din_r1; //打拍
reg               din_r2;

wire              nedge;

reg              rx_flag;


always @(*)begin
   case(baud_set)
      0:rx_bps = BPS_115200;
      1:rx_bps = BPS_57600;
      2:rx_bps = BPS_38400;
      3:rx_bps = BPS_19200;
      4:rx_bps = BPS_9600;
      default : rx_bps = BPS_115200;
   endcase
end


//cnt_bps 计数器
always @(posedge clk or negedge rst_n)begin 
   if(!rst_n)begin
      cnt_bps <= 0;
   end 
   else if(add_cnt_bps)begin 
      if(end_cnt_bps)begin 
         cnt_bps <= 0;
      end
      else begin 
         cnt_bps <= cnt_bps + 1;
      end 
   end
end 
assign add_cnt_bps = rx_flag  ;
assign end_cnt_bps = add_cnt_bps && cnt_bps == rx_bps -1 ;

//同步   打拍
always @(posedge clk or negedge rst_n)begin
   if (!rst_n)begin
      din_r0 <= 1'b1;
      din_r1 <= 1'b1;
   end
   else begin
      din_r0 <= din;
      din_r1 <= din_r0;   //打拍
      din_r2 <= din_r1;

   end
end

//检测到下降沿
assign nedge = ~din_r1 & din_r2;

//rx_flag 
always @(posedge clk or negedge rst_n)begin 
      if(!rst_n)begin
          rx_flag <= 1'b0;
      end 
      else if(nedge && rx_flag == 1'b0 )begin 
         rx_flag <= 1'b1; 
      end 
      else if(end_cnt_bit && rx_flag == 1'b1)begin
         rx_flag <= 1'b0;
      end 
end


//cnt_bit 计数器
always @(posedge clk or negedge rst_n)begin 
   if(!rst_n)begin
       cnt_bit <= 0;
   end 
   else if(add_cnt_bit)begin 
      if(end_cnt_bit)begin 
         cnt_bit <= 0;
      end
      else begin 
         cnt_bit <= cnt_bit + 1;
      end 
   end
end 
assign add_cnt_bit = end_cnt_bps;
assign end_cnt_bit = add_cnt_bit && (cnt_bit == 10-1 || rx_data_r[0]);

//rx_data_r 
always @(posedge clk or negedge rst_n)begin
    if(!rst_n) begin
      rx_data_r <= 0;
    end
    else if (rx_flag &&  cnt_bps == (cnt_bps>>1 ))begin
       rx_data_r[cnt_bit] <= din ;
    end
end

//rx_dout
always @(posedge clk or negedge rst_n) begin
   if(!rst_n) begin
      rx_dout <= 0;
   end
   else if (end_cnt_bit)begin
      rx_dout <= rx_data_r[8:1] ;
   end
end

//rx_vld
   always @(posedge clk or negedge rst_n) begin
      if(!rst_n)begin
         rx_vld <= 1'b0;
      end
      else if (end_cnt_bit)begin
         rx_vld <= 1'b1;
      end
      else  begin
         rx_vld <= 1'b0;
      end
   end
                        
endmodule
