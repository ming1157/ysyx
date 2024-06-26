
package uvm_message_pkg;
  import uvm_pkg::*;
  `include "uvm_macros.svh"
  
  class config_obj extends uvm_object;
    `uvm_object_utils(config_obj)
    function new(string name = "config_obj");
      super.new(name);
      `uvm_info("CREATE", $sformatf("config_obj type [%s] created", name), UVM_LOW)
    endfunction
  endclass
  
  class comp2 extends uvm_component;
    `uvm_component_utils(comp2)
    function new(string name = "comp2", uvm_component parent = null);
      super.new(name, parent);
      `uvm_info("CREATE", $sformatf("unit type [%s] created", name), UVM_LOW)
    endfunction
    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      `uvm_info("BUILD", "comp2 build phase entered", UVM_LOW)
      `uvm_info("BUILD", "comp2 build phase exited", UVM_LOW)
    endfunction
  endclass

  class comp1 extends uvm_component;
    `uvm_component_utils(comp1)
    function new(string name = "comp1", uvm_component parent = null);
      super.new(name, parent);
      `uvm_info("CREATE", $sformatf("unit type [%s] created", name), UVM_LOW)
    endfunction
    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      `uvm_info("BUILD", "comp1 build phase entered", UVM_LOW)
      `uvm_info("BUILD", "comp1 build phase exited", UVM_LOW)
    endfunction
  endclass

  class uvm_message_test extends uvm_test;
    config_obj cfg;
    `uvm_component_utils(uvm_message_test)
    function new(string name = "uvm_message_test", uvm_component parent = null);
      super.new(name, parent);
    endfunction
    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      
      //TODO-5.1
      //Use set_report_verbosity_level_hier() to disable all of UVM messages
      //under the uvm_message_test
      
      //TODO-5.2
      //Use set_report_id_verbosity_level_hier() to disable all of 
      //'BUILD', "CREATE", “RUN” ID message under the uvm_message_test
      
      //TODO-5.3
      //Why the UVM message from config_obj type and uvm_message module
      //could not be disabled? Please use the message filter methods
      //to disable them
      
      `uvm_info("BUILD", "uvm_message_test build phase entered", UVM_LOW)
      cfg = config_obj::type_id::create("cfg");
      `uvm_info("BUILD", "uvm_message_test build phase exited", UVM_LOW)
    endfunction
    task run_phase(uvm_phase phase);
      super.run_phase(phase);
      `uvm_info("RUN", "uvm_message_test run phase entered", UVM_LOW)
      phase.raise_objection(this);
      phase.drop_objection(this);
      `uvm_info("RUN", "uvm_message_test run phase exited", UVM_LOW)
    endtask
  endclass
endpackage

module uvm_message;

  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import uvm_message_pkg::*;
  
  initial begin
    //TODO-5.3
    //Why the UVM message from config_obj type and uvm_message module
    //could not be disabled? Please use the message filter methods
    //to disable them
    
    `uvm_info("TOPTB", "RUN TEST entered", UVM_LOW)
    run_test(""); // empty test name
    `uvm_info("TOPTB", "RUN TEST exited", UVM_LOW)
  end

endmodule