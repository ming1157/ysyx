
//simulator分为两种，一种叫做initialater（主动发起数据）和responder（被动响应请求）
//本package在formatter端，是responder
//其实在formatter端要模拟出一个FIFO出来，如果上行FIF消化数据比较快，而下端消化数据比较慢，会产生滞涨现象，缓存会满
//当然颠倒过来，上面速率比较小，下面速率比较大的时候，会很顺利地消化数据，所以我们需要模拟这样一个buffer

package fmt_pkg;
  import rpt_pkg::*;

  typedef enum {SHORT_FIFO, MED_FIFO, LONG_FIFO, ULTRA_FIFO} fmt_fifo_t;
  typedef enum {LOW_WIDTH, MED_WIDTH, HIGH_WIDTH, ULTRA_WIDTH} fmt_bandwidth_t;

  class fmt_trans;  //其实只需要模拟FMT_GRANT与DUT的交互 //但是我们希望能自洽地实现FMT_GRANT信号的功能，所以引入了FIFO //FIFO是transaction的彰显
  //实际上transaction只是模拟了一个自定义容量FIFO，这个FIFO是transaction的彰显
  //通过FIFO的满空来控制fmt_grant的输出
    rand fmt_fifo_t fifo; //容量大小，小容量/中等容量/大容量/特别大容量（ULTRA过激的）
    rand fmt_bandwidth_t bandwidth; //带宽，低带宽/中等带宽/高带宽/特别高的带宽（ULTRA过激的）
   
  //用来控制fomatter捕捉到了什么样的数据
    bit [9:0] length;   //长度，这里存的是真实值，原本DUT中的长度是有映射关系的，0对应的是4,1对应的是8,2对应的是16,3对应的是32
    bit [31:0] data[];  //数据包，长度待定
    bit [1:0] ch_id;    //arbiter端的控制信号，是哪个通道来的
    bit rsp;            //标识符         
	
    constraint cstr{
      soft fifo == MED_FIFO;         //默认的FIFO是中等容量的FIFO
      soft bandwidth == MED_WIDTH;   //默认的带宽是中等容量的带宽
    };
	
    function fmt_trans clone();
      fmt_trans c = new();
      c.fifo = this.fifo;
      c.bandwidth = this.bandwidth;
      c.length = this.length;
      c.data = this.data;
      c.ch_id = this.ch_id;
      c.rsp = this.rsp;
      return c;
    endfunction

    function string sprint();
      string s;
      s = {s, $sformatf("=======================================\n")};
      s = {s, $sformatf("fmt_trans object content is as below: \n")};
      s = {s, $sformatf("fifo = %s: \n", this.fifo)};
      s = {s, $sformatf("bandwidth = %s: \n", this.bandwidth)};
      s = {s, $sformatf("length = %s: \n", this.length)};
      foreach(data[i]) s = {s, $sformatf("data[%0d] = %8x \n", i, this.data[i])};
      s = {s, $sformatf("ch_id = %0d: \n", this.ch_id)};
      s = {s, $sformatf("rsp = %0d: \n", this.rsp)};
      s = {s, $sformatf("=======================================\n")};
      return s;
    endfunction

    function bit compare(fmt_trans t);  //比较当前的transaction和传递进来的transaction是否一致
	                           //可以利用compare()做两个数据之间的比较
      string s;
      compare = 1;  //在此类中没有定义compare变量，所以我们在外部引用这个函数的时候，要设置compare变量
      s = "\n=======================================\n";
      s = {s, $sformatf("COMPARING fmt_trans object at time %0d \n", $time)};
	  
      if(this.length != t.length) begin
        compare = 0;
        s = {s, $sformatf("sobj length %0d != tobj length %0d \n", this.length, t.length)};
      end
	  
      if(this.ch_id != t.ch_id) begin
        compare = 0;
        s = {s, $sformatf("sobj ch_id %0d != tobj ch_id %0d\n", this.ch_id, t.ch_id)};
      end
	  
      foreach(this.data[i]) begin
        if(this.data[i] != t.data[i]) begin
          compare = 0;
          s = {s, $sformatf("sobj data[%0d] %8x != tobj data[%0d] %8x\n", i, this.data[i], i, t.data[i])};
        end
      end
	  
      if(compare == 1) s = {s, "COMPARED SUCCESS!\n"};
      else  s = {s, "COMPARED FAILURE!\n"};
      s = {s, "=======================================\n"};
      rpt_pkg::rpt_msg("[CMPOBJ]", s, rpt_pkg::INFO, rpt_pkg::MEDIUM);
    endfunction
  endclass

  class fmt_driver;   //从generator中按到transaction，将transaction中的信息与自定义变量做统一，然后发送激励
    local string name;
    local virtual fmt_intf intf;  //与DUT进行交互，所以要例化interface
	
    mailbox #(fmt_trans) req_mb;  //与generator握手通信的
    mailbox #(fmt_trans) rsp_mb;   //与generator握手通信的

    local mailbox #(bit[31:0]) fifo;  //mailbox，用来模拟buffer，mailbox是systemverilog原生FIFO,可以用size做定容
    local int fifo_bound;   //最大长度
    local int data_consum_peroid;  //时间消耗
  
    function new(string name = "fmt_driver");  //有没有必要做new呢？
      this.name = name;
      this.fifo = new();
      this.fifo_bound = 4096;  //长度初始化
      this.data_consum_peroid = 1;  //数据消耗的周期
    endfunction
  
    function void set_interface(virtual fmt_intf intf);
      if(intf == null)
        $error("interface handle is NULL, please check if target interface has been intantiated");
      else
        this.intf = intf;
    endfunction

    task run();
      fork
        this.do_receive();  //接受数据               //内部有forever语句，
        this.do_consume();  //发送数据（消耗数据）   //内部有forever语句
        this.do_config();  //配置FIFO                //内部有forever语句，但会被req_mb的mailbox阻塞，也就是说从generator中拿到transaction才能进行
        this.do_reset();   //复位                    //内部有forever语句，当rstn为零时，做复位
      join //为什么是fork...join，因为模拟的是硬件的行为，上述行为可以随时发生
    endtask

    task do_config();  //配置设计的FIFO，从generator中拿到transaction与本类中的数据变量做同步统一，本类中是用两个变量和一个mailbox构造成的FIFO
	                   //这些元素用来配置我们的formatter，让它表现的像是一个buffer（FIFO）一样。
      fmt_trans req, rsp;
      forever begin
        this.req_mb.get(req); //从generator拿到transaction,来配置
        case(req.fifo)  //容量大小，小容量/中等容量/大容量/特别大容量（ULTRA过激的）
          SHORT_FIFO: this.fifo_bound = 64; //调整FIFO最长的长度
          MED_FIFO: this.fifo_bound = 256;
          LONG_FIFO: this.fifo_bound = 512;
          ULTRA_FIFO: this.fifo_bound = 2048;
        endcase
        this.fifo = new(this.fifo_bound); //重新例化，并制定mailbox的长度
        case(req.bandwidth) //带宽，低带宽/中等带宽/高带宽/特别高的带宽（ULTRA过激的）
          LOW_WIDTH: this.data_consum_peroid = 8;  //带宽  //每一拍会消耗8个数据
          MED_WIDTH: this.data_consum_peroid = 4;          //每一拍会消耗4个数据
          HIGH_WIDTH: this.data_consum_peroid = 2;         //每一拍会消耗2个数据
          ULTRA_WIDTH: this.data_consum_peroid = 1;        //每一拍会消耗1个数据
        endcase
        rsp = req.clone();
        rsp.rsp = 1;  //表示已经成功进行更新配置了
        this.rsp_mb.put(rsp);  //将含有更新之后的信息以及置为1的rsp的rsp放入另一个mailbox中，和generator做握手通信
      end
    endtask

    task do_reset();
      forever begin
        @(negedge intf.rstn) //复位信号为零时
        intf.fmt_grant <= 0;  //驱动grant信号为零，grant信号：允许发送数据
      end
    endtask

    task do_receive();  //模拟从formatter接收数据存在mailbox模拟的FIFO中，与do_consume()做阻塞
      forever begin
        @(posedge intf.fmt_req);  //等待request拉高
		  //这里DUT在等待fmt_req是的值，但需要先判断FIFO是不是满了，没满才能给DUTgrant信号
        forever begin
          @(posedge intf.clk);   //在每个时钟周期上升沿判断余量能不能满足数据通过
          if((this.fifo_bound-this.fifo.num()) >= intf.fmt_length) //最大空间-已经存的数据空间=目前可利用的余量（即将要发送的数据包长度）
            break;
        end
        intf.drv_ck.fmt_grant <= 1;  //这里有唯一的一处被赋值，在要模拟交互的行为的时候，在TB一端做模拟，而DUT的信号是直接拿来用的，无需约束
		
        @(posedge intf.fmt_start);  //等待start的上升沿
		//----spec上面没有说，但是波形图上显示了---所以说这个信号是无关的---我们用了fork..join_none
        fork
          begin
            @(posedge intf.clk);        //再过一拍 grant变为0
            intf.drv_ck.fmt_grant <= 0;  //同样是唯一的一处被赋值
          end
        join_none
		//这里在fmt_grant置为高时，下一个周期fmt_req也要置为低
		
		//但为什么没有fmt_req置低呢，因为fmt_req是DUT的信号，我们需要在checker中验证此行为，但和我们往interface中做驱动无关
		//--------以下代码在start上升沿之后立即发生-------------
        repeat(intf.fmt_length) begin  //fmt_length指的是packet的长度有4/8/16/32
          @(negedge intf.clk); //这里是下降沿触发，是每个时钟周期的下降沿进行触发
		                   //因为data是整周期上升沿变化的，所以正好采样到了中间
          this.fifo.put(intf.fmt_data); //将DUT的数据放入FIFO，每一拍都要采样数据
        end
      end
    endtask

    task do_consume();  //FIFO的消耗数据，从mailbox模拟的FIFO中拿数据，与do_receive()做阻塞
      bit[31:0] data;
      forever begin
	  //直接调用非viod类型返回值返回的函数，虽然合法，但是会出warning，直接用void'()修饰就可以了
        void'(this.fifo.try_get(data));  //从mailbox里面拿数据，不管有没有都会尝试着拿一次，try_get不发生阻塞
		   //用void进行修饰，表示try_get()拿的状态无需进行搁置，其是无用的，可弃置
        repeat($urandom_range(1, this.data_consum_peroid)) @(posedge intf.clk); //延迟设置
		//每过一定的时间从FIFO中拿数据
      end
    endtask
  
  endclass

  class fmt_generator;  //产生一个经过随机化的transaction,送入driver
    rand fmt_fifo_t fifo = MED_FIFO;  //容量大小，小容量/中等容量/大容量/特别大容量（ULTRA过激的）
    rand fmt_bandwidth_t bandwidth = MED_WIDTH;  //带宽，低带宽/中等带宽/高带宽/特别高的带宽（ULTRA过激的）

    mailbox #(fmt_trans) req_mb;    //和driver做握手通信
    mailbox #(fmt_trans) rsp_mb;    //和driver做握手通信

    constraint cstr{
      soft fifo == MED_FIFO;  //默认为中等容量
      soft bandwidth == MED_WIDTH;  //默认为中等带宽
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
      fmt_trans req, rsp;
      req = new();
      assert(req.randomize with {local::fifo != MED_FIFO -> fifo == local::fifo; 
                                 local::bandwidth != MED_WIDTH -> bandwidth == local::bandwidth;
                               })
        else $fatal("[RNDFAIL] formatter packet randomization failure!");
      $display(req.sprint());
      this.req_mb.put(req);  //和driver做握手通信,将随机化的transaction(FIFO的彰显)信息传入driver中
      this.rsp_mb.get(rsp);  //和driver做握手通信，拿到了
      $display(rsp.sprint());
      assert(rsp.rsp)
        else $error("[RSPERR] %0t error response received!", $time);
    endtask

    function string sprint();
      string s;
      s = {s, $sformatf("=======================================\n")};
      s = {s, $sformatf("fmt_generator object content is as below: \n")};
      s = {s, $sformatf("fifo = %s: \n", this.fifo)};
      s = {s, $sformatf("bandwidth = %s: \n", this.bandwidth)};
      s = {s, $sformatf("=======================================\n")};
      return s;
    endfunction

    function void post_randomize();
      string s;
      s = {"AFTER RANDOMIZATION \n", this.sprint()};
      $display(s);
    endfunction

  endclass

  class fmt_monitor;
    local string name;
    local virtual fmt_intf intf;
    mailbox #(fmt_trans) mon_mb; //是要传递给checker的
	
    function new(string name="fmt_monitor");
      this.name = name;
    endfunction
	
    function void set_interface(virtual fmt_intf intf);
      if(intf == null)
        $error("interface handle is NULL, please check if target interface has been intantiated");
      else
        this.intf = intf;
    endfunction

    task run();
      this.mon_trans();
    endtask

    task mon_trans();
      fmt_trans m;
      string s;
      forever begin
        @(posedge intf.mon_ck.fmt_start);
        m = new();
        m.length = intf.mon_ck.fmt_length; //将fmt_length传入新创建的trans里
        m.ch_id = intf.mon_ck.fmt_chid;   //将fmt_chid传入新创建的trans里
        m.data = new[m.length];           //data就是length的长度，这里例化了一个动态数组
        foreach(m.data[i]) begin    //将数据存进去
          @(posedge intf.clk);
          m.data[i] = intf.mon_ck.fmt_data;
        end
        mon_mb.put(m); //至此，m句柄中保存了数据/通道ID/数据长度，将它发送到checker中，
        s = $sformatf("=======================================\n");
        s = {s, $sformatf("%0t %s monitored a packet: \n", $time, this.name)};
        s = {s, $sformatf("length = %0d: \n", m.length)};
        s = {s, $sformatf("chid = %0d: \n", m.ch_id)};
        foreach(m.data[i]) s = {s, $sformatf("data[%0d] = %8x \n", i, m.data[i])};
        s = {s, $sformatf("=======================================\n")};
        $display(s);
      end
    endtask
  endclass

  class fmt_agent;  //仅仅是一个盒子
    local string name;
    fmt_driver driver;
    fmt_monitor monitor;
    local virtual fmt_intf vif;
    function new(string name = "fmt_agent");
      this.name = name;
      this.driver = new({name, ".driver"});
      this.monitor = new({name, ".monitor"});
    endfunction

    function void set_interface(virtual fmt_intf vif);
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
