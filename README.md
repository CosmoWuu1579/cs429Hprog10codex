# CS 429H Prog 10 by Cosmo Wu cyw356

## How to Run Testing Code

### Memory testbench
To run the code, run the command below:
```bash
iverilog -g2012 -o vvp/tb_memory test/tb_memory.sv && vvp vvp/tb_memory
```

### Register File testbench
To run the code, run the command below:
```bash
iverilog -g2012 -o vvp/tb_reg_file test/tb_reg_file.sv && vvp vvp/tb_reg_file
```

### Register Alias Table testbench
To run the code, run the command below:
```bash
iverilog -g2012 -o vvp/tb_rat test/tb_rat.sv && vvp vvp/tb_rat
```

### Instruction Fetch testbench
To run the code, run the command below:
```bash
iverilog -g2012 -o vvp/tb_fetch test/tb_fetch.sv && vvp vvp/tb_fetch
```

### Instruction Decoder testbench
To run the code, run the command below:
```bash
iverilog -g2012 -o vvp/tb_instruction_decoder test/tb_instruction_decoder.sv && vvp vvp/tb_instruction_decoder
```

### ALU/LS testbench
To run the code, run the command below:
```bash
iverilog -g2012 -o vvp/tb_alu_ls test/tb_alu_ls.sv && vvp vvp/tb_alu_ls
```

### FPU testbench
To run the code, run the command below:
```bash
iverilog -g2012 -o vvp/tb_fpu hdl/fpu.sv test/tb_fpu.sv && vvp vvp/tb_fpu
```

### Reservation Station testbench
To run the code, run the command below:
```bash
iverilog -g2012 -o vvp/tb_rs test/tb_rs.sv && vvp vvp/tb_rs
```

### Load/Store Queue testbench
To run the code, run the command below:
```bash
iverilog -g2012 -o vvp/tb_lsq test/tb_lsq.sv && vvp vvp/tb_lsq
```

### Reorder Buffer testbench
To run the code, run the command below:
```bash
iverilog -g2012 -o vvp/tb_rob test/tb_rob.sv && vvp vvp/tb_rob
```

### Complete Tinker Core Testing Code
To run the code, run the command below:
```bash
iverilog -g2012 -o vvp/tb_tinker_core test/tb_tinker_core.sv && vvp vvp/tb_tinker_core
```

### Debug Control testbench
To run the code, run the command below:
```bash
iverilog -g2012 -o vvp/tb_debug_control test/tb_debug_control.sv && vvp vvp/tb_debug_control
```
