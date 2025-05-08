// Control the build without using the command line
BUILD_HOST :: false;

#run {
   set_build_options_dc(.{ do_output = false });

   ws := compiler_create_workspace();

   options := get_build_options(ws);
   options.output_path = "runtime";

   args := options.compile_time_command_line;

   build_file := "source/program.jai";
   if args.count > 0 && args[0] == "host" || BUILD_HOST {
      #if OS == {
         case .WINDOWS; EXT :: "exe";
         case .MACOS;   EXT :: "bin";
         case .LINUX;   EXT :: "bin";
         case .WASM;    EXT :: "wasm";
      }

      print("** Building host executable **\n");
      build_file = "source/host.jai";
      options.output_type = .EXECUTABLE;
      options.output_executable_name = tprint("host.%", EXT);
   }
   else {
      print("** Building library **\n");
      options.output_type = .DYNAMIC_LIBRARY;
      options.output_executable_name = "lib";
   }

   set_build_options(options, ws);

   compiler_begin_intercept(ws);
   add_build_file(build_file, ws);
   compiler_end_intercept(ws);
}

#import "Basic";
#import "Compiler";
