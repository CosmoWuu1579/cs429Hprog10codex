// Unit tests for lsq.sv — Load/Store Queue.
// Tests: load dispatch + memory access, store dispatch + commit, store-to-load forwarding,
// CDB snoop for store data, flush.
`timescale 1ns/1ps
`include "hdl/lsq.sv"

module tb_lsq;
    reg  clk, reset, flush;

    // Load dispatch
    reg         ld_disp_en;
    reg  [5:0]  ld_dest_preg;
    reg  [3:0]  ld_rob_idx;
    reg  [63:0] ld_base;
    reg  [11:0] ld_L;

    // Store dispatch
    reg         st_disp_en;
    reg  [3:0]  st_rob_idx;
    reg  [63:0] st_base, st_data;
    reg         st_data_rdy;
    reg  [5:0]  st_data_preg;
    reg  [11:0] st_L;

    // CDB
    reg         cdb0_valid, cdb1_valid;
    reg  [5:0]  cdb0_preg, cdb1_preg;
    reg  [63:0] cdb0_data, cdb1_data;

    // Memory read
    wire [63:0] mem_rd_addr;
    reg  [63:0] mem_rd_data;

    // Load CDB output
    wire        ld_cdb_valid;
    wire [63:0] ld_cdb_data;
    wire [5:0]  ld_cdb_preg;
    wire [3:0]  ld_cdb_rob;

    // Store commit
    reg         st_commit_en;
    reg  [3:0]  st_commit_rob;
    wire        mem_wr_en;
    wire [63:0] mem_wr_addr, mem_wr_data;

    wire        ld_full, st_full;

    lsq dut (
        .clk(clk), .reset(reset), .flush(flush),
        .ld_disp_en(ld_disp_en), .ld_dest_preg(ld_dest_preg),
        .ld_rob_idx(ld_rob_idx), .ld_base(ld_base), .ld_L(ld_L),
        .st_disp_en(st_disp_en), .st_rob_idx(st_rob_idx),
        .st_base(st_base), .st_data(st_data), .st_data_rdy(st_data_rdy),
        .st_data_preg(st_data_preg), .st_L(st_L),
        .cdb0_valid(cdb0_valid), .cdb0_preg(cdb0_preg), .cdb0_data(cdb0_data),
        .cdb1_valid(cdb1_valid), .cdb1_preg(cdb1_preg), .cdb1_data(cdb1_data),
        .mem_rd_addr(mem_rd_addr), .mem_rd_data(mem_rd_data),
        .ld_cdb_valid(ld_cdb_valid), .ld_cdb_data(ld_cdb_data),
        .ld_cdb_preg(ld_cdb_preg), .ld_cdb_rob(ld_cdb_rob),
        .st_commit_en(st_commit_en), .st_commit_rob(st_commit_rob),
        .mem_wr_en(mem_wr_en), .mem_wr_addr(mem_wr_addr), .mem_wr_data(mem_wr_data),
        .ld_full(ld_full), .st_full(st_full)
    );

    always #5 clk = ~clk;

    integer failures = 0;

    task reset_inputs;
        begin
            ld_disp_en = 0; st_disp_en = 0; st_commit_en = 0;
            cdb0_valid = 0; cdb1_valid = 0;
            flush = 0; mem_rd_data = 0;
            ld_base = 0; ld_L = 0; ld_dest_preg = 0; ld_rob_idx = 0;
            st_base = 0; st_data = 0; st_data_rdy = 1; st_data_preg = 0;
            st_L = 0; st_rob_idx = 0; st_commit_rob = 0;
        end
    endtask

    initial begin
        clk = 0; reset = 1;
        reset_inputs();
        @(posedge clk); @(posedge clk);
        reset = 0;

        // --- Test 1: Load from memory (no store forwarding) ---
        ld_disp_en = 1; ld_dest_preg = 6'd32; ld_rob_idx = 4'd0;
        ld_base = 64'h1000; ld_L = 12'd8; // addr = 0x1008
        @(posedge clk);
        ld_disp_en = 0;

        // Cycle 1: LSQ issues mem read, sets lq_sent
        @(posedge clk); #1;
        if (mem_rd_addr !== 64'h1008) begin
            $display("FAIL test 1a: mem_rd_addr=%h expect 0x1008", mem_rd_addr);
            failures = failures + 1;
        end

        // Cycle 2: provide data, LSQ reads result and broadcasts on CDB
        mem_rd_data = 64'hDEAD_CAFE;
        @(posedge clk); #1;
        if (!ld_cdb_valid || ld_cdb_data !== 64'hDEAD_CAFE || ld_cdb_preg !== 6'd32) begin
            $display("FAIL test 1b: ld_cdb_valid=%b data=%h preg=%0d",
                ld_cdb_valid, ld_cdb_data, ld_cdb_preg);
            failures = failures + 1;
        end

        // --- Test 2: Store dispatch + commit to memory ---
        reset = 1; @(posedge clk); reset = 0; reset_inputs();

        st_disp_en = 1; st_rob_idx = 4'd0;
        st_base = 64'h2000; st_L = 12'd0; // addr = 0x2000
        st_data = 64'hABCD_1234; st_data_rdy = 1;
        @(posedge clk);
        st_disp_en = 0;

        // Commit the store
        st_commit_en = 1; st_commit_rob = 4'd0;
        @(posedge clk); #1;
        st_commit_en = 0;
        if (!mem_wr_en || mem_wr_addr !== 64'h2000 || mem_wr_data !== 64'hABCD_1234) begin
            $display("FAIL test 2: mem_wr_en=%b addr=%h data=%h",
                mem_wr_en, mem_wr_addr, mem_wr_data);
            failures = failures + 1;
        end

        // --- Test 3: Store-to-load forwarding ---
        reset = 1; @(posedge clk); reset = 0; reset_inputs();

        // First dispatch store to addr 0x3000 with data ready
        st_disp_en = 1; st_rob_idx = 4'd0;
        st_base = 64'h3000; st_L = 12'd0;
        st_data = 64'h1122_3344; st_data_rdy = 1;
        @(posedge clk);
        st_disp_en = 0;

        // Then dispatch load from same addr
        ld_disp_en = 1; ld_dest_preg = 6'd33; ld_rob_idx = 4'd1;
        ld_base = 64'h3000; ld_L = 12'd0;
        @(posedge clk);
        ld_disp_en = 0;

        // Load should forward from store without going to memory
        @(posedge clk); #1;
        if (!ld_cdb_valid || ld_cdb_data !== 64'h1122_3344) begin
            $display("FAIL test 3: store-to-load forward: valid=%b data=%h expect 0x11223344",
                ld_cdb_valid, ld_cdb_data);
            failures = failures + 1;
        end

        // --- Test 4: CDB snoop fills store data ---
        reset = 1; @(posedge clk); reset = 0; reset_inputs();

        // Dispatch store with data NOT ready
        st_disp_en = 1; st_rob_idx = 4'd0;
        st_base = 64'h4000; st_L = 12'd0;
        st_data = 64'h0; st_data_rdy = 0; st_data_preg = 6'd40;
        @(posedge clk);
        st_disp_en = 0;

        // CDB provides value for preg 40
        cdb0_valid = 1; cdb0_preg = 6'd40; cdb0_data = 64'hBEEF_CAFE;
        @(posedge clk); cdb0_valid = 0;

        // Commit — store data should now be ready
        st_commit_en = 1; st_commit_rob = 4'd0;
        @(posedge clk); #1;
        st_commit_en = 0;
        if (!mem_wr_en || mem_wr_data !== 64'hBEEF_CAFE) begin
            $display("FAIL test 4: CDB store data: wr_en=%b data=%h expect BEEFCAFE",
                mem_wr_en, mem_wr_data);
            failures = failures + 1;
        end

        // --- Test 5: Flush clears load queue ---
        reset = 1; @(posedge clk); reset = 0; reset_inputs();

        ld_disp_en = 1; ld_dest_preg = 6'd34; ld_rob_idx = 4'd2;
        ld_base = 64'h5000; ld_L = 12'd0;
        @(posedge clk); ld_disp_en = 0;

        flush = 1; @(posedge clk); flush = 0;
        @(posedge clk); #1;
        if (ld_cdb_valid) begin
            $display("FAIL test 5: ld_cdb_valid after flush, should be cleared");
            failures = failures + 1;
        end

        if (failures == 0)
            $display("PASS: lsq — all 5 tests passed");
        else
            $display("FAIL: lsq — %0d test(s) failed", failures);
        $finish;
    end
endmodule
