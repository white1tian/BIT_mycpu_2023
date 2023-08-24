`timescale 1ns / 1ps

module pc_reg(
    input wire  clk,
    input wire  rst,
    output  reg[`InstAddrBus]   pc,  //pc存指令地址，指令地址宽度为32比特，4字节；
                                    //pc会传送给指令ROM以取出指令。
    output  reg                 ce  //ce全程chip_enable芯片使能，决定了指令ROM能否被访问。
    );
    
    always @ (posedge clk) begin
        if (rst == `RstEnable) begin
            ce <=  `ChipDisable;    //复位时指令ROM芯片禁用
        end else begin 
            ce <= `ChipEnable;      
        end
    end
    
    always @ (posedge clk) begin
        if (ce ==  `ChipDisable) begin
            pc <=  32'h0000_0000;   //指令ROM芯片禁用时pc置为0
        end else begin 
            pc <= pc + 32'h4;   //每条MIPS指令都是等长的32位，4字节，故pc + 4
        end
    end
endmodule
