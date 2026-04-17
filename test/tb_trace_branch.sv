`timescale 1ns/1ps
`include "tinker.sv"

module tb_trace_branch;
    reg clk, reset;
    wire hlt;

    tinker_core dut (.clk(clk), .reset(reset), .hlt(hlt));

    always #5 clk = ~clk;

    task write_instr;
        input [63:0] addr;
        input [31:0] instr;
        begin
            dut.memory.bytes[addr]   = instr[7:0];
            dut.memory.bytes[addr+1] = instr[15:8];
            dut.memory.bytes[addr+2] = instr[23:16];
            dut.memory.bytes[addr+3] = instr[31:24];
        end
    endtask

    function [31:0] enc3;
        input [4:0] op, d, s, t;
        begin
            enc3 = {op, d, s, t, 12'b0};
        end
    endfunction

    function [31:0] encL;
        input [4:0] op, d;
        input [11:0] L;
        begin
            encL = {op, d, 10'b0, L};
        end
    endfunction

    function [31:0] enc_halt;
        begin
            enc_halt = {5'h0f, 27'b0};
        end
    endfunction

    integer cyc;

    initial begin
        clk = 0;
        reset = 1;
        write_instr(64'h2000, enc3(5'h08, 5'd1, 5'd0, 5'd0));
        write_instr(64'h2004, encL(5'h19, 5'd0, 12'd1));
        write_instr(64'h2010, enc_halt());
        @(posedge clk);
        @(posedge clk);
        reset = 0;
        @(posedge clk);
        dut.reg_file.registers[0] = 64'd110;
        dut.reg_file.registers[1] = 64'h2010;

        for (cyc = 0; cyc < 20; cyc = cyc + 1) begin
            @(posedge clk);
            $display("cyc=%0d pc0=%h v0=%b instr0=%h d0=%b robh=%0d robt=%0d robcnt=%0d rvalid0=%b rready0=%b ishalt0=%b flush=%b hlt=%b commit0=%b areg0=%0d",
                cyc,
                dut.fetch_unit.out_pc0,
                dut.fetch_unit.out_valid0,
                dut.fetch_unit.out_instr0,
                dut.dispatch0_en,
                dut.rob_inst.head,
                dut.rob_inst.tail,
                dut.rob_inst.count,
                dut.rob_inst.r_valid[0],
                dut.rob_inst.r_ready[0],
                dut.rob_inst.r_is_halt[0],
                dut.flush_sig,
                hlt,
                dut.commit0_en,
                dut.commit0_areg);
        end
        $finish;
    end
endmodule
