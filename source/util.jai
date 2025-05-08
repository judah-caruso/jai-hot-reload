Kilobyte :: 1024;
Megabyte :: 1024 * Kilobyte;
Gigabyte :: 1024 * Megabyte;

Status :: enum {
   none;
   quit;
   soft_reload;
   hard_reload;
}

Arena :: struct {
   memory:      *void;
   memory_size: u64;
   offset:      u64;
}

InitArena :: (a: *Arena, memory: *void, size: u64) {
   a.memory      = memory;
   a.memory_size = size;
   a.offset      = 0;
}

ArenaAllocatorProc :: (mode: Allocator_Mode, size: s64, old_size: s64, old_memory: *void, allocator_data: *void) -> *void {
   arena := allocator_data.(*Arena);
   if mode == {
      case .ALLOCATE;
         return ArenaAlloc(arena, size);

      case .RESIZE;
         if old_memory == null {
            return ArenaAlloc(arena, size);
         }

         if size == 0 {
            return null;
         }

         if size == old_size {
            return old_memory;
         }

         new_memory := ArenaAlloc(arena, size);
         memcpy(new_memory, old_memory, old_size);
         return new_memory;
      case;
   }

   return null;
}

ArenaAlloc :: (a: *Arena, count: int, alignment := DefaultAlignment, loc := #caller_location) -> *void {
   assert(a.memory != null, "arena: not initialized", loc = loc);
   assert(IsPowerOfTwo(alignment));

   end := a.memory.(*u8) + a.offset;
   ptr := align_forward(end.(s64), xx alignment);
   total_size := (count + ptr.(*u8) - end.(*u8)).(u64);

   assert(a.offset + total_size <= a.memory_size, "arena: out of memory", loc = loc);
   a.offset += total_size;

   return ptr.(*void);
}

CrashAllocatorProc :: (mode: Allocator_Mode, size: s64, old_size: s64, old_memory: *void, allocator_data: *void) -> *void {
   message: string;
   if mode == {
      case .ALLOCATE;
         message = tprint("Attempt to allocate % byte(s) using the crash allocator!", size);
      case .RESIZE;
         message = tprint("Attempt to resize (from % to % byte(s)) using the crash allocator!", old_size, size);
      case .FREE;
         message = tprint("Attempt to free % byte(s) using the crash allocator!", size);
   }

   assert(false, message);
   debug_break();
   return null;
}

DefaultAlignment :: 2 * #run align_of(*void);

IsPowerOfTwo :: (x: int) -> bool {
   if x <= 0 return false;
   return (x & (x - 1)) == 0;
}

align_of :: ($T: Type) -> int #expand {
   return #run -> int {
      info := type_info(struct{ p: u8; t: T; });
      return info.members[1].offset_in_bytes;
   };
}

#import "Basic";
