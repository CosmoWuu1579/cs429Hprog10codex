// tb_fpu.sv - Testbench for 4-stage pipelined FPU execution unit
// Tests ADDF, SUBF, MULF, DIVF with IEEE 754 double-precision
`timescale 1ns/1ps
`include "hdl/cpu_pkg.sv"

module tb_fpu;

    reg clk, reset, flush;
    reg        issue_valid;
    reg [4:0]  issue_opcode;
    reg [63:0] issue_Vj, issue_Vk;
    reg [4:0]  issue_rob_tag;
    reg [5:0]  issue_phys_dest;

    wire        cdb_valid;
    wire [4:0]  cdb_tag;
    wire [63:0] cdb_value;
    wire [5:0]  cdb_phys_dest;
    wire        eu_busy;

    fpu dut (.*);

    initial clk = 0;
    always #5 clk = ~clk;

    integer test_num = 0;
    integer pass_count = 0;
    integer fail_count = 0;

    task clear_issue;
        begin
            issue_valid = 0;
            issue_opcode = 0;
            issue_Vj = 0;
            issue_Vk = 0;
            issue_rob_tag = 0;
            issue_phys_dest = 0;
        end
    endtask

    task check(input [63:0] expected, input [4:0] exp_tag, input [5:0] exp_phys, input string name);
        begin
            test_num = test_num + 1;
            if (cdb_valid && cdb_value === expected && cdb_tag === exp_tag && cdb_phys_dest === exp_phys) begin
                $display("  PASS %0d: %s", test_num, name);
                pass_count = pass_count + 1;
            end else begin
                $display("  FAIL %0d: %s", test_num, name);
                $display("    valid=%b tag=%0d phys=%0d value=%016h (expected tag=%0d phys=%0d value=%016h)",
                         cdb_valid, cdb_tag, cdb_phys_dest, cdb_value, exp_tag, exp_phys, expected);
                fail_count = fail_count + 1;
            end
        end
    endtask

    task check_nan(input string name);
        begin
            test_num = test_num + 1;
            if (cdb_valid && cdb_value[62:52] == 11'h7FF && cdb_value[51:0] != 0) begin
                $display("  PASS %0d: %s", test_num, name);
                pass_count = pass_count + 1;
            end else begin
                $display("  FAIL %0d: %s (expected NaN, got %016h)", test_num, name, cdb_value);
                fail_count = fail_count + 1;
            end
        end
    endtask

    // Issue an FP instruction and wait for 4-stage pipeline result
    // Pipeline: issue -> s2(posedge+1) -> s3(posedge+2) -> s4(posedge+3)
    // Result available after 3rd posedge following issue setup
    task issue_and_wait(
        input [4:0] op, input [63:0] vj, input [63:0] vk,
        input [4:0] tag, input [5:0] phys
    );
        begin
            issue_valid = 1;
            issue_opcode = op;
            issue_Vj = vj;
            issue_Vk = vk;
            issue_rob_tag = tag;
            issue_phys_dest = phys;
            @(posedge clk); #1; // s2 latches
            clear_issue;
            @(posedge clk); #1; // s3 latches
            @(posedge clk); #1; // s4 latches, output available
        end
    endtask

    // IEEE 754 double constants
    localparam [63:0] FP_0    = 64'h0000000000000000;
    localparam [63:0] FP_N0   = 64'h8000000000000000;
    localparam [63:0] FP_1    = 64'h3FF0000000000000;
    localparam [63:0] FP_N1   = 64'hBFF0000000000000;
    localparam [63:0] FP_2    = 64'h4000000000000000;
    localparam [63:0] FP_3    = 64'h4008000000000000;
    localparam [63:0] FP_4    = 64'h4010000000000000;
    localparam [63:0] FP_5    = 64'h4014000000000000;
    localparam [63:0] FP_10   = 64'h4024000000000000;
    localparam [63:0] FP_0_5  = 64'h3FE0000000000000;
    localparam [63:0] FP_0_25 = 64'h3FD0000000000000;
    localparam [63:0] FP_INF  = 64'h7FF0000000000000;
    localparam [63:0] FP_NINF = 64'hFFF0000000000000;

    initial begin
        $display("=== fpu Testbench ===");
        reset = 1; flush = 0;
        clear_issue;
        @(posedge clk); #1;
        @(posedge clk); #1;
        reset = 0;

        // --- eu_busy ---
        test_num = test_num + 1;
        if (eu_busy === 1'b0) begin
            $display("  PASS %0d: eu_busy is 0", test_num);
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL %0d: eu_busy should be 0", test_num);
            fail_count = fail_count + 1;
        end

        // ===================== ADDF tests =====================

        // 1.0 + 2.0 = 3.0
        issue_and_wait(OP_ADDF, FP_1, FP_2, 5'd1, 6'd32);
        check(FP_3, 5'd1, 6'd32, "ADDF: 1.0 + 2.0 = 3.0");

        // 0.0 + 5.0 = 5.0
        issue_and_wait(OP_ADDF, FP_0, FP_5, 5'd2, 6'd33);
        check(FP_5, 5'd2, 6'd33, "ADDF: 0.0 + 5.0 = 5.0");

        // 5.0 + 0.0 = 5.0
        issue_and_wait(OP_ADDF, FP_5, FP_0, 5'd3, 6'd34);
        check(FP_5, 5'd3, 6'd34, "ADDF: 5.0 + 0.0 = 5.0");

        // 1.0 + (-1.0) = 0.0
        issue_and_wait(OP_ADDF, FP_1, FP_N1, 5'd4, 6'd35);
        check(FP_0, 5'd4, 6'd35, "ADDF: 1.0 + (-1.0) = 0.0");

        // inf + 1.0 = inf
        issue_and_wait(OP_ADDF, FP_INF, FP_1, 5'd5, 6'd36);
        check(FP_INF, 5'd5, 6'd36, "ADDF: inf + 1.0 = inf");

        // inf + (-inf) = NaN
        issue_and_wait(OP_ADDF, FP_INF, FP_NINF, 5'd6, 6'd37);
        check_nan("ADDF: inf + (-inf) = NaN");

        // ===================== SUBF tests =====================

        // 3.0 - 1.0 = 2.0
        issue_and_wait(OP_SUBF, FP_3, FP_1, 5'd7, 6'd38);
        check(FP_2, 5'd7, 6'd38, "SUBF: 3.0 - 1.0 = 2.0");

        // 1.0 - 1.0 = 0.0
        issue_and_wait(OP_SUBF, FP_1, FP_1, 5'd8, 6'd39);
        check(FP_0, 5'd8, 6'd39, "SUBF: 1.0 - 1.0 = 0.0");

        // 0.0 - 5.0 = -5.0
        issue_and_wait(OP_SUBF, FP_0, FP_5, 5'd9, 6'd40);
        check(64'hC014000000000000, 5'd9, 6'd40, "SUBF: 0.0 - 5.0 = -5.0");

        // 1.0 - (-1.0) = 2.0
        issue_and_wait(OP_SUBF, FP_1, FP_N1, 5'd10, 6'd41);
        check(FP_2, 5'd10, 6'd41, "SUBF: 1.0 - (-1.0) = 2.0");

        // inf - inf = NaN
        issue_and_wait(OP_SUBF, FP_INF, FP_INF, 5'd11, 6'd42);
        check_nan("SUBF: inf - inf = NaN");

        // ===================== MULF tests =====================

        // 2.0 * 3.0 = 6.0
        issue_and_wait(OP_MULF, FP_2, FP_3, 5'd12, 6'd43);
        check(64'h4018000000000000, 5'd12, 6'd43, "MULF: 2.0 * 3.0 = 6.0");

        // 1.0 * 0.0 = 0.0
        issue_and_wait(OP_MULF, FP_1, FP_0, 5'd13, 6'd44);
        check(FP_0, 5'd13, 6'd44, "MULF: 1.0 * 0.0 = 0.0");

        // -1.0 * 2.0 = -2.0
        issue_and_wait(OP_MULF, FP_N1, FP_2, 5'd14, 6'd45);
        check(64'hC000000000000000, 5'd14, 6'd45, "MULF: -1.0 * 2.0 = -2.0");

        // 0.5 * 0.5 = 0.25
        issue_and_wait(OP_MULF, FP_0_5, FP_0_5, 5'd15, 6'd46);
        check(FP_0_25, 5'd15, 6'd46, "MULF: 0.5 * 0.5 = 0.25");

        // 0 * inf = NaN
        issue_and_wait(OP_MULF, FP_0, FP_INF, 5'd16, 6'd47);
        check_nan("MULF: 0 * inf = NaN");

        // ===================== DIVF tests =====================

        // 10.0 / 2.0 = 5.0
        issue_and_wait(OP_DIVF, FP_10, FP_2, 5'd17, 6'd48);
        check(FP_5, 5'd17, 6'd48, "DIVF: 10.0 / 2.0 = 5.0");

        // 1.0 / 1.0 = 1.0
        issue_and_wait(OP_DIVF, FP_1, FP_1, 5'd18, 6'd49);
        check(FP_1, 5'd18, 6'd49, "DIVF: 1.0 / 1.0 = 1.0");

        // 0.0 / 5.0 = 0.0
        issue_and_wait(OP_DIVF, FP_0, FP_5, 5'd19, 6'd50);
        check(FP_0, 5'd19, 6'd50, "DIVF: 0.0 / 5.0 = 0.0");

        // 1.0 / 0.0 = inf
        issue_and_wait(OP_DIVF, FP_1, FP_0, 5'd20, 6'd51);
        check(FP_INF, 5'd20, 6'd51, "DIVF: 1.0 / 0.0 = inf");

        // 0.0 / 0.0 = NaN
        issue_and_wait(OP_DIVF, FP_0, FP_0, 5'd21, 6'd52);
        check_nan("DIVF: 0.0 / 0.0 = NaN");

        // -1.0 / 2.0 = -0.5
        issue_and_wait(OP_DIVF, FP_N1, FP_2, 5'd22, 6'd53);
        check(64'hBFE0000000000000, 5'd22, 6'd53, "DIVF: -1.0 / 2.0 = -0.5");

        // ===================== Pipeline tests =====================

        // Flush in middle of pipeline
        issue_valid = 1; issue_opcode = OP_ADDF;
        issue_Vj = FP_1; issue_Vk = FP_2;
        issue_rob_tag = 5'd23; issue_phys_dest = 6'd54;
        @(posedge clk); #1;
        clear_issue;
        flush = 1;
        @(posedge clk); #1;
        flush = 0;
        @(posedge clk); #1;
        @(posedge clk); #1;
        test_num = test_num + 1;
        if (cdb_valid === 1'b0) begin
            $display("  PASS %0d: flush clears FPU pipeline", test_num);
            pass_count = pass_count + 1;
        end else begin
            $display("  FAIL %0d: cdb_valid should be 0 after flush", test_num);
            fail_count = fail_count + 1;
        end

        // Pipeline throughput: issue back-to-back
        issue_valid = 1; issue_opcode = OP_ADDF;
        issue_Vj = FP_1; issue_Vk = FP_1;
        issue_rob_tag = 5'd24; issue_phys_dest = 6'd55;
        @(posedge clk); #1; // s2 latches 1st
        issue_Vj = FP_2; issue_Vk = FP_2;
        issue_rob_tag = 5'd25; issue_phys_dest = 6'd56;
        @(posedge clk); #1; // s2 latches 2nd, s3 has 1st
        clear_issue;
        @(posedge clk); #1; // s4 has 1st, s3 has 2nd
        // 1st result now at s4 output
        check(FP_2, 5'd24, 6'd55, "Pipeline: 1st result (1+1=2)");
        @(posedge clk); #1; // s4 has 2nd
        check(FP_4, 5'd25, 6'd56, "Pipeline: 2nd result (2+2=4)");

        $display("\n=== Results: %0d passed, %0d failed out of %0d ===", pass_count, fail_count, test_num);
        if (fail_count == 0) $display("ALL TESTS PASSED");
        $finish;
    end
endmodule
