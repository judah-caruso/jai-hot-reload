#scope_export;

HOT_RELOAD    :: true;
RELEASE_BUILD :: false;

G: *struct {
   allocator: Allocator;
   iterations: int;
};

#program_export MaxMemory : u64 = 4 * Gigabyte;
#program_export StateSize : u64 = size_of(type_of(G.*));

#program_export Init :: (state: *void, allocator: Allocator, reset: bool) {
   Remap_Context();
   context.allocator = .{ proc = CrashAllocatorProc };

   G = xx state;
   G.allocator = allocator;
   if !reset return;
}

#program_export Startup :: () {
   print("in startup\n");
}

#program_export Teardown :: () {
   print("in teardown\n");
}

#program_export Frame :: () -> Status {
   G.iterations += 1; // change this line and rebuild the program library

   print("in frame, count: %\n", G.iterations);
   sleep_milliseconds(1000);
   return .none;
}

#scope_file;

#import,file "util.jai";

#import "Remap_Context"(!RELEASE_BUILD);
#import "Basic";
