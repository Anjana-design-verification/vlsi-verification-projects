class transaction;
  
  rand bit din;
  bit dout;
  int id;
//  time tstamp;
  
  function transaction copy();
    // creates a deep copy of the transaction to avoid modifyng original object (used in scoreboard/monitor)
    copy = new();
    copy.din = this.din;
    copy.dout = this.dout;
    copy.id = this.id;
    // this = current object
  endfunction
  
  function void display(input string tag);
    $display("%s ID: %d DIN : %b DOUT : %b", tag, id, din, dout);
  endfunction
  
endclass

//////////////////////////////////////////////

class generator;
  transaction tr;
  mailbox #(transaction) mbx;
  mailbox #(transaction) mbxref;
  
  event sconext;
//  event done;
  int count;
  int txn_id = 0;
  
  function new(mailbox #(transaction) mbx, mailbox #(transaction) mbxref);
    //constructor class
    this.mbx = mbx;
    this.mbxref = mbxref;
    //receives mailbox handles from outside and stores them in the class
    tr = new();
  endfunction 
  
  task run();
    repeat(count) begin
      assert(tr.randomize()) else $error("[GEN] : RANDOMIZATION FAILED");
      txn_id++;
      tr.id = txn_id;
      mbx.put(tr.copy);
      mbxref.put(tr.copy);
      tr.display("GEN");
      @(sconext);
      //waiting for sconext to be triggered before creating next transaction
    end
//    -> done;
  endtask
  
endclass

//////////////////////////////////////////////

class driver;
  transaction tr;
  mailbox #(transaction) mbx;
  virtual dff_if vif;
  
  function new(mailbox #(transaction) mbx);
    this.mbx = mbx;
  endfunction
  
  task reset();
    // the driver applies the reset through the interface so the DUT starts from a known state
    vif.rst <= 1'b1;
    repeat(5) @(posedge vif.clk);
    vif.rst <= 1'b0;
    @(posedge vif.clk);
    $display("[DRV] : RESET DONE");
  endtask
  
  task run();
    forever begin
      mbx.get(tr);
      //wait till transaction is available
      vif.din <= tr.din;
      @(posedge vif.clk);
      tr.display("DRV");
      //show what was driven
      vif.din <= 1'b0;
      @(posedge vif.clk);
    end
  endtask
endclass

//////////////////////////////////////////////

class monitor;
  transaction tr;
  mailbox #(transaction) mbx;
  virtual dff_if vif;
  int txn_id = 0;
  
  function new(mailbox #(transaction) mbx);
    this.mbx = mbx;
  endfunction
  
  task run();
//    tr = new();
    //should be inside forever loop?
    forever begin    
      tr = new();
      txn_id++;
      tr.id = txn_id;
      repeat(2) @(posedge vif.clk);
      tr.dout = vif.dout;
      mbx.put(tr);
      tr.display("MON");
    end 
  endtask
  
endclass

//////////////////////////////////////////////

class scoreboard;
  transaction tr;
  transaction trref;
  mailbox #(transaction) mbx;
  mailbox #(transaction) mbxref;
  event sconext;
  
  int total_transactions = 0;
  int total_matched = 0;
  int total_mismatched = 0;
  
  function new(mailbox #(transaction) mbx, mailbox #(transaction) mbxref);
    this.mbx = mbx;
    this.mbxref = mbxref;
  endfunction
  
  task run();
    forever begin
      mbx.get(tr);
      mbxref.get(trref);
      tr.display("SCO");
      trref.display("GOLDEN DATA");
      if(tr.dout == trref.din) begin
        $display("DATA MATCH");
        total_matched++;
      end
      else begin
        $display("DATA MISMATCH");
        total_mismatched++;
      end
      $display("----------------------------------------------------");
      total_transactions++;
      ->sconext;
      $display("Total transactions = %d", total_transactions);
      $display("Total matched = %d", total_matched);
      $display("Total mismatched = %d", total_mismatched);
      $display("----------------------------------------------------");
    end
  endtask
  
endclass

/////////////////////////////////////////////

class environment;
  generator gen;
  driver drv;
  monitor mon;
  scoreboard sco;
  
  event next;
  
  mailbox #(transaction) gdmbx;
  mailbox #(transaction) msmbx;
  mailbox #(transaction) mbxref;
  
  virtual dff_if vif;
  
  function new(virtual dff_if vif);
    gdmbx = new();
    msmbx = new();
    mbxref = new();
    gen = new(gdmbx, mbxref);
    drv = new(gdmbx);
    mon = new(msmbx);
    sco = new(msmbx, mbxref);
    
    this.vif = vif;
    drv.vif = this.vif;
    mon.vif = this.vif;
    
    gen.sconext = next;
    sco.sconext = next;
  endfunction
  
  task pre_test();
    drv.reset();
  endtask
  
  task test();
    fork
      gen.run();
      drv.run();
      mon.run();
      sco.run();
    join_any
  endtask
  
  task post_test();
    //wait(sco.done.triggered);
    wait(sco.total_transactions == gen.count);
    $finish;
  endtask
  
  task run();
    pre_test();
    test();
    post_test();
  endtask
  
endclass

/////////////////////////////////////////////

module tb;
  dff_if vif();
  dff dut(vif);
  
  initial begin
    vif.clk <= 0;
  end
  
  always #10 vif.clk <= ~vif.clk;
  
  environment env;
  
  initial begin
    env = new(vif);
    env.gen.count = 30;
    env.run();
  end
  
  initial begin
    $dumpfile("dump.vcd");
    $dumpvars;
  end
  
endmodule
