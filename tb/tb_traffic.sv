`timescale 1ns/1ps
`include "noc_defs.vh"

// Six isolated scenarios in ONE simulation:
// LOW/MEDIUM/HIGH x UNIFORM/HOTSPOT.
// Per scenario: reset -> warmup -> measurement -> drain -> assertions.
// For FAST-vs-baseline comparisons, rerun with parameter FAST=1.
// Timestamps: first SOURCE header handshake -> last DESTINATION tail handshake.
module tb_traffic;
    parameter NX = 2, NY = 2, FAST = 0;
    parameter WARMUP_CYCLES = 2000;
    parameter MEASURE_CYCLES = 10000;
    parameter MAX_DRAIN_CYCLES = 15000;
    parameter MAX_IDS = 8192;
    localparam N = NX * NY;

    reg clk = 0, rst = 1, enable = 0, hotspot = 0;
    reg [15:0] rate = 0;
    always #5 clk = ~clk;

    wire [N*64-1:0] tx, rx, ifl, efl;
    wire [N-1:0] tv, tr, rv, iv, ic, ev, ec;
    reg [N-1:0] rr = 0;
    wire [31:0] injected [0:N-1];

    noc_mesh #(.NX(NX), .NY(NY), .FAST(FAST)) mesh (
        clk, rst, ifl, iv, ic, efl, ev, ec
    );

    genvar gn;
    generate for (gn=0; gn<N; gn=gn+1) begin: nodes
        traffic_source #(
            .NODE(gn), .NX(NX), .NY(NY), .SEED(32'h24ba7831+gn)
        ) source (
            clk, rst, enable, hotspot, rate,
            tx[gn*64+:64], tv[gn], tr[gn], injected[gn]
        );
        noc_endpoint ep (
            clk, rst, tx[gn*64+:64], tv[gn], tr[gn],
            rx[gn*64+:64], rv[gn], rr[gn],
            ifl[gn*64+:64], iv[gn], ic[gn],
            efl[gn*64+:64], ev[gn], ec[gn]
        );
    end endgenerate

    // Window values: 0=WARMUP, 1=MEASURE, 2=DRAIN.
    integer phase_id = 0, window_id = 0;
    string pattern_name = "uniform";
    string rate_name = "low";
    string window_name = "warmup";
    integer phase_cycle = 0, global_cycle = 0;

    // Per-phase packet bookkeeping; ID is unique PER SOURCE, and reset per scenario.
    reg [MAX_IDS-1:0] injection_seen [0:N-1];
    reg [MAX_IDS-1:0] completion_seen [0:N-1];
    integer injection_cycle [0:N-1][0:MAX_IDS-1];
    integer injection_dest  [0:N-1][0:MAX_IDS-1];
    integer injection_window[0:N-1][0:MAX_IDS-1];
    integer flitpos [0:N-1];
    integer recv_src[0:N-1], recv_id[0:N-1];

    integer started = 0, injected_tails = 0, delivered = 0;
    integer measured_started = 0, measured_completions = 0;
    integer measured_delivered = 0;
    integer measured_source_flits = 0, measured_sink_flits = 0;
    integer measured_source_stalls = 0, measured_sink_stalls = 0;
    integer fd_packets, fd_cycles, fd_summary;
    string packet_path = "noc_packet_events.csv";
    string cycle_path = "noc_cycle_stats.csv";
    string summary_path = "noc_run_summary.csv";

    function integer bitcount;
        input [N-1:0] mask;
        integer j;
        begin
            bitcount = 0;
            for (j=0; j<N; j=j+1) if(mask[j]) bitcount=bitcount+1;
        end
    endfunction

    // Reproduce the existing periodic receive stalls. Drive on falling edges.
    integer k;
    always @(negedge clk) begin
        for (k=0; k<N; k=k+1)
            rr[k] = ((phase_cycle + k*7) % 13 < 8);
    end

    // All counting samples the pre-clock handshake levels at the positive edge.
    // Source and destination observations are collected in the SAME clock domain.
    integer s, d, sid, pid, dst, sx, sy, dx, dy, hops;
    integer src_flits, sink_flits, src_stalls, sink_stalls;
    always @(posedge clk) begin
        if (rst) begin
            phase_cycle = 0;
            started = 0;
            injected_tails = 0;
            delivered = 0;
            measured_started = 0;
            measured_completions = 0;
            measured_delivered = 0;
            measured_source_flits = 0;
            measured_sink_flits = 0;
            measured_source_stalls = 0;
            measured_sink_stalls = 0;
            for (s=0; s<N; s=s+1) begin
                injection_seen[s] = '0;
                completion_seen[s] = '0;
                flitpos[s] = 0;
                recv_src[s] = 0;
                recv_id[s] = 0;
            end
        end else begin
            phase_cycle = phase_cycle + 1;
            global_cycle = global_cycle + 1;
            src_flits = 0;
            sink_flits = 0;
            src_stalls = 0;
            sink_stalls = 0;

            // Log the FIRST SOURCE-ACCEPTED HEADER, not a packet-generation guess.
            for (s=0; s<N; s=s+1) begin
                if (tv[s] && !tr[s]) src_stalls = src_stalls + 1;
                if (tv[s] && tr[s]) begin
                    src_flits = src_flits + 1;
                    if (tx[s*64+`HEAD]) begin
                        pid = tx[s*64+8+:24];
                        dx = tx[s*64+60+:2];
                        dy = tx[s*64+58+:2];
                        sx = tx[s*64+56+:2];
                        sy = tx[s*64+54+:2];
                        dst = dy * NX + dx;
                        if (pid < 0 || pid >= MAX_IDS)
                            $fatal(1,"Packet ID exceeded MAX_IDS; increase parameter");
                        if (dx >= NX || dy >= NY || sx != (s%NX) || sy != (s/NX))
                            $fatal(1,"Invalid source header at source %0d",s);
                        if (injection_seen[s][pid])
                            $fatal(1,"Repeated source header src=%0d id=%0d",s,pid);
                        injection_seen[s][pid] = 1;
                        injection_cycle[s][pid] = phase_cycle;
                        injection_dest[s][pid] = dst;
                        injection_window[s][pid] = window_id;
                        started = started + 1;
                        if (window_id == 1) measured_started = measured_started + 1;
                    end
                    if (tx[s*64+`TAIL]) injected_tails = injected_tails + 1;
                end
            end

            // Destination stream is checked end-to-end and matched by source/ID.
            for (d=0; d<N; d=d+1) begin
                if (rv[d] && !rr[d]) sink_stalls = sink_stalls + 1;
                if (rv[d] && rr[d]) begin
                    sink_flits = sink_flits + 1;
                    if (flitpos[d] == 0) begin
                        if (!rx[d*64+`HEAD] || rx[d*64+`TAIL] ||
                            rx[d*64+60+:2] != d%NX ||
                            rx[d*64+58+:2] != d/NX)
                            $fatal(1,"Header misroute at node %0d",d);
                        sid = rx[d*64+54+:2]*NX + rx[d*64+56+:2];
                        pid = rx[d*64+8+:24];
                        if (sid < 0 || sid >= N || pid < 0 || pid >= MAX_IDS)
                            $fatal(1,"Invalid received source or packet ID");
                        if (!injection_seen[sid][pid] || completion_seen[sid][pid])
                            $fatal(1,"Unknown or duplicate packet src=%0d id=%0d",sid,pid);
                        if (injection_dest[sid][pid] != d)
                            $fatal(1,"Destination mismatch src=%0d id=%0d",sid,pid);
                        recv_src[d] = sid;
                        recv_id[d] = pid;
                        flitpos[d] = 1;
                    end else begin
                        sid = recv_src[d];
                        pid = recv_id[d];
                        if (rx[d*64+`HEAD] || rx[d*64+:8] != flitpos[d] ||
                            rx[d*64+8+:24] != pid)
                            $fatal(1,"Data corruption / interleaving at dst=%0d",d);
                        if (flitpos[d] == 2) begin
                            if (!rx[d*64+`TAIL]) $fatal(1,"Missing tail");
                            completion_seen[sid][pid] = 1;
                            delivered = delivered + 1;
                            if (window_id == 1) measured_completions = measured_completions + 1;
                            if (injection_window[sid][pid] == 1)
                                measured_delivered = measured_delivered + 1;
                            hops = ((sid%NX) > (d%NX) ? (sid%NX)-(d%NX) : (d%NX)-(sid%NX))
                                 + ((sid/NX) > (d/NX) ? (sid/NX)-(d/NX) : (d/NX)-(sid/NX));
                            // Only complete packets are reported.  A measured packet
                            // can complete during DRAIN and is still retained.
                            $fdisplay(fd_packets,
                                "%0d,%0s,%0s,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d",
                                phase_id,pattern_name,rate_name,rate,FAST,
                                sid,d,pid,injection_cycle[sid][pid],phase_cycle,
                                phase_cycle-injection_cycle[sid][pid],hops,
                                injection_window[sid][pid],window_id,global_cycle);
                            flitpos[d] = 0;
                        end else flitpos[d] = 2;
                    end
                end
            end
            if (window_id == 1) begin
                measured_source_flits = measured_source_flits + src_flits;
                measured_sink_flits = measured_sink_flits + sink_flits;
                measured_source_stalls = measured_source_stalls + src_stalls;
                measured_sink_stalls = measured_sink_stalls + sink_stalls;
            end
            $fdisplay(fd_cycles,
              "%0d,%0s,%0s,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d",
              phase_id,pattern_name,rate_name,rate,FAST,window_id,
              phase_cycle,global_cycle,src_flits,bitcount(iv),bitcount(ev),
              sink_flits,src_stalls,sink_stalls,bitcount(tv),bitcount(tr),
              bitcount(rv),bitcount(rr),started,injected_tails,delivered,
              started-delivered);
        end
    end

    integer p, drain_cycles, expected, run_total = 0;
    integer j;
    initial begin
        if ($value$plusargs("PACKETS=%s",packet_path)) begin end
        if ($value$plusargs("CYCLES=%s",cycle_path)) begin end
        if ($value$plusargs("SUMMARY=%s",summary_path)) begin end
        fd_packets=$fopen(packet_path,"w");
        fd_cycles=$fopen(cycle_path,"w");
        fd_summary=$fopen(summary_path,"w");
        if (!fd_packets || !fd_cycles || !fd_summary)
            $fatal(1,"Could not open NoC CSV output files");
        $fdisplay(fd_packets,"PhaseID,Pattern,RateLabel,RateThreshold,FAST,SrcNode,DestNode,PacketID,InjectionCycle,DeliveryCycle,LatencyCycles,HopCount,InjectionWindow,DeliveryWindow,GlobalDeliveryCycle");
        $fdisplay(fd_cycles,"PhaseID,Pattern,RateLabel,RateThreshold,FAST,Window,PhaseCycle,GlobalCycle,SourceFlits,MeshInjectedFlits,MeshEjectedFlits,SinkFlits,SourceStallNodeCycles,SinkStallNodeCycles,SourceValidNodes,SourceReadyNodes,SinkValidNodes,SinkReadyNodes,StartedPackets,InjectedPackets,DeliveredPackets,OutstandingPackets");
        $fdisplay(fd_summary,"PhaseID,Pattern,RateLabel,RateThreshold,FAST,NX,NY,WarmupCycles,MeasurementCycles,DrainCycles,StartedPackets,InjectedPackets,DeliveredPackets,MeasuredStartedPackets,MeasuredCompletedDuringWindow,MeasuredInjectedDelivered,MeasuredSourceFlits,MeasuredSinkFlits,MeasuredSourceStallNodeCycles,MeasuredSinkStallNodeCycles");

        for (p=0; p<6; p=p+1) begin
            @(negedge clk);
            rst=1; enable=0; window_id=0;
            phase_id=p;
            hotspot=(p%2)==1;
            pattern_name=hotspot ? "hotspot" : "uniform";
            case (p/2)
                0: begin rate_name="low";    rate=16'h2000; end
                1: begin rate_name="medium"; rate=16'h8000; end
                default: begin rate_name="high"; rate=16'hf000; end
            endcase
            repeat (5) @(negedge clk);
            rst=0; enable=1;
            $display("START phase=%0d pattern=%0s rate=%0s (threshold=%0d) FAST=%0d",
                     phase_id,pattern_name,rate_name,rate,FAST);

            repeat (WARMUP_CYCLES) @(negedge clk);
            window_id=1;
            repeat (MEASURE_CYCLES) @(negedge clk);
            window_id=2; enable=0;

            // Drain until ALL headers have been delivered and the source
            // generators are inactive.  Never silently drop unfinished traffic.
            drain_cycles=0;
            while (((started != delivered) || (tv != {N{1'b0}}) ||
                    (injected_tails != delivered)) &&
                    drain_cycles < MAX_DRAIN_CYCLES) begin
                @(negedge clk);
                drain_cycles=drain_cycles+1;
            end
            if (drain_cycles == MAX_DRAIN_CYCLES || started != delivered ||
                injected_tails != delivered || tv != {N{1'b0}})
                $fatal(1,"DRAIN TIMEOUT phase=%0d started=%0d tails=%0d delivered=%0d active=%b",
                       phase_id,started,injected_tails,delivered,tv);
            expected=0;
            for (j=0; j<N; j=j+1) expected=expected+injected[j];
            if (delivered != expected || delivered != started ||
                measured_started != measured_delivered)
                $fatal(1,"PACKET LOSS phase=%0d source_tails=%0d started=%0d delivered=%0d measured_started=%0d measured_delivered=%0d",
                    phase_id,expected,started,delivered,measured_started,measured_delivered);
            if (measured_started < 10)
                $fatal(1,"Too few measured packets in phase %0d",phase_id);

            $fdisplay(fd_summary,
                "%0d,%0s,%0s,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d",
                phase_id,pattern_name,rate_name,rate,FAST,NX,NY,
                WARMUP_CYCLES,MEASURE_CYCLES,drain_cycles,
                started,injected_tails,delivered,measured_started,
                measured_completions,measured_delivered,
                measured_source_flits,measured_sink_flits,
                measured_source_stalls,measured_sink_stalls);
            run_total=run_total+delivered;
            $display("PHASE PASS id=%0d %0s %0s packets=%0d measured=%0d drain=%0d",
                     phase_id,pattern_name,rate_name,delivered,measured_started,drain_cycles);
        end
        $fclose(fd_packets);
        $fclose(fd_cycles);
        $fclose(fd_summary);
        $display("ALL 6 TRAFFIC SCENARIOS PASS NX=%0d NY=%0d FAST=%0d packets=%0d",
                 NX,NY,FAST,run_total);
        $finish;
    end
endmodule
