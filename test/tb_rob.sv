// Unit tests for rob.sv — 16-entry Reorder Buffer.
// Tests: allocation, CDB writeback, commit (single + dual), misprediction flush, halt.
`timescale 1ns/1ps
`include "hdl/rob.sv"

module tb_rob;
    reg  clk, reset;

    // Allocation port 0
    reg         alloc0_en;
    reg  [1:0]  alloc0_fu_type;
    reg  [4:0]  alloc0_dest_areg;
    reg  [5:0]  alloc0_dest_preg;
    reg  [5:0]  alloc0_old_preg;
    reg         alloc0_reg_write;
    reg         alloc0_is_store;
    reg         alloc0_is_branch;
    reg         alloc0_is_halt;
    reg  [63:0] alloc0_pred_pc;
    reg  [191:0] alloc0_rat_snap;
    wire [3:0]  alloc0_idx;

    // Allocation port 1
    reg         alloc1_en;
    reg  [1:0]  alloc1_fu_type;
    reg  [4:0]  alloc1_dest_areg;
    reg  [5:0]  alloc1_dest_preg;
    reg  [5:0]  alloc1_old_preg;
    reg         alloc1_reg_write;
    reg         alloc1_is_store;
    reg         alloc1_is_branch;
    reg         alloc1_is_halt;
    reg  [63:0] alloc1_pred_pc;
    reg  [191:0] alloc1_rat_snap;
    wire [3:0]  alloc1_idx;

    wire        rob_full;

    // CDB
    reg         cdb0_valid, cdb1_valid;
    reg  [3:0]  cdb0_rob_idx, cdb1_rob_idx;
    reg  [63:0] cdb0_result, cdb1_result;
    reg         cdb0_mis_pred, cdb1_mis_pred;
    reg  [63:0] cdb0_actual_pc, cdb1_actual_pc;

    // Commit outputs
    wire        commit0_en, commit1_en;
    wire [4:0]  commit0_areg, commit1_areg;
    wire [5:0]  commit0_preg, commit1_preg;
    wire [5:0]  commit0_old_preg, commit1_old_preg;
    wire [63:0] commit0_result, commit1_result;
    wire        commit0_reg_write, commit1_reg_write;
    wire        commit0_is_store, commit1_is_store;

    wire        flush;
    wire [63:0] flush_pc;
    wire [191:0] flush_rat_snap;
    wire [3:0]  flush_rob_idx;
    wire        hlt;

    rob dut (
        .clk(clk), .reset(reset),
        .alloc0_en(alloc0_en), .alloc0_fu_type(alloc0_fu_type),
        .alloc0_dest_areg(alloc0_dest_areg), .alloc0_dest_preg(alloc0_dest_preg),
        .alloc0_old_preg(alloc0_old_preg), .alloc0_reg_write(alloc0_reg_write),
        .alloc0_is_store(alloc0_is_store), .alloc0_is_branch(alloc0_is_branch),
        .alloc0_is_halt(alloc0_is_halt), .alloc0_pred_pc(alloc0_pred_pc),
        .alloc0_rat_snap(alloc0_rat_snap), .alloc0_idx(alloc0_idx),
        .alloc1_en(alloc1_en), .alloc1_fu_type(alloc1_fu_type),
        .alloc1_dest_areg(alloc1_dest_areg), .alloc1_dest_preg(alloc1_dest_preg),
        .alloc1_old_preg(alloc1_old_preg), .alloc1_reg_write(alloc1_reg_write),
        .alloc1_is_store(alloc1_is_store), .alloc1_is_branch(alloc1_is_branch),
        .alloc1_is_halt(alloc1_is_halt), .alloc1_pred_pc(alloc1_pred_pc),
        .alloc1_rat_snap(alloc1_rat_snap), .alloc1_idx(alloc1_idx),
        .rob_full(rob_full),
        .cdb0_valid(cdb0_valid), .cdb0_rob_idx(cdb0_rob_idx),
        .cdb0_result(cdb0_result), .cdb0_mis_pred(cdb0_mis_pred),
        .cdb0_actual_pc(cdb0_actual_pc),
        .cdb1_valid(cdb1_valid), .cdb1_rob_idx(cdb1_rob_idx),
        .cdb1_result(cdb1_result), .cdb1_mis_pred(cdb1_mis_pred),
        .cdb1_actual_pc(cdb1_actual_pc),
        .commit0_en(commit0_en), .commit0_areg(commit0_areg),
        .commit0_preg(commit0_preg), .commit0_old_preg(commit0_old_preg),
        .commit0_result(commit0_result), .commit0_reg_write(commit0_reg_write),
        .commit0_is_store(commit0_is_store),
        .commit1_en(commit1_en), .commit1_areg(commit1_areg),
        .commit1_preg(commit1_preg), .commit1_old_preg(commit1_old_preg),
        .commit1_result(commit1_result), .commit1_reg_write(commit1_reg_write),
        .commit1_is_store(commit1_is_store),
        .flush(flush), .flush_pc(flush_pc),
        .flush_rat_snap(flush_rat_snap), .flush_rob_idx(flush_rob_idx),
        .hlt(hlt)
    );

    always #5 clk = ~clk;

    integer failures = 0;

    task reset_inputs;
        begin
            alloc0_en = 0; alloc1_en = 0;
            alloc0_fu_type = 0; alloc0_dest_areg = 0; alloc0_dest_preg = 0;
            alloc0_old_preg = 0; alloc0_reg_write = 0; alloc0_is_store = 0;
            alloc0_is_branch = 0; alloc0_is_halt = 0; alloc0_pred_pc = 0;
            alloc0_rat_snap = 0;
            alloc1_fu_type = 0; alloc1_dest_areg = 0; alloc1_dest_preg = 0;
            alloc1_old_preg = 0; alloc1_reg_write = 0; alloc1_is_store = 0;
            alloc1_is_branch = 0; alloc1_is_halt = 0; alloc1_pred_pc = 0;
            alloc1_rat_snap = 0;
            cdb0_valid = 0; cdb0_rob_idx = 0; cdb0_result = 0;
            cdb0_mis_pred = 0; cdb0_actual_pc = 0;
            cdb1_valid = 0; cdb1_rob_idx = 0; cdb1_result = 0;
            cdb1_mis_pred = 0; cdb1_actual_pc = 0;
        end
    endtask

    reg [3:0] saved_idx0;

    initial begin
        clk = 0; reset = 1;
        reset_inputs();
        @(posedge clk); @(posedge clk);
        reset = 0;

        // --- Test 1: Allocate one entry, CDB writeback, commit ---
        alloc0_en = 1; alloc0_dest_areg = 5'd2; alloc0_dest_preg = 6'd32;
        alloc0_old_preg = 6'd2; alloc0_reg_write = 1; alloc0_is_halt = 0;
        alloc0_pred_pc = 64'h2004;
        saved_idx0 = alloc0_idx; // should be 0
        @(posedge clk);
        alloc0_en = 0;

        // CDB writes back result
        cdb0_valid = 1; cdb0_rob_idx = saved_idx0;
        cdb0_result = 64'd42; cdb0_mis_pred = 0; cdb0_actual_pc = 64'h2004;
        @(posedge clk);
        cdb0_valid = 0;

        // Commit should fire next cycle
        @(posedge clk); #1;
        if (!commit0_en || commit0_areg !== 5'd2 || commit0_preg !== 6'd32 ||
            commit0_result !== 64'd42) begin
            $display("FAIL test 1: commit0_en=%b areg=%0d preg=%0d result=%0d",
                commit0_en, commit0_areg, commit0_preg, commit0_result);
            failures = failures + 1;
        end

        // --- Test 2: Halt instruction commits → hlt asserted ---
        reset = 1; @(posedge clk); reset = 0; reset_inputs();

        alloc0_en = 1; alloc0_is_halt = 1; alloc0_reg_write = 0;
        alloc0_pred_pc = 64'h2000;
        saved_idx0 = alloc0_idx;
        @(posedge clk);
        alloc0_en = 0;

        cdb0_valid = 1; cdb0_rob_idx = saved_idx0; cdb0_result = 0;
        cdb0_mis_pred = 0; cdb0_actual_pc = 64'h2000;
        @(posedge clk); cdb0_valid = 0;

        @(posedge clk); #1;
        if (!hlt) begin
            $display("FAIL test 2: hlt not asserted after halt instruction commits");
            failures = failures + 1;
        end

        // --- Test 3: Misprediction flush ---
        reset = 1; @(posedge clk); reset = 0; reset_inputs();

        alloc0_en = 1; alloc0_is_branch = 1; alloc0_reg_write = 0;
        alloc0_pred_pc = 64'h2004; // predicted pc+4
        alloc0_rat_snap = 192'hDEAD;
        saved_idx0 = alloc0_idx;
        @(posedge clk);
        alloc0_en = 0;

        // CDB says actual PC was 0x3000 (branch taken, mispredicted)
        cdb0_valid = 1; cdb0_rob_idx = saved_idx0; cdb0_result = 0;
        cdb0_mis_pred = 1; cdb0_actual_pc = 64'h3000;
        @(posedge clk); cdb0_valid = 0;

        @(posedge clk); #1;
        if (!flush || flush_pc !== 64'h3000) begin
            $display("FAIL test 3: flush=%b flush_pc=%h expect flush=1 pc=0x3000",
                flush, flush_pc);
            failures = failures + 1;
        end

        // --- Test 4: Dual alloc + dual commit ---
        reset = 1; @(posedge clk); reset = 0; reset_inputs();

        alloc0_en = 1; alloc0_dest_areg = 5'd1; alloc0_dest_preg = 6'd33;
        alloc0_old_preg = 6'd1; alloc0_reg_write = 1; alloc0_pred_pc = 64'h2004;
        alloc1_en = 1; alloc1_dest_areg = 5'd2; alloc1_dest_preg = 6'd34;
        alloc1_old_preg = 6'd2; alloc1_reg_write = 1; alloc1_pred_pc = 64'h2008;
        @(posedge clk);
        alloc0_en = 0; alloc1_en = 0;

        // Both write back on CDB
        cdb0_valid = 1; cdb0_rob_idx = 4'd0; cdb0_result = 64'd10; cdb0_mis_pred = 0; cdb0_actual_pc = 64'h2004;
        cdb1_valid = 1; cdb1_rob_idx = 4'd1; cdb1_result = 64'd20; cdb1_mis_pred = 0; cdb1_actual_pc = 64'h2008;
        @(posedge clk); cdb0_valid = 0; cdb1_valid = 0;

        @(posedge clk); #1;
        if (!commit0_en || !commit1_en ||
            commit0_result !== 64'd10 || commit1_result !== 64'd20) begin
            $display("FAIL test 4: dual commit: c0=%b c1=%b r0=%0d r1=%0d",
                commit0_en, commit1_en, commit0_result, commit1_result);
            failures = failures + 1;
        end

        // --- Test 5: rob_full when filled ---
        reset = 1; @(posedge clk); reset = 0; reset_inputs();
        begin
            integer k;
            for (k = 0; k < 15; k = k + 1) begin
                alloc0_en = 1; alloc0_dest_areg = 5'd1; alloc0_dest_preg = 6'd32;
                alloc0_old_preg = 6'd1; alloc0_reg_write = 1;
                alloc0_pred_pc = 64'h2000 + k*4;
                @(posedge clk);
                alloc0_en = 0;
            end
        end
        #1;
        if (!rob_full) begin
            $display("FAIL test 5: rob_full not asserted with 15 entries");
            failures = failures + 1;
        end

        if (failures == 0)
            $display("PASS: rob — all 5 tests passed");
        else
            $display("FAIL: rob — %0d test(s) failed", failures);
        $finish;
    end
endmodule
