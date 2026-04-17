Plan this as a dual-issue, out-of-order Tomasulo-style pipeline, not a simple in-order 5-stage core. The clean flow is Fetch -> Decode/Rename/Dispatch -> Issue/Wait -> Execute -> CDB Writeback -> Commit, with the ROB, RSes, and LSQ acting as the real “pipeline state” after decode. That matches spec.md, clarifications.md, clarifications2.md, the Tinker manual, and the reusable prog09 blocks in prog09/hdl.

Pipeline Stages

IF: Keep a 64-byte fetch buffer that reads 16 instructions at a time from memory starting at the current fetch PC. Do branch prediction here. Each cycle, supply up to 2 valid instructions plus their PCs and prediction metadata.
ID/RN: Decode 2 instructions, classify each as integer/FP/load/store/branch/halt, read the current RAT mappings for sources, allocate new physical registers for destinations, allocate ROB entries, and dispatch to the correct backend structure. Rename the 2 instructions in program order so same-bundle dependencies are handled correctly.
DISP/QUEUE: Insert integer/branch ops into the integer RS, FP ops into the FP RS, loads/stores into the LSQ, and mark their destination physical registers not-ready. halt allocates a ROB entry but needs no execution unit.
ISSUE: Each cycle, select oldest-ready ops from the integer RS, FP RS, and LSQ. Issue up to 2 integer ops, 2 FP ops, and 2 memory ops if resources are free.
EX: Integer ALUs handle logic, shifts, integer arithmetic, simple moves, and branch target/condition evaluation. FPUs handle addf/subf/mulf/divf. LSU address generation computes effective addresses; loads read memory or forward from older stores; stores only produce address/data and wait for commit.
WB/CDB: Completed ALU/FPU/load results broadcast {valid, rob_idx, dest_preg, value} on a common data bus. RSes snoop it to wake dependents, the physical register file captures the value, and the ROB marks the entry ready.
COMMIT: Retire from the ROB in order. On commit, copy the committed value into the architectural reg_file, free the overwritten physical register, write committed stores to memory, and assert hlt only when a committed priv with L=0 reaches the head.
Module Breakdown

tinker.sv: top-level tinker_core; instantiates the required visible modules and wires frontend, backend, CDB, and commit.
hdl/fetch.sv: fetch PC, 64-byte line buffer, branch predictor, redirect/flush logic.
hdl/instruction_decoder.sv: unchanged single-instruction decoder; instantiate twice.
hdl/rat_prf.sv: RAT, free list, physical register file, ready bits, branch checkpoints.
hdl/rob.sv: reorder buffer, in-order commit, precise-state recovery, halt handling.
hdl/rs.sv: parameterized reservation station; instantiate once for integer/branch and once for FP.
hdl/lsq.sv: load queue + store queue + store-to-load forwarding + memory-order checks.
hdl/fetch_memory_if.sv or folded into memory.sv: optional 64-byte fetch-line read helper if you want to keep fetch logic simple.
hdl/memory.sv: same bytes array, but widened/read-port-adapted for 64-byte fetch and LSU reads; stores still write only at commit.
hdl/alu.sv: integer-only execution unit, reusing the integer/control case logic from prog09/hdl/alu.sv.
hdl/fpu.sv: floating-point execution unit, reusing the FP case logic from prog09/hdl/alu.sv; first instance must be named fpu.
hdl/reg_file.sv: architectural register file visible to the autograder; updated only at commit.
I would not add standalone “pipeline register modules”; keep those as packed structs or arrays inside fetch, rob, rs, and lsq to save files and HDL.

Pipeline Registers / Inter-Stage State

IF/ID latch: valid[1:0], instr[1:0], pc[1:0], pred_taken[1:0], pred_target[1:0].
Decode/rename dispatch packet: opcode, L, pc, rob_idx, dest_arch, dest_preg, old_preg, src*_preg, src*_ready, src*_value, is_int/is_fp/is_load/is_store/is_branch/is_halt, and prediction metadata.
Integer/FP RS entry: valid, opcode, pc, L, rob_idx, dest_preg, src1_tag/value/ready, src2_tag/value/ready, plus branch prediction bits for branches.
LSQ entry: valid, is_load, is_store, is_return, rob_idx, base_tag/value/ready, store_data_tag/value/ready, imm, addr_valid, addr, forwardable.
FU input register: valid, opcode, pc, rob_idx, dest_preg, operand1, operand2, L.
FU result register / CDB packet: valid, rob_idx, dest_preg, result, and for branches taken, actual_target, mispredict.
ROB entry: valid, ready, opcode/class, dest_arch, dest_preg, old_preg, result, is_store, store_addr, store_data, is_branch, pred_taken, pred_target, checkpoint, is_halt.
Hazard Handling

RAW register hazards: solved with renaming plus CDB wakeup. If a source physical register is not ready, the instruction waits in RS/LSQ.
Same-bundle RAW/WAW/WAR hazards: solve in rename by processing slot 0 before slot 1 and letting slot 1 see slot 0’s newly allocated destination mapping.
Load-use hazards: consumer waits on the load’s physical destination tag until the load broadcasts on the CDB.
Store-to-load forwarding: a load checks all older stores in the SQ; if an older store has the same known address and ready data, forward from it.
Memory-order hazards: do not let a load pass an older store with unknown address. If an older matching-address store exists but its data is not ready, stall the load.
Structural hazards: stall dispatch when the ROB is full, free list is empty/low, the target RS is full, or the LSQ is full. Stall issue when all units of the needed type are busy. Arbitrate CDB conflicts with fixed priority.
Control hazards: predict in fetch, resolve when the branch/return executes, and on mispredict flush younger IF/ID entries, RS entries, LSQ entries, and ROB entries; restore RAT/free-list state from the branch checkpoint; redirect fetch immediately.
call: treat as a branch that also creates a committed store of pc+4 to r31-8.
return: treat as a load-like control op through the LSQ; prediction can use the BTB, but actual target comes from memory.
halt: allocate in the ROB, mark ready without an FU, and only assert hlt when it commits at the ROB head.
Control Logic

Generate per-instruction control bits once in decode: source usage, destination write, functional-unit class, memory type, branch type, halt.
Carry those bits inside ROB/RS/LSQ entries instead of recomputing them later.
Keep stall logic centralized near rename/dispatch: dispatch_stall = rob_full || freelist_empty || rs_full || lsq_full.
Give flush highest priority over commit, commit higher priority over normal dispatch/fetch.
Mark newly allocated physical destinations not-ready at rename; mark ready only on CDB writeback.
For precise recovery, checkpoint the RAT and free-list head on each predicted branch.
Reuse Plan

Reuse unchanged: prog09/hdl/instruction_decoder.sv.
Reuse behavior unchanged but repackage: the integer and FP execution logic from prog09/hdl/alu.sv, split into separate alu.sv and fpu.sv wrappers because prog10 requires a distinct FPU module.
Reuse with small interface changes: prog09/hdl/memory.sv and prog09/hdl/reg_file.sv. Keep the required bytes and registers arrays and reset behavior, but adapt them to the pipelined core’s fetch/commit needs.
Replace entirely: prog09/tinker.sv, prog09/hdl/instruction_fetch.sv, and prog09/hdl/control_state.sv. A multicycle FSM is the wrong control structure here.
Write from scratch: fetch.sv, rat_prf.sv, rob.sv, rs.sv, and lsq.sv.
If you want, I can turn this into a build order next: the exact order to implement and test the modules so you can bring the pipeline up incrementally without getting buried.