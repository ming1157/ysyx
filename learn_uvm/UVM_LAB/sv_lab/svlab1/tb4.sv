`timescale 1ns/1ps

module chnl_initiator(
  input      reg        clk,
  input      reg        rstn,
  output     logic [31:0] ch_data,
  output     logic        ch_valid,
  input      logic        ch_ready,
  input      logic [4:0]  ch_margin //FIFO的余量
);

static logic [31:0] chn_arr[];
static int i;
string name;

function void set_name(string s);
  name = s;
endfunction

task chnl_write(input logic[31:0] data);
  // USER TODO
  // drive valid data
  // ...
  @(posedge clk);
  wait(ch_ready);
  ch_data <= data;
  ch_valid <=1;
  
  $display("%t channel initial [%s] sent data %x", $time, name, data);
  chnl_idle();
endtask

task chnl_idle();
  // USER TODO
  // drive idle data
  // ...
  @(posedge clk);
  ch_valid <= 0;
  ch_data  <= 0;
endtask


initial begin 
   chn_arr = new[100];
   foreach(chn_arr[i]) begin
      chn_arr[i]={$random}%(8'b1111_1111);
   end

   @(posedge rstn);
   repeat(10) @(posedge clk);
   
   for(i=0;i<100;i++)
   begin
     @(posedge clk);
	   ch_valid <= 0;
	   ch_data <= 0;
	 @(posedge clk);
	   ch_valid <=1;
	   ch_data <= chn_arr[i];
   end
end 
endmodule


module tb4;
logic         clk;
logic         rstn;
logic [31:0]  ch0_data;
logic         ch0_valid;
logic         ch0_ready;
logic [ 4:0]  ch0_margin;
logic [31:0]  ch1_data;
logic         ch1_valid;
logic         ch1_ready;
logic [ 4:0]  ch1_margin;
logic [31:0]  ch2_data;
logic         ch2_valid;
logic         ch2_ready;
logic [ 4:0]  ch2_margin;
logic [31:0]  mcdt_data;
logic         mcdt_val;
logic [ 1:0]  mcdt_id;

mcdt dut(
   .clk_i(clk)
  ,.rstn_i(rstn)
  ,.ch0_data_i(ch0_data)
  ,.ch0_valid_i(ch0_valid)
  ,.ch0_ready_o(ch0_ready)
  ,.ch0_margin_o(ch0_margin)
  ,.ch1_data_i(ch1_data)
  ,.ch1_valid_i(ch1_valid)
  ,.ch1_ready_o(ch1_ready)
  ,.ch1_margin_o(ch1_margin)
  ,.ch2_data_i(ch2_data)
  ,.ch2_valid_i(ch2_valid)
  ,.ch2_ready_o(ch2_ready)
  ,.ch2_margin_o(ch2_margin)
  ,.mcdt_data_o(mcdt_data)
  ,.mcdt_val_o(mcdt_val)
  ,.mcdt_id_o(mcdt_id)
);

// clock generation
initial begin 
    clk <= 0;
  forever begin
    #5 clk <= !clk;
  end
end

// reset trigger
initial begin 
  #10 rstn <= 0;
  repeat(10) @(posedge clk);
  rstn <= 1;
end

initial begin 
  repeat(1000) @(posedge clk);
  chnl0_init.set_name("This_is_chn10");
  chnl1_init.set_name("This_is_chn11");
  chnl2_init.set_name("This_is_chn12");
end

chnl_initiator chnl0_init(   //实例类型名称  实例名
  .clk      (clk),
  .rstn     (rstn),
  .ch_data  (ch0_data),
  .ch_valid (ch0_valid),
  .ch_ready (ch0_ready),
  .ch_margin(ch0_margin) 
);
chnl_initiator chnl1_init(
  .clk      (clk),
  .rstn     (rstn),
  .ch_data  (ch1_data),
  .ch_valid (ch1_valid),
  .ch_ready (ch1_ready),
  .ch_margin(ch1_margin) 
);
chnl_initiator chnl2_init(
  .clk      (clk),
  .rstn     (rstn),
  .ch_data  (ch2_data),
  .ch_valid (ch2_valid),
  .ch_ready (ch2_ready),
  .ch_margin(ch2_margin) 
);
endmodule

