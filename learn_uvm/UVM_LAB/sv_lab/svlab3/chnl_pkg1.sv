package chnl_pkg1;

   // static variables shared by resources
  semaphore run_stop_flags = new();   //the default number of keys is ‘0’
  //这是在class外声明的，不随class的生命周期结束而结束
  
  class chnl_trans;
    rand bit[31:0] data[];
    rand int ch_id;     //channel id标识符  //要发送至哪一个channel(也对应着哪一个generator发送的)
    rand int pkt_id;    //packet id标识符   //当前的packet的id  //packet是一组data的集合  //在generator中有定义每产生一个transaction自增一
    rand int data_nidles;    //data和data之间的空闲周期是多少
    rand int pkt_nidles;     //packet和packet之间的空闲周期是多少
    bit rsp;                 //默认初始化是0，而且没有rand属性，为了标记是否成功握手了
    local static int obj_id = 0;  //例化次数标志符
    // USER TODO 1.1.
    // Specify constraint to match the chnl_basic_test request
    constraint cstr{
      data.size inside {[4:8]};     //动态数组长度也能做随机变量
      foreach(data[i]) data[i] == 'hC000_0000 + (this.ch_id<<24) + (this.pkt_id<<8) + i;   //为什么设置16进制'hC000_0000？在处理后的对应的数据上面会对应着C0/C1/C2//便于观察
      soft ch_id == 0;              //默认channel为0，可以外部修改  //保证没有任何的数据是重合的  //同时也增强了溯源性，如果在乱序的情况下，我们知道数据是从哪一个地方发送出来的
      soft pkt_id == 0;             //默认pkt_id为0，当前的transation的id为0 	  //可以确认到底哪里是不完整
         //soft关键字可以定义外部约束域
	  data_nidles inside {[0:2]};   //data之间至多间隔3个周期
      pkt_nidles inside {[1:10]};   //transation之间至少要间隔1-10个周期
    };
	
    function new();
      this.obj_id++;       //每例化一次就自增一
    endfunction

    function chnl_trans clone(); //把当前对象的值赋值给了新的对象，返回新对象的句柄
      chnl_trans c = new();
      c.data = this.data;
      c.ch_id = this.ch_id;
      c.pkt_id = this.pkt_id;
      c.data_nidles = this.data_nidles;
      c.pkt_nidles = this.pkt_nidles;
      c.rsp = this.rsp;
      // USER TODO 1.2
      // Could we put c.obj_id = this.obj_id here? and why?
      return c;
    endfunction

    function string sprint();             //返回的字符串保存了transation里的内容
      string s;
      s = {s, $sformatf("=======================================\n")};                      //字符串拼接
      s = {s, $sformatf("chnl_trans object content is as below: \n")};                      //字符串拼接
      s = {s, $sformatf("obj_id = %0d: \n", this.obj_id)};                                  //字符串拼接
      foreach(data[i]) s = {s, $sformatf("data[%0d] = %8x \n", i, this.data[i])};           //字符串拼接
      s = {s, $sformatf("ch_id = %0d: \n", this.ch_id)};                                    //字符串拼接
      s = {s, $sformatf("pkt_id = %0d: \n", this.pkt_id)};                                  //字符串拼接
      s = {s, $sformatf("data_nidles = %0d: \n", this.data_nidles)};                        //字符串拼接
      s = {s, $sformatf("pkt_nidles = %0d: \n", this.pkt_nidles)};                          //字符串拼接
      s = {s, $sformatf("rsp = %0d: \n", this.rsp)};                                        //字符串拼接
      s = {s, $sformatf("=======================================\n")};                      //字符串拼接
      return s;
    endfunction
  endclass: chnl_trans
   
  class chnl_initiator;
    local string name;
    local virtual chnl_intf intf;
    mailbox #(chnl_trans) req_mb;     //参数化的mailbox，只能存放chn1_trans类型
    mailbox #(chnl_trans) rsp_mb;     //参数化的mailbox，只能存放chn1_trans类型
  
    function new(string name = "chnl_initiator");
      this.name = name;
    endfunction
  
    function void set_name(string s);
      this.name = s;
    endfunction
  
    function void set_interface(virtual chnl_intf intf);
      if(intf == null)
        $error("interface handle is NULL, please check if target interface has been intantiated");
      else
        this.intf = intf;
    endfunction

    task run();
      this.drive();
    endtask

    task drive();
      chnl_trans req, rsp;
      @(posedge intf.rstn);
      forever begin       //永不停息地drive
        this.req_mb.get(req);    //通过mailbox拿到generator中的句柄并赋值给req
        this.chnl_write(req);    //送入interface中
        rsp = req.clone();       //clone一个新的对象，将句柄赋值给rsp //想告诉generator我已经将你的数据送出去了
        rsp.rsp = 1;
        this.rsp_mb.put(rsp);   //在rsp_mb的mailbox中放置句柄rsp
      end
    endtask
  
    task chnl_write(input chnl_trans t);
      foreach(t.data[i]) begin
        @(posedge intf.clk);
         intf.drv_ck.ch_valid <= 1;
         intf.drv_ck.ch_data <= t.data[i];
        wait(intf.ch_ready === 'b1);
        $display("%0t channel initiator [%s] sent data %x", $time, name, t.data[i]);
        repeat(t.data_nidles) chnl_idle();    //这里体会data_idle的用法，是data与data之间的间隔
      end
      repeat(t.pkt_nidles) chnl_idle();       //这里体会pkt_nidles的用法，是packet与packet的间隔，一个packet等于一组带间隔的data
    endtask
    
    task chnl_idle();
      @(posedge intf.clk);
      intf.drv_ck.ch_valid <= 0;
      intf.drv_ck.ch_data <= 0;
    endtask
  endclass: chnl_initiator
    
  class chnl_generator;
    int pkt_id;     //当前的packet的id     //默认为0
    int ch_id;     //要发送至哪一个channel     //受配置
    int ntrans;      //发送几个transaction     //受配置
    int data_nidles;  //data和data之间的空闲周期是多少  //没有考虑，无约束，里面是初始化的垃圾值
    mailbox #(chnl_trans) req_mb;    //无需例化的mailbox
    mailbox #(chnl_trans) rsp_mb;    //无需例化的mailbox

    function new(int ch_id, int ntrans); //只配置了ch_id和ntrans
      this.ch_id = ch_id;
      this.pkt_id = 0;
      this.ntrans = ntrans;
      this.req_mb = new();
      this.rsp_mb = new();
    endfunction

    task run();
      repeat(ntrans) send_trans();
	  run_stop_flags.put();      //放钥匙  
    endtask

    // generate transaction and put into local mailbox 
    task send_trans();
      chnl_trans req, rsp;
      req = new();
      assert(req.randomize with {ch_id == local::ch_id; pkt_id == local::pkt_id; data_nidles inside {[3:5]}; pkt_nidles inside {[0:2]}})   //在generator中保留了配置transaction的接口
        else $fatal("[RNDFAIL] channel packet randomization failure!");
      this.pkt_id++;  //当前执行到了哪一个packet
      $display(req.sprint());
      this.req_mb.put(req);    //在req_mb的mailbox中放置句柄req
      this.rsp_mb.get(rsp);    //在rsp_mb的mailbox中拿出句柄并赋值给rsp
      $display(rsp.sprint());   
      assert(rsp.rsp)         //如果为1则继续执行，如果为0执行下面的else，断言是否握手成功，断言是否成功送入interface
        else $error("[RSPERR] %0t error response received!", $time);
    endtask
  endclass: chnl_generator

  class chnl_agent;
    chnl_generator gen;
    chnl_initiator init;
    local virtual chnl_intf vif;
    function new(string name = "chnl_agent", int id = 0, int ntrans = 1);
      this.gen = new(id, ntrans);
      this.init = new(name);
    endfunction
    function void set_interface(virtual chnl_intf vif);  //注意这里类中也定义了interface，传入的interface与类中定义的interface做了同步，可以方便为未来扩展类的使用
      this.vif = vif;
      init.set_interface(vif);
    endfunction
    task run();
      this.init.req_mb = this.gen.req_mb;    //要保证mailbox一致性
      this.init.rsp_mb = this.gen.rsp_mb;    //要保证mailbox一致性 
      fork
        gen.run();  
        init.run(); //永动机是forever状态
      join_any    //所以用join_any，只要有任何一个线程执行完毕就准备退出了
    endtask
  endclass: chnl_agent

  class chnl_root_test;
    chnl_agent agent[3];
    protected string name;
    function new(int ntrans = 100, string name = "chnl_root_test");
      foreach(agent[i]) begin
        this.agent[i] = new($sformatf("chnl_agent%0d",i), i, ntrans);
      end
      this.name = name;
      $display("%s instantiate objects", this.name);
    endfunction
    task run();
      $display($sformatf("*****************%s started********************", this.name));
      fork
        agent[0].run();
        agent[1].run();
        agent[2].run();
      join
      $display($sformatf("*****************%s finished********************", this.name));
      // USER TODO 1.3
      // Please move the $finish statement from the test run task to generator
      // You would put it anywhere you like inside generator to stop test when
      // all transactions have been transfered
      //$finish();
	   run_stop_callback(); // wait until run stop control task finished   //必须要在结束之后才能开始收集钥匙
	  
      // USER TODO 1.4
      // Apply 'vsim -novopt -solvefaildebug -sv_seed 0 work.tb1' to run the
      // simulation, and check if the generated data is the same as previously
      // Then use 'vsim -novopt -solvefaildebug -sv_seed random work.tb1' to
      // run the test 2 times, and check if the data generated of 2 times are
      // is the same or not?
      
      // USER TODO 1.5
      // In the last chnl_trans object content display, why the object_id is
      // 1200? How is it counted and finally as the value 1200?
    endtask
	
	virtual task run_stop_callback();
      $display("run_stop_callback enterred");
      // by default, run would be finished once generators raised 'finish'
      // flags 
      $display("%s: wait for all generators have generated and tranferred transcations", this.name);
      run_stop_flags.get(3);    //自动被阻塞，如果拿不到就一直被阻塞
      $display($sformatf("*****************%s finished********************", this.name));
      $finish();
    endtask
	
    function void set_interface(virtual chnl_intf ch0_vif, virtual chnl_intf ch1_vif, virtual chnl_intf ch2_vif);
      agent[0].set_interface(ch0_vif);
      agent[1].set_interface(ch1_vif);
      agent[2].set_interface(ch2_vif);
    endfunction
  endclass

  // USER TODO 1.1
  // each channel send data with idle_cycles inside [0:2]
  // and idle peroids between sequential packets should be inside [3:5]
  // each channel send out 200 data then to finish the test
  // The idle_cycle constraint should be specified inside chnl_trans
  class chnl_basic_test extends chnl_root_test;   //这里不做扩展，定义在了chnl_pkg3_ref中
    function new(int ntrans = 200, string name = "chnl_basic_test");
      super.new(ntrans, name);
    endfunction	
	$display("%s configured objects", this.name);
  endclass: chnl_basic_test

  // Refer to chnl_basic_test, and extend another 2 tests
  
  // chnl_burst_test, chnl_fifo_full_test
  // each channel send data with idle_cycles == 0  //无法实现，因为idle_cycle的约束在chn1_generator中，无法被复用
  // each channel send out 500 data
  // then to finish the test
  class chnl_burst_test extends chnl_root_test;    //这里不做扩展，定义在了chnl_pkg3_ref中
  // USER TODO
	function new(int ntrans = 500, string name = "chnl_burst_test");
      super.new(ntrans, name);
    endfunction	
  endclass: chnl_burst_test

  // each channel send data with idle_cycles == 0
  // each channel send out 500 data
  // The test should be immediately finished when all of channels
  // have been reached fifo full state, but not all reaching
  // fifo full at the same time
  //只要到达三路的fifo的状态全满就直接停下来
  class chnl_fifo_full_test extends chnl_root_test;    //这里不做扩展，定义在了chnl_pkg3_ref中
    // USER TODO
    function new(int ntrans = 500, string name = "chnl_fifo_full_test");
      super.new(ntrans, name);
    endfunction	

	task run();
      $display($sformatf("*****************%s started********************", this.name));
      fork:fork_all_run
        agent[0].run();
        agent[1].run();
        agent[2].run();
      join_none
	  $display("%s: 3 agents running now", this.name);
      $display("%s: waiting 3 channel fifos to be full", this.name);
	  fork
        wait(agent[0].vif.ch_margin == 0);
        wait(agent[1].vif.ch_margin == 0);
        wait(agent[2].vif.ch_margin == 0);
      join
      $display("%s: 3 channel fifos have reached full", this.name);
      $display("%s: stop 3 agents running", this.name);  
	  disable fork_all_run;               //注意！！这里disable掉，但是钥匙放没放进去不知道！！
      $display("%s: set and ensure all agents' initiator are idle state", this.name);
      fork //让所有的数据传完
        agent[0].init.chnl_idle();
        agent[1].init.chnl_idle();
        agent[2].init.chnl_idle();
      join
      $display("%s waiting DUT transfering all of data", this.name);
	  fork
        wait(agent[0].vif.ch_margin == 'h20);
        wait(agent[1].vif.ch_margin == 'h20);
        wait(agent[2].vif.ch_margin == 'h20);
      join
	  
	  $display("%s: 3 channel fifos have transferred all data", this.name);
      $display("%s finished testing DUT", this.name);
	  
	  run_stop_callback(); // wait until run stop control task finished  //所以这里钥匙大概率会一直拿不到，所以callback会失效。
    endtask


	virtual task run_stop_callback();
      $display("run_stop_callback enterred");
      // by default, run would be finished once generators raised 'finish'
      // flags 
      $display("%s: wait for all generators have generated and tranferred transcations", this.name);
      run_stop_flags.get(3);    //自动被阻塞，如果拿不到就一直被阻塞
      $display($sformatf("*****************%s finished********************", this.name));
      $finish();
    endtask
  endclass: chnl_fifo_full_test

endpackage


