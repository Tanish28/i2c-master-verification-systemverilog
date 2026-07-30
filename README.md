# Verification of I2C Master Controller using Constrained Random SystemVerilog Testbench

## Project Overview

This project focuses on the functional verification of an I2C Master Controller using a constrained-random SystemVerilog testbench. The objective is to verify that the RTL correctly performs I2C read and write operations while handling acknowledgments and protocol timing.

The verification environment generates randomized transactions and checks the DUT behavior using a scoreboard.

---

## Features

- RTL implementation of I2C Master Controller
- Constrained Random Transaction Generation
- Driver
- Monitor
- Scoreboard
- Mailbox-based Communication
- Functional Verification of
  - Write Transactions
  - Read Transactions
  - ACK Detection
  - Busy/Done Signals
- Waveform Generation

---

## Project Structure

```
RTL/
    i2c_master.sv

TB/
    i2c_tb.sv

Waveform/
    waveform.png

README.md
```

---

## Design Block Diagram

```
Generator
     |
Mailbox
     |
Driver ---> DUT (I2C Master)
     |
Monitor
     |
Scoreboard
```

---

## Verification Flow

1. Generator creates randomized I2C transactions.
2. Driver applies transactions to the DUT.
3. DUT performs I2C read/write operation.
4. Monitor observes DUT outputs.
5. Scoreboard compares expected and actual results.
6. Waveforms are generated for analysis.

---

## Random Constraints

### Slave Address

```systemverilog
constraint addr_c {
    addr inside {[7'h10:7'h60]};
}
```

### Read/Write Distribution

```systemverilog
constraint rw_c {
    rw dist {0:=1, 1:=1};
}
```

---

## Simulation Result

Example scoreboard output

```
PASS = 5
FAIL = 0
```

---

## Waveform

The following waveform shows successful execution of multiple randomized I2C transactions.

![Waveform](Waveform/waveform.png)

---

## Tools Used

- SystemVerilog
- GTKWave
- Icarus Verilog
- GitHub

---

## Authors

ECE Mini Project
Verification of I2C Master Controller using Constraint Random SystemVerilog Testbench
