// Unit tests for rs.sv — Reservation Station (depth=8).
// Tests: dispatch, CDB snoop, issue selection (oldest ROB idx), CDB-at-dispatch forwarding, flush.
`timescale 1ns/1ps
`include "hdl/rs.sv"

module tb_rs;
    reg  clk, reset, flush;
    reg  [3:0] flush_rob_idx;

    // Dispatch port 0
    reg         disp0_en;
    reg  [4:0]  disp0_op;
    reg  [5:0]  disp0_dest_preg;
    reg  [3:0]  disp0_rob_idx;
    reg  [5:0]  disp0_s_preg;
    reg  [63:0] disp0_s_val;
    reg         disp0_s_rdy;
    reg  [5:0]  disp0_t_preg;
    reg  [63:0] disp0_t_val;
    reg         disp0_t_rdy;
    reg  [11:0] disp0_L;
    reg  [63:0] disp0_pc;
    reg  [5:0]  disp0_rd_preg;
    reg  [63:0] disp0_rd_val;
    reg         disp0_rd_rdy;

    // Dispatch port 1
    reg         disp1_en;
    reg  [4:0]  disp1_op;
    reg  [5:0]  disp1_dest_preg;
    reg  [3:0]  disp1_rob_idx;
    reg  [5:0]  disp1_s_preg;
    reg  [63:0] disp1_s_val;
    reg         disp1_s_rdy;
    reg  [5:0]  disp1_t_preg;
    reg  [63:0] disp1_t_val;
    reg         disp1_t_rdy;
    reg  [11:0] disp1_L;
    reg  [63:0] disp1_pc;
    reg  [5:0]  disp1_rd_preg;
    reg  [63:0] disp1_rd_val;
    reg         disp1_rd_rdy;

    // CDB
    reg         cdb0_valid, cdb1_valid;
    reg  [5:0]  cdb0_preg, cdb1_preg;
    reg  [63:0] cdb0_data, cdb1_data;

    wire        issue_valid;
    wire [4:0]  issue_op;
    wire [5:0]  issue_dest_preg;
    wire [3:0]  issue_rob_idx;
    wire [63:0] issue_src1, issue_src2;
    wire [11:0] issue_L;
    wire [63:0] issue_pc, issue_rd_val;
    wire        full;

    rs #(.DEPTH(8)) dut (
        .clk(clk), .reset(reset), .flush(flush), .flush_rob_idx(flush_rob_idx),
        .disp0_en(disp0_en), .disp0_op(disp0_op), .disp0_dest_preg(disp0_dest_preg),
        .disp0_rob_idx(disp0_rob_idx), .disp0_s_preg(disp0_s_preg),
        .disp0_s_val(disp0_s_val), .disp0_s_rdy(disp0_s_rdy),
        .disp0_t_preg(disp0_t_preg), .disp0_t_val(disp0_t_val), .disp0_t_rdy(disp0_t_rdy),
        .disp0_L(disp0_L), .disp0_pc(disp0_pc),
        .disp0_rd_preg(disp0_rd_preg), .disp0_rd_val(disp0_rd_val), .disp0_rd_rdy(disp0_rd_rdy),
        .disp1_en(disp1_en), .disp1_op(disp1_op), .disp1_dest_preg(disp1_dest_preg),
        .disp1_rob_idx(disp1_rob_idx), .disp1_s_preg(disp1_s_preg),
        .disp1_s_val(disp1_s_val), .disp1_s_rdy(disp1_s_rdy),
        .disp1_t_preg(disp1_t_preg), .disp1_t_val(disp1_t_val), .disp1_t_rdy(disp1_t_rdy),
        .disp1_L(disp1_L), .disp1_pc(disp1_pc),
        .disp1_rd_preg(disp1_rd_preg), .disp1_rd_val(disp1_rd_val), .disp1_rd_rdy(disp1_rd_rdy),
        .cdb0_valid(cdb0_valid), .cdb0_preg(cdb0_preg), .cdb0_data(cdb0_data),
        .cdb1_valid(cdb1_valid), .cdb1_preg(cdb1_preg), .cdb1_data(cdb1_data),
        .issue_valid(issue_valid), .issue_op(issue_op), .issue_dest_preg(issue_dest_preg),
        .issue_rob_idx(issue_rob_idx), .issue_src1(issue_src1), .issue_src2(issue_src2),
        .issue_L(issue_L), .issue_pc(issue_pc), .issue_rd_val(issue_rd_val),
        .full(full)
    );

    always #5 clk = ~clk;

    integer failures = 0;

    task reset_inputs;
        begin
            disp0_en = 0; disp1_en = 0; flush = 0; flush_rob_idx = 0;
            cdb0_valid = 0; cdb1_valid = 0;
            disp0_s_rdy = 1; disp0_t_rdy = 1; disp0_rd_rdy = 1;
            disp1_s_rdy = 1; disp1_t_rdy = 1; disp1_rd_rdy = 1;
            disp0_s_val = 0; disp0_t_val = 0; disp0_rd_val = 0;
            disp1_s_val = 0; disp1_t_val = 0; disp1_rd_val = 0;
            disp0_L = 0; disp0_pc = 0; disp1_L = 0; disp1_pc = 0;
            disp0_s_preg = 0; disp0_t_preg = 0; disp0_rd_preg = 0;
            disp1_s_preg = 0; disp1_t_preg = 0; disp1_rd_preg = 0;
            disp0_dest_preg = 0; disp0_rob_idx = 0; disp0_op = 0;
            disp1_dest_preg = 0; disp1_rob_idx = 0; disp1_op = 0;
        end
    endtask

    initial begin
        clk = 0; reset = 1;
        reset_inputs();
        @(posedge clk); @(posedge clk);
        reset = 0;

        // --- Test 1: Dispatch ready entry → issues next cycle ---
        disp0_en = 1; disp0_op = 5'h18; disp0_dest_preg = 6'd32;
        disp0_rob_idx = 4'd0; disp0_s_val = 64'd10; disp0_s_rdy = 1;
        disp0_t_val = 64'd20; disp0_t_rdy = 1; disp0_rd_rdy = 1;
        @(posedge clk);
        disp0_en = 0;
        @(posedge clk); #1;
        if (!issue_valid || issue_op !== 5'h18 || issue_src1 !== 64'd10 || issue_src2 !== 64'd20) begin
            $display("FAIL test 1: issue_valid=%b op=%h src1=%0d src2=%0d",
                issue_valid, issue_op, issue_src1, issue_src2);
            failures = failures + 1;
        end

        // --- Test 2: Entry not ready until CDB provides value ---
        @(posedge clk); // let previous issue clear
        disp0_en = 1; disp0_op = 5'h18; disp0_dest_preg = 6'd33;
        disp0_rob_idx = 4'd1; disp0_s_val = 64'd0; disp0_s_rdy = 0;
        disp0_s_preg = 6'd40; // waiting for preg 40
        disp0_t_val = 64'd5; disp0_t_rdy = 1; disp0_rd_rdy = 1;
        @(posedge clk);
        disp0_en = 0;

        @(posedge clk); #1;
        if (issue_valid) begin
            $display("FAIL test 2: should not issue while src not ready, issue_valid=%b", issue_valid);
            failures = failures + 1;
        end

        // CDB broadcasts value for preg 40
        cdb0_valid = 1; cdb0_preg = 6'd40; cdb0_data = 64'd99;
        @(posedge clk); cdb0_valid = 0;

        @(posedge clk); #1;
        if (!issue_valid || issue_src1 !== 64'd99) begin
            $display("FAIL test 2b: after CDB: issue_valid=%b src1=%0d expect 99",
                issue_valid, issue_src1);
            failures = failures + 1;
        end

        // --- Test 3: CDB forwarding at dispatch (same cycle) ---
        @(posedge clk);
        // Dispatch entry whose src is not ready, but CDB broadcasts it same cycle
        disp0_en = 1; disp0_op = 5'h18; disp0_dest_preg = 6'd34;
        disp0_rob_idx = 4'd2; disp0_s_val = 64'd0; disp0_s_rdy = 0;
        disp0_s_preg = 6'd41;
        disp0_t_val = 64'd7; disp0_t_rdy = 1; disp0_rd_rdy = 1;
        cdb0_valid = 1; cdb0_preg = 6'd41; cdb0_data = 64'd55;
        @(posedge clk);
        disp0_en = 0; cdb0_valid = 0;

        // Should issue next cycle (CDB forward applied)
        @(posedge clk); #1;
        if (!issue_valid || issue_src1 !== 64'd55) begin
            $display("FAIL test 3: CDB@dispatch forward: issue_valid=%b src1=%0d expect 55",
                issue_valid, issue_src1);
            failures = failures + 1;
        end

        // --- Test 4: Oldest ROB entry issued first ---
        @(posedge clk);
        // Dispatch two entries: rob_idx=5 (newer) then rob_idx=3 (older)
        disp0_en = 1; disp0_op = 5'h1a; disp0_dest_preg = 6'd35;
        disp0_rob_idx = 4'd5; disp0_s_val = 64'd1; disp0_s_rdy = 1;
        disp0_t_val = 64'd2; disp0_t_rdy = 1; disp0_rd_rdy = 1;
        disp1_en = 1; disp1_op = 5'h1c; disp1_dest_preg = 6'd36;
        disp1_rob_idx = 4'd3; disp1_s_val = 64'd3; disp1_s_rdy = 1;
        disp1_t_val = 64'd4; disp1_t_rdy = 1; disp1_rd_rdy = 1;
        @(posedge clk);
        disp0_en = 0; disp1_en = 0;

        @(posedge clk); #1;
        // rob_idx=3 is older → should issue first
        if (!issue_valid || issue_rob_idx !== 4'd3) begin
            $display("FAIL test 4: oldest-first: issue_valid=%b rob_idx=%0d expect 3",
                issue_valid, issue_rob_idx);
            failures = failures + 1;
        end

        // --- Test 5: Flush clears all entries ---
        @(posedge clk);
        flush = 1; flush_rob_idx = 4'd0;
        @(posedge clk); flush = 0;
        @(posedge clk); #1;
        if (issue_valid) begin
            $display("FAIL test 5: after flush issue_valid still high");
            failures = failures + 1;
        end

        // --- Test 6: Full signal when 7+ entries occupied ---
        reset = 1; @(posedge clk); reset = 0; reset_inputs();
        begin
            integer k;
            reg [5:0] preg_tmp;
            for (k = 0; k < 7; k = k + 1) begin
                preg_tmp = k[5:0] + 6'd40;
                disp0_en = 1; disp0_op = 5'h18; disp0_dest_preg = k[5:0];
                disp0_rob_idx = k[3:0]; disp0_s_rdy = 0; disp0_t_rdy = 1; disp0_rd_rdy = 1;
                disp0_s_preg = preg_tmp; // never ready
                @(posedge clk);
                disp0_en = 0;
            end
        end
        #1;
        if (!full) begin
            $display("FAIL test 6: full not asserted with 7 waiting entries");
            failures = failures + 1;
        end

        if (failures == 0)
            $display("PASS: rs — all 6 tests passed");
        else
            $display("FAIL: rs — %0d test(s) failed", failures);
        $finish;
    end
endmodule
