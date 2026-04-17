// cpu_pkg.sv - Shared definitions for the Tinker OOO pipelined processor
// Yosys-compatible: no typed localparams, no enum typedefs, old-style functions,
// no automatic keyword on functions, fixed-bound loops only.

`ifndef CPU_PKG_SV
`define CPU_PKG_SV

    // =========================================================================
    // Memory & Architecture Constants
    // =========================================================================
    localparam MEM_SIZE       = 524288;       // 512KB physical memory
    localparam PC_RESET       = 64'h2000;     // Initial PC value
    localparam STACK_INIT     = 524288;       // Initial stack pointer (r31)
    localparam INSTR_WIDTH    = 32;           // Instruction width in bits
    localparam DATA_WIDTH     = 64;           // Data width in bits
    localparam ARCH_REG_COUNT = 32;           // Number of architectural registers
    localparam PHYS_REG_COUNT = 64;           // Number of physical registers
    localparam ARCH_REG_BITS  = 5;            // Bits to address arch registers
    localparam PHYS_REG_BITS  = 6;            // Bits to address phys registers

    // =========================================================================
    // Pipeline Sizing
    // =========================================================================
    localparam FETCH_WIDTH    = 2;            // Dual-issue: fetch 2 instructions/cycle
    localparam ROB_SIZE       = 32;           // Reorder buffer entries
    localparam ROB_TAG_BITS   = 5;            // Bits to address ROB (log2(32))
    localparam RS_ALU_SIZE    = 8;            // ALU reservation station entries
    localparam RS_FPU_SIZE    = 8;            // FPU reservation station entries
    localparam RS_LS_SIZE     = 8;            // Load/store queue entries
    localparam RS_TAG_BITS    = 3;            // Bits for RS index (log2(8))

    // Execution unit counts and pipeline depths
    localparam ALU_COUNT      = 2;            // Number of ALU execution units
    localparam FPU_COUNT      = 2;            // Number of FPU execution units
    localparam ALU_STAGES     = 2;            // ALU pipeline stages
    localparam FPU_STAGES     = 4;            // FPU pipeline stages
    localparam LS_STAGES      = 2;            // Load/store pipeline stages
    localparam RS_BRANCH_SIZE = 4;            // Branch reservation station entries

    // Number of CDB buses (one per execution unit)
    localparam CDB_COUNT      = 7;            // 2 ALU + 2 FPU + 2 LS + 1 Branch

    // =========================================================================
    // Opcode Definitions (5-bit, from instruction[31:27])
    // =========================================================================
    localparam [4:0] OP_AND    = 5'h00;  // rd = rs & rt
    localparam [4:0] OP_OR     = 5'h01;  // rd = rs | rt
    localparam [4:0] OP_XOR    = 5'h02;  // rd = rs ^ rt
    localparam [4:0] OP_NOT    = 5'h03;  // rd = ~rs
    localparam [4:0] OP_SHFTR  = 5'h04;  // rd = rs >> rt
    localparam [4:0] OP_SHFTRI = 5'h05;  // rd = rd >> L
    localparam [4:0] OP_SHFTL  = 5'h06;  // rd = rs << rt
    localparam [4:0] OP_SHFTLI = 5'h07;  // rd = rd << L
    localparam [4:0] OP_BR     = 5'h08;  // PC = rd (unconditional jump)
    localparam [4:0] OP_BRR    = 5'h09;  // PC = PC + rd (relative jump)
    localparam [4:0] OP_BRR_L  = 5'h0A;  // PC = PC + sign_ext(L)
    localparam [4:0] OP_BRNZ   = 5'h0B;  // if (rs != 0) PC = rd
    localparam [4:0] OP_CALL   = 5'h0C;  // push PC+4, PC = rd
    localparam [4:0] OP_RETURN = 5'h0D;  // pop PC from stack
    localparam [4:0] OP_BRGT   = 5'h0E;  // if (signed(rs) > signed(rt)) PC = rd
    localparam [4:0] OP_HALT   = 5'h0F;  // stop execution
    localparam [4:0] OP_LOAD   = 5'h10;  // rd = mem[rs + sign_ext(L)]
    localparam [4:0] OP_MOV    = 5'h11;  // rd = rs
    localparam [4:0] OP_MOVI   = 5'h12;  // rd = {rd[63:12], L}
    localparam [4:0] OP_STORE  = 5'h13;  // mem[rd + sign_ext(L)] = rs
    localparam [4:0] OP_ADDF   = 5'h14;  // rd = rs +f rt (IEEE 754)
    localparam [4:0] OP_SUBF   = 5'h15;  // rd = rs -f rt (IEEE 754)
    localparam [4:0] OP_MULF   = 5'h16;  // rd = rs *f rt (IEEE 754)
    localparam [4:0] OP_DIVF   = 5'h17;  // rd = rs /f rt (IEEE 754)
    localparam [4:0] OP_ADD    = 5'h18;  // rd = rs + rt
    localparam [4:0] OP_ADDI   = 5'h19;  // rd = rd + L
    localparam [4:0] OP_SUB    = 5'h1A;  // rd = rs - rt
    localparam [4:0] OP_SUBI   = 5'h1B;  // rd = rd - L
    localparam [4:0] OP_MUL    = 5'h1C;  // rd = rs * rt
    localparam [4:0] OP_DIV    = 5'h1D;  // rd = signed(rs) / signed(rt)

    // =========================================================================
    // Functional Unit Type Constants
    // =========================================================================
    localparam [2:0] FU_ALU    = 3'd0;   // Integer ALU
    localparam [2:0] FU_FPU    = 3'd1;   // Floating-point unit
    localparam [2:0] FU_LS     = 3'd2;   // Load/store unit
    localparam [2:0] FU_BRANCH = 3'd3;   // Branch unit (handled by ALU)
    localparam [2:0] FU_NONE   = 3'd4;   // No execution needed (HALT)

    // =========================================================================
    // Instruction classification function
    // Returns which functional unit handles a given opcode
    // =========================================================================
    function [2:0] get_fu_type;
        input [4:0] opcode;
        begin
            case (opcode)
                OP_AND, OP_OR, OP_XOR, OP_NOT,
                OP_SHFTR, OP_SHFTRI, OP_SHFTL, OP_SHFTLI,
                OP_ADD, OP_ADDI, OP_SUB, OP_SUBI,
                OP_MUL, OP_DIV,
                OP_MOV, OP_MOVI:                           get_fu_type = FU_ALU;

                OP_ADDF, OP_SUBF, OP_MULF, OP_DIVF:       get_fu_type = FU_FPU;

                OP_LOAD, OP_STORE:                          get_fu_type = FU_LS;

                OP_BR, OP_BRR, OP_BRR_L, OP_BRNZ,
                OP_CALL, OP_RETURN, OP_BRGT:                get_fu_type = FU_BRANCH;

                OP_HALT:                                    get_fu_type = FU_NONE;

                default:                                    get_fu_type = FU_NONE;
            endcase
        end
    endfunction

    // =========================================================================
    // Instruction property helpers
    // =========================================================================

    // Does this instruction write to a destination register?
    function writes_reg;
        input [4:0] opcode;
        begin
            case (opcode)
                OP_AND, OP_OR, OP_XOR, OP_NOT,
                OP_SHFTR, OP_SHFTRI, OP_SHFTL, OP_SHFTLI,
                OP_ADD, OP_ADDI, OP_SUB, OP_SUBI,
                OP_MUL, OP_DIV,
                OP_MOV, OP_MOVI,
                OP_ADDF, OP_SUBF, OP_MULF, OP_DIVF,
                OP_LOAD:                                    writes_reg = 1'b1;
                default:                                    writes_reg = 1'b0;
            endcase
        end
    endfunction

    // Does this instruction read rs (source 1)?
    function reads_rs;
        input [4:0] opcode;
        begin
            case (opcode)
                OP_AND, OP_OR, OP_XOR, OP_NOT,
                OP_SHFTR, OP_SHFTL,
                OP_ADD, OP_SUB, OP_MUL, OP_DIV,
                OP_ADDF, OP_SUBF, OP_MULF, OP_DIVF,
                OP_BRNZ, OP_BRGT,
                OP_MOV,
                OP_LOAD, OP_STORE,
                OP_CALL, OP_RETURN:                         reads_rs = 1'b1;
                default:                                    reads_rs = 1'b0;
            endcase
        end
    endfunction

    // Does this instruction read rt (source 2)?
    function reads_rt;
        input [4:0] opcode;
        begin
            case (opcode)
                OP_AND, OP_OR, OP_XOR,
                OP_SHFTR, OP_SHFTL,
                OP_ADD, OP_SUB, OP_MUL, OP_DIV,
                OP_ADDF, OP_SUBF, OP_MULF, OP_DIVF,
                OP_BRGT:                                    reads_rt = 1'b1;
                default:                                    reads_rt = 1'b0;
            endcase
        end
    endfunction

    // Does this instruction read rd (used as source in some instructions)?
    // SHFTRI, SHFTLI, ADDI, SUBI use rd as both source and dest
    // MOVI uses rd as partial source (keeps upper bits)
    // BR, BRR, BRNZ, BRGT, CALL use rd as branch target
    // STORE uses rd as base address
    function reads_rd;
        input [4:0] opcode;
        begin
            case (opcode)
                OP_SHFTRI, OP_SHFTLI,
                OP_ADDI, OP_SUBI,
                OP_MOVI,
                OP_BR, OP_BRR, OP_BRNZ, OP_BRGT, OP_CALL,
                OP_STORE:                                   reads_rd = 1'b1;
                default:                                    reads_rd = 1'b0;
            endcase
        end
    endfunction

    // Is this a branch/jump instruction?
    function is_branch;
        input [4:0] opcode;
        begin
            case (opcode)
                OP_BR, OP_BRR, OP_BRR_L, OP_BRNZ,
                OP_CALL, OP_RETURN, OP_BRGT:                is_branch = 1'b1;
                default:                                    is_branch = 1'b0;
            endcase
        end
    endfunction

    // Is this a store instruction?
    function is_store;
        input [4:0] opcode;
        begin
            is_store = (opcode == OP_STORE);
        end
    endfunction

    // Is this a load instruction?
    function is_load;
        input [4:0] opcode;
        begin
            is_load = (opcode == OP_LOAD);
        end
    endfunction

    // Does this instruction use the L (immediate) field?
    function uses_imm;
        input [4:0] opcode;
        begin
            case (opcode)
                OP_SHFTRI, OP_SHFTLI,
                OP_BRR_L,
                OP_ADDI, OP_SUBI,
                OP_MOVI,
                OP_LOAD, OP_STORE:                          uses_imm = 1'b1;
                default:                                    uses_imm = 1'b0;
            endcase
        end
    endfunction

    // Does this instruction need the stack pointer? (CALL pushes, RETURN pops)
    function needs_stack;
        input [4:0] opcode;
        begin
            needs_stack = (opcode == OP_CALL || opcode == OP_RETURN);
        end
    endfunction

    // Sign-extend the 12-bit L field to 64 bits
    function [63:0] sign_extend_L;
        input [11:0] L;
        begin
            sign_extend_L = {{52{L[11]}}, L};
        end
    endfunction

`endif // CPU_PKG_SV
