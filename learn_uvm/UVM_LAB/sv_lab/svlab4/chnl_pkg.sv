package chnl_pkg;
  //完全复用之前的channel package 
  class chnl_trans;  //transaction是一组数据发送到DUT的
    rand bit[31:0] data[];  //动态数组
    rand int ch_id;         //要发送至哪一个channel(也对应着哪一个generator发送的)
    rand int pkt_id;        //当前的packet的id  //packet是一组data[i]的集合      //在generator中有定义每产生一个packet自增一
    rand int data_nidles;   //data[i]和data[i]之间的空闲是多少
    rand int pkt_nidles;    //packet和packet之间的空闲周期是多少
    bit rsp;                //默认初始化是0，而且没有rand属性，为了标记是否成功握手了
	
    constraint cstr{
      soft data.size inside {[4:32]};  //动态数组长度也能做随机变量
      foreach(data[i]) data[i] == 'hC000_0000 + (this.ch_id<<24) + (this.pkt_id<<8) + i; //为什么设置16进制'hC000_0000？在处理后的对应的数据上面会对应着C0/C1/C2//便于观察
      soft ch_id == 0;   //默认channel为0，可以外部修改     //保证没有任何的数据是重合的  //同时也增强了溯源性，如果在乱序的情况下，我们知道数据是从哪一个地方发送出来的
      soft pkt_id == 0;    //默认pkt_id为0，当前的packet的id为0                //可以确认到底哪里是不完整
      data_nidles inside {[0:2]};  //data之间至多间隔3个周期
      pkt_nidles inside {[1:10]};  //packet之间至少要间隔1-10个周期
    };

    function chnl_trans clone();  //把当前对象的值赋值给了新的对象，返回新对象的句柄
      chnl_trans c = new();
      c.data = this.data;
      c.ch_id = this.ch_id;
      c.pkt_id = this.pkt_id;
      c.data_nidles = this.data_nidles;
      c.pkt_nidles = this.pkt_nidles;
      c.rsp = this.rsp;
      return c;
    endfunction

    function string sprint();   //返回的字符串保存了transation里的内容
      string s;
      s = {s, $sformatf("=======================================\n")};
      s = {s, $sformatf("chnl_trans object content is as below: \n")};
      foreach(data[i]) s = {s, $sformatf("data[%0d] = %8x \n", i, this.data[i])};
      s = {s, $sformatf("ch_id = %0d: \n", this.ch_id)};
      s = {s, $sformatf("pkt_id = %0d: \n", this.pkt_id)};
      s = {s, $sformatf("data_nidles = %0d: \n", this.data_nidles)};
      s = {s, $sformatf("pkt_nidles = %0d: \n", this.pkt_nidles)};
      s = {s, $sformatf("rsp = %0d: \n", this.rsp)};
      s = {s, $sformatf("=======================================\n")};
      return s;
    endfunction
  endclass: chnl_trans
  
  class chnl_driver;  //在driver中设置了data与data间，packet与packet之间的延迟，这点要理解
    local string name;                //自定义的chn1_driver姓名，用于标记
    local virtual chnl_intf intf;     //只有接触DUT才需要传递interface
    mailbox #(chnl_trans) req_mb;     //和generator通信的mailbox，参数化的mailbox，只能存放chn1_trans类型
    mailbox #(chnl_trans) rsp_mb;     //和generator通信的mailbox，参数化的mailbox，只能存放chn1_trans类型
  
    function new(string name = "chnl_driver");
      this.name = name;
    endfunction
  
    function void set_interface(virtual chnl_intf intf);   //只有接触DUT才传递interface
      if(intf == null)
        $error("interface handle is NULL, please check if target interface has been intantiated");
      else
        this.intf = intf;
    endfunction

    task run();
      fork   //并行执行
       this.do_drive();  
       this.do_reset();
      join
    endtask

    task do_reset();
      forever begin
        @(negedge intf.rstn);  //下降沿敏感
        intf.ch_valid <= 0;
        intf.ch_data <= 0;
      end
    endtask

    task do_drive();   
      chnl_trans req, rsp;      //驱动transaction，当然要例化transaction了
      @(posedge intf.rstn);   
      forever begin             //forever表示一直在驱动
        this.req_mb.get(req);   //在req_mb的mailbox中拿出句柄并赋值给req,如果句柄为空则阻塞
        this.chnl_write(req);   //送入interface中，外置函数
        rsp = req.clone();      //clone一个新的对象，将句柄赋值给rsp //想告诉generator我已经将你的数据送出去了 //原来的对象已经送入interface中了，再进行操作不太好
        rsp.rsp = 1;            //写入interface后，克隆出来并设置标识符
        this.rsp_mb.put(rsp);   //在rsp_mb的mailbox中放置句柄rsp
      end
    endtask
  
    task chnl_write(input chnl_trans t);  
      foreach(t.data[i]) begin  //解析transcation
        @(posedge intf.clk);
        intf.drv_ck.ch_valid <= 1;  //要写入数据了，将ch_valid拉高
        intf.drv_ck.ch_data <= t.data[i];  //将数据写入
        @(negedge intf.clk);  //为什么要过半个周期哈，其实是没有必要的，加了也无妨，因为是单时钟域，半个时钟周期是触发的最小时间单位
        wait(intf.ch_ready === 'b1); //等待ready为高，表示已经将数据写入，可以发送下一个了
        $display("%0t channel driver [%s] sent data %x", $time, name, t.data[i]);
        repeat(t.data_nidles) chnl_idle(); //设置data与data的延迟，这里认定data与data之间的间隔为ready拉高之后到发送下一个trans的间隔
      end
      repeat(t.pkt_nidles) chnl_idle();  //设置packet与packet的延迟
    endtask
    
    task chnl_idle();
      @(posedge intf.clk);
      intf.drv_ck.ch_valid <= 0;
      intf.drv_ck.ch_data <= 0;
    endtask
  endclass: chnl_driver
  
  class chnl_generator;
    /*这些变量都是用于约束transaction的，是个transaction里的约束复用的*/
	
    rand int pkt_id = 0;          //当前packet的id 
    rand int ch_id = -1;          //要发送至哪一个channel
    rand int data_nidles = -1;    //发送几个transaction
    rand int pkt_nidles = -1;    //data和data之间的空闲周期是多少
	
    rand int data_size = -1;   //约束的是rand bit[31:0] data[];的data.size()
    rand int ntrans = 10;      //有多少簇transaction

    mailbox #(chnl_trans) req_mb;     //需要例化的mailbox
    mailbox #(chnl_trans) rsp_mb;     //需要例化的mailbox

    constraint cstr{
      soft ch_id == -1;
      soft pkt_id == 0;
      soft data_size == -1;
      soft data_nidles == -1;
      soft pkt_nidles == -1;
      soft ntrans == 10;
    }

    function new();
      this.req_mb = new();       //需要例化的mailbox
      this.rsp_mb = new();       //需要例化的mailbox
    endfunction

    task start();
      repeat(ntrans) send_trans();
    endtask

    task send_trans();
      chnl_trans req, rsp;  //一个用于产生transaction，一个用于记录到底transaction到底发没发出去
      req = new();
      assert(req.randomize with {local::ch_id >= 0 -> ch_id == local::ch_id;         //这里的判断语句是为了判断外部约束是否加载到了此类中
                                 local::pkt_id >= 0 -> pkt_id == local::pkt_id;      //如果外部约束成功加载到了此类中，约束要统一
                                 local::data_nidles >= 0 -> data_nidles == local::data_nidles;
                                 local::pkt_nidles >= 0 -> pkt_nidles == local::pkt_nidles;
                                 local::data_size >0 -> data.size() == local::data_size; 
                               })
        else $fatal("[RNDFAIL] channel packet randomization failure!");   
      this.pkt_id++;           //
      $display(req.sprint());
      this.req_mb.put(req);   //在req_mb的mailbox中放置句柄req，driver一端会拿到这个句柄
      this.rsp_mb.get(rsp);   //在rsp_mb的mailbox（driver端）中拿出句柄并赋值给rsp，否则被阻塞
      $display(rsp.sprint());
      assert(rsp.rsp)       //如果为1则继续执行，如果为0执行下面的else，断言是否握手成功，断言是否成功送入interface
        else $error("[RSPERR] %0t error response received!", $time);
    endtask

    function string sprint();
      string s;
      s = {s, $sformatf("=======================================\n")};
      s = {s, $sformatf("chnl_generator object content is as below: \n")};
      s = {s, $sformatf("ntrans = %0d: \n", this.ntrans)};
      s = {s, $sformatf("ch_id = %0d: \n", this.ch_id)};
      s = {s, $sformatf("pkt_id = %0d: \n", this.pkt_id)};
      s = {s, $sformatf("data_nidles = %0d: \n", this.data_nidles)};
      s = {s, $sformatf("pkt_nidles = %0d: \n", this.pkt_nidles)};
      s = {s, $sformatf("data_size = %0d: \n", this.data_size)};
      s = {s, $sformatf("=======================================\n")};
      return s;
    endfunction

    function void post_randomize();
      string s;
      s = {"AFTER RANDOMIZATION \n", this.sprint()};
      $display(s);
    endfunction
  endclass: chnl_generator

  typedef struct packed {
    bit[31:0] data;
    bit[1:0] id;
  } mon_data_t;  //注意这里是一个单一的形式，并不是packet的形式

  class chnl_monitor;  //在monitor中接受的数据是以单一的数据形式发送的，而不是packet的形式
    local string name;           //monitor的识别姓名
    local virtual chnl_intf intf;    //因为monitor的监测对象是interface，所以需要传interface
    mailbox #(mon_data_t) mon_mb;  //没有必要做握手，所以只例化了一个mailbox，与checker做通信
	//这里的mailbox是没有空间限制的，
    
	function new(string name="chnl_monitor");  //保留了参数化的例化选择
      this.name = name;
    endfunction
	
    function void set_interface(virtual chnl_intf intf);
      if(intf == null)
        $error("interface handle is NULL, please check if target interface has been intantiated");
      else
        this.intf = intf;
    endfunction
	
    task run();   
      this.mon_trans();  //每个组件都会封装在run()里
    endtask

    task mon_trans();
      mon_data_t m;
      forever begin         //vaild为高（已经将数据写入）才能传，ready为高（可以接受数据FIFO有余量）才能传
        @(posedge intf.clk iff (intf.mon_ck.ch_valid==='b1 && intf.mon_ck.ch_ready==='b1)); //因为generator在前后都设置了阻塞，所以无论有没有idle，都可以拿出ch_data
		//这里的iff放置得很精巧，只有vaild为高时才能发送数据，每拍只发送一个
		//而对于ready而言，在传送过程中一直被置为高，当为低时，需要重新传送一个data，这样的iff判断非常精巧
		//避免了重复计数的困扰
        m.data = intf.mon_ck.ch_data;  //没有必要将interface中的ID传入mon_data_t中，因为ID只是来用作识别
        mon_mb.put(m);
        $display("%0t %s monitored channle data %8x", $time, this.name, m.data);
      end
    endtask
  endclass
  
  class chnl_agent;
    local string name;  //设置名字
    chnl_driver driver;     //例化一个driver
    chnl_monitor monitor;   //例化一个monitor
    local virtual chnl_intf vif;  //因为monitor的监测对象是interface，所以需要传interface
   
   function new(string name = "chnl_agent");
      this.name = name;
      this.driver = new({name, ".driver"});
      this.monitor = new({name, ".monitor"});
    endfunction

    function void set_interface(virtual chnl_intf vif);
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
  endclass: chnl_agent

endpackage

