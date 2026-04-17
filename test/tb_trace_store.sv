`timescale 1ns/1ps
`include "tinker.sv"

module tb_trace_store;
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

    function [31:0] enc_halt;
        begin
            enc_halt = {5'h0f, 27'b0};
        end
    endfunction

    integer cyc;

    initial begin
        clk = 0;
        reset = 1;
        write_instr(64'h2000, enc3(5'h13, 5'd2, 5'd1, 5'd0));
        write_instr(64'h2004, enc_halt());
        @(posedge clk);
        @(posedge clk);
        reset = 0;
        @(posedge clk);
        dut.reg_file.registers[1] = 64'h1122_3344_5566_7788;
        dut.reg_file.registers[2] = 64'h3000;

        for (cyc = 0; cyc < 15; cyc = cyc + 1) begin
            @(posedge clk);
            $display("cyc=%0d pc0=%h v0=%b instr0=%h d0=%b robcnt=%0d sq0v=%b sq0addr=%h sq0data=%h commit0=%b isstore=%b mwr=%b maddr=%h mdata=%h hlt=%b",
                cyc,
                dut.fetch_unit.out_pc0,
                dut.fetch_unit.out_valid0,
                dut.fetch_unit.out_instr0,
                dut.dispatch0_en,
                dut.rob_inst.count,
                dut.lsq_inst.sq_v[0],
                dut.lsq_inst.sq_addr[0],
                dut.lsq_inst.sq_data[0],
                dut.commit0_en,
                dut.commit0_is_store,
                dut.core_mem_wr_en,
                dut.core_mem_wr_addr,
                dut.core_mem_wr_data,
                hlt);
        end
        $finish;
    end
endmodule
