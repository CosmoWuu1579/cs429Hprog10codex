`timescale 1ns/1ps
`include "hdl/reg_file.sv"

module tb_reg_file;
    reg clk;
    reg reset;
    reg [4:0] d;
    reg [4:0] s;
    reg [4:0] t;
    reg write0;
    reg [4:0] waddr0;
    reg [63:0] wdata0;
    reg write1;
    reg [4:0] waddr1;
    reg [63:0] wdata1;

    wire [63:0] rd;
    wire [63:0] rs;
    wire [63:0] rt;
    wire [63:0] stack_pointer;
    wire [63:0] reg_array_out_0;
    wire [63:0] reg_array_out_1;
    wire [63:0] reg_array_out_2;
    wire [63:0] reg_array_out_3;
    wire [63:0] reg_array_out_4;
    wire [63:0] reg_array_out_5;
    wire [63:0] reg_array_out_6;
    wire [63:0] reg_array_out_7;
    wire [63:0] reg_array_out_8;
    wire [63:0] reg_array_out_9;
    wire [63:0] reg_array_out_10;
    wire [63:0] reg_array_out_11;
    wire [63:0] reg_array_out_12;
    wire [63:0] reg_array_out_13;
    wire [63:0] reg_array_out_14;
    wire [63:0] reg_array_out_15;
    wire [63:0] reg_array_out_16;
    wire [63:0] reg_array_out_17;
    wire [63:0] reg_array_out_18;
    wire [63:0] reg_array_out_19;
    wire [63:0] reg_array_out_20;
    wire [63:0] reg_array_out_21;
    wire [63:0] reg_array_out_22;
    wire [63:0] reg_array_out_23;
    wire [63:0] reg_array_out_24;
    wire [63:0] reg_array_out_25;
    wire [63:0] reg_array_out_26;
    wire [63:0] reg_array_out_27;
    wire [63:0] reg_array_out_28;
    wire [63:0] reg_array_out_29;
    wire [63:0] reg_array_out_30;
    wire [63:0] reg_array_out_31;

    integer failures;

    register_file dut (
        .clk(clk),
        .reset(reset),
        .reg_array_out_0(reg_array_out_0),
        .reg_array_out_1(reg_array_out_1),
        .reg_array_out_2(reg_array_out_2),
        .reg_array_out_3(reg_array_out_3),
        .reg_array_out_4(reg_array_out_4),
        .reg_array_out_5(reg_array_out_5),
        .reg_array_out_6(reg_array_out_6),
        .reg_array_out_7(reg_array_out_7),
        .reg_array_out_8(reg_array_out_8),
        .reg_array_out_9(reg_array_out_9),
        .reg_array_out_10(reg_array_out_10),
        .reg_array_out_11(reg_array_out_11),
        .reg_array_out_12(reg_array_out_12),
        .reg_array_out_13(reg_array_out_13),
        .reg_array_out_14(reg_array_out_14),
        .reg_array_out_15(reg_array_out_15),
        .reg_array_out_16(reg_array_out_16),
        .reg_array_out_17(reg_array_out_17),
        .reg_array_out_18(reg_array_out_18),
        .reg_array_out_19(reg_array_out_19),
        .reg_array_out_20(reg_array_out_20),
        .reg_array_out_21(reg_array_out_21),
        .reg_array_out_22(reg_array_out_22),
        .reg_array_out_23(reg_array_out_23),
        .reg_array_out_24(reg_array_out_24),
        .reg_array_out_25(reg_array_out_25),
        .reg_array_out_26(reg_array_out_26),
        .reg_array_out_27(reg_array_out_27),
        .reg_array_out_28(reg_array_out_28),
        .reg_array_out_29(reg_array_out_29),
        .reg_array_out_30(reg_array_out_30),
        .reg_array_out_31(reg_array_out_31),
        .d(d),
        .s(s),
        .t(t),
        .rd(rd),
        .rs(rs),
        .rt(rt),
        .stack_pointer(stack_pointer),
        .write0(write0),
        .waddr0(waddr0),
        .wdata0(wdata0),
        .write1(write1),
        .waddr1(waddr1),
        .wdata1(wdata1)
    );

    always #5 clk = ~clk;

    task check_values;
        input [63:0] exp_rd;
        input [63:0] exp_rs;
        input [63:0] exp_rt;
        input [31:0] id;
        begin
            #1;
            if (rd !== exp_rd || rs !== exp_rs || rt !== exp_rt) begin
                $display("FAIL reg_file %0d: rd=%h rs=%h rt=%h", id, rd, rs, rt);
                failures = failures + 1;
            end
        end
    endtask

    initial begin
        clk = 0;
        reset = 1;
        d = 0;
        s = 0;
        t = 0;
        write0 = 0;
        waddr0 = 0;
        wdata0 = 0;
        write1 = 0;
        waddr1 = 0;
        wdata1 = 0;
        failures = 0;

        @(posedge clk);
        @(posedge clk);
        reset = 0;
        @(posedge clk);

        d = 5'd0;
        s = 5'd31;
        t = 5'd1;
        check_values(64'd0, 64'd524288, 64'd0, 1);

        write0 = 1;
        waddr0 = 5'd5;
        wdata0 = 64'hDEAD_BEEF;
        @(posedge clk);
        #1;
        write0 = 0;
        d = 5'd5;
        s = 5'd5;
        t = 5'd5;
        check_values(64'hDEAD_BEEF, 64'hDEAD_BEEF, 64'hDEAD_BEEF, 2);

        write0 = 1;
        waddr0 = 5'd10;
        wdata0 = 64'd100;
        write1 = 1;
        waddr1 = 5'd11;
        wdata1 = 64'd200;
        @(posedge clk);
        #1;
        write0 = 0;
        write1 = 0;
        d = 5'd10;
        s = 5'd11;
        t = 5'd0;
        check_values(64'd100, 64'd200, 64'd0, 3);

        if (stack_pointer !== 64'd524288 || reg_array_out_31 !== 64'd524288) begin
            $display("FAIL reg_file 4: stack pointer path incorrect");
            failures = failures + 1;
        end

        if (failures == 0) begin
            $display("PASS: reg_file");
        end else begin
            $display("FAIL: reg_file with %0d failures", failures);
        end
        $finish;
    end
endmodule
