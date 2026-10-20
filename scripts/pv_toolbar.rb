# encoding: UTF-8
# Load both presentation versions; repeat loads reuse registered toolbars.
require 'sketchup.rb'
if defined?(SuPvToolbar)
  SuPvToolbar.instance_variable_get(:@toolbar)&.hide
  warn '旧版工具栏已隐藏；重启SU后加载本入口，可清除旧菜单注册。'
end
load File.expand_path('pv_toolbar2.rb', __dir__)
load File.expand_path('pv_toolbar1.rb', __dir__)
