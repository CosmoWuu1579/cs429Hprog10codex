// Unit tests for rat.sv — Register Alias Table + Free List + Physical Register File.
// Tests: reset identity mapping, rename, CDB writeback, commit, flush/restore, is_initial forwarding.
`timescale 1ns/1ps
`include "hdl/reg_file.sv"
`include "hdl/rat.sv"

module tb_rat;
    reg  clk, reset;

    // arch_regs driving rat (normally from reg_file)
    reg  [63:0] arch_reg [0:31];

    // Flush
    reg         flush;
    reg  [191:0] flush_rat_snap;

    // Rename port 0
    reg         rename0_en;
    reg  [4:0]  rename0_d, rename0_s, rename0_t;
    wire [5:0]  rename0_new_preg, rename0_old_preg;
    wire [5:0]  rename0_s_preg, rename0_t_preg;
    wire [63:0] rename0_s_val, rename0_t_val;
    wire        rename0_s_rdy, rename0_t_rdy;
    wire [63:0] rename0_old_val;
    wire        rename0_old_rdy;

    // Rename port 1
    reg         rename1_en;
    reg  [4:0]  rename1_d, rename1_s, rename1_t;
    wire [5:0]  rename1_new_preg, rename1_old_preg;
    wire [5:0]  rename1_s_preg, rename1_t_preg;
    wire [63:0] rename1_s_val, rename1_t_val;
    wire        rename1_s_rdy, rename1_t_rdy;
    wire [63:0] rename1_old_val;
    wire        rename1_old_rdy;

    wire        free_avail;

    // CDB
    reg         cdb0_valid, cdb1_valid;
    reg  [5:0]  cdb0_preg, cdb1_preg;
    reg  [63:0] cdb0_data, cdb1_data;

    // Commit
    reg         commit0_en, commit1_en;
    reg  [4:0]  commit0_areg, commit1_areg;
    reg  [5:0]  commit0_preg, commit1_preg;
    reg  [5:0]  commit0_old, commit1_old;

    wire [191:0] rat_map_out;

    rat dut (
        .clk(clk), .reset(reset),
        .reg_array_out_0(arch_reg[0]),   .reg_array_out_1(arch_reg[1]),
        .reg_array_out_2(arch_reg[2]),   .reg_array_out_3(arch_reg[3]),
        .reg_array_out_4(arch_reg[4]),   .reg_array_out_5(arch_reg[5]),
        .reg_array_out_6(arch_reg[6]),   .reg_array_out_7(arch_reg[7]),
        .reg_array_out_8(arch_reg[8]),   .reg_array_out_9(arch_reg[9]),
        .reg_array_out_10(arch_reg[10]), .reg_array_out_11(arch_reg[11]),
        .reg_array_out_12(arch_reg[12]), .reg_array_out_13(arch_reg[13]),
        .reg_array_out_14(arch_reg[14]), .reg_array_out_15(arch_reg[15]),
        .reg_array_out_16(arch_reg[16]), .reg_array_out_17(arch_reg[17]),
        .reg_array_out_18(arch_reg[18]), .reg_array_out_19(arch_reg[19]),
        .reg_array_out_20(arch_reg[20]), .reg_array_out_21(arch_reg[21]),
        .reg_array_out_22(arch_reg[22]), .reg_array_out_23(arch_reg[23]),
        .reg_array_out_24(arch_reg[24]), .reg_array_out_25(arch_reg[25]),
        .reg_array_out_26(arch_reg[26]), .reg_array_out_27(arch_reg[27]),
        .reg_array_out_28(arch_reg[28]), .reg_array_out_29(arch_reg[29]),
        .reg_array_out_30(arch_reg[30]), .reg_array_out_31(arch_reg[31]),
        .flush(flush), .flush_rat_snap(flush_rat_snap),
        .rename0_en(rename0_en), .rename0_d(rename0_d),
        .rename0_s(rename0_s), .rename0_t(rename0_t),
        .rename0_new_preg(rename0_new_preg), .rename0_old_preg(rename0_old_preg),
        .rename0_s_preg(rename0_s_preg), .rename0_t_preg(rename0_t_preg),
        .rename0_s_val(rename0_s_val), .rename0_t_val(rename0_t_val),
        .rename0_s_rdy(rename0_s_rdy), .rename0_t_rdy(rename0_t_rdy),
        .rename0_old_val(rename0_old_val), .rename0_old_rdy(rename0_old_rdy),
        .rename1_en(rename1_en), .rename1_d(rename1_d),
        .rename1_s(rename1_s), .rename1_t(rename1_t),
        .rename1_new_preg(rename1_new_preg), .rename1_old_preg(rename1_old_preg),
        .rename1_s_preg(rename1_s_preg), .rename1_t_preg(rename1_t_preg),
        .rename1_s_val(rename1_s_val), .rename1_t_val(rename1_t_val),
        .rename1_s_rdy(rename1_s_rdy), .rename1_t_rdy(rename1_t_rdy),
        .rename1_old_val(rename1_old_val), .rename1_old_rdy(rename1_old_rdy),
        .free_avail(free_avail),
        .cdb0_valid(cdb0_valid), .cdb0_preg(cdb0_preg), .cdb0_data(cdb0_data),
        .cdb1_valid(cdb1_valid), .cdb1_preg(cdb1_preg), .cdb1_data(cdb1_data),
        .commit0_en(commit0_en), .commit0_areg(commit0_areg),
        .commit0_preg(commit0_preg), .commit0_old(commit0_old),
        .commit1_en(commit1_en), .commit1_areg(commit1_areg),
        .commit1_preg(commit1_preg), .commit1_old(commit1_old),
        .rat_map_out(rat_map_out)
    );

    always #5 clk = ~clk;

    integer failures = 0;
    integer j;

    task reset_inputs;
        begin
            rename0_en = 0; rename1_en = 0; flush = 0;
            cdb0_valid = 0; cdb1_valid = 0;
            commit0_en = 0; commit1_en = 0;
            flush_rat_snap = 0;
        end
    endtask

    initial begin
        clk = 0; reset = 1;
        reset_inputs();
        for (j = 0; j < 32; j = j + 1) arch_reg[j] = 64'b0;
        arch_reg[31] = 64'd524288;

        @(posedge clk); @(posedge clk);
        reset = 0;
        @(posedge clk);

        // --- Test 1: After reset, arch[r1] maps to phys[1], rdy=1 ---
        rename0_en = 0; rename0_s = 5'd1; rename0_t = 5'd2; rename0_d = 5'd3;
        #1;
        if (rename0_s_preg !== 6'd1 || rename0_t_preg !== 6'd2) begin
            $display("FAIL test 1: identity mapping: s_preg=%0d t_preg=%0d expect 1,2",
                rename0_s_preg, rename0_t_preg);
            failures = failures + 1;
        end
        if (!rename0_s_rdy || !rename0_t_rdy) begin
            $display("FAIL test 1b: preg rdy not set after reset: s_rdy=%b t_rdy=%b",
                rename0_s_rdy, rename0_t_rdy);
            failures = failures + 1;
        end

        // --- Test 2: is_initial — before any CDB write, reads from arch_reg ---
        arch_reg[1] = 64'd42; arch_reg[2] = 64'd99;
        #1;
        if (rename0_s_val !== 64'd42 || rename0_t_val !== 64'd99) begin
            $display("FAIL test 2: is_initial read: s_val=%0d t_val=%0d expect 42,99",
                rename0_s_val, rename0_t_val);
            failures = failures + 1;
        end

        // --- Test 3: CDB write to phys[1] clears is_initial, reads from phys_reg ---
        cdb0_valid = 1; cdb0_preg = 6'd1; cdb0_data = 64'd77;
        @(posedge clk); cdb0_valid = 0; #1;
        // After CDB write, preg[1] = 77 and is_initial[1] cleared
        // rename0_s (r1 → phys 1) should now read 77 from phys_regs
        arch_reg[1] = 64'd999; // change arch_reg; should not affect result
        #1;
        if (rename0_s_val !== 64'd77) begin
            $display("FAIL test 3: after CDB: s_val=%0d expect 77", rename0_s_val);
            failures = failures + 1;
        end

        // --- Test 4: Rename allocates new physical reg ---
        rename0_en = 1; rename0_d = 5'd5; rename0_s = 5'd1; rename0_t = 5'd2;
        #1;
        begin
            reg [5:0] np;
            np = rename0_new_preg;
            if (np < 6'd32) begin
                $display("FAIL test 4: new_preg=%0d should be >= 32", np);
                failures = failures + 1;
            end
        end
        @(posedge clk); rename0_en = 0;

        // --- Test 5: After rename, rename1 sees rename0's write (same-cycle forwarding) ---
        rename0_en = 1; rename0_d = 5'd7; rename0_s = 5'd0; rename0_t = 5'd0;
        rename1_en = 1; rename1_d = 5'd8; rename1_s = 5'd7; rename1_t = 5'd0;
        #1;
        // rename1_s_preg should see rename0's allocated new_preg for arch[7]
        if (rename1_s_preg !== rename0_new_preg) begin
            $display("FAIL test 5: forwarding: rename1.s_preg=%0d expect rename0.new=%0d",
                rename1_s_preg, rename0_new_preg);
            failures = failures + 1;
        end
        @(posedge clk); rename0_en = 0; rename1_en = 0;

        // --- Test 6: Commit frees old physical reg ---
        commit0_en = 1; commit0_areg = 5'd5; commit0_preg = 6'd32; commit0_old = 6'd5;
        @(posedge clk); commit0_en = 0;
        // free_avail should still be 1 after freeing one reg
        #1;
        if (!free_avail) begin
            $display("FAIL test 6: free_avail=0 after commit+free");
            failures = failures + 1;
        end

        // --- Test 7: rat_map_out contains current mapping ---
        #1;
        // arch[0] should map to phys[0] at reset (identity)
        if (rat_map_out[5:0] !== 6'd0) begin
            $display("FAIL test 7: rat_map_out[0]=%0d expect 0", rat_map_out[5:0]);
            failures = failures + 1;
        end

        // --- Test 8: Flush restores RAT from snapshot ---
        begin
            reg [191:0] snap;
            integer k;
            // Build a snap where every arch reg i maps to phys reg i
            snap = 192'b0;
            for (k = 0; k < 32; k = k + 1)
                snap[k*6 +: 6] = k[5:0];
            flush = 1; flush_rat_snap = snap;
            @(posedge clk); flush = 0; #1;
            // After flush, arch[3] should map to phys[3]
            rename0_s = 5'd3;
            #1;
            if (rename0_s_preg !== 6'd3) begin
                $display("FAIL test 8: after flush s_preg=%0d expect 3", rename0_s_preg);
                failures = failures + 1;
            end
        end

        if (failures == 0)
            $display("PASS: rat — all 8 tests passed");
        else
            $display("FAIL: rat — %0d test(s) failed", failures);
        $finish;
    end
endmodule
