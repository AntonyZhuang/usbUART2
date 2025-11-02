
module uart_tx(
    input         clk,
    input         rst_n,
    input  [2:0]  baud_set,
    input  [7:0]  tx_din,    //发送数据(8bit)
    input         tx_vld,    //发送数据有效指示标志（发送请求）

    output  reg   tx_dout ,
    output   reg   busy    
);

//参数定义 每个波特率下计数器最大计数值
    localparam  BPS_115200 = 434,
                BPS_57600  = 868,
                BPS_38400  = 1302,
                BPS_19200  = 2604,
                BPS_9600   = 5208;

//中间信号    
    reg   [12:0]  cnt_bps;    //波特率计数器
    wire          add_cnt_bps;
    wire          end_cnt_bps;

    reg   [3:0]   cnt_bit;    //bit计数器   0-9
    wire          add_cnt_bit;
    wire          end_cnt_bit;

    reg          tx_flag;

    reg    [12:0] tx_bps;

    reg    [9:0]  tx_data_r;  //表示一帧的数据（10bit）

//tx_bps用组合逻辑做一个波特率选择器
    always @ (*)begin
        case(baud_set)
            0 : tx_bps = BPS_115200;
            1 : tx_bps = BPS_57600;
            2 : tx_bps = BPS_38400;
            3 : tx_bps = BPS_19200;
            4 : tx_bps = BPS_9600;
            default : tx_bps = BPS_115200;
        endcase
    end 



//cnt_bps 计数器
    always @ (posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            cnt_bps <= 0;
        end
        else if (add_cnt_bps)begin
            if(end_cnt_bps)
                cnt_bps <= 0;
            else 
                cnt_bps <= cnt_bps + 1;    
        end

    end

    assign add_cnt_bps = tx_flag ;
    assign end_cnt_bps = add_cnt_bps && cnt_bps == tx_bps - 1;


//cnt_bit 计数器
    always @(posedge clk or negedge rst_n)begin 
            if(!rst_n)begin
                cnt_bit <= 0;
            end 
            else if(add_cnt_bit)begin 
                if(end_cnt_bit)
                    cnt_bit <= 0;
                else   
                    cnt_bit <= cnt_bit + 1;  
            end 
    end
    assign add_cnt_bit = end_cnt_bps;
    assign end_cnt_bit = add_cnt_bit && cnt_bit == 10-1;


//tx_flag
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            tx_flag <= 1'b0;
        end
        else if(tx_vld)       //当有发送请求时，flag = 1; 
            tx_flag <= 1'b1;
        else if(end_cnt_bit)   //当10bit数据发送完的时候 tx_flag = 0;
            tx_flag <= 1'b0;
    end


//tx_dout
    //assign tx_data_r = tx_vld?{1'b1,tx_din,1'b0}:tx_data_r;
    always @(posedge clk or negedge rst_n)begin 
            if(!rst_n)begin
               tx_data_r <= 0;
            end 
            else if(tx_vld)begin 
                tx_data_r <= {1'b1,tx_din,1'b0};
            end 
    end

    always @(posedge clk or negedge rst_n)begin 
            if(!rst_n)begin
                tx_dout <= 1'b1;  //初始状态为高电平   ？原因:如果是低电平的话 ，当下一次发送数据时，就会误以为是起始位
            end 
            else if(tx_flag && cnt_bps == 2-1 )begin  //发送信号拉高且bps计数器开始计数时
                tx_dout <= tx_data_r[cnt_bit];
            end 
            else begin 
                tx_dout <= tx_dout;
            end 
    end

    /*always @(posedge clk or negedge rst_n)begin 
            if(!rst_n)begin
                busy <= 0;
            end 
            else if(tx_vld || tx_flag)begin 
                busy <= 1'b1;
            end 
            else begin 
                busy <= 0
            end 
    end*/
//busy
    always @(*)begin 
        if(tx_vld || tx_flag)begin 
            busy = 1'b1;
        end 
        else begin 
            busy = 0;
        end 
    end

endmodule
