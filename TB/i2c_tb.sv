`timescale 1ns/1ps

// ============================================================
// 1. INTERFACE
// ============================================================
interface i2c_if(input logic clk);
    logic rst_n, start, rw;
    logic [6:0] slave_addr;
    logic [7:0] data_in;
    logic [7:0] data_out;
    logic busy, done, ack_error;
    wire  sda;
    wire  scl;
endinterface

// ============================================================
// 2. TRANSACTION
// ============================================================
class transaction;
    rand bit [6:0] addr;
    rand bit       rw;      // 0 = write, 1 = read
    rand bit [7:0] data;
    bit [7:0] data_read;
    bit ack_err;

    constraint addr_c { addr inside {[7'h10:7'h60]}; }
    constraint rw_c   { rw dist {0:=1, 1:=1}; }

    function void display(string tag);
        $display("[%0t] [%s] addr=%h rw=%b data=%h", $time, tag, addr, rw, data);
    endfunction
endclass

// ============================================================
// 3. GENERATOR
// ============================================================
class generator;
    mailbox gen2drv;
    int num_txns;

    function new(mailbox gen2drv, int num_txns);
        this.gen2drv = gen2drv;
        this.num_txns = num_txns;
    endfunction

    task run();
        transaction tr;
        repeat (num_txns) begin
            tr = new();
            assert(tr.randomize()) else $display("RANDOMIZE FAILED");
            tr.display("GEN");
            gen2drv.put(tr);
        end
    endtask
endclass

// ============================================================
// 4. DRIVER
// ============================================================
class driver;
    virtual i2c_if vif;
    mailbox gen2drv;
    mailbox drv2scb;

    function new(virtual i2c_if vif, mailbox gen2drv, mailbox drv2scb);
        this.vif     = vif;
        this.gen2drv = gen2drv;
        this.drv2scb = drv2scb;
    endfunction

    task run();
        transaction tr;
        forever begin
            gen2drv.get(tr);
            @(posedge vif.clk);
            vif.slave_addr <= tr.addr;
            vif.rw         <= tr.rw;
            vif.data_in    <= tr.data;
            vif.start      <= 1;
            @(posedge vif.clk);
            vif.start      <= 0;

            @(posedge vif.done);
            tr.ack_err   = vif.ack_error;
            tr.data_read = vif.data_out;
            tr.display("DRV-DONE");
            drv2scb.put(tr);
            @(posedge vif.clk);
        end
    endtask
endclass

// ============================================================
// 5. MONITOR
// ============================================================
class monitor;
    virtual i2c_if vif;
    function new(virtual i2c_if vif);
        this.vif = vif;
    endfunction

    task run();
        forever begin
            @(posedge vif.done);
        end
    endtask
endclass

// ============================================================
// 6. SCOREBOARD  (FIX: fail_cnt now actually increments on NACK)
// ============================================================
class scoreboard;
    mailbox drv2scb;
    int pass_cnt, fail_cnt;

    function new(mailbox drv2scb);
        this.drv2scb = drv2scb;
        pass_cnt = 0; fail_cnt = 0;
    endfunction

    task run();
        transaction tr;
        forever begin
            drv2scb.get(tr);
            if (tr.ack_err) begin
                $display("[SCB] addr=%h rw=%b -> NACK seen (ack_err=1)", tr.addr, tr.rw);
                fail_cnt++;
            end else if (!tr.rw) begin
                $display("[SCB] WRITE addr=%h data=%h -> PASS (ack ok)", tr.addr, tr.data);
                pass_cnt++;
            end else begin
                $display("[SCB] READ addr=%h data_read=%h -> PASS (ack ok)", tr.addr, tr.data_read);
                pass_cnt++;
            end
        end
    endtask

    function void report();
        $display("\n==================================================");
        $display("   SCOREBOARD REPORT: PASS=%0d | FAIL=%0d", pass_cnt, fail_cnt);
        $display("==================================================\n");
    endfunction
endclass

// ============================================================
// 7. ENVIRONMENT  (FIX: wait for all transactions to be scored,
//    instead of guessing a fixed delay before reporting)
// ============================================================
class environment;
    generator  gen;
    driver     drv;
    monitor    mon;
    scoreboard scb;
    mailbox    gen2drv, drv2scb;
    int num_txns;

    function new(virtual i2c_if vif, int num_txns);
        this.num_txns = num_txns;
        gen2drv = new();
        drv2scb = new();
        gen     = new(gen2drv, num_txns);
        drv     = new(vif, gen2drv, drv2scb);
        mon     = new(vif);
        scb     = new(drv2scb);
    endfunction

    task run();
        fork
            drv.run();
            mon.run();
            scb.run();
        join_none
        gen.run();
        wait (scb.pass_cnt + scb.fail_cnt == num_txns);
        #50;
        scb.report();
    endtask
endclass

// ============================================================
// 8. TOP MODULE
// ============================================================
module tb;
    logic clk;
    initial clk = 0;
    always #5 clk = ~clk;

    i2c_if vif(clk);
    pullup(vif.sda);

    i2c_master #(.CLK_DIV(4)) dut (
        .clk        (clk),
        .rst_n      (vif.rst_n),
        .start      (vif.start),
        .rw         (vif.rw),
        .slave_addr (vif.slave_addr),
        .data_in    (vif.data_in),
        .data_out   (vif.data_out),
        .busy       (vif.busy),
        .done       (vif.done),
        .ack_error  (vif.ack_error),
        .sda        (vif.sda),
        .scl        (vif.scl)
    );

    logic slave_drive;
    assign vif.sda = slave_drive ? 1'b0 : 1'bz;

    always @(negedge vif.scl or negedge vif.rst_n) begin
        if (!vif.rst_n) begin
            slave_drive <= 1'b0;
        end else begin
            if (dut.state == dut.WAIT_ACK_ADDR || dut.state == dut.WAIT_ACK_DATA)
                slave_drive <= 1'b1;
            else
                slave_drive <= 1'b0;
        end
    end

    environment env;

    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, tb);

        fork
            begin
                #1_000_000;
                $display("\n[ERROR] Simulation Watchdog Timeout!");
                $finish;
            end
        join_none

        vif.rst_n      = 0;
        vif.start      = 0;
        vif.rw         = 0;
        vif.slave_addr = 0;
        vif.data_in    = 0;
        slave_drive    = 0;

        #40 vif.rst_n  = 1;

        env = new(vif, 5);
        env.run();

        #100 $finish;
    end
endmodule
