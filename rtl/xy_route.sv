module xy_route #(parameter X=0,Y=0,MINIMIZED=0)(
    input wire [1:0] dx,dy,
    output wire [2:0] port
);
    generate if(MINIMIZED) begin: optimized
        wire [4:0] onehot;
        localparam [1:0] XX=X,YY=Y;
        xy_minimized logic_block({dy,dx,YY,XX},onehot);
        assign port=onehot[1]?3'd1:onehot[2]?3'd2:onehot[3]?3'd3:onehot[4]?3'd4:3'd0;
    end else begin: behavioral
        assign port = dx>X ? 3'd1 : dx<X ? 3'd2 : dy>Y ? 3'd3 : dy<Y ? 3'd4 : 3'd0;
    end endgenerate
endmodule
