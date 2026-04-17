`timescale 1ns/1ps
`include "hdl/instruction_decoder.sv"

module tb_instruction_decoder;
    reg  [31:0] instruction;
    wire [4:0]  opcode;
    wire [4:0]  d;
    wire [4:0]  s;
    wire [4:0]  t;
    wire [11:0] L;

    integer failures;

    instruction_decoder dut (
        .instruction(instruction),
        .opcode(opcode),
        .d(d),
        .s(s),
        .t(t),
        .L(L)
    );

    task check;
        input [4:0] exp_opcode;
        input [4:0] exp_d;
        input [4:0] exp_s;
        input [4:0] exp_t;
        input [11:0] exp_L;
        input [31:0] id;
        begin
            #1;
            if (opcode !== exp_opcode || d !== exp_d || s !== exp_s || t !== exp_t || L !== exp_L) begin
                $display("FAIL decoder %0d: got op=%h d=%0d s=%0d t=%0d L=%h", id, opcode, d, s, t, L);
                failures = failures + 1;
            end
        end
    endtask

    initial begin
        failures = 0;
        instruction = 32'h0000_0000;
        check(5'h00, 5'd0, 5'd0, 5'd0, 12'd0, 1);

        instruction = 32'hFFFF_FFFF;
        check(5'h1F, 5'd31, 5'd31, 5'd31, 12'hFFF, 2);

        instruction = {5'h18, 5'd3, 5'd1, 5'd2, 12'd0};
        check(5'h18, 5'd3, 5'd1, 5'd2, 12'd0, 3);

        instruction = {5'h10, 5'd2, 5'd4, 5'd0, 12'd16};
        check(5'h10, 5'd2, 5'd4, 5'd0, 12'd16, 4);

        instruction = {5'h0f, 27'b0};
        check(5'h0f, 5'd0, 5'd0, 5'd0, 12'd0, 5);

        if (failures == 0) begin
            $display("PASS: instruction_decoder");
        end else begin
            $display("FAIL: instruction_decoder with %0d failures", failures);
        end
        $finish;
    end
endmodule

