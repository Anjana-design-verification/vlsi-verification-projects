module dff (
  dff_if vif
);
  
  always @(posedge vif.clk)
    begin
      if (vif.rst)
        vif.dout <= 1'b0;
      else
        vif.dout <= vif.din; 
    end
  
endmodule

interface dff_if;
  
  logic din;
  logic rst;
  logic clk;
  logic dout;
  
endinterface
