`timescale 1ns/1ps
`include "hdl/fetch.sv"

module tb_fetch;
    reg clk;
    reg reset;
    reg stall;
    reg consume;
    reg consume_slot0_only;
    reg flush;
    reg [63:0] flush_pc;
    reg bp0_update;
    reg [63:0] bp0_pc;
    reg bp0_taken;
    reg [63:0] bp0_target;
    reg bp1_update;
    reg [63:0] bp1_pc;
    reg bp1_taken;
    reg [63:0] bp1_target;
    reg [31:0] mem_instr0;
    reg [31:0] mem_instr1;

    wire [63:0] fetch_pc0;
    wire [63:0] fetch_pc1;
    wire out_valid0;
    wire [31:0] out_instr0;
    wire [63:0] out_pc0;
    wire out_valid1;
    wire [31:0] out_instr1;
    wire [63:0] out_pc1;
    wire [63:0] out_pred_pc0;
    wire [63:0] out_pred_pc1;
    wire [63:0] out_pred_pc;

    integer failures;

    fetch dut (
        .clk(clk),
        .reset(reset),
        .stall(stall),
        .consume(consume),
        .consume_slot0_only(consume_slot0_only),
        .flush(flush),
        .flush_pc(flush_pc),
        .bp0_update(bp0_update),
        .bp0_pc(bp0_pc),
        .bp0_taken(bp0_taken),
        .bp0_target(bp0_target),
        .bp1_update(bp1_update),
        .bp1_pc(bp1_pc),
        .bp1_taken(bp1_taken),
        .bp1_target(bp1_target),
        .mem_instr0(mem_instr0),
        .mem_instr1(mem_instr1),
        .fetch_pc0(fetch_pc0),
        .fetch_pc1(fetch_pc1),
        .out_valid0(out_valid0),
        .out_instr0(out_instr0),
        .out_pc0(out_pc0),
        .out_valid1(out_valid1),
        .out_instr1(out_instr1),
        .out_pc1(out_pc1),
        .out_pred_pc0(out_pred_pc0),
        .out_pred_pc1(out_pred_pc1),
        .out_pred_pc(out_pred_pc)
    );

    always #5 clk = ~clk;

    always @(*) begin
        mem_instr0 = fetch_pc0[31:0] | 32'h1;
        mem_instr1 = fetch_pc1[31:0] | 32'h1;
    end

    initial begin
        clk = 0;
        reset = 1;
        stall = 0;
        consume = 0;
        consume_slot0_only = 0;
        flush = 0;
        flush_pc = 0;
        bp0_update = 0;
        bp0_pc = 0;
        bp0_taken = 0;
        bp0_target = 0;
        bp1_update = 0;
        bp1_pc = 0;
        bp1_taken = 0;
        bp1_target = 0;
        failures = 0;

        @(posedge clk);
        @(posedge clk);
        reset = 0;
        #1;
        if (fetch_pc0 !== 64'h2000) begin
            $display("FAIL fetch 1: fetch_pc0=%h", fetch_pc0);
            failures = failures + 1;
        end

        @(posedge clk);
        #1;
        if (!out_valid0 || !out_valid1 || out_pc0 !== 64'h2000 || out_pc1 !== 64'h2004) begin
            $display("FAIL fetch 2: v0=%b v1=%b pc0=%h pc1=%h", out_valid0, out_valid1, out_pc0, out_pc1);
            failures = failures + 1;
        end

        stall = 1;
        @(posedge clk);
        #1;
        if (!out_valid0 || !out_valid1 || out_pc0 !== 64'h2000 || out_pc1 !== 64'h2004) begin
            $display("FAIL fetch 3: hold during stall v0=%b v1=%b pc0=%h pc1=%h", out_valid0, out_valid1, out_pc0, out_pc1);
            failures = failures + 1;
        end

        consume = 1;
        @(posedge clk);
        #1;
        if (out_valid0 || out_valid1) begin
            $display("FAIL fetch 4: consume during stall did not clear bundle");
            failures = failures + 1;
        end
        consume = 0;
        stall = 0;

        flush = 1;
        flush_pc = 64'h4000;
        @(posedge clk);
        #1;
        flush = 0;
        if (fetch_pc0 !== 64'h4000 || out_valid0 || out_valid1) begin
            $display("FAIL fetch 5: flush redirect failed");
            failures = failures + 1;
        end

        @(posedge clk);
        #1;
        if (!out_valid0 || out_pc0 !== 64'h4000) begin
            $display("FAIL fetch 6: post-flush dispatch wrong");
            failures = failures + 1;
        end

        consume_slot0_only = 1;
        @(posedge clk);
        #1;
        consume_slot0_only = 0;
        if (!out_valid0 || out_valid1 || out_pc0 !== 64'h4004) begin
            $display("FAIL fetch 7: partial consume shift wrong v0=%b v1=%b pc0=%h", out_valid0, out_valid1, out_pc0);
            failures = failures + 1;
        end

        if (failures == 0) begin
            $display("PASS: fetch");
        end else begin
            $display("FAIL: fetch with %0d failures", failures);
        end
        $finish;
    end
endmodule
