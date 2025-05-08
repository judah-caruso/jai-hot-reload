main :: () {
   set_working_directory(path_strip_filename(get_path_of_running_executable()));

   system_allocator := context.allocator;

   #if HOT_RELOAD {
      lib_api, ok := LoadLibrary(0);
      assert(ok, "host: failed to load library");

      lib_versions: [..]Library;
      lib_versions.allocator = system_allocator;

      L := lib_api;

      next_lib_version := 1;

      defer {
         for * lib_versions {
            UnloadLibrary(it);
         }

         UnloadLibrary(*L);
         free(lib_versions.data,, allocator = lib_versions.allocator);
      }
   }
   else {
      L :: program;
   }

   print("host: allocating % bytes memory (% for state)\n", L.MaxMemory, L.StateSize);

   lib_memory := alloc(xx L.MaxMemory,, allocator = system_allocator);
   assert(lib_memory != null, "host: failed to allocate memory!");
   defer free(lib_memory,, allocator = system_allocator);

   lib_arena: Arena;
   InitArena(*lib_arena, lib_memory, L.MaxMemory);
   lib_allocator := Allocator.{ proc = ArenaAllocatorProc, data = *lib_arena };

   lib_state := alloc(xx L.StateSize,, allocator = lib_allocator);

   L.Init(lib_state, lib_allocator, true);
   L.Startup();

   while true {
      defer reset_temporary_storage();

      status := L.Frame();
      if status == .quit break;

      #if HOT_RELOAD {
         reload := status == .hard_reload || status == .soft_reload;
         if !reload {
            default_path := tprint(DefaultLibPath, LibExtension);
            mod := file_modtime_and_size(default_path);
            if mod != L.mod_time {
               reload = true;
            }
         }

         if !reload {
            continue;
         }

         new_api, ok := LoadLibrary(next_lib_version);
         if !ok {
            print("host: failed to load version % of the library\n", next_lib_version);
            continue;
         }

         old_ssize := L.StateSize;
         old_msize := L.MaxMemory;
         new_ssize := new_api.StateSize;
         new_msize := new_api.MaxMemory;

         if old_ssize != new_ssize || old_msize != new_msize {
            status = .hard_reload;
         }

         if status == .hard_reload {
            print("host: performing hard reload...\n");
            if old_msize <= new_msize {
               lib_arena.offset = 0;
            }
            else {
               free(lib_memory,, allocator = system_allocator);

               lib_memory = alloc(xx new_msize,, allocator = system_allocator);
               assert(lib_memory != null, "host: failed to allocate new memory!");

               InitArena(*lib_arena, lib_memory, new_msize);
               lib_state = alloc(xx new_ssize,, allocator = lib_allocator);
            }
         }
         else {
            print("host: performing soft reload...\n");
            array_add(*lib_versions, L);
         }

         L = new_api;
         next_lib_version += 1;

         L.Init(lib_state, lib_allocator, status == .hard_reload);
      }
   }

   L.Teardown();
}

// Ensure laptops use the higher performance GPU on windows.
#if OS == .WINDOWS {
   /*
   https://docs.nvidia.com/gameworks/content/technologies/desktop/optimus.htm

   Starting with the Release 302 drivers, application developers can direct the Optimus driver at runtime to use the High Performance Graphics to render any application —- even those applications for which there is no existing application profile. They can do this by exporting a global variable named NvOptimusEnablement. The Optimus driver looks for the existence and value of the export. Only the LSB of the DWORD matters at this time. A value of 0x00000001 indicates that rendering should be performed using High Performance Graphics. A value of 0x00000000 indicates that this method should be ignored.
   */
   #program_export NvOptimusEnablement: u32 = 0x00000001;

   /*
   https://gpuopen.com/learn/amdpowerxpressrequesthighperformance/

   Many gaming and workstation laptops are available with both (1) integrated power saving and (2) discrete high performance graphics devices. Unfortunately, 3D intensive application performance may suffer greatly if the best graphics device is not selected. For example, a game may run at 30 Frames Per Second (FPS) on the integrated GPU rather than the 60 FPS the discrete GPU would enable. As a developer you can easily fix this problem by adding only one line to your executable’s source code:
   */
   #program_export AmdPowerXpressRequestHighPerformance: u32 = 0x00000001;
}

#if HOT_RELOAD {
   Library :: struct {
      MaxMemory: type_of(program.MaxMemory);
      StateSize: type_of(program.StateSize);
      Init:      type_of(program.Init);
      Startup:   type_of(program.Startup);
      Teardown:  type_of(program.Teardown);
      Frame:     type_of(program.Frame);

      version:  int;
      handle:   *void;
      mod_time: Apollo_Time;
   }

   DefaultLibPath     :: "lib.%";
   TempLibPathPattern :: "__temp_lib_%.%";

   #if OS == {
      case .WINDOWS;
         LibExtension :: "dll";
      case .MACOS;
         LibExtension :: "dylib";
      case .LINUX;
         LibExtension :: "so";
   }

   LoadLibrary :: (version: int) -> Library, bool {
      default_path := tprint(DefaultLibPath, LibExtension);
      mod, size, exists := file_modtime_and_size(default_path);
      if !exists {
         print("host: % did not exist\n", default_path);
         return .{}, false;
      }

      new_path := tprint(TempLibPathPattern, version, LibExtension);
      if !copy_file(default_path, new_path,, allocator = temp) {
         print("host: could not copy % to %\n", default_path, new_path);
         return .{}, false;
      }

      handle := OsLoadLibrary(new_path);
      if !handle {
         print("host: failed to load library at %\n", new_path);
         return .{}, false;
      }

      return .{
         MaxMemory = OsFindLibrarySymbol(handle, "MaxMemory").(*type_of(program.MaxMemory)).*,
         StateSize = OsFindLibrarySymbol(handle, "StateSize").(*type_of(program.StateSize)).*,
         Init      = OsFindLibrarySymbol(handle, "Init"),
         Startup   = OsFindLibrarySymbol(handle, "Startup"),
         Teardown  = OsFindLibrarySymbol(handle, "Teardown"),
         Frame     = OsFindLibrarySymbol(handle, "Frame"),

         version  = version,
         handle   = handle,
         mod_time = mod,
      }, true;
   }

   UnloadLibrary :: (library: *Library) {
      path := tprint(TempLibPathPattern, library.version, LibExtension);
      if library.handle && !OsUnloadLibrary(library.handle) {
         print("host: failed to unload temporary library: %\n", path);
      }

      if !file_delete(path) {
         print("host: failed to delete temporary library: %\n", path);
      }
   }

   #if OS == .WINDOWS {
      #import "Windows";
      // @note(judah): Haven't tested this on my windows machine,
      // but I remember things working like this.

      OsLoadLibrary :: (path: string) -> *void {
         handle := LoadLibraryA(temp_c_string(path));
         return handle;
      }

      OsUnloadLibrary :: (handle: *void) -> bool {
         return FreeLibrary(handle);
      }

      OsFindLibrarySymbol :: (handle: *void, symbol: string) -> *void {
         return GetProcAddress(handle, temp_c_string(symbol));
      }
   }
   else #if OS == .MACOS || OS == .LINUX {
      #import "POSIX";

      OsLoadLibrary :: (path: string) -> *void {
         handle := dlopen(temp_c_string(path), RTLD_NOW);
         return handle;
      }

      OsUnloadLibrary :: (handle: *void) -> bool {
         return dlclose(handle) == 0;
      }

      OsFindLibrarySymbol :: (handle: *void, symbol: string) -> *void {
         return dlsym(handle, temp_c_string(symbol));
      }
   }
   else {
      #assert(false, "only windows, mac, and linux are supported for now");
   }
}

#import,file "util.jai";

program :: #import,file "program.jai";
HOT_RELOAD    :: program.HOT_RELOAD;
RELEASE_BUILD :: program.RELEASE_BUILD;

#import "Basic";
#import "String";
#import "File";
#import "System";
#import "File_Utilities";
