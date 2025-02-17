`timescale 1ns / 1ps

//id段负责分析指令，依据指令特征字段区分指令，确定要读取的寄存器情况、要执行的运算、要写入的目的寄存器
//suffix中，_i表示输入，_o表示输出
module id(
    input   wire    rst,
    input   wire[`InstAddrBus]  pc_i,       //输入被译码的指令在指令ROM中的地址
    input   wire[`InstBus]      inst_i,     //输入被译码的指令
    
    //读取的Regfile的值
    input   wire[`RegBus]       reg1_data_i,    //输入寄存器堆读端口1的数据
    input   wire[`RegBus]       reg2_data_i,    //输入寄存器堆读端口2的数据
    
    //输出到Regfile的值
    output  reg                 reg1_read_o,    //输出寄存器堆读端口1的使能信号
    output  reg                 reg2_read_o,    //输出寄存器堆读端口2的使能信号
    output  reg[`RegAddrBus]    reg1_addr_o,    //输出寄存器堆读端口1的读地址
    output  reg[`RegAddrBus]    reg2_addr_o,    //输出寄存器堆读端口2的读地址
    
    //送到EX段的信息
    output  reg[`AluOpBus]      aluop_o,    //输出运算子类型
    output  reg[`AluSelBus]     alusel_o,   //输出运算类型
    output  reg[`RegBus]        reg1_o,     //输出源操作数1，ALU的两个输入之一
    output  reg[`RegBus]        reg2_o,     //输出源操作数2，ALU的两个输入之一
    output  reg                 wreg_o,     //输出写寄存器使能信号
    output  reg[`RegAddrBus]    wDestRegAddr_o,  //输出写寄存器地址
    
    
//为了解决数据相关（只会出现写后读数据相关），建立数据旁路，将ex段和mem段的待写回数据直接传到id段
    //1.ex段传回数据可以解决相邻指令的数据相关；
    input   wire                ex_wreg_i,
    input   wire[`RegAddrBus]   ex_wDestRegAddr_i,
    input   wire[`RegBus]       ex_wdata_i,
    //2.mem段传回数据可以解决相隔一条指令的数据相关
    input   wire                mem_wreg_i,
    input   wire[`RegAddrBus]   mem_wDestRegAddr_i,
    input   wire[`RegBus]       mem_wdata_i,
    
    //指令跳转
    output  reg                     branch_flag_o,
    output  reg[`InstAddrBus]       branch_target_addr_o,
    output  reg                     in_delayslot_o,
    output  reg                     next_inst_in_delayslot_o,
    input   wire                    in_delayslot_i
    
    );
    
     //取指令的指令码和功能码
    wire[5:0]   op = inst_i[31:26];     //指令码
    wire[4:0]   op2 = inst_i[10:6];     //移位位数
    wire[5:0]   op3 = inst_i[5:0];      //功能码
    wire[4:0]   op4 = inst_i[20:16];
    
    //如果是I指令，需要存指令中的立即数
    reg[`RegBus]    imm;
    
    //
    wire[`RegBus] pc_plus_4;
    assign pc_plus_4 = pc_i + 4;//保存该pc下一条指令的地址
    
    reg instValid;  //指令是否有效    
    
// ************************************ 一.指令译码 ************************************************************************
    always @ (*) begin
        if (rst == `RstEnable) begin
            aluop_o <= `EXE_NOP_OP;
            alusel_o <= `EXE_RES_NOP;
            wDestRegAddr_o <= `NOPRegAddr;
            wreg_o  <= `WriteDisable;
            instValid <= `InstValid;
            reg1_read_o <= 1'b0;
            reg2_read_o <= 1'b0;
            reg1_addr_o <= `NOPRegAddr;
            reg2_addr_o <= `NOPRegAddr;
            imm <= 32'h0;
            
            branch_flag_o <= 0;
            branch_target_addr_o <= 0;
            next_inst_in_delayslot_o <= 0;
        end else begin
            aluop_o <= `EXE_NOP_OP;
            alusel_o <= `EXE_RES_NOP;
            wDestRegAddr_o <= inst_i[15:11];//写地址
            wreg_o  <= `WriteDisable;   //是否写寄存器还需要看具体的指令内容
            instValid <= `InstInvalid;
            reg1_read_o <= 1'b0;
            reg2_read_o <= 1'b0;
            reg1_addr_o <= inst_i[25:21];
            reg2_addr_o <= inst_i[20:16];
            imm <= 32'h0;
            
            branch_flag_o <= 0;
            branch_target_addr_o <= 0;
            next_inst_in_delayslot_o <= 0;
            case (op)
                `EXE_J:   begin
                    wreg_o <= `WriteDisable;         //不需要写寄存器
                    aluop_o <= `EXE_J_OP;         //运算
                    alusel_o <= `EXE_RES_JUMP;     //运算类型
                    reg1_read_o <= 1'b0;            //不需要读端口1
                    reg2_read_o <= 1'b0;            //不需要读端口2
                    instValid <= `InstValid;
                    if (in_delayslot_i == 0) begin  //避免有两条连续跳转指令
                        branch_flag_o <= 1;
                    end
                    branch_target_addr_o <= { pc_plus_4[31:28] , inst_i[25:0] , 2'b00 };
                    next_inst_in_delayslot_o <= 1;
                         
                end
                `EXE_ANDI:   begin
                    wreg_o <= `WriteEnable;         //需要写寄存器
                    aluop_o <= `EXE_AND_OP;         //逻辑与运算
                    alusel_o <= `EXE_RES_LOGIC;     //逻辑运算类型
                    reg1_read_o <= 1'b1;            //需要读端口1
                    reg2_read_o <= 1'b0;            //不需要读端口2
                    imm <= {16'h0,inst_i[15:0]};    //i指令，取立即数，并将立即数扩展到32位
                    wDestRegAddr_o <= inst_i[20:16];    //得到写寄存器地址
                    instValid <= `InstValid;
                end
                `EXE_ORI:   begin
                    wreg_o <= `WriteEnable;         //需要写寄存器
                    aluop_o <= `EXE_OR_OP;          //逻辑或运算
                    alusel_o <= `EXE_RES_LOGIC;     //逻辑运算类型
                    reg1_read_o <= 1'b1;            //需要读端口1
                    reg2_read_o <= 1'b0;            //不需要读端口2
                    imm <= {16'h0,inst_i[15:0]};    //i指令，取立即数，并将立即数扩展到32位
                    wDestRegAddr_o <= inst_i[20:16];    //得到写寄存器地址
                    instValid <= `InstValid;
                end
                `EXE_ANDI:   begin
                    wreg_o <= `WriteEnable;         //需要写寄存器
                    aluop_o <= `EXE_AND_OP;         //逻辑与运算
                    alusel_o <= `EXE_RES_LOGIC;     //逻辑运算类型
                    reg1_read_o <= 1'b1;            //需要读端口1
                    reg2_read_o <= 1'b0;            //不需要读端口2
                    imm <= {16'h0,inst_i[15:0]};    //i指令，取立即数，并将立即数扩展到32位
                    wDestRegAddr_o <= inst_i[20:16];    //得到写寄存器地址
                    instValid <= `InstValid;
                end
                `EXE_XORI:   begin
                    wreg_o <= `WriteEnable;         //需要写寄存器
                    aluop_o <= `EXE_XOR_OP;         //逻辑异或运算
                    alusel_o <= `EXE_RES_LOGIC;     //逻辑运算类型
                    reg1_read_o <= 1'b1;            //需要读端口1
                    reg2_read_o <= 1'b0;            //不需要读端口2
                    imm <= {16'h0,inst_i[15:0]};    //i指令，取立即数，并将立即数扩展到32位
                    wDestRegAddr_o <= inst_i[20:16];    //得到写寄存器地址
                    instValid <= `InstValid;
                end
               `EXE_LUI:   begin
                    wreg_o <= `WriteEnable;         //需要写寄存器
                    aluop_o <= `EXE_OR_OP;          //逻辑或运算（需要保证值不变，故将取出的扩展立即数与0进行或运算）
                    alusel_o <= `EXE_RES_LOGIC;     //逻辑运算类型
                    reg1_read_o <= 1'b1;            //需要读端口1（恒为$0)
                    reg2_read_o <= 1'b0;            //不需要读端口2
                    imm <= {inst_i[15:0],16'h0};    //取立即数，高16位为imm，低16位补0，将此数据写回寄存器即可
                    wDestRegAddr_o <= inst_i[20:16];    //得到写寄存器地址
                    instValid <= `InstValid;
                end
                `EXE_SPECIAL_INST:   begin  //special类指令
                    case (op2)      //根据sa判断指令类型
                        5'b00000:   begin    
                            case(op3)       //根据func判断指令类型
                                `EXE_OR:    begin
                                    wreg_o <= `WriteEnable;         //需要写寄存器
                                    aluop_o <= `EXE_OR_OP;          //逻辑或运算
                                    alusel_o <= `EXE_RES_LOGIC;     //逻辑运算类型
                                    reg1_read_o <= 1'b1;            //需要读端口1
                                    reg2_read_o <= 1'b1;            //需要读端口2
                                    wDestRegAddr_o <= inst_i[15:11];    //得到写寄存器地址
                                    instValid <= `InstValid;
                                end
                                `EXE_AND:    begin
                                    wreg_o <= `WriteEnable;         //需要写寄存器
                                    aluop_o <= `EXE_AND_OP;          //逻辑或运算
                                    alusel_o <= `EXE_RES_LOGIC;     //逻辑运算类型
                                    reg1_read_o <= 1'b1;            //需要读端口1
                                    reg2_read_o <= 1'b1;            //需要读端口2
                                    wDestRegAddr_o <= inst_i[15:11];    //得到写寄存器地址
                                    instValid <= `InstValid;
                                end
                                `EXE_XOR:    begin
                                    wreg_o <= `WriteEnable;         //需要写寄存器
                                    aluop_o <= `EXE_XOR_OP;          //逻辑或运算
                                    alusel_o <= `EXE_RES_LOGIC;     //逻辑运算类型
                                    reg1_read_o <= 1'b1;            //需要读端口1
                                    reg2_read_o <= 1'b1;            //需要读端口2
                                    wDestRegAddr_o <= inst_i[15:11];    //得到写寄存器地址
                                    instValid <= `InstValid;
                                end
                                `EXE_NOR:    begin
                                    wreg_o <= `WriteEnable;         //需要写寄存器
                                    aluop_o <= `EXE_NOR_OP;          //逻辑或运算
                                    alusel_o <= `EXE_RES_LOGIC;     //逻辑运算类型
                                    reg1_read_o <= 1'b1;            //需要读端口1
                                    reg2_read_o <= 1'b1;            //需要读端口2
                                    wDestRegAddr_o <= inst_i[15:11];    //得到写寄存器地址
                                    instValid <= `InstValid;
                                end
                                `EXE_SLLV:    begin
                                    wreg_o <= `WriteEnable;         //需要写寄存器
                                    aluop_o <= `EXE_SLL_OP;          //左移运算
                                    alusel_o <= `EXE_RES_SHIFT;     //移位运算
                                    reg1_read_o <= 1'b1;            //需要读端口1
                                    reg2_read_o <= 1'b1;            //需要读端口2
                                    wDestRegAddr_o <= inst_i[15:11];    //得到写寄存器地址
                                    instValid <= `InstValid;
                                end
                                `EXE_SRLV:    begin
                                    wreg_o <= `WriteEnable;         //需要写寄存器
                                    aluop_o <= `EXE_SRL_OP;          //逻辑右移运算
                                    alusel_o <= `EXE_RES_SHIFT;     //移位运算
                                    reg1_read_o <= 1'b1;            //需要读端口1
                                    reg2_read_o <= 1'b1;            //需要读端口2
                                    wDestRegAddr_o <= inst_i[15:11];    //得到写寄存器地址
                                    instValid <= `InstValid;
                                end
                                `EXE_SRAV:    begin
                                    wreg_o <= `WriteEnable;         //需要写寄存器
                                    aluop_o <= `EXE_SRA_OP;          //算术右移运算
                                    alusel_o <= `EXE_RES_SHIFT;     //移位运算
                                    reg1_read_o <= 1'b1;            //需要读端口1
                                    reg2_read_o <= 1'b1;            //需要读端口2
                                    wDestRegAddr_o <= inst_i[15:11];    //得到写寄存器地址
                                    instValid <= `InstValid;
                                end
                                `EXE_ADD:    begin
                                    wreg_o <= `WriteEnable;         //需要写寄存器
                                    aluop_o <= `EXE_ADD_OP;          //有符号加运算
                                    alusel_o <= `EXE_RES_ARITHMETIC;     //算术运算
                                    reg1_read_o <= 1'b1;            //需要读端口1
                                    reg2_read_o <= 1'b1;            //需要读端口2
                                    wDestRegAddr_o <= inst_i[15:11];    //得到写寄存器地址
                                    instValid <= `InstValid;
                                end
                                `EXE_ADDU:    begin
                                    wreg_o <= `WriteEnable;         //需要写寄存器
                                    aluop_o <= `EXE_ADDU_OP;          //无符号加运算
                                    alusel_o <= `EXE_RES_ARITHMETIC;     //算术运算
                                    reg1_read_o <= 1'b1;            //需要读端口1
                                    reg2_read_o <= 1'b1;            //需要读端口2
                                    wDestRegAddr_o <= inst_i[15:11];    //得到写寄存器地址
                                    instValid <= `InstValid;
                                end
                                `EXE_SUB:    begin
                                    wreg_o <= `WriteEnable;         //需要写寄存器
                                    aluop_o <= `EXE_SUB_OP;          //有符号减运算
                                    alusel_o <= `EXE_RES_ARITHMETIC;     //算术运算
                                    reg1_read_o <= 1'b1;            //需要读端口1
                                    reg2_read_o <= 1'b1;            //需要读端口2
                                    wDestRegAddr_o <= inst_i[15:11];    //得到写寄存器地址
                                    instValid <= `InstValid;
                                end
                                `EXE_SUBU:    begin
                                    wreg_o <= `WriteEnable;         //需要写寄存器
                                    aluop_o <= `EXE_SUBU_OP;          //无符号减运算
                                    alusel_o <= `EXE_RES_ARITHMETIC;     //算术运算
                                    reg1_read_o <= 1'b1;            //需要读端口1
                                    reg2_read_o <= 1'b1;            //需要读端口2
                                    wDestRegAddr_o <= inst_i[15:11];    //得到写寄存器地址
                                    instValid <= `InstValid;
                                end
                                `EXE_SLT:    begin
                                    wreg_o <= `WriteEnable;         //需要写寄存器
                                    aluop_o <= `EXE_SLT_OP;          //有符号比较运算
                                    alusel_o <= `EXE_RES_ARITHMETIC;     //算术运算
                                    reg1_read_o <= 1'b1;            //需要读端口1
                                    reg2_read_o <= 1'b1;            //需要读端口2
                                    wDestRegAddr_o <= inst_i[15:11];    //得到写寄存器地址
                                    instValid <= `InstValid;
                                end
                                `EXE_SLTU:    begin
                                    wreg_o <= `WriteEnable;         //需要写寄存器
                                    aluop_o <= `EXE_SLTU_OP;          //无符号比较运算
                                    alusel_o <= `EXE_RES_ARITHMETIC;     //算术运算
                                    reg1_read_o <= 1'b1;            //需要读端口1
                                    reg2_read_o <= 1'b1;            //需要读端口2
                                    wDestRegAddr_o <= inst_i[15:11];    //得到写寄存器地址
                                    instValid <= `InstValid;
                                end
                                
                                
                                default:    begin
                                end
                            endcase // case func
                        end
                        default:    begin
                        end
                   endcase  // case sa
                end // op = special
                default:    begin
                end
            endcase // case op
            
            if(inst_i[31:21] == 11'b000000_00000)   begin
                if(op3 == `EXE_SLL) begin
                    wreg_o <= `WriteEnable;         //需要写寄存器
                    aluop_o <= `EXE_SLL_OP;          //左移运算
                    alusel_o <= `EXE_RES_SHIFT;     //移位运算
                    reg1_read_o <= 1'b0;            //不需要读端口1
                    reg2_read_o <= 1'b1;            //需要读端口2
                    imm <= { 27'b0 , inst_i[10:6] };    //取sa存到立即数后五位中
                    wDestRegAddr_o <= inst_i[15:11];    //得到写寄存器地址
                    instValid <= `InstValid;
                end else if (op3 == `EXE_SRL)   begin
                    wreg_o <= `WriteEnable;         //需要写寄存器
                    aluop_o <= `EXE_SRL_OP;          //逻辑右移运算
                    alusel_o <= `EXE_RES_SHIFT;     //移位运算
                    reg1_read_o <= 1'b0;            //不需要读端口1
                    reg2_read_o <= 1'b1;            //需要读端口2
                    imm <= { 27'b0 , inst_i[10:6] };    //取sa存到立即数后五位中
                    wDestRegAddr_o <= inst_i[15:11];    //得到写寄存器地址
                    instValid <= `InstValid;
                end else if (op3 == `EXE_SRA)   begin
                    wreg_o <= `WriteEnable;         //需要写寄存器
                    aluop_o <= `EXE_SRA_OP;          //算术右移运算
                    alusel_o <= `EXE_RES_SHIFT;     //
                    reg1_read_o <= 1'b0;            //不需要读端口1
                    reg2_read_o <= 1'b1;            //需要读端口2
                    imm <= { 27'b0 , inst_i[10:6] };    //取sa存到立即数后五位中
                    wDestRegAddr_o <= inst_i[15:11];    //得到写寄存器地址
                    instValid <= `InstValid;
                end
            end 
            
        end //if
    end //always 
    
    
// ************************************ 二.确定源操作数1 ************************************************************************
    always @ (*) begin 
        if(rst == `RstEnable) begin
            reg1_o <= 32'h0;
        //数据冒险判断如下，注意判断顺序，先要判断离id段最近的ex段，再判断mem段，如果顺序错误可能导致取到脏数据
        end else if((reg1_read_o == 1'b1) && (ex_wreg_i == 1'b1) && (ex_wDestRegAddr_i == reg1_addr_o)) begin//如果上条指令修改了本条指令要读的寄存器
            reg1_o <= ex_wdata_i;
        end else if((reg1_read_o == 1'b1) && (mem_wreg_i == 1'b1) && (mem_wDestRegAddr_i == reg1_addr_o)) begin//如果上上条指令修改了本条指令要读的寄存器
            reg1_o <= mem_wdata_i;
        /////////////////////////////////////////////////////////////////////////////////////
        end else if(reg1_read_o == 1'b1) begin
            reg1_o <= reg1_data_i;
        end else if(reg1_read_o == 1'b0) begin
            reg1_o <= imm;
        end else begin
            reg1_o <= 32'h0;
        end
    end
    
// ************************************ 三.确定源操作数2 ************************************************************************
    always @ (*) begin 
        if(rst == `RstEnable) begin
            reg2_o <= 32'h0;
        //数据冒险判断如下，注意判断顺序，先要判断离id段最近的ex段，再判断mem段，如果顺序错误可能导致取到脏数据
        end else if((reg2_read_o == 1'b1) && (ex_wreg_i == 1'b1) && (ex_wDestRegAddr_i == reg2_addr_o)) begin//如果上条指令修改了本条指令要读的寄存器
            reg2_o <= ex_wdata_i;
        end else if((reg2_read_o == 1'b1) && (mem_wreg_i == 1'b1) && (mem_wDestRegAddr_i == reg2_addr_o)) begin//如果上上条指令修改了本条指令要读的寄存器
            reg2_o <= mem_wdata_i;
        /////////////////////////////////////////////////////////////////////////////////////
        end else if(reg2_read_o == 1'b1) begin
            reg2_o <= reg2_data_i;
        end else if(reg2_read_o == 1'b0) begin
            reg2_o <= imm;
        end else begin
            reg2_o <= 32'h0;
        end
    end 
    
// ************************************ 四.告诉后续流水段此指令是否为延迟槽指令 ************************************************************************
    always @ (*) begin 
        if(rst == `RstEnable) begin
            in_delayslot_o <= 0;
        end else begin
            in_delayslot_o <= in_delayslot_i;
        end
    end
         
endmodule
