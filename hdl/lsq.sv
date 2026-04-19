module lsq (
    input  clk,
    input  reset,
    input  wire flush,

    input  wire        ld0_disp_en,
    input  wire [5:0]  ld0_dest_preg,
    input  wire [3:0]  ld0_rob_idx,
    input  wire [63:0] ld0_base,
    input  wire [11:0] ld0_L,
    input  wire        ld1_disp_en,
    input  wire [5:0]  ld1_dest_preg,
    input  wire [3:0]  ld1_rob_idx,
    input  wire [63:0] ld1_base,
    input  wire [11:0] ld1_L,

    input  wire        st_disp_en,
    input  wire [3:0]  st_rob_idx,
    input  wire [63:0] st_base,
    input  wire [63:0] st_data,
    input  wire        st_data_rdy,
    input  wire [5:0]  st_data_preg,
    input  wire [11:0] st_L,

    input  wire        cdb0_valid,
    input  wire [5:0]  cdb0_preg,
    input  wire [63:0] cdb0_data,
    input  wire        cdb1_valid,
    input  wire [5:0]  cdb1_preg,
    input  wire [63:0] cdb1_data,

    output reg  [63:0] mem_rd_addr,
    input  wire [63:0] mem_rd_data,
    input  wire        ld_cdb_grant,
    output reg         ld_cdb_valid,
    output reg  [63:0] ld_cdb_data,
    output reg  [5:0]  ld_cdb_preg,
    output reg  [3:0]  ld_cdb_rob,

    input  wire        st_commit_en,
    input  wire [3:0]  st_commit_rob,
    output reg         mem_wr_en,
    output reg  [63:0] mem_wr_addr,
    output reg  [63:0] mem_wr_data,
    output wire        ld_full,
    output wire        st_full,
    output wire        ld_one_avail,
    output wire        ld_two_avail,
    output wire        st_one_avail
);
    localparam LQ_DEPTH = 8;
    localparam SQ_DEPTH = 4;
    localparam CQ_DEPTH = 8;

    reg        lq_v    [0:LQ_DEPTH-1];
    reg [5:0]  lq_preg [0:LQ_DEPTH-1];
    reg [3:0]  lq_rob  [0:LQ_DEPTH-1];
    reg [63:0] lq_addr [0:LQ_DEPTH-1];

    reg        cq_v    [0:CQ_DEPTH-1];
    reg [63:0] cq_data [0:CQ_DEPTH-1];
    reg [5:0]  cq_preg [0:CQ_DEPTH-1];
    reg [3:0]  cq_rob  [0:CQ_DEPTH-1];

    reg        sq_v     [0:SQ_DEPTH-1];
    reg [3:0]  sq_rob   [0:SQ_DEPTH-1];
    reg [63:0] sq_addr  [0:SQ_DEPTH-1];
    reg [63:0] sq_data  [0:SQ_DEPTH-1];
    reg        sq_drdy  [0:SQ_DEPTH-1];
    reg [5:0]  sq_dpreg [0:SQ_DEPTH-1];

    reg [1:0] sq_head, sq_tail;
    reg [2:0] sq_count;
    reg [2:0] lq_head, lq_tail;
    reg [3:0] lq_count;
    reg [2:0] cq_head, cq_tail;
    reg [3:0] cq_count;

    integer i;
    reg [63:0] fwd_data;
    reg        fwd_found;
    reg        store_commit_fire;
    reg        load_issue_fire;
    reg        load_direct_cdb_fire;
    reg [63:0] load_issue_data;
    reg [3:0]  eff_cq_count;

    assign ld_full = (lq_count >= LQ_DEPTH - 1) || (eff_cq_count >= CQ_DEPTH - 1);
    assign st_full = (sq_count >= SQ_DEPTH - 1);
    assign ld_one_avail = (lq_count < LQ_DEPTH) && (eff_cq_count < CQ_DEPTH);
    assign ld_two_avail = (lq_count <= LQ_DEPTH - 2) && (eff_cq_count <= CQ_DEPTH - 2);
    assign st_one_avail = (sq_count < SQ_DEPTH);

    always @(*) begin
        store_commit_fire = st_commit_en && sq_v[sq_head] && sq_drdy[sq_head];
        mem_wr_en = store_commit_fire;
        mem_wr_addr = sq_addr[sq_head];
        mem_wr_data = sq_data[sq_head];
    end

    always @(*) begin
        mem_rd_addr = lq_v[lq_head] ? lq_addr[lq_head] : 64'd0;
    end

    always @(*) begin
        fwd_data = 64'd0;
        fwd_found = 1'b0;
        for (i = 0; i < SQ_DEPTH; i = i + 1) begin
            if (sq_v[i] && sq_drdy[i] && sq_addr[i] == lq_addr[lq_head]) begin
                fwd_data = sq_data[i];
                fwd_found = 1'b1;
            end
        end
    end

    always @(*) begin
        eff_cq_count = cq_count - ((ld_cdb_valid && ld_cdb_grant) ? 4'd1 : 4'd0);
        load_issue_fire = lq_v[lq_head] && (cq_count < CQ_DEPTH);
        load_direct_cdb_fire = load_issue_fire && !ld_cdb_valid && (cq_count == 0);
        load_issue_data = fwd_found ? fwd_data : mem_rd_data;
    end

    always @(posedge clk) begin
        reg lq_push;
        reg lq_pop;
        reg [1:0] lq_push_count;
        reg sq_push;
        reg sq_pop;
        reg cq_push;
        reg cq_pop;
        if (reset || flush) begin
            for (i = 0; i < LQ_DEPTH; i = i + 1) begin
                lq_v[i] <= 0;
                cq_v[i] <= 0;
            end
            for (i = 0; i < SQ_DEPTH; i = i + 1) sq_v[i] <= 0;
            lq_head <= 0;
            lq_tail <= 0;
            lq_count <= 0;
            cq_head <= 0;
            cq_tail <= 0;
            cq_count <= 0;
            sq_head <= 0;
            sq_tail <= 0;
            sq_count <= 0;
            ld_cdb_valid <= 0;
            ld_cdb_data <= 0;
            ld_cdb_preg <= 0;
            ld_cdb_rob <= 0;
        end else begin
            lq_push = 0;
            lq_pop = 0;
            lq_push_count = 0;
            sq_push = 0;
            sq_pop = 0;
            cq_push = 0;
            cq_pop = 0;

            for (i = 0; i < SQ_DEPTH; i = i + 1) begin
                if (sq_v[i] && !sq_drdy[i]) begin
                    if (cdb0_valid && sq_dpreg[i] == cdb0_preg) begin
                        sq_data[i] <= cdb0_data;
                        sq_drdy[i] <= 1;
                    end else if (cdb1_valid && sq_dpreg[i] == cdb1_preg) begin
                        sq_data[i] <= cdb1_data;
                        sq_drdy[i] <= 1;
                    end
                end
            end

            if (ld0_disp_en && (lq_count + lq_push_count < LQ_DEPTH)) begin
                lq_v[lq_tail + lq_push_count] <= 1;
                lq_preg[lq_tail + lq_push_count] <= ld0_dest_preg;
                lq_rob[lq_tail + lq_push_count] <= ld0_rob_idx;
                lq_addr[lq_tail + lq_push_count] <= ld0_base + {{52{ld0_L[11]}}, ld0_L};
                lq_push = 1;
                lq_push_count = lq_push_count + 1'b1;
            end

            if (ld1_disp_en && (lq_count + lq_push_count < LQ_DEPTH)) begin
                lq_v[lq_tail + lq_push_count] <= 1;
                lq_preg[lq_tail + lq_push_count] <= ld1_dest_preg;
                lq_rob[lq_tail + lq_push_count] <= ld1_rob_idx;
                lq_addr[lq_tail + lq_push_count] <= ld1_base + {{52{ld1_L[11]}}, ld1_L};
                lq_push = 1;
                lq_push_count = lq_push_count + 1'b1;
            end

            if (st_disp_en && sq_count < SQ_DEPTH) begin
                sq_v[sq_tail] <= 1;
                sq_rob[sq_tail] <= st_rob_idx;
                sq_addr[sq_tail] <= st_base + {{52{st_L[11]}}, st_L};
                sq_data[sq_tail] <= st_data;
                sq_drdy[sq_tail] <= st_data_rdy;
                sq_dpreg[sq_tail] <= st_data_preg;
                sq_tail <= sq_tail + 1'b1;
                sq_push = 1;
            end

            if (load_issue_fire) begin
                if (load_direct_cdb_fire) begin
                    ld_cdb_valid <= 1;
                    ld_cdb_data <= load_issue_data;
                    ld_cdb_preg <= lq_preg[lq_head];
                    ld_cdb_rob <= lq_rob[lq_head];
                end else begin
                    cq_v[cq_tail] <= 1;
                    cq_data[cq_tail] <= load_issue_data;
                    cq_preg[cq_tail] <= lq_preg[lq_head];
                    cq_rob[cq_tail] <= lq_rob[lq_head];
                    cq_tail <= cq_tail + 1'b1;
                    cq_push = 1;
                end
                lq_v[lq_head] <= 0;
                lq_pop = 1;
            end

            if (ld_cdb_valid) begin
                if (ld_cdb_grant) begin
                    if (cq_v[cq_head]) begin
                        cq_v[cq_head] <= 0;
                        cq_head <= cq_head + 1'b1;
                        cq_pop = 1;
                        if (cq_count > 4'd1) begin
                            ld_cdb_valid <= 1;
                            ld_cdb_data <= cq_data[cq_head + 1'b1];
                            ld_cdb_preg <= cq_preg[cq_head + 1'b1];
                            ld_cdb_rob <= cq_rob[cq_head + 1'b1];
                        end else begin
                            ld_cdb_valid <= 0;
                        end
                    end else begin
                        ld_cdb_valid <= 0;
                    end
                end
            end else if (cq_v[cq_head]) begin
                ld_cdb_valid <= 1;
                ld_cdb_data <= cq_data[cq_head];
                ld_cdb_preg <= cq_preg[cq_head];
                ld_cdb_rob <= cq_rob[cq_head];
            end

            if (store_commit_fire) begin
                sq_v[sq_head] <= 0;
                sq_head <= sq_head + 1'b1;
                sq_pop = 1;
            end

            if (lq_pop)
                lq_head <= lq_head + 1'b1;
            if (lq_push)
                lq_tail <= lq_tail + lq_push_count;
            lq_count <= lq_count + lq_push_count - (lq_pop ? 1'b1 : 1'b0);

            case ({cq_push, cq_pop})
                2'b10: cq_count <= cq_count + 1'b1;
                2'b01: cq_count <= cq_count - 1'b1;
                default: cq_count <= cq_count;
            endcase

            case ({sq_push, sq_pop})
                2'b10: sq_count <= sq_count + 1'b1;
                2'b01: sq_count <= sq_count - 1'b1;
                default: sq_count <= sq_count;
            endcase
        end
    end
endmodule
