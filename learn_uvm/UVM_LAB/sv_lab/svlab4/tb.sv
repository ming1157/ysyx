`timescale 1ns/1ps

`include "param_def.v"

interface chnl_intf(input clk, input rstn);
  logic [31:0] ch_data;
  logic        ch_valid;
  logic        ch_ready;
  clocking drv_ck @(posedge clk);
    default input #1ns output #1ns;
    output ch_data, ch_valid;
    input ch_ready;
  endclocking
  clocking mon_ck @(posedge clk);
    default input #1ns output #1ns;
    input ch_data, ch_valid, ch_ready;
  endclocking
endinterface

interface reg_intf(input clk, input rstn);
  logic [1:0]                 cmd;            //寄存器读写命令
  logic [`ADDR_WIDTH-1:0]     cmd_addr;       //地址端口 //parameter是由设计文件来的，体现了我们的复用性，设计的位宽扩展了，我们的验证环境的位宽就一样的被扩展
  logic [`CMD_DATA_WIDTH-1:0] cmd_data_s2m;   //slave到master，读端口，寄存器写入数据
  logic [`CMD_DATA_WIDTH-1:0] cmd_data_m2s;   //master到slave，写端口，寄存器读出数据
  clocking drv_ck @(posedge clk);
    default input #1ns output #1ns;
    output cmd, cmd_addr, cmd_data_m2s;
    input cmd_data_s2m;
  endclocking
  clocking mon_ck @(posedge clk);
    default input #1ns output #1ns;
    input cmd, cmd_addr, cmd_data_m2s, cmd_data_s2m;
  endclocking
endinterface

interface arb_intf(input clk, input rstn); //暂时不用，因为是子系统的验证环境，不需要引用interface
  // ... ignored                      //但是我们要把这个放在这里，只是体验一下
endinterface

interface fmt_intf(input clk, input rstn);
  logic        fmt_grant;    //整形数据包被允许发送的接受标示
  logic [1:0]  fmt_chid;     //整形数据包的通道 ID 号。 
  logic        fmt_req;      //整形数据包发送请求
  logic [5:0]  fmt_length;   //整形数据包长度信号
  logic [31:0] fmt_data;     //数据输出端口
  logic        fmt_start;    //数据包起始标示
  logic        fmt_end;      //数据包结束标示
  clocking drv_ck @(posedge clk);
    default input #1ns output #1ns;
    input fmt_chid, fmt_req, fmt_length, fmt_data, fmt_start;
    output fmt_grant;
  endclocking
  clocking mon_ck @(posedge clk);
    default input #1ns output #1ns;
    input fmt_grant, fmt_chid, fmt_req, fmt_length, fmt_data, fmt_start;
  endclocking
endinterface

interface mcdf_intf(input clk, input rstn);   //设置这个interface是为了检测内部信号，可以直接把design里的信号放在这个interface里，这样软件域里的任何一个组件就都可以拿到这个接口，灰盒验证，尽量少的去监测内部信号
  // USER TODO
  // To define those signals which do not exsit in
  // reg_if, chnl_if, arb_if or fmt_if


  clocking mon_ck @(posedge clk);
    default input #1ns output #1ns;
  endclocking
endinterface

module tb;
  logic         clk;
  logic         rstn;

  mcdf dut( //例化DUT
     .clk_i       (clk                )    //clk和rst
    ,.rstn_i      (rstn               )
	
    ,.cmd_i       (reg_if.cmd         )    //register的接口
    ,.cmd_addr_i  (reg_if.cmd_addr    ) 
    ,.cmd_data_i  (reg_if.cmd_data_m2s)  
    ,.cmd_data_o  (reg_if.cmd_data_s2m) 
	
    ,.ch0_data_i  (chnl0_if.ch_data   )   //channel_10的interface
    ,.ch0_vld_i   (chnl0_if.ch_valid  )
    ,.ch0_ready_o (chnl0_if.ch_ready  )
	
    ,.ch1_data_i  (chnl1_if.ch_data   )   //channel_11的interface
    ,.ch1_vld_i   (chnl1_if.ch_valid  )
    ,.ch1_ready_o (chnl1_if.ch_ready  )
	 
    ,.ch2_data_i  (chnl2_if.ch_data   )   //channel_12的interface
    ,.ch2_vld_i   (chnl2_if.ch_valid  )
    ,.ch2_ready_o (chnl2_if.ch_ready  )
	
    ,.fmt_grant_i (fmt_if.fmt_grant   )    //fomatter的interface
    ,.fmt_chid_o  (fmt_if.fmt_chid    ) 
    ,.fmt_req_o   (fmt_if.fmt_req     ) 
    ,.fmt_length_o(fmt_if.fmt_length  )    
    ,.fmt_data_o  (fmt_if.fmt_data    )  
    ,.fmt_start_o (fmt_if.fmt_start   )  
    ,.fmt_end_o   (fmt_if.fmt_end     )  
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

  import chnl_pkg::*;   //将类拷贝进去，进行动态的例化
  import reg_pkg::*;
  import arb_pkg::*;
  import fmt_pkg::*;
  import mcdf_pkg::*;

  reg_intf  reg_if(.*);     //例化了接口
  chnl_intf chnl0_if(.*); 
  chnl_intf chnl1_if(.*);
  chnl_intf chnl2_if(.*);
  arb_intf  arb_if(.*);    //很少使用arbiter接口，因为是内部信号
  fmt_intf  fmt_if(.*);
  mcdf_intf mcdf_if(.*);

  mcdf_data_consistence_basic_test t1;  //mcdf_data_consistence_basic_test是在mcdf_pkg中定义的扩展类
  mcdf_base_test tests[string];         //关联数组，索引类型是string,存放类型是mcdf_base_test     //mcdf_base_test是父类
  string name;

  initial begin 
    t1 = new();  //子类句柄
    tests["mcdf_data_consistence_basic_test"] = t1;  //父类句柄指向子类对象
    if($value$plusargs("TESTNAME=%s", name)) begin   //通过命令行进行交互，灵活仿真的选择
      if(tests.exists(name)) begin
        tests[name].set_interface(chnl0_if, chnl1_if, chnl2_if, reg_if, fmt_if, mcdf_if);
        tests[name].run();
      end
      else begin
        $fatal($sformatf("[ERRTEST], test name %s is invalid, please specify a valid name!", name));
      end
    end
    else begin
      $display("NO runtime optiont +TESTNAME=xxx is configured, and run default test mcdf_data_consistence_basic_test");
      tests["mcdf_data_consistence_basic_test"].set_interface(chnl0_if, chnl1_if, chnl2_if, reg_if, fmt_if, mcdf_if);
      tests["mcdf_data_consistence_basic_test"].run();
    end
  end
endmodule

