# Pure Ruby checks using the Ruby DLL bundled with SketchUp; does not launch SU or load its model API.
import os, ctypes, sys
from pathlib import Path
ruby_dir=Path('C:/Program Files/SketchUp/SketchUp 2022')
os.add_dll_directory(str(ruby_dir))
ruby=ctypes.CDLL(str(ruby_dir/'x64-msvcrt-ruby270.dll'))
argc=ctypes.c_int(1)
argv_data=(ctypes.c_char_p*2)(b'pv_ruby_checks',None)
argv=ctypes.cast(argv_data,ctypes.POINTER(ctypes.c_char_p))
ruby.ruby_sysinit.argtypes=[ctypes.POINTER(ctypes.c_int),ctypes.POINTER(ctypes.POINTER(ctypes.c_char_p))]
ruby.ruby_sysinit(ctypes.byref(argc),ctypes.byref(argv))
# The OS stack upper bound remains valid across the C calls; initialize Ruby's stack marker there.
kernel=ctypes.WinDLL('kernel32',use_last_error=True)
low=ctypes.c_size_t();high=ctypes.c_size_t()
kernel.GetCurrentThreadStackLimits(ctypes.byref(low),ctypes.byref(high))
ruby.ruby_init_stack.argtypes=[ctypes.c_void_p]
ruby.ruby_init_stack(ctypes.c_void_p(high.value-16))
ruby.ruby_setup.restype=ctypes.c_int
code=ruby.ruby_setup()
if code:raise RuntimeError('ruby_setup failed: '+str(code))
ruby.rb_gc_disable.restype=ctypes.c_size_t
ruby.rb_gc_disable()
ruby.rb_eval_string_protect.argtypes=[ctypes.c_char_p,ctypes.POINTER(ctypes.c_int)]
ruby.rb_eval_string_protect.restype=ctypes.c_size_t
ruby.rb_string_value_cstr.argtypes=[ctypes.POINTER(ctypes.c_size_t)]
ruby.rb_string_value_cstr.restype=ctypes.c_char_p
source=Path(sys.argv[1]).resolve().as_posix()
script=('load '+repr(source)+'; "Ruby checks passed"').encode('utf-8')
state=ctypes.c_int()
value=ctypes.c_size_t(ruby.rb_eval_string_protect(script,ctypes.byref(state)))
if state.value:
 state2=ctypes.c_int();value=ctypes.c_size_t(ruby.rb_eval_string_protect(b'$!.full_message',ctypes.byref(state2)))
 print(ruby.rb_string_value_cstr(ctypes.byref(value)).decode('utf-8',errors='replace'))
 sys.exit(1)
print(ruby.rb_string_value_cstr(ctypes.byref(value)).decode('utf-8'))
