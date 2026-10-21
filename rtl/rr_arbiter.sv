module rr_arbiter #(parameter N=5,MINIMIZED=0)(
    input wire clk,rst,advance,
    input wire [N-1:0] request,
    output reg [N-1:0] grant
);
    reg [$clog2(N)-1:0] next;
    integer k;
    reg [$clog2(N):0] idx;
    generate if(MINIMIZED && N==5) begin: optimized
        wire [4:0] minimized_grant;
        rr_minimized logic_block({next,request},minimized_grant);
        always @* grant=minimized_grant;
    end else begin: behavioral
    always @* begin
        grant=0;
        for(integer j=0;j<N;j=j+1) begin
            idx=next+j;
            if(idx>=N) idx=idx-N;
            if(request[idx] && grant==0) grant[idx]=1'b1;
        end
    end
    end endgenerate
    always @(posedge clk) begin
        if(rst) next<=0;
        else if(advance) for(k=0;k<N;k=k+1)
            if(grant[k]) next <= k==N-1 ? 0 : k+1;
    end
endmodule
