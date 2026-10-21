// 64/32 restoring divider: one quotient bit per cycle.
module unsigned_divider(
    input wire clk,rst,start,input wire [63:0] numerator,input wire [31:0] denominator,
    output reg busy,done,output reg [63:0] quotient
);
    reg [32:0] remainder;
    reg [31:0] divisor;
    reg [6:0] left;
    wire [33:0] shifted={remainder,quotient[63]};
    wire subtract=shifted>={2'b0,divisor};
    always @(posedge clk) begin
        if(rst) begin busy<=0; done<=0; quotient<=0; remainder<=0; divisor<=1; left<=0; end
        else begin
            done<=0;
            if(start && !busy) begin
                busy<=1; quotient<=numerator; remainder<=0; divisor<=denominator; left<=64;
            end else if(busy) begin
                quotient<={quotient[62:0],subtract};
                remainder<=subtract?shifted-{2'b0,divisor}:shifted;
                left<=left-1'b1;
                if(left==1) begin busy<=0; done<=1; end
            end
        end
    end
endmodule
