// Multicycle RV32I unprivileged integer core, no compressed/M/CSR/extensions.
// All instruction fetches and data accesses use the same external request port.
module rv32_core(
    input wire clk,rst,
    output wire req_valid,input wire req_ready,
    output wire req_write,output wire [31:0] req_addr,req_wdata,output wire [3:0] req_wstrb,
    input wire rsp_valid,output wire rsp_ready,input wire [31:0] rsp_data,input wire rsp_error,
    output reg halted,trap,output reg [31:0] pc
);
    localparam FETCH=0,FETCH_WAIT=1,EXEC=2,MEM=3,MEM_WAIT=4;
    reg [2:0] state;
    reg [31:0] regs [0:31];
    reg [31:0] insn,mem_addr,mem_data;
    reg [3:0] mem_strb;
    reg mem_write;
    reg [2:0] load_kind;
    reg [4:0] load_rd;
    wire [4:0] rs1=insn[19:15],rs2=insn[24:20],rd=insn[11:7];
    wire [2:0] f3=insn[14:12];
    wire [31:0] a=rs1==0?0:regs[rs1],b=rs2==0?0:regs[rs2];
    wire [31:0] imm_i={{20{insn[31]}},insn[31:20]};
    wire [31:0] imm_s={{20{insn[31]}},insn[31:25],insn[11:7]};
    wire [31:0] imm_b={{19{insn[31]}},insn[31],insn[7],insn[30:25],insn[11:8],1'b0};
    wire [31:0] imm_j={{11{insn[31]}},insn[31],insn[19:12],insn[20],insn[30:21],1'b0};
    reg [31:0] value,next_pc,ea,operand,store_value,loaded;
    reg [3:0] store_mask;
    reg legal,write_reg,is_mem,is_store,take_branch,stop;
    assign req_valid=!halted && (state==FETCH || state==MEM);
    assign req_write=state==MEM && mem_write;
    assign req_addr=state==FETCH?pc:{mem_addr[31:2],2'b00};
    assign req_wdata=mem_data; assign req_wstrb=mem_strb;
    assign rsp_ready=state==FETCH_WAIT || state==MEM_WAIT;
    always @* begin
        legal=1; write_reg=0; is_mem=0; is_store=0; take_branch=0; stop=0;
        value=0; next_pc=pc+4; ea=0; operand=0; store_value=0; store_mask=0;
        case(insn[6:0])
            7'h37: begin value={insn[31:12],12'b0}; write_reg=1; end
            7'h17: begin value=pc+{insn[31:12],12'b0}; write_reg=1; end
            7'h6f: begin value=pc+4; next_pc=pc+imm_j; write_reg=1; end
            7'h67: begin value=pc+4; next_pc=(a+imm_i)&32'hfffffffe; write_reg=1; legal=f3==0; end
            7'h63: begin
                case(f3)
                    0: take_branch=a==b; 1: take_branch=a!=b;
                    4: take_branch=$signed(a)<$signed(b); 5: take_branch=$signed(a)>=$signed(b);
                    6: take_branch=a<b; 7: take_branch=a>=b;
                    default: legal=0;
                endcase
                if(take_branch) next_pc=pc+imm_b;
            end
            7'h13,7'h33: begin
                operand=(insn[6:0]==7'h13) ? imm_i : b; write_reg=1;
                case(f3)
                    0: value=(insn[6:0]==7'h33 && insn[30])?a-operand:a+operand;
                    1: value=a<<operand[4:0];
                    2: value={31'b0,$signed(a)<$signed(operand)};
                    3: value={31'b0,a<operand};
                    4: value=a^operand;
                    5: begin
                        if(insn[30]) value=$signed(a)>>>operand[4:0];
                        else value=a>>operand[4:0];
                    end
                    6: value=a|operand; 7: value=a&operand;
                endcase
                if(insn[6:0]==7'h33)
                    legal=insn[31:25]==0 || (insn[31:25]==7'h20 && (f3==0 || f3==5));
                else if(f3==1) legal=insn[31:25]==0;
                else if(f3==5) legal=insn[31:25]==0 || insn[31:25]==7'h20;
            end
            7'h03,7'h23: begin
                is_mem=1; is_store=insn[6:0]==7'h23;
                ea=a+(is_store?imm_s:imm_i);
                store_value=b<<(8*ea[1:0]);
                case(f3)
                    0: store_mask=4'b0001<<ea[1:0];
                    1: begin store_mask=4'b0011<<ea[1:0]; legal=ea[0]==0; end
                    2: begin store_mask=15; legal=ea[1:0]==0; end
                    4: legal=!is_store;
                    5: legal=!is_store && ea[0]==0;
                    default: legal=0;
                endcase
            end
            7'h0f: legal=f3==0; // FENCE: transactions already serialized.
            7'h73: begin stop=1; legal=insn==32'h00100073; end // EBREAK halt.
            default: legal=0;
        endcase
        if(next_pc[1:0]!=0) legal=0;
        loaded=rsp_data>>(8*mem_addr[1:0]);
        case(load_kind)
            0: loaded={{24{loaded[7]}},loaded[7:0]};
            1: loaded={{16{loaded[15]}},loaded[15:0]};
            4: loaded={24'b0,loaded[7:0]};
            5: loaded={16'b0,loaded[15:0]};
            default: ;
        endcase
    end
    always @(posedge clk) begin
        if(rst) begin
            state<=FETCH; pc<=0; halted<=0; trap<=0; insn<=0;
            mem_addr<=0; mem_data<=0; mem_strb<=0; mem_write<=0; load_kind<=0; load_rd<=0;
            for(integer i=0;i<32;i=i+1) regs[i]<=0;
        end else if(!halted) begin
            case(state)
                FETCH: if(req_ready) state<=FETCH_WAIT;
                FETCH_WAIT: if(rsp_valid) begin
                    if(rsp_error) begin halted<=1; trap<=1; end
                    else begin insn<=rsp_data; state<=EXEC; end
                end
                EXEC: begin
                    if(!legal) begin halted<=1; trap<=1; end
                    else if(stop) halted<=1;
                    else begin
                        pc<=next_pc;
                        if(write_reg && rd!=0) regs[rd]<=value;
                        if(is_mem) begin
                            mem_addr<=ea; mem_data<=store_value; mem_strb<=store_mask; mem_write<=is_store;
                            load_kind<=f3; load_rd<=rd; state<=MEM;
                        end else state<=FETCH;
                    end
                end
                MEM: if(req_ready) state<=MEM_WAIT;
                MEM_WAIT: if(rsp_valid) begin
                    if(rsp_error) begin halted<=1; trap<=1; end
                    else begin if(!mem_write && load_rd!=0) regs[load_rd]<=loaded; state<=FETCH; end
                end
                default: begin halted<=1; trap<=1; end
            endcase
        end
    end
endmodule
