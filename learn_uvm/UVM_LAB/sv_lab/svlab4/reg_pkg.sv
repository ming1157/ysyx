`include "param_def.v"
//发送寄存器的配置数据
package reg_pkg;

  class reg_trans;
    rand bit[7:0] addr;     //地址，分别索引六个寄存器`SLV0_R_ADDR, `SLV1_R_ADDR, `SLV2_R_ADDR, `SLV0_W_ADDR, `SLV1_W_ADDR, `SLV2_W_ADDR
    rand bit[1:0] cmd;      //控制读写指令类别，WRITE/READ or IDLE
    rand bit[31:0] data;    //数据
	
    bit rsp;   //标记读写反馈的数据是否正常

//-----做寄存器配置---------
    constraint cstr {  
      soft cmd inside {`WRITE, `READ, `IDLE};  //parameter的复用，有单独的.v文件写定义，在param_def中
      soft addr inside {`SLV0_RW_ADDR, `SLV1_RW_ADDR, `SLV2_RW_ADDR, `SLV0_R_ADDR, `SLV1_R_ADDR, `SLV2_R_ADDR}; //在param_def.v中有定义
      //依据specfication缩小随机的状态空间范围
	  soft addr[7:4]==0 && cmd==`WRITE -> data[31:6]==0;  //当地址位第7-4位为零时，即十六进制的第一位为0时，即0x00/0X04/0X08(表示的是读写寄存器)
	                                                  //而且命令为写状态的时候，那么高26位为零，高26位是保留位，是无效的，没有必要进行随机
      soft addr[7:5]==0;   //soft情况下，第7位到第5位为零，因为地址位0x00/0x04/0x08和0x10/0x14/0x18首位至多为1
	                       //地址范围为0X00-0X18，取到最高1也富余3位，也就是7/6/5没有用，我们将其置零
      addr[4]==1 -> soft cmd == `READ;  //当地址第4bit位为1时，也就是0x10/0x14/0x18时，也就是只读寄存器状态时，将控制指令操作类别设置为READ
	                                    //soft在前和在后是一样的，等价于soft addr[4]==1 -> cmd == `READ; 
    };

    function reg_trans clone();
      reg_trans c = new();
      c.addr = this.addr;
      c.cmd = this.cmd;
      c.data = this.data;
      c.rsp = this.rsp;
      return c;
    endfunction

    function string sprint();
      string s;
      s = {s, $sformatf("=======================================\n")};
      s = {s, $sformatf("reg_trans object content is as below: \n")};
      s = {s, $sformatf("addr = %2x: \n", this.addr)};
      s = {s, $sformatf("cmd = %2b: \n", this.cmd)};
      s = {s, $sformatf("data = %8x: \n", this.data)};
      s = {s, $sformatf("rsp = %0d: \n", this.rsp)};
      s = {s, $sformatf("=======================================\n")};
      return s;
    endfunction
  endclass

  class reg_driver;
    local string name;
    local virtual reg_intf intf;
    mailbox #(reg_trans) req_mb;  //和generator握手
    mailbox #(reg_trans) rsp_mb;  //和generator握手

    function new(string name = "reg_driver");
      this.name = name;
    endfunction
  
    function void set_interface(virtual reg_intf intf);
      if(intf == null)
        $error("interface handle is NULL, please check if target interface has been intantiated");
      else
        this.intf = intf;
    endfunction

    task run();
      fork    //并行执行
        this.do_drive();
        this.do_reset();
      join
    endtask

    task do_reset();
      forever begin
        @(negedge intf.rstn);    //等待rst信号
        intf.cmd_addr <= 0;      //没有竞争关系，不需要用clocking  //地址设为零
        intf.cmd <= `IDLE;               //cmd设为idle
        intf.cmd_data_m2s <= 0;           //写的数据置零
      end
    endtask

    task do_drive();
      reg_trans req, rsp;
      @(posedge intf.rstn);
      forever begin             //无阻塞的驱动
        this.req_mb.get(req);      //只要从generator中拿到req就开始写，否则被阻塞
        this.reg_write(req);       //对寄存器做写操作
        rsp = req.clone();        //做克隆
        rsp.rsp = 1;              //做标记
        this.rsp_mb.put(rsp);     //返回来
      end
    endtask
  
    task reg_write(reg_trans t);
      @(posedge intf.clk iff intf.rstn);  //当rst为1时再看intf.clk信号
      case(t.cmd)
        `WRITE: begin 
                  intf.drv_ck.cmd_addr <= t.addr;     //地址写上去
                  intf.drv_ck.cmd <= t.cmd;           //写指令写上去
                  intf.drv_ck.cmd_data_m2s <= t.data; //数据发送到总线上去
                end
        `READ:  begin 
                  intf.drv_ck.cmd_addr <= t.addr; //总线写上去
                  intf.drv_ck.cmd <= t.cmd;       //读指令写上去
                  repeat(2) @(negedge intf.clk);  //等两个时钟的下降沿，为什么呢？因为上述代码是上升沿触发，等待一个下降沿还是当前周期，等第二个下降沿是下一个周期
				                                 //这样保证了读采样一定在下一个周期
                  t.data = intf.cmd_data_s2m;     //将数据从interface中驱动出来
                end
        `IDLE:  begin 
                  this.reg_idle();   //地址和data置零，cmd置为idle
                end
        default: $error("command %b is illegal", t.cmd);
      endcase
      $display("%0t reg driver [%s] sent addr %2x, cmd %2b, data %8x", $time, name, t.addr, t.cmd, t.data);
    endtask
    
    task reg_idle();
      @(posedge intf.clk); 
      intf.drv_ck.cmd_addr <= 0;      //地址设为零
      intf.drv_ck.cmd <= `IDLE;       //cmd设为idle
      intf.drv_ck.cmd_data_m2s <= 0;  //data设为idle
    endtask
  endclass

  class reg_generator;  //没有在agent中例化，只是做了声明，后续会用到
    rand bit[7:0]  addr = -1;       //外置transaction随机化的配置
    rand bit[1:0]  cmd  = -1;       //外置transaction随机化的配置
    rand bit[31:0] data = -1;       //外置transaction随机化的配置，表示真实的寄存器

    mailbox #(reg_trans) req_mb;  //与driver握手//是在当前类例化的
    mailbox #(reg_trans) rsp_mb;  //与driver握手//是在当前类例化的

    reg_trans reg_req[$]; //队列，存的是reg_trans类型

    constraint cstr{
      soft addr == -1;
      soft cmd == -1;
      soft data == -1;
    }

    function new();
      this.req_mb = new();
      this.rsp_mb = new();
    endfunction

    task start();
      send_trans();
    endtask

    // generate transaction and put into local mailbox
    task send_trans();
      reg_trans req, rsp;
      req = new();
      assert(req.randomize with {local::addr >= 0 -> addr == local::addr; //如果外部设置了约束，则将约束传入transaction约束中，这里的addr指的是req的变量，而local::addr指的是reg_generator内部声明的变量
                                 local::cmd >= 0  -> cmd  == local::cmd;  //如果外部设置了约束，则将约束传入transaction约束中
                                 local::data >= 0 -> data == local::data; //如果外部设置了约束，则将约束传入transaction约束中
                               })
        else $fatal("[RNDFAIL] register packet randomization failure!");
      $display(req.sprint());
      this.req_mb.put(req);   //交给driver
      this.rsp_mb.get(rsp);   //从与driver共享的mailbox里面拿到response
	                          //一次完整的握手
      $display(rsp.sprint());
      if(req.cmd == `READ) 
        this.data = rsp.data;  //如果为读命令，驱动出来，这里是为了最后在checker中进行读状态下的数据比对
      assert(rsp.rsp)  //判断是否做了标记，来标记是否驱动到interface成功
        else $error("[RSPERR] %0t error response received!", $time);
    endtask

    function string sprint();
      string s;
      s = {s, $sformatf("=======================================\n")};
      s = {s, $sformatf("reg_generator object content is as below: \n")};
      s = {s, $sformatf("addr = %2x: \n", this.addr)};
      s = {s, $sformatf("cmd = %2b: \n", this.cmd)};
      s = {s, $sformatf("data = %8x: \n", this.data)};
      s = {s, $sformatf("=======================================\n")};
      return s;
    endfunction

    function void post_randomize();
      string s;
      s = {"AFTER RANDOMIZATION \n", this.sprint()};
      $display(s);
    endfunction
  endclass

  class reg_monitor;
    local string name;
    local virtual reg_intf intf;
    mailbox #(reg_trans) mon_mb;  //创建mailbox，传递给checker
	
    function new(string name="reg_monitor");
      this.name = name;
    endfunction
	
    function void set_interface(virtual reg_intf intf);
      if(intf == null)
        $error("interface handle is NULL, please check if target interface has been intantiated");
      else
        this.intf = intf;
    endfunction
	
    task run();
      this.mon_trans();
    endtask

    task mon_trans();
      reg_trans m;  //transaction类型的句柄
      forever begin
        @(posedge intf.clk iff (intf.rstn && intf.mon_ck.cmd != `IDLE)); //这里设置了一个条件，cmd不为idle，因为idle是没有意义的嘛
        m = new();
        m.addr = intf.mon_ck.cmd_addr; //地址传进来
        m.cmd = intf.mon_ck.cmd;    //cmd传进来
        if(intf.mon_ck.cmd == `WRITE) begin
          m.data = intf.mon_ck.cmd_data_m2s; //写指令的话，把当前总线上的数据也放进来
        end
        else if(intf.mon_ck.cmd == `READ) begin  //读指令的话，
          @(posedge intf.clk);   //等待下一个时钟周期上升沿
          m.data = intf.mon_ck.cmd_data_s2m;  //下个时钟周期时，总线就有数据了，我们把数据写到data里面
        end
        mon_mb.put(m);  //只要每次捕捉到了数据，都要写进来，交给checker
        $display("%0t %s monitored addr %2x, cmd %2b, data %8x", $time, this.name, m.addr, m.cmd, m.data);
      end
    endtask
  endclass

  class reg_agent;  //非常简单就是做了封装
    local string name;
    reg_driver driver;     //例化了driver
    reg_monitor monitor;   //例化了monitor
    local virtual reg_intf vif;
	
    function new(string name = "reg_agent");
      this.name = name;
      this.driver = new({name, ".driver"});
      this.monitor = new({name, ".monitor"});
    endfunction

    function void set_interface(virtual reg_intf vif);
      this.vif = vif;
      driver.set_interface(vif);
      monitor.set_interface(vif);
    endfunction
	
    task run();
      fork
        driver.run();
        monitor.run();
      join
    endtask
  endclass

endpackage
