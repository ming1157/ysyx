      `include "param_def.v"

package mcdf_pkg;

  import chnl_pkg::*;
  import reg_pkg::*;
  import arb_pkg::*;
  import fmt_pkg::*;
  import rpt_pkg::*;

  typedef struct packed {
    bit[2:0] len;
    bit[1:0] prio;
    bit en;
    bit[7:0] avail;
  } mcdf_reg_t;

  typedef enum {RW_LEN, RW_PRIO, RW_EN, RD_AVAIL} mcdf_field_t;

  class mcdf_refmod;
    local virtual mcdf_intf intf;
    local string name;
    mcdf_reg_t regs[3];
    mailbox #(reg_trans) reg_mb;
    mailbox #(mon_data_t) in_mbs[3];
    mailbox #(fmt_trans) out_mbs[3];

    function new(string name="mcdf_refmod");
      this.name = name;
      foreach(this.out_mbs[i]) this.out_mbs[i] = new();
    endfunction

    task run();
      fork
        do_reset();
        this.do_reg_update();
        do_packet(0);
        do_packet(1);
        do_packet(2);
      join
    endtask

    task do_reg_update();
      reg_trans t;
      forever begin
        this.reg_mb.get(t);
        if(t.addr[7:4] == 0 && t.cmd == `WRITE) begin
          this.regs[t.addr[3:2]].en = t.data[0];
          this.regs[t.addr[3:2]].prio = t.data[2:1];
          this.regs[t.addr[3:2]].len = t.data[5:3];
        end
        else if(t.addr[7:4] == 1 && t.cmd == `READ) begin
          this.regs[t.addr[3:2]].avail = t.data[7:0];
        end
      end
    endtask

    task do_packet(int id);
      fmt_trans ot;
      mon_data_t it;
      forever begin
        this.in_mbs[id].peek(it);
        ot = new();
        ot.length = 4 << (this.get_field_value(id, RW_LEN) & 'b11);
        ot.data = new[ot.length];
        ot.ch_id = id;
        foreach(ot.data[m]) begin
          this.in_mbs[id].get(it);
          ot.data[m] = it.data;
        end
        this.out_mbs[id].put(ot);
      end
    endtask

    function int get_field_value(int id, mcdf_field_t f);
      case(f)
        RW_LEN: return regs[id].len;
        RW_PRIO: return regs[id].prio;
        RW_EN: return regs[id].en;
        RD_AVAIL: return regs[id].avail;
      endcase
    endfunction 

    task do_reset();
      forever begin
        @(negedge intf.rstn); 
        foreach(regs[i]) begin
          regs[i].len = 'h0;
          regs[i].prio = 'h3;
          regs[i].en = 'h1;
          regs[i].avail = 'h20;
        end
      end
    endtask

    function void set_interface(virtual mcdf_intf intf);
      if(intf == null)
        $error("interface handle is NULL, please check if target interface has been intantiated");
      else
        this.intf = intf;
    endfunction
    
  endclass

  class mcdf_checker;
    local string name;
    local int err_count;
    local int total_count;
    local int chnl_count[3];
    local virtual chnl_intf chnl_vifs[3]; 
    local virtual arb_intf arb_vif; 
    local virtual mcdf_intf mcdf_vif;
    local mcdf_refmod refmod;
    mailbox #(mon_data_t) chnl_mbs[3];
    mailbox #(fmt_trans) fmt_mb;
    mailbox #(reg_trans) reg_mb;
    mailbox #(fmt_trans) exp_mbs[3];

    function new(string name="mcdf_checker");
      this.name = name;
      foreach(this.chnl_mbs[i]) this.chnl_mbs[i] = new();
      this.fmt_mb = new();
      this.reg_mb = new();
      this.refmod = new();
      foreach(this.refmod.in_mbs[i]) begin
        this.refmod.in_mbs[i] = this.chnl_mbs[i];
        this.exp_mbs[i] = this.refmod.out_mbs[i];
      end
      this.refmod.reg_mb = this.reg_mb;
      this.err_count = 0;
      this.total_count = 0;
      foreach(this.chnl_count[i]) this.chnl_count[i] = 0;
    endfunction

    function void set_interface(virtual mcdf_intf mcdf_vif, virtual chnl_intf chnl_vifs[3], virtual arb_intf arb_vif);
      if(mcdf_vif == null)
        $error("mcdf interface handle is NULL, please check if target interface has been intantiated");
      else begin
        this.mcdf_vif = mcdf_vif;
        this.refmod.set_interface(mcdf_vif);
      end
      if(chnl_vifs[0] == null || chnl_vifs[1] == null || chnl_vifs[2] == null)
        $error("chnl interface handle is NULL, please check if target interface has been intantiated");
      else begin
        this.chnl_vifs = chnl_vifs;
      end
      if(arb_vif == null)
        $error("arb interface handle is NULL, please check if target interface has been intantiated");
      else begin
        this.arb_vif = arb_vif;
      end
    endfunction

    task run();
      fork
        this.do_channel_disable_check(0);
        this.do_channel_disable_check(1);
        this.do_channel_disable_check(2);
        this.do_arbiter_priority_check();
        this.do_compare();
        this.refmod.run();
      join
    endtask

    task do_compare();
      fmt_trans expt, mont;
      bit cmp;
      forever begin
        this.fmt_mb.get(mont);
        this.exp_mbs[mont.ch_id].get(expt);
        cmp = mont.compare(expt);   
        this.total_count++;
        this.chnl_count[mont.ch_id]++;
        if(cmp == 0) begin
          this.err_count++;
          rpt_pkg::rpt_msg("[CMPFAIL]", 
            $sformatf("%0t %0dth times comparing but failed! MCDF monitored output packet is different with reference model output", $time, this.total_count),
            rpt_pkg::ERROR,
            rpt_pkg::TOP,
            rpt_pkg::LOG);
        end
        else begin
          rpt_pkg::rpt_msg("[CMPSUCD]",
            $sformatf("%0t %0dth times comparing and succeeded! MCDF monitored output packet is the same with reference model output", $time, this.total_count),
            rpt_pkg::INFO,
            rpt_pkg::HIGH);
        end
      end
    endtask

    task do_channel_disable_check(int id);
      forever begin
        @(posedge this.mcdf_vif.clk iff (this.mcdf_vif.rstn && this.mcdf_vif.mon_ck.chnl_en[id]===0));
        if(this.chnl_vifs[id].mon_ck.ch_valid===1 && this.chnl_vifs[id].mon_ck.ch_ready===1)
          rpt_pkg::rpt_msg("[CHKERR]", 
            $sformatf("ERROR! %0t when channel disabled, ready signal raised when valid high",$time), 
            rpt_pkg::ERROR, 
            rpt_pkg::TOP);
      end
    endtask

    task do_arbiter_priority_check();
      int id;
      forever begin
        @(posedge this.arb_vif.clk iff (this.arb_vif.rstn && this.arb_vif.mon_ck.f2a_id_req===1));
        id = this.get_slave_id_with_prio();
        if(id >= 0) begin
          @(posedge this.arb_vif.clk);
          if(this.arb_vif.mon_ck.a2s_acks[id] !== 1)
            rpt_pkg::rpt_msg("[CHKERR]",
              $sformatf("ERROR! %0t arbiter received f2a_id_req===1 and channel[%0d] raising request with high priority, but is not granted by arbiter", $time, id),
              rpt_pkg::ERROR,
              rpt_pkg::TOP);
        end
      end
    endtask

    function int get_slave_id_with_prio();
      int id=-1;
      int prio=999;
      foreach(this.arb_vif.mon_ck.slv_prios[i]) begin
        if(this.arb_vif.mon_ck.slv_prios[i] < prio && this.arb_vif.mon_ck.slv_reqs[i]===1) begin
          id = i;
          prio = this.arb_vif.mon_ck.slv_prios[i];
        end
      end
      return id;
    endfunction

    function void do_report();
      string s;
      s = "\n---------------------------------------------------------------\n";
      s = {s, "CHECKER SUMMARY \n"}; 
      s = {s, $sformatf("total comparison count: %0d \n", this.total_count)}; 
      foreach(this.chnl_count[i]) s = {s, $sformatf(" channel[%0d] comparison count: %0d \n", i, this.chnl_count[i])};
      s = {s, $sformatf("total error count: %0d \n", this.err_count)}; 
      foreach(this.chnl_mbs[i]) begin
        if(this.chnl_mbs[i].num() != 0)
          s = {s, $sformatf("WARNING:: chnl_mbs[%0d] is not empty! size = %0d \n", i, this.chnl_mbs[i].num())}; 
      end
      if(this.fmt_mb.num() != 0)
          s = {s, $sformatf("WARNING:: fmt_mb is not empty! size = %0d \n", this.fmt_mb.num())}; 
      s = {s, "---------------------------------------------------------------\n"};
      rpt_pkg::rpt_msg($sformatf("[%s]",this.name), s, rpt_pkg::INFO, rpt_pkg::TOP);
    endfunction
  endclass

  class mcdf_coverage;  //这是个独立的类，不参与层次关系
    local virtual chnl_intf chnl_vifs[3]; 
    local virtual arb_intf arb_vif; 
    local virtual mcdf_intf mcdf_vif;
    local virtual reg_intf reg_vif;
    local virtual fmt_intf fmt_vif;
    local string name;
    local int delay_req_to_grant;
	
	
	
//--------------------------------寄存器读写测试-------------------------------------------------------------------
//----------------------对所有控制寄存器的读写进行测试，所有状态寄存器的读写进行测试--------------------
    covergroup cg_mcdf_reg_write_read;  
      addr: coverpoint reg_vif.mon_ck.cmd_addr {  //这里在register interface下覆盖了6个特定的地址
        type_option.weight = 0;  //对总体生效，对单一不生效
		//会收集bin，但是不会对该covergroup有权重，不占任何比例
		//注意这里有一个应用的小技巧，这里的cmd_addr是8位的，所以除了接下来的6个bin外，还会产生很多default bin(256个-6个).
		//因为max_bin=64个，所以除了点明的6个bin外，还会将250个bin分配到58个bin上
		//这些默认的bin在cross中还会再次出现，也就是这些default的bin会应用在cross中
		//用type_option.weight=0修饰后，default的bin就不会被实现
		//也就是当weight=0时，也就是不会对covergroup造成任何贡献时，默认的cross则不会生成任何的bin
		//这样我们就可以从0添加我们关心的组合情况
        bins slv0_rw_addr = {`SLV0_RW_ADDR};  //对6个寄存器的地址都要覆盖到
        bins slv1_rw_addr = {`SLV1_RW_ADDR};
        bins slv2_rw_addr = {`SLV2_RW_ADDR};
        bins slv0_r_addr  = {`SLV0_R_ADDR };
        bins slv1_r_addr  = {`SLV1_R_ADDR };
        bins slv2_r_addr  = {`SLV2_R_ADDR };
      }
      cmd: coverpoint reg_vif.mon_ck.cmd {  //这里在register interface下覆盖了3种cmd指令
        type_option.weight = 0;  //会收集bin，但是不会对该covergroup有权重，不占任何比例
        bins write = {`WRITE};  //覆盖读写指令，也就是WRITE/READ/IDLE
        bins read  = {`READ};
        bins idle  = {`IDLE};
      }
      cmdXaddr: cross cmd, addr {   //更精细地覆盖指令
	  //------这6个bin和我们的上面的bins是一样的----------
	  //------为什么要再次声明？因为上面我们已经把bins置为0了---------
        bins slv0_rw_addr = binsof(addr.slv0_rw_addr);
        bins slv1_rw_addr = binsof(addr.slv1_rw_addr);
        bins slv2_rw_addr = binsof(addr.slv2_rw_addr);
        bins slv0_r_addr  = binsof(addr.slv0_r_addr );
        bins slv1_r_addr  = binsof(addr.slv1_r_addr );
        bins slv2_r_addr  = binsof(addr.slv2_r_addr );
      //-------这三个bin也和上面的bins是一样的--------
	  //-------为什么要再次声明？因为上面我们已经把bins置为0了---------
        bins write        = binsof(cmd.write);
        bins read         = binsof(cmd.read );
        bins idle         = binsof(cmd.idle );
	  //------
        bins write_slv0_rw_addr  = binsof(cmd.write) && binsof(addr.slv0_rw_addr);  //第0个读写寄存器，是否执行了写状态
        bins write_slv1_rw_addr  = binsof(cmd.write) && binsof(addr.slv1_rw_addr);  //第1个读写寄存器，是否执行了写状态
        bins write_slv2_rw_addr  = binsof(cmd.write) && binsof(addr.slv2_rw_addr);  //第2个读写寄存器，是否执行了写状态
        bins read_slv0_rw_addr   = binsof(cmd.read) && binsof(addr.slv0_rw_addr);   //第0个读写寄存器，是否执行了读状态
        bins read_slv1_rw_addr   = binsof(cmd.read) && binsof(addr.slv1_rw_addr);   //第1个读写寄存器，是否执行了读状态
        bins read_slv2_rw_addr   = binsof(cmd.read) && binsof(addr.slv2_rw_addr);   //第2个读写寄存器，是否执行了读状态
        bins read_slv0_r_addr    = binsof(cmd.read) && binsof(addr.slv0_r_addr);    //第0个读寄存器，是否执行了读状态
        bins read_slv1_r_addr    = binsof(cmd.read) && binsof(addr.slv1_r_addr);    //第1个读寄存器，是否执行了读状态
        bins read_slv2_r_addr    = binsof(cmd.read) && binsof(addr.slv2_r_addr);    //第2个读寄存器，是否执行了读状态
      }
    endgroup


//---------------------寄存器稳定性测试--------------------------------
//----------测试内容：对非法地址的读写，对控制寄存器的保留域进行读写，对状态寄存器进行写操作--------
    covergroup cg_mcdf_reg_illegal_access;
	
//-----------------------对部分非法的寄存器的进行甄别----------------
      addr: coverpoint reg_vif.mon_ck.cmd_addr {
        type_option.weight = 0;
        bins legal_rw = {`SLV0_RW_ADDR, `SLV1_RW_ADDR, `SLV2_RW_ADDR};  //读写寄存器
        bins legal_r = {`SLV0_R_ADDR, `SLV1_R_ADDR, `SLV2_R_ADDR};  //只读寄存器
        bins illegal = {[8'h20:$], 8'hC, 8'h1C};    //只是一些非法寄存器的子集
      }
//----------------------寄存器的的读写命令---------------------------------
      cmd: coverpoint reg_vif.mon_ck.cmd {
        type_option.weight = 0;
        bins write = {`WRITE};
        bins read  = {`READ};
      }
//----------------------查看register端的读出的数据--------------------------------
      wdata: coverpoint reg_vif.mon_ck.cmd_data_m2s {
        type_option.weight = 0;
        bins legal = {[0:'h3F]};   //0000_0000 - 0011_1111都是合法的
        bins illegal = {['h40:$]}; //0011_1111 - 1111_1111都是非法的 //这里只是名称为illegal，仿真不会报错，更不会停止下来
      } 
//---------------------查看register端写入的数据-----------------------------------	  	  
      rdata: coverpoint reg_vif.mon_ck.cmd_data_s2m {
        type_option.weight = 0;
        bins legal = {[0:'hFF]};  //0000_0000 - 1111_1111都是合法的
        illegal_bins illegal = default;  //其他的数值是非法的，会报错，仿真会停下来
      }
//----------------------交叉覆盖率---------------------------------------------	  
      cmdXaddrXdata: cross cmd, addr, wdata, rdata {
        bins addr_legal_rw = binsof(addr.legal_rw);
        bins addr_legal_r = binsof(addr.legal_r);
        bins addr_illegal = binsof(addr.illegal);
		
        bins cmd_write = binsof(cmd.write);
        bins cmd_read = binsof(cmd.read);
		
        bins wdata_legal = binsof(wdata.legal);
        bins wdata_illegal = binsof(wdata.illegal);
		
        bins rdata_legal = binsof(rdata.legal);    //这里不会引入illegal_bins
		
        bins write_illegal_addr = binsof(cmd.write) && binsof(addr.illegal);  //对于任何一个非法的地址有没有做过写操作
        bins read_illegal_addr  = binsof(cmd.read) && binsof(addr.illegal);   //对于任何一个非法的地址有没有做过读操作
       
    	bins write_illegal_rw_data = binsof(cmd.write) && binsof(addr.legal_rw) && binsof(wdata.illegal); //对读写寄存器进行了写操作，且写进了非法的数据
        bins write_illegal_r_data = binsof(cmd.write) && binsof(addr.legal_r) && binsof(wdata.illegal);   //对只读寄存器进行了写操作，且写进了非法的数据
        //其实没有必要做这一步，因为给只读寄存器做写操作本身就是非法的
		//bins write_illegal_r_data = binsof(cmd.write) && binsof(addr.legal_r); 这样比较合适
		}
    endgroup


//------------------------------数据通道开关测试--------------------------------------------
//-----------对每一个数据通道对应的控制寄存器en配置为0，在关闭状态下测试数据是否通过--------
    covergroup cg_channel_disable;
	
      ch0_en: coverpoint mcdf_vif.mon_ck.chnl_en[0] {      //通道0是否使能了enable为0
        type_option.weight = 0;
        wildcard bins en  = {1'b1};     //wildcard是通配符，这里没有XZ或？，所以和普通的bin一样
        wildcard bins dis = {1'b0};     //wildcard是通配符，这里没有XZ或？，所以和普通的bin一样
      }
	  
      ch1_en: coverpoint mcdf_vif.mon_ck.chnl_en[1] {      //通道1是否使能了
        type_option.weight = 0;
        wildcard bins en  = {1'b1};     
        wildcard bins dis = {1'b0};
      }
	  
      ch2_en: coverpoint mcdf_vif.mon_ck.chnl_en[2] {      //通道2是否使能了
        type_option.weight = 0;
        wildcard bins en  = {1'b1};
        wildcard bins dis = {1'b0};
      }
	  
      ch0_vld: coverpoint chnl_vifs[0].mon_ck.ch_valid {   //valid就是有没有做过写操作，valid为1
        type_option.weight = 0;
        bins hi = {1'b1};
        bins lo = {1'b0};
      }
	  
      ch1_vld: coverpoint chnl_vifs[1].mon_ck.ch_valid {   //valid就是有没有做过写操作，valid为1
        type_option.weight = 0;
        bins hi = {1'b1};
        bins lo = {1'b0};
      }
	  
      ch2_vld: coverpoint chnl_vifs[2].mon_ck.ch_valid {   //valid就是有没有做过写操作，valid为1
        type_option.weight = 0;
        bins hi = {1'b1};
        bins lo = {1'b0};
      }
	  
      chenXchvld: cross ch0_en, ch1_en, ch2_en, ch0_vld, ch1_vld, ch2_vld {
        bins ch0_en  = binsof(ch0_en.en);
        bins ch0_dis = binsof(ch0_en.dis);
        bins ch1_en  = binsof(ch1_en.en);
        bins ch1_dis = binsof(ch1_en.dis);
        bins ch2_en  = binsof(ch2_en.en);
        bins ch2_dis = binsof(ch2_en.dis);
        bins ch0_hi  = binsof(ch0_vld.hi);
        bins ch0_lo  = binsof(ch0_vld.lo);
        bins ch1_hi  = binsof(ch1_vld.hi);
        bins ch1_lo  = binsof(ch1_vld.lo);
        bins ch2_hi  = binsof(ch2_vld.hi);
        bins ch2_lo  = binsof(ch2_vld.lo);
        bins ch0_en_vld = binsof(ch0_en.en) && binsof(ch0_vld.hi);
        bins ch0_dis_vld = binsof(ch0_en.dis) && binsof(ch0_vld.hi);
        bins ch1_en_vld = binsof(ch1_en.en) && binsof(ch1_vld.hi);
        bins ch1_dis_vld = binsof(ch1_en.dis) && binsof(ch1_vld.hi);
        bins ch2_en_vld = binsof(ch2_en.en) && binsof(ch2_vld.hi);
        bins ch2_dis_vld = binsof(ch2_en.dis) && binsof(ch2_vld.hi);
      }
    endgroup


//-------------------------------------------优先级测试-----------------------------------------------
//------------将不同数据通道配置为相同或者不同的优先级，在数据通道使能的情况下进行测试----------------
    covergroup cg_arbiter_priority;
      ch0_prio: coverpoint arb_vif.mon_ck.slv_prios[0] { //通道0的优先级
        bins ch_prio0 = {0}; 
        bins ch_prio1 = {1}; 
        bins ch_prio2 = {2}; 
        bins ch_prio3 = {3}; 
      }
      ch1_prio: coverpoint arb_vif.mon_ck.slv_prios[1] {  //通道1的优先级
        bins ch_prio0 = {0}; 
        bins ch_prio1 = {1}; 
        bins ch_prio2 = {2}; 
        bins ch_prio3 = {3}; 
      }
      ch2_prio: coverpoint arb_vif.mon_ck.slv_prios[2] {  //通道2的优先级
        bins ch_prio0 = {0}; 
        bins ch_prio1 = {1}; 
        bins ch_prio2 = {2}; 
        bins ch_prio3 = {3}; 
      }
    endgroup


//---------------------------------发包长度测试------------------------
//-----------将不同数据通道随机配置为各自的长度，在数据通道使能的情况下进行测试------------------
    covergroup cg_formatter_length;
      id: coverpoint fmt_vif.mon_ck.fmt_chid {       //fmt_chid是两位的变量
        bins ch0 = {0};
        bins ch1 = {1};
        bins ch2 = {2};
        illegal_bins illegal = default;   
      }
      length: coverpoint fmt_vif.mon_ck.fmt_length {    //fmt_length是六位的
        bins len4  = {4};
        bins len8  = {8};
        bins len16 = {16};
        bins len32 = {32};
        illegal_bins illegal = default;
      }
    endgroup

//---------------------------------下行从端低带宽测试------------------------
//------------------将MCDF下行数据接收端设置为小存储量，低带宽的类型，由此使得在由formatter发送出数据之后，
//------------------下行从端有更多的机会延迟grant信号的置位，用来模拟真实的场景--------------
    covergroup cg_formatter_grant();
      delay_req_to_grant: coverpoint this.delay_req_to_grant {
        bins delay1 = {1};
        bins delay2 = {2};
        bins delay3_or_more = {[3:10]};
        illegal_bins illegal = {0};
      }
    endgroup


    function new(string name="mcdf_coverage");
      this.name = name;
      this.cg_mcdf_reg_write_read = new();
      this.cg_mcdf_reg_illegal_access = new();
      this.cg_channel_disable = new();
      this.cg_arbiter_priority = new();
      this.cg_formatter_length = new();
      this.cg_formatter_grant = new();
    endfunction

    task run();
      fork 
        this.do_reg_sample();
        this.do_channel_sample();
        this.do_arbiter_sample();
        this.do_formater_sample();
      join
    endtask

    task do_reg_sample();   //寄存器读写测试和寄存器稳定性测试
      forever begin
        @(posedge reg_vif.clk iff reg_vif.rstn);
        this.cg_mcdf_reg_write_read.sample();       //寄存器读写测试
        this.cg_mcdf_reg_illegal_access.sample();   //寄存器稳定性测试
      end
    endtask

    task do_channel_sample();  //数据通道开关测试
      forever begin
        @(posedge mcdf_vif.clk iff mcdf_vif.rstn);
        if(chnl_vifs[0].mon_ck.ch_valid===1
          || chnl_vifs[1].mon_ck.ch_valid===1
          || chnl_vifs[2].mon_ck.ch_valid===1)
          this.cg_channel_disable.sample();
      end
    endtask

    task do_arbiter_sample();  //优先级测试
      forever begin
        @(posedge arb_vif.clk iff arb_vif.rstn);
        if(arb_vif.slv_reqs[0]!==0 || arb_vif.slv_reqs[1]!==0 || arb_vif.slv_reqs[2]!==0)
          this.cg_arbiter_priority.sample();
      end
    endtask

    task do_formater_sample();  //发包长度测试
      fork
        forever begin
          @(posedge fmt_vif.clk iff fmt_vif.rstn);
          if(fmt_vif.mon_ck.fmt_req === 1)
            this.cg_formatter_length.sample();
        end
		
        forever begin
          @(posedge fmt_vif.mon_ck.fmt_req);
          this.delay_req_to_grant = 0;
          forever begin
            if(fmt_vif.fmt_grant === 1) begin
              this.cg_formatter_grant.sample();
              break;
            end
            else begin
              @(posedge fmt_vif.clk);
              this.delay_req_to_grant++;
            end
          end
        end
      join
    endtask

    function void do_report();
      string s;
      s = "\n---------------------------------------------------------------\n";
      s = {s, "COVERAGE SUMMARY \n"}; 
      s = {s, $sformatf("total coverage: %.1f \n", $get_coverage())}; 
      s = {s, $sformatf("  cg_mcdf_reg_write_read coverage: %.1f \n", this.cg_mcdf_reg_write_read.get_coverage())}; 
      s = {s, $sformatf("  cg_mcdf_reg_illegal_access coverage: %.1f \n", this.cg_mcdf_reg_illegal_access.get_coverage())}; 
      s = {s, $sformatf("  cg_channel_disable_test coverage: %.1f \n", this.cg_channel_disable.get_coverage())}; 
      s = {s, $sformatf("  cg_arbiter_priority_test coverage: %.1f \n", this.cg_arbiter_priority.get_coverage())}; 
      s = {s, $sformatf("  cg_formatter_length_test coverage: %.1f \n", this.cg_formatter_length.get_coverage())}; 
      s = {s, $sformatf("  cg_formatter_grant_test coverage: %.1f \n", this.cg_formatter_grant.get_coverage())}; 
      s = {s, "---------------------------------------------------------------\n"};
      rpt_pkg::rpt_msg($sformatf("[%s]",this.name), s, rpt_pkg::INFO, rpt_pkg::TOP);
    endfunction

    virtual function void set_interface(virtual chnl_intf ch_vifs[3],virtual reg_intf reg_vif,virtual arb_intf arb_vif,virtual fmt_intf fmt_vif,virtual mcdf_intf mcdf_vif);
      this.chnl_vifs = ch_vifs;
      this.arb_vif = arb_vif;
      this.reg_vif = reg_vif;
      this.fmt_vif = fmt_vif;
      this.mcdf_vif = mcdf_vif;
      if(chnl_vifs[0] == null || chnl_vifs[1] == null || chnl_vifs[2] == null)  $error("chnl interface handle is NULL, please check if target interface has been intantiated");
      if(arb_vif == null)  $error("arb interface handle is NULL, please check if target interface has been intantiated");
      if(reg_vif == null)  $error("reg interface handle is NULL, please check if target interface has been intantiated");
      if(fmt_vif == null)  $error("fmt interface handle is NULL, please check if target interface has been intantiated");
      if(mcdf_vif == null) $error("mcdf interface handle is NULL, please check if target interface has been intantiated");
    endfunction
  endclass

  class mcdf_env;
    chnl_agent chnl_agts[3];
    reg_agent reg_agt;
    fmt_agent fmt_agt;
    mcdf_checker chker;
    mcdf_coverage cvrg;
    protected string name;

    function new(string name = "mcdf_env");
      this.name = name;
      this.chker = new();
      foreach(chnl_agts[i]) begin
        this.chnl_agts[i] = new($sformatf("chnl_agts[%0d]",i));
        this.chnl_agts[i].monitor.mon_mb = this.chker.chnl_mbs[i];
      end
      this.reg_agt = new("reg_agt");
      this.reg_agt.monitor.mon_mb = this.chker.reg_mb;
      this.fmt_agt = new("fmt_agt");
      this.fmt_agt.monitor.mon_mb = this.chker.fmt_mb;
      this.cvrg = new();
      $display("%s instantiated and connected objects", this.name);
    endfunction

    virtual task run();
      $display($sformatf("*****************%s started********************", this.name));
      this.do_config();
      fork
        this.chnl_agts[0].run();
        this.chnl_agts[1].run();
        this.chnl_agts[2].run();
        this.reg_agt.run();
        this.fmt_agt.run();
        this.chker.run();
        this.cvrg.run();
      join
    endtask

    virtual function void do_config();
    endfunction

    virtual function void do_report();
      this.chker.do_report();
      this.cvrg.do_report();
    endfunction

  endclass

  class mcdf_base_test;
    chnl_generator chnl_gens[3];
    reg_generator reg_gen;
    fmt_generator fmt_gen;
    mcdf_env env;
    protected string name;
    local int timeout = 10; // 10 * ms

    function new(string name = "mcdf_base_test");
      this.name = name;
      this.env = new("env");

      foreach(this.chnl_gens[i]) begin
        this.chnl_gens[i] = new();
        this.env.chnl_agts[i].driver.req_mb = this.chnl_gens[i].req_mb;
        this.env.chnl_agts[i].driver.rsp_mb = this.chnl_gens[i].rsp_mb;
      end

      this.reg_gen = new();
      this.env.reg_agt.driver.req_mb = this.reg_gen.req_mb;
      this.env.reg_agt.driver.rsp_mb = this.reg_gen.rsp_mb;

      this.fmt_gen = new();
      this.env.fmt_agt.driver.req_mb = this.fmt_gen.req_mb;
      this.env.fmt_agt.driver.rsp_mb = this.fmt_gen.rsp_mb;

      rpt_pkg::logname = {this.name, "_check.log"};
      rpt_pkg::clean_log();
      $display("%s instantiated and connected objects", this.name);
    endfunction

    virtual task run();
      fork
        env.run();
      join_none
      rpt_pkg::rpt_msg("[TEST]",
        $sformatf("=====================%s AT TIME %0t STARTED=====================", this.name, $time),
        rpt_pkg::INFO,
        rpt_pkg::HIGH);
      this.do_reg();
      this.do_formatter();
      fork
        this.do_data();
        this.do_watchdog();
      join_any
      rpt_pkg::rpt_msg("[TEST]",
        $sformatf("=====================%s AT TIME %0t FINISHED=====================", this.name, $time),
        rpt_pkg::INFO,
        rpt_pkg::HIGH);
      this.do_report();
      $finish();
    endtask

    // do register configuration
    virtual task do_reg();
    endtask

    // do external formatter down stream slave configuration
    virtual task do_formatter();
    endtask

    // do data transition from 3 channel slaves
    virtual task do_data();
    endtask

    // timeout watchdog to avoid simulation pending
    virtual task do_watchdog();
      rpt_pkg::rpt_msg("[TEST]",
        $sformatf("=====================%s AT TIME %0t WATCHDOG GUARDING=====================", this.name, $time),
        rpt_pkg::INFO,
        rpt_pkg::HIGH);
      #(this.timeout * 1ms);
      rpt_pkg::rpt_msg("[TEST]",
        $sformatf("=====================%s AT TIME %0t WATCHDOG BARKING=====================", this.name, $time),
        rpt_pkg::INFO,
        rpt_pkg::HIGH);
    endtask

    // do simulation summary
    virtual function void do_report();
      this.env.do_report();
      rpt_pkg::do_report();
    endfunction

    virtual function void set_interface(virtual chnl_intf ch0_vif 
                                        ,virtual chnl_intf ch1_vif 
                                        ,virtual chnl_intf ch2_vif 
                                        ,virtual reg_intf reg_vif
                                        ,virtual arb_intf arb_vif
                                        ,virtual fmt_intf fmt_vif
                                        ,virtual mcdf_intf mcdf_vif
                                      );
      this.env.chnl_agts[0].set_interface(ch0_vif);
      this.env.chnl_agts[1].set_interface(ch1_vif);
      this.env.chnl_agts[2].set_interface(ch2_vif);
      this.env.reg_agt.set_interface(reg_vif);
      this.env.fmt_agt.set_interface(fmt_vif);
      this.env.chker.set_interface(mcdf_vif, '{ch0_vif, ch1_vif, ch2_vif}, arb_vif);
      this.env.cvrg.set_interface('{ch0_vif, ch1_vif, ch2_vif}, reg_vif, arb_vif, fmt_vif, mcdf_vif);
    endfunction

    virtual function bit diff_value(int val1, int val2, string id = "value_compare");
      if(val1 != val2) begin
        rpt_pkg::rpt_msg("[CMPERR]", 
          $sformatf("ERROR! %s val1 %8x != val2 %8x", id, val1, val2), 
          rpt_pkg::ERROR, 
          rpt_pkg::TOP);
        return 0;
      end
      else begin
        rpt_pkg::rpt_msg("[CMPSUC]", 
          $sformatf("SUCCESS! %s val1 %8x == val2 %8x", id, val1, val2),
          rpt_pkg::INFO,
          rpt_pkg::HIGH);
        return 1;
      end
    endfunction

    virtual task idle_reg();
      void'(reg_gen.randomize() with {cmd == `IDLE; addr == 0; data == 0;});
      reg_gen.start();
    endtask

    virtual task write_reg(bit[7:0] addr, bit[31:0] data);
      void'(reg_gen.randomize() with {cmd == `WRITE; addr == local::addr; data == local::data;});
      reg_gen.start();
    endtask

    virtual task read_reg(bit[7:0] addr, output bit[31:0] data);
      void'(reg_gen.randomize() with {cmd == `READ; addr == local::addr;});
      reg_gen.start();
      data = reg_gen.data;
    endtask
  endclass

  class mcdf_data_consistence_basic_test extends mcdf_base_test;
    function new(string name = "mcdf_data_consistence_basic_test");
      super.new(name);
    endfunction

    task do_reg();
      bit[31:0] wr_val, rd_val;
      // slv0 with len=8,  prio=0, en=1
      wr_val = (1<<3)+(0<<1)+1;
      this.write_reg(`SLV0_RW_ADDR, wr_val);
      this.read_reg(`SLV0_RW_ADDR, rd_val);
      void'(this.diff_value(wr_val, rd_val, "SLV0_WR_REG"));

      // slv1 with len=16, prio=1, en=1
      wr_val = (2<<3)+(1<<1)+1;
      this.write_reg(`SLV1_RW_ADDR, wr_val);
      this.read_reg(`SLV1_RW_ADDR, rd_val);
      void'(this.diff_value(wr_val, rd_val, "SLV1_WR_REG"));

      // slv2 with len=32, prio=2, en=1
      wr_val = (3<<3)+(2<<1)+1;
      this.write_reg(`SLV2_RW_ADDR, wr_val);
      this.read_reg(`SLV2_RW_ADDR, rd_val);
      void'(this.diff_value(wr_val, rd_val, "SLV2_WR_REG"));

      // send IDLE command
      this.idle_reg();
    endtask

    task do_formatter();
      void'(fmt_gen.randomize() with {fifo == LONG_FIFO; bandwidth == HIGH_WIDTH;});
      fmt_gen.start();
    endtask

    task do_data();
      void'(chnl_gens[0].randomize() with {ntrans==100; ch_id==0; data_nidles==0; pkt_nidles==1; data_size==8; });
      void'(chnl_gens[1].randomize() with {ntrans==100; ch_id==1; data_nidles==1; pkt_nidles==4; data_size==16;});
      void'(chnl_gens[2].randomize() with {ntrans==100; ch_id==2; data_nidles==2; pkt_nidles==8; data_size==32;});
      fork
        chnl_gens[0].start();
        chnl_gens[1].start();
        chnl_gens[2].start();
      join
      #10us; // wait until all data haven been transfered through MCDF
    endtask
  endclass

  class mcdf_full_random_test extends mcdf_base_test;
    function new(string name = "mcdf_full_random_test");
      super.new(name);
    endfunction

    task do_reg();
      bit[31:0] wr_val, rd_val;
      // slv0 with len={4,8,16,32},  prio={[0:3]}, en={[0:1]}
      wr_val = ($urandom_range(0,3)<<3)+($urandom_range(0,3)<<1)+$urandom_range(0,1);
      this.write_reg(`SLV0_RW_ADDR, wr_val);
      this.read_reg(`SLV0_RW_ADDR, rd_val);
      void'(this.diff_value(wr_val, rd_val, "SLV0_WR_REG"));

      // slv0 with len={4,8,16,32},  prio={[0:3]}, en={[0:1]}
      wr_val = ($urandom_range(0,3)<<3)+($urandom_range(0,3)<<1)+$urandom_range(0,1);
      this.write_reg(`SLV1_RW_ADDR, wr_val);
      this.read_reg(`SLV1_RW_ADDR, rd_val);
      void'(this.diff_value(wr_val, rd_val, "SLV1_WR_REG"));

      // slv0 with len={4,8,16,32},  prio={[0:3]}, en={[0:1]}
      wr_val = ($urandom_range(0,3)<<3)+($urandom_range(0,3)<<1)+$urandom_range(0,1);
      this.write_reg(`SLV2_RW_ADDR, wr_val);
      this.read_reg(`SLV2_RW_ADDR, rd_val);
      void'(this.diff_value(wr_val, rd_val, "SLV2_WR_REG"));

      // send IDLE command
      this.idle_reg();
    endtask

    task do_formatter();
      void'(fmt_gen.randomize() with {fifo inside {SHORT_FIFO, ULTRA_FIFO}; bandwidth inside {LOW_WIDTH, ULTRA_WIDTH};});
      fmt_gen.start();
    endtask

    task do_data();
      void'(chnl_gens[0].randomize() with {ntrans inside {[400:600]}; ch_id==0; data_nidles inside {[0:3]}; pkt_nidles inside {1,2,4,8}; data_size inside {8,16,32};});
      void'(chnl_gens[1].randomize() with {ntrans inside {[400:600]}; ch_id==1; data_nidles inside {[0:3]}; pkt_nidles inside {1,2,4,8}; data_size inside {8,16,32};});
      void'(chnl_gens[2].randomize() with {ntrans inside {[400:600]}; ch_id==2; data_nidles inside {[0:3]}; pkt_nidles inside {1,2,4,8}; data_size inside {8,16,32};});
      fork
        chnl_gens[0].start();
        chnl_gens[1].start();
        chnl_gens[2].start();
      join
      #10us; // wait until all data haven been transfered through MCDF
    endtask
  endclass

endpackage
