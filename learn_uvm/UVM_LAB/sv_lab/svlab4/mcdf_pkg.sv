`include "param_def.v"

package mcdf_pkg;

  import chnl_pkg::*;
  import reg_pkg::*;
  import arb_pkg::*;
  import fmt_pkg::*;
  import rpt_pkg::*;  //做外部声明的
  
//这个结构体是例化在了reference model的寄存器中的，模拟的是硬件的寄存器
  typedef struct packed {
    bit[2:0] len;     //存放长度length
    bit[1:0] prio;    //存放优先级priority
    bit en;           //存放enable
    bit[7:0] avail;   //存放available，可写余量
  } mcdf_reg_t;    //reference model中的寄存器，我们在DUT中的register是某些位是有特定功能的，这里就是把DUT的bit位单独拿出来映射为一些特定的功能

  typedef enum {RW_LEN, RW_PRIO, RW_EN, RD_AVAIL} mcdf_field_t; //自定义的域,标识符,不同的比特位有不同的功能

  class mcdf_refmod;  //refernece model
  //我们回顾性地看，这个reference model没有模拟slave的开关控制
  //也没有模拟Arbiter的仲裁，我们假定Arbiter的仲裁是正确的，才能输入到三个out mailbox里
  //Arbiter决定哪些数据包在前，哪些数据包在后，也就是priority的仲裁
    local virtual mcdf_intf intf;   //这里的interface只是为了将reset传入,从而控制复位
    local string name;
    mcdf_reg_t regs[3];  //分别表示channel 0/1/2的寄存器,是在reference中模拟出的，寄存器内存放为结构体类型（mcdf_field_t），定义在reference model内
                    //此寄存器是在reference model中模拟硬件的寄存器行为的
					//只不过定义没有硬件域那么啰嗦，直接用一个结构体表达出来了
	mailbox #(reg_trans) reg_mb;      //mailbox存的是硬件域reg的trans的信息
    mailbox #(mon_data_t) in_mbs[3];  //mailbox存的是chnl的transaction的信息 bit[31:0] data; bit[1:0] id;
    mailbox #(fmt_trans) out_mbs[3];  //mailbox存的是fmt的trans的信息

    function new(string name="mcdf_refmod");
      this.name = name;
      foreach(this.out_mbs[i]) this.out_mbs[i] = new();//只有out的mailbox才进行例化
    endfunction

    task run();
      fork
        do_reset();  //每当reset为下降沿时复位
        this.do_reg_update();  //模拟寄存器，来给reference model中的寄存器的数据做配置
        do_packet(0);  //模拟硬件 //模拟formatter给三路数据做打包，内置阻塞，所以可以并行
        do_packet(1);  //模拟硬件 //模拟formatter给三路数据做打包，内置阻塞，所以可以并行
        do_packet(2);  //模拟硬件 //模拟formatter给三路数据做打包，内置阻塞，所以可以并行
      join
    endtask

    task do_reg_update(); //捕捉实际硬件中寄存器配置信息，更新reference model中的寄存器配置
      reg_trans t;     //reg_trans 里包含三个变量 addr表示地址（哪个寄存器），cmd表示是读/写，data表示数据
      forever begin
        this.reg_mb.get(t); //从monitor传来的寄存器配置信息，寄存器是32bit的向量，bit(0):通道使能信号  /bit(2:1):优先级  /bit(5:3):数据包长度  /bit(31:6):保留位，无法写入
		                   //也就是我们定义的结构体,拿不到就被阻塞
        if(t.addr[7:4] == 0 && t.cmd == `WRITE) begin //将从register中拿来的信息同步到reference model中的寄存器中 //同时转化了格式 //这里选的是读写寄存器
          this.regs[t.addr[3:2]].en   = t.data[0];        //先索引哪个寄存器，再传递enable    //这里没有和reg做统一，采用了结构体的形式
          this.regs[t.addr[3:2]].prio = t.data[2:1];      //先索引哪个寄存器，再传递priority  //这里没有和reg做统一，采用了结构体的形式   //这里priority并不是一个独立的变量
          this.regs[t.addr[3:2]].len  = t.data[5:3];      //先索引哪个寄存器，再传递length    //这里没有和reg做统一，采用了结构体的形式
         //配置了使能信号/优先级/数据包长度
		end                                          //只有0-5是可利用的，其他都是无效位
        else if(t.addr[7:4] == 1 && t.cmd == `READ) begin  //DUT的寄存器配置的是只读寄存器
          this.regs[t.addr[3:2]].avail = t.data[7:0];   //先索引哪个寄存器，再传递可写余量margin  //只有7-0是可写余量，其他位无效
          //只需配置可写余量margin
		  //注意我们的读寄存器也包含上述三个寄存器，因为他们是读/写的
	   end
      end
    endtask

    task do_packet(int id);  //将从channel中monitor到的信息，打包交给输出的mailbox，送给formatter
      fmt_trans ot;   //packet的数据格式 //fmt_trans数据类型的变量，包含fmt的信息
     // rand fmt_fifo_t fifo; //容量大小，小容量/中等容量/大容量/特别大容量（ULTRA过激的）
     // rand fmt_bandwidth_t bandwidth; //带宽，低带宽/中等带宽/高带宽/特别高的带宽（ULTRA过激的） 
     // bit [9:0] length;   //长度
     // bit [31:0] data[];  //数据包，长度待定
     // bit [1:0] ch_id;    //arbiter端的控制信号，是哪个通道来的
     // bit rsp;            //标识符   
      mon_data_t it;  //单一的结构体数据格式 //chnl中monitor收集到的的信息  
	 // bit[31:0] data;
     //	bit[1:0] id;
      forever begin
	  //在forever里实现了将reference寄存器的配置和数据赋值给了新创建的fmt_trans类型的变量ot
	  //相当于将已知的数据做数据格式的统一，统一输出为fmt_trans格式
        this.in_mbs[id].peek(it);  //等价于wait(this.in_mbs[id].num()>0); 如果mailbox为空，则当前进程将阻塞，但不会破坏原有数据
        ot = new();
        ot.length = 4 << (this.get_field_value(id, RW_LEN) & 'b11);   //从特定的reference model寄存器中拿到数据包长度值
		//regs中的长度len为三位：0对应4，1对应8，2对应16，3对应32，其它数值（4-7）均暂时对应长度32。复位值为 0。
		//length中的长度length为7位，表示的是经过解码后的真实值
		//这里要做一个长度的转化，得到一个真实的数据的长度
		//这里的逻辑设计很精巧，但是可读性差，我自己也是通过举例归纳才知晓这个逻辑的
		//如果你熟悉RTL design的话，这里的逻辑设计又不是很精巧，通过&来禁止无效位的使能
        ot.data = new[ot.length];  //有了长度之后，可以开辟空间，但是开辟空间之后都是垃圾值
        ot.ch_id = id;    //注意这里的id并不来源于monitor监测到的单一数据格式，而是来自于mailbox的编码
        foreach(ot.data[m]) begin   //对于每一个bit[31:0]data[]来说 
          this.in_mbs[id].get(it);  //从in_mailbox(channel mailbox)中拿数据，覆盖垃圾值
          ot.data[m] = it.data;     //通过foreach将mon_data_t单一的数据形式转化为bit[31:0]data[]形式，也就是packet的形式
        end
        this.out_mbs[id].put(ot);   //放到对应的mailbox里面，mailbox可以与do_compare通信
      end
    endtask
	
    //从reference model中的register拿值，模拟了DUT中信息从register传递到各个FIFO的行为
    function int get_field_value(int id, mcdf_field_t f);  //根据特定ID，以及标识符（RW_LEN, RW_PRIO, RW_EN, RD_AVAIL），返回在reference model中定义的register的信息
	         
      case(f)     //从reference model中的register中返回特定的值
        RW_LEN: return regs[id].len;     //模拟了DUT中将register中的信号给slave/FIFO/Arbiter/Formatter中
        RW_PRIO: return regs[id].prio;    //返回的是reference model中的值
        RW_EN: return regs[id].en;
        RD_AVAIL: return regs[id].avail;
      endcase
    endfunction 

    task do_reset(); //其实有补充的余地，spec中没有说明好复位值
	//其实do_reset()也是模拟的是硬件的功能
	//另外，在硬件中还是需要复位Arbiter/FIFO/Formatter中的缓存的
      forever begin
        @(negedge intf.rstn);  
        foreach(regs[i]) begin
          regs[i].len = 'h0;      //对软件域的寄存器做了复位，复位值在spec中声明了
          regs[i].prio = 'h3;     //对软件域的寄存器做了复位，复位值在spec中声明了
          regs[i].en = 'h1;       //对软件域的寄存器做了复位，复位值在spec中声明了
          regs[i].avail = 'h20;   //对软件域的寄存器做了复位，复位值在spec中声明了
        end
		foreach(out_mbs[i]) out_mbs[i].delete(); //各个mailbox清空，也可以实例化一个新的mailbox
		//我们只在reference model中例化了out_mbs所以，只需要reset out_mbs[i]
		//我们在checker中也需要有reset
      //或者实例化一个新的mailbox也是ok的
	  //foreach(out_mbs[i]) out_mbs[i] = new();
	  end
    endtask

    function void set_interface(virtual mcdf_intf intf);
      if(intf == null)
        $error("interface handle is NULL, please check if target interface has been intantiated");
      else
        this.intf = intf;
    endfunction
    
  endclass
//其实reference model有些东西都没有模拟，比如控制slave的开关
//Arbiter的仲裁也是没有模拟的，就是数据谁在前谁在后

  class mcdf_checker;  //checker中包含reference model
    local string name;
    local int err_count;  //错误的次数
    local int total_count;  //错误累积的次数
    local int chnl_count[3];  //每一个channel比较的数据次数
	
    local virtual mcdf_intf intf;
    local mcdf_refmod refmod;  //reference model的句柄
	
    mailbox #(mon_data_t) chnl_mbs[3]; //在checker中例化了，存放的是
    mailbox #(fmt_trans) fmt_mb;       //在checker中例化了 
    mailbox #(reg_trans) reg_mb;       //在checker中例化了 
	
    mailbox #(fmt_trans) exp_mbs[3];   //没有在checker实例化，只做链接，内容相当于refmod中的out_mbs

    function new(string name="mcdf_checker");
      this.name = name;
      foreach(this.chnl_mbs[i]) 
	  this.chnl_mbs[i] = new();  //做了实例化
      this.fmt_mb = new();       //做了实例化
      this.reg_mb = new();       //做了实例化
      this.refmod = new();       //做了实例化
      foreach(this.refmod.in_mbs[i]) begin  //完成了一个链接
	  //链接的行为一般都定义在mailbox实例以及mailbox的句柄的最小包含范围内
        this.refmod.in_mbs[i] = this.chnl_mbs[i];   //checker的mailbox赋值给了reference model的mailbox
        this.exp_mbs[i] = this.refmod.out_mbs[i];   //reference model实例化的mailbox赋值给了checker的悬空句柄
      end
      this.refmod.reg_mb = this.reg_mb;
      this.err_count = 0;                                  //计数初始化
      this.total_count = 0;                                //计数初始化
      foreach(this.chnl_count[i]) this.chnl_count[i] = 0;  //计数初始化
    endfunction

    function void set_interface(virtual mcdf_intf intf);
      if(intf == null)
        $error("interface handle is NULL, please check if target interface has been intantiated");
      else
        this.intf = intf;
        this.refmod.set_interface(intf);
    endfunction

    task run();
      fork
        this.do_compare();
        this.refmod.run();
      join
    endtask

    task do_compare();
      fmt_trans expt, mont;  //这里统一了格式，也和mailbox中一定要成放统一数据类型的变量规则保持一致
      bit cmp;  
      forever begin
        this.fmt_mb.get(mont);                //在输入的fmt_mailbox里拿一个数据
        this.exp_mbs[mont.ch_id].get(expt);   //复用上面的ID来索引，从reference model中输出的数据来索引
        cmp = mont.compare(expt);   //这时候利用fmt_trans里的内置函数compare来比较，这个函数已经定义了，是在tmt_pkg里定义的
        this.total_count++;        //每比较一次自增1
        this.chnl_count[mont.ch_id]++;  //每比较一次chnl_count的计数也自增1
        if(cmp == 0) begin       //在这个task变量声明部分定义了cmp变量，如果为0则不匹配
          this.err_count++;
          rpt_pkg::rpt_msg("[CMPFAIL]", 
            $sformatf("%0t %0dth times comparing but failed! MCDF monitored output packet is different with reference model output", $time, this.total_count),
            rpt_pkg::ERROR,
            rpt_pkg::TOP,
            rpt_pkg::LOG);
        end
        else begin  //如果比较不成功
          rpt_pkg::rpt_msg("[CMPSUCD]",
            $sformatf("%0t %0dth times comparing and succeeded! MCDF monitored output packet is the same with reference model output", $time, this.total_count),
            rpt_pkg::INFO,
            rpt_pkg::HIGH);
        end
      end
    endtask

    function void do_report(); //仿真结束之后要做summary
      string s;
      s = "\n---------------------------------------------------------------\n";
      s = {s, "CHECKER SUMMARY \n"}; 
      s = {s, $sformatf("total comparison count: %0d \n", this.total_count)}; //总共比较多少次
      foreach(this.chnl_count[i]) 
	    s = {s, $sformatf(" channel[%0d] comparison count: %0d \n", i, this.chnl_count[i])};  //每一个channel比较多少次
		
      s = {s, $sformatf("total error count: %0d \n", this.err_count)};  //失败多少次
      
	  foreach(this.chnl_mbs[i]) begin  //chnl_mbs mailbox为空的话,表示有剩余，报错
        if(this.chnl_mbs[i].num() != 0)
          s = {s, $sformatf("WARNING:: chnl_mbs[%0d] is not empty! size = %0d \n", i, this.chnl_mbs[i].num())}; 
      end
      if(this.fmt_mb.num() != 0)   //fammter mailbox为空的话,表示有剩余，报错
      s = {s, $sformatf("WARNING:: fmt_mb is not empty! size = %0d \n", this.fmt_mb.num())}; 
	  
      s = {s, "---------------------------------------------------------------\n"};
      rpt_pkg::rpt_msg($sformatf("[%s]",this.name), s, rpt_pkg::INFO, rpt_pkg::TOP); //调用了report_pkg里的函数
   //function void rpt_msg(string src, string i, report_t r=INFO, severity_t s=LOW, action_t a=LOG);
   //(src从哪里过来的，i真正要打印的消息内容，r默认是INFO的类型，s消息级别比较低的LOW的类型，a默认会写到LOG文件里面)
   //这里import了packet，可以不用这个域
	endfunction
  endclass

  class mcdf_env;   //相对于各个agent而言，是顶层
    chnl_agent chnl_agts[3];  //三个channel agent
    reg_agent reg_agt;        //一个register agent
    fmt_agent fmt_agt;         //一个formatter agent
    mcdf_checker chker;        //一个checker agent
    protected string name;

    function new(string name = "mcdf_env");
      this.name = name;
      this.chker = new();  //checker的例化
      foreach(chnl_agts[i]) begin
        this.chnl_agts[i] = new($sformatf("chnl_agts[%0d]",i));  //3个channel的例化
        this.chnl_agts[i].monitor.mon_mb = this.chker.chnl_mbs[i];  //mailbox链接。注意链接一定发生在例化之后
      end
      this.reg_agt = new("reg_agt");  //register的例化
      this.reg_agt.monitor.mon_mb = this.chker.reg_mb;  //mailbox链接
      this.fmt_agt = new("fmt_agt");  //fmatter的例化
      this.fmt_agt.monitor.mon_mb = this.chker.fmt_mb;  //mailbox链接
      $display("%s instantiated and connected objects", this.name);
    endfunction

    virtual task run();
      $display($sformatf("*****************%s started********************", this.name));
      this.do_config();
      fork   //所有组件跑起来
        this.chnl_agts[0].run();
        this.chnl_agts[1].run();
        this.chnl_agts[2].run();
        this.reg_agt.run();
        this.fmt_agt.run();
        this.chker.run();
      join
    endtask

    virtual function void do_config();  //回调函数，预留回调入口
    endfunction

    virtual function void do_report();  //要调用checker的report
      this.chker.do_report();
    endfunction
  endclass

  class mcdf_base_test;
    chnl_generator chnl_gens[3];  //声明了三个channel的三个generator
    reg_generator reg_gen;        //声明了register的generator
    fmt_generator fmt_gen;        //声明了formmter的generator
    mcdf_env env;                 //声明了env
    protected string name;        //只对该类和子类可见，对类外不可见，也不可改变

    function new(string name = "mcdf_base_test");
      this.name = name;
      this.env = new("env");

      foreach(this.chnl_gens[i]) begin
        this.chnl_gens[i] = new();  //例化三个channel_generator的mailbox  
		//除了例化也要把通信方式定义出来，这里是握手，是两个mailbox
        this.env.chnl_agts[i].driver.req_mb = this.chnl_gens[i].req_mb; //将channel_generator的mailbox与channel_agent中的driver的mailbox相连接
        this.env.chnl_agts[i].driver.rsp_mb = this.chnl_gens[i].rsp_mb; //将channel_generator的mailbox与channel_agent中的driver的mailbox相连接
      end

      this.reg_gen = new();    //例化register的mailbox //先例化后mailbox链接
	  //除了例化也要把通信方式定义出来，这里是握手，是两个mailbox
      this.env.reg_agt.driver.req_mb = this.reg_gen.req_mb;   //register_generator中的mailbox句柄与register的agent中的driver的mailbox相连接
      this.env.reg_agt.driver.rsp_mb = this.reg_gen.rsp_mb;   //register_generator中的mailbox句柄与register的agent中的driver的mailbox相连接

      this.fmt_gen = new();    //例化register的mailbox //先例化后mailbox链接
	  //除了例化也要把通信方式定义出来，这里是握手，是两个mailbox
      this.env.fmt_agt.driver.req_mb = this.fmt_gen.req_mb; //fmatter_generator中的mailbox句柄与famtter的agent中的driver的mailbox相连接
      this.env.fmt_agt.driver.rsp_mb = this.fmt_gen.rsp_mb; //fmatter_generator中的mailbox句柄与famtter的agent中的driver的mailbox相连接

      rpt_pkg::logname = {this.name, "_check.log"};  //做拼接，对rpt_pkg中的静态字符串变量logname赋值
      rpt_pkg::clean_log();                          //将文件句柄置零
      $display("%s instantiated and connected objects", this.name);  //"mcdf_base_test"已经被例化了
    endfunction

    virtual task run();
      fork
        env.run();  //各个checker monitor driver都能run起来
      join_none     //不一定能run完，因为里面很多都是forever语句，所以让它在后台挂着
      rpt_pkg::rpt_msg("[TEST]",$sformatf("=========%s AT TIME %0t STARTED==========", this.name, $time),rpt_pkg::INFO,rpt_pkg::HIGH);  //这里少传递了一个参数，表示默认的操作方式是LOG
	//--------function void rpt_msg(string src, string i, report_t r=INFO, severity_t s=LOW, action_t a=LOG);----------------
	
	//--------下述方法目前都定义为virtual，是虚方法，本类中没有定义-----------
      this.do_reg();       //配置硬件模块的寄存器,reg_generator传递信号给driver
      this.do_formatter(); //要把env中的responder要配置好，配置其FIFO的深度和带宽，让他表现的更像一个真实的硬件
      this.do_data();
	//--------上述方法目前都定义为virtual，是虚方法，本类中没有定义------------
      rpt_pkg::rpt_msg("[TEST]",$sformatf("======%s AT TIME %0t FINISHED========", this.name, $time),rpt_pkg::INFO,rpt_pkg::HIGH);  //这里少传递了一个参数，表示默认的操作方式是LOG
      this.do_report();  //在下面有定义
      $finish();
    endtask
 //----------------三个virtual方法，需要子类去配置的-----------
    // do register configuration
    virtual task do_reg();
    endtask
    // do external formatter down stream slave configuration
    virtual task do_formatter();
    endtask
    // do data transition from 3 channel slaves
    virtual task do_data();
    endtask

    // do simulation summary
    virtual function void do_report();
      this.env.do_report();
      rpt_pkg::do_report();
    endfunction

    virtual function void set_interface(virtual chnl_intf ch0_vif ,virtual chnl_intf ch1_vif ,virtual chnl_intf ch2_vif ,virtual reg_intf reg_vif,virtual fmt_intf fmt_vif,virtual mcdf_intf mcdf_vif );
      this.env.chnl_agts[0].set_interface(ch0_vif);
      this.env.chnl_agts[1].set_interface(ch1_vif);
      this.env.chnl_agts[2].set_interface(ch2_vif);
      this.env.reg_agt.set_interface(reg_vif);
      this.env.fmt_agt.set_interface(fmt_vif);
      this.env.chker.set_interface(mcdf_vif);
    endfunction
	
//就是比较两个数据
    virtual function bit diff_value(int val1, int val2, string id = "value_compare");
      if(val1 != val2) begin
        rpt_pkg::rpt_msg("[CMPERR]", $sformatf("ERROR! %s val1 %8x != val2 %8x", id, val1, val2), rpt_pkg::ERROR, rpt_pkg::TOP);
        return 0;
      end
      else begin
        rpt_pkg::rpt_msg("[CMPSUC]", $sformatf("SUCCESS! %s val1 %8x == val2 %8x", id, val1, val2),rpt_pkg::INFO,rpt_pkg::HIGH);
        return 1;
      end
    endfunction

//--------三个task进行寄存器的配置，间接地控制register，当前是空闲状态----------------
    virtual task idle_reg();
	//void'表示括号里的函数在定义时是有返回值的，在引用时我们考虑到无需利用到函数的返回值
	//故我们无需分配返回值的空间，所以可以用void'(function())来表示省略返回值
      void'(reg_gen.randomize() with {cmd == `IDLE; addr == 0; data == 0;});
      reg_gen.start();
    endtask
//三个配置的task，间接地控制register，当前是写状态
    virtual task write_reg(bit[7:0] addr, bit[31:0] data);    //没有指明方向就是input，这里全为input，也就是无需返回值
      void'(reg_gen.randomize() with {cmd == `WRITE; addr == local::addr; data == local::data;});
      reg_gen.start();
    endtask
//三个配置的task，间接地控制register，当前是读状态
    virtual task read_reg(bit[7:0] addr, output bit[31:0] data);   //task中没有指明方向就是input
      void'(reg_gen.randomize() with {cmd == `READ; addr == local::addr;});
      reg_gen.start();  //原来我们的bit[31:0]是被默认值充盈的，在执行完这个函数之后，reg_gen中的data被DUT中的data所返回
      data = reg_gen.data; //我们读出reg_gen的data然后做返回
    endtask
  endclass

  class mcdf_data_consistence_basic_test extends mcdf_base_test;  //基本的数据完整性检查
    function new(string name = "mcdf_data_consistence_basic_test");
      super.new(name);
    endfunction
	
//-----------实现了register的配置场景，也就是定向配置，在父类中是virtual的空方法，这里进行了重写--------------------
    task do_reg();
      bit[31:0] wr_val, rd_val;
      // slv0 with len=8,  prio=0, en=1
      wr_val = (1<<3)+(0<<1)+1;  //通过移动位置来配置寄存器，将上一行的信息做配置
	  // `SLV0_RW_ADDR表示第一个读写寄存器的地址
      this.write_reg(`SLV0_RW_ADDR, wr_val); //写进去值
      this.read_reg(`SLV0_RW_ADDR, rd_val);  //读出来值，存在re_val里
      void'(this.diff_value(wr_val, rd_val, "SLV0_WR_REG")); //看看写进去的值和读出来的值是否一致，一致性检验

      // slv1 with len=16, prio=1, en=1
      wr_val = (2<<3)+(1<<1)+1;  //通过移动位置来配置寄存器，将上一行的信息做配置
      this.write_reg(`SLV1_RW_ADDR, wr_val);  //写进去值
      this.read_reg(`SLV1_RW_ADDR, rd_val);   //读出来值，存在re_val里
      void'(this.diff_value(wr_val, rd_val, "SLV1_WR_REG")); //看看写进去的值和读出来的值是否一致

      // slv2 with len=32, prio=2, en=1
      wr_val = (3<<3)+(2<<1)+1;  //通过移动位置来配置寄存器，将上一行的信息做配置
      this.write_reg(`SLV2_RW_ADDR, wr_val);  //写进去值
      this.read_reg(`SLV2_RW_ADDR, rd_val);   //读出来值，存在re_val里
      void'(this.diff_value(wr_val, rd_val, "SLV2_WR_REG")); //看看写进去的值和读出来的值是否一致

      // send IDLE command
      this.idle_reg();
    endtask
	
	
//-------------------实现了formatter的配置场景，在父类中是virtual的空方法，这里进行了重写-----------------
//------------注意这里并不是主动发送数据，而是对responder进行配置------------------------
    task do_formatter(); 
	//表示配置的FIFO长度比较长，带宽比较宽，比较容易的将grant拉起来
      void'(fmt_gen.randomize() with {fifo == LONG_FIFO; bandwidth == HIGH_WIDTH;});
      fmt_gen.start();
    endtask
	
	
//-------------------实现了data的配置场景，在父类中是virtual的空方法，这里进行了重写--------------------
    task do_data();
      void'(chnl_gens[0].randomize() with {ntrans==100; ch_id==0; data_nidles==0; pkt_nidles==1; data_size==8; });
      void'(chnl_gens[1].randomize() with {ntrans==100; ch_id==1; data_nidles==1; pkt_nidles==4; data_size==16;});
      void'(chnl_gens[2].randomize() with {ntrans==100; ch_id==2; data_nidles==2; pkt_nidles==8; data_size==32;});
      fork
        chnl_gens[0].start();
        chnl_gens[1].start();
        chnl_gens[2].start();
      join
      #10us; // wait until all data haven been transfered through MCDF，注意这里：#10 us真的够吗？
    endtask
	
	
  endclass
endpackage
