`ifndef __LOGS__
`define __LOGS__

`define LOG(module_name, va_msg)   $display("%-20s LOG   Time %0t: %s", $sformatf("[%s]", module_name), $time, $sformatf va_msg);
`define INFO(module_name, va_msg)  $display("%-29s \033[94mINFO \033[0m Time %0t: %s", $sformatf("\033[94m[%s]\033[0m", module_name), $time, $sformatf va_msg);
`define WARN(module_name, va_msg)  $display("%-29s \033[93mWARN \033[0m Time %0t: %s", $sformatf("\033[93m[%s]\033[0m", module_name), $time, $sformatf va_msg);
`ifndef BREAK_ON_ERROR
`define ERROR(module_name, va_msg) $display("%-29s \033[91mERROR\033[0m Time %0t: %s", $sformatf("\033[91m[%s]\033[0m", module_name), $time, $sformatf va_msg);
`else
`define ERROR(module_name, va_msg) $display("%-29s \033[91mERROR\033[0m Time %0t: %s", $sformatf("\033[91m[%s]\033[0m", module_name), $time, $sformatf va_msg); $finish;
`endif

`define ASSERT(TEST, MESSAGE) if (!(TEST)) begin $display({"\033[91mASSERT\033[0m: ", MESSAGE}); $fatal; end

`endif // __LOGS__
