

package rpt_pkg;  //消息的管理，消息包，管理消息会更加容易
  typedef enum {INFO, WARNING, ERROR, FATAL} report_t; //报告的类型
  typedef enum {LOW, MEDIUM, HIGH, TOP} severity_t;  //严重等级
  typedef enum {LOG, STOP, EXIT} action_t;   //对信息的处理方式

  static severity_t svrt = LOW;              //默认是low，也就是大家都没有那么重要，svrt可以在类外进行配置，即将过滤级别配置阈值
  static string logname = "report.log";      //打印到report.log里
  //----------消息汇总-------------
  static int info_count = 0;        //info类型的消息汇总
  static int warning_count = 0;     //warning类型的消息汇总
  static int error_count = 0;       //error类型的消息汇总
  static int fatal_count = 0;       //fatal类型的消息汇总
  
             //从checker过来的，打印的消息的内容，默认是一个INFO的类型，消息级别比较低的类型，默认写到了log文件里面
  function void rpt_msg(string src, string i, report_t r=INFO, severity_t s=LOW, action_t a=LOG); //mcdf_pkg用了这个函数
    integer logf;  //这里文件句柄是整数就默认为32位，最低位（第0位）默认被设置1，默认开放标准输出通道，也就是transcript窗口
    string msg;
    case(r)  //计数
      INFO: info_count++;
      WARNING: warning_count++;
      ERROR: error_count++;
      FATAL: fatal_count++;
    endcase
    if(s >= svrt) begin  //判断阈值，大于等于过滤的级别（枚举类型实际是依次递减的），就可以把消息打印出来了,现在svrt为“LOW”，也就是任何信息都能打出来
      msg = $sformatf("@%0t [%s] %s : %s", $time, r, src, i);  //这些参数都是函数传递的参数
	  //在mcdf_pkg中，$time为时间参数，r为报告的类型INFO, src为“[TEST]”, i为"$sformatf("=========%s AT TIME %0t STARTED==========")"
	  //msg中包含了上述这些信息
      logf = $fopen(logname, "a+");  //在当前目录打开logname对应的文件，并返回文件句柄
	             //"a+" 以附加方式打开可读写的文件。若文件不存在，则会建立该文件，如果文件存在，写入的数据会被加到文件尾
      $display(msg);  //这行不是写文件上的，而是打印到transcript上的
      $fwrite(logf, $sformatf("%s\n", msg));  //将内存区域中的数据写入到本地文本并空行\n
      $fclose(logf);       //关闭句柄
	  //------------如果传入的操作类型不是LOG而是STOP和EXIT-------------------
      if(a == STOP) begin  //停止仿真  //a为对信息处理的方式，LOG为存储，STOP为停止，EXIT为退出
        $stop();
      end
      else if(a == EXIT) begin  //退出仿真
        $finish();
      end
    end
  endfunction

  function void do_report();
    string s;
    s = "\n---------------------------------------------------------------\n";
    s = {s, "REPORT SUMMARY\n"}; 
    s = {s, $sformatf("info count: %0d \n", info_count)}; 
    s = {s, $sformatf("warning count: %0d \n", warning_count)}; 
    s = {s, $sformatf("error count: %0d \n", error_count)}; 
    s = {s, $sformatf("fatal count: %0d \n", fatal_count)}; 
    s = {s, "---------------------------------------------------------------\n"};
    rpt_msg("[REPORT]", s, rpt_pkg::INFO, rpt_pkg::TOP);
  endfunction

  function void clean_log(); //将文件句柄置零
    integer logf;
    logf = $fopen(logname, "w");  //这里返回了文件句柄 //log_name为字符串"report.log"
    $fclose(logf);  //将句柄置零
  endfunction
endpackage
