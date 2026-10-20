# encoding: UTF-8
load File.expand_path('check_plugin.rb',__dir__)
root=File.expand_path('..',__dir__)
load "#{root}/scripts/toolbar2/button_02_pv_panel.rb"
load "#{root}/scripts/toolbar2/button_03_pv_array.rb"
check(UI.toolbars[0].name=='变电站光伏 · toolbar2' && UI.toolbars[0].length==5,'toolbar2 registration')
check(UI.toolbars[1].name=='变电站光伏 · toolbar1' && UI.toolbars[1].length==4,'toolbar1 registration')
commands=SuPvToolbar1.instance_variable_get(:@commands)
dispatch=[]
[SuPvStationTool,SuPvPanelTool1,SuPvArrayTool1,SuPvFlushTool].each_with_index do |tool,index|
  previous=tool.method(:activate)
  tool.define_singleton_method(:activate){dispatch<<index}
  commands[index].action.call
  tool.define_singleton_method(:activate,previous)
end
check(dispatch==[0,1,2,3],'toolbar1 dispatched to the wrong version')
count=UI.toolbars.length
SuPvToolbar1.setup
check(UI.toolbars.length==count && SuPvToolbar1.instance_variable_get(:@commands)==commands,'Reload duplicated toolbar1 commands')

class UI::HtmlDialog
  STYLE_DIALOG=0
  attr_reader :callbacks,:options,:scripts
  def initialize(**options);@options=options;@callbacks={};@scripts=[];@visible=false;end
  def add_action_callback(name,&block);@callbacks[name]=block;end
  def set_on_closed(&block);@on_closed=block;end
  def set_file(path);raise 'Missing HTML' unless File.file?(path);end
  def show;@visible=true;end
  def visible?;@visible;end
  def bring_to_front;end
  def close;@visible=false;@on_closed.call;end
  def execute_script(script);@scripts<<script;end
  def receive(function)
    source=@scripts.reverse.find{|s|s.start_with?("window.#{function}(")}
    JSON.parse(source.sub("window.#{function}(",'').sub(/\);\z/,''))
  end
end
def UI.savepanel(*args);nil;end
model=FakeModel.new(nil);Sketchup.instance_variable_set(:@model,model)
panel_tools=[SuPvPanelTool1,SuPvPanelTool]
panel_tools.each_with_index do |tool,index|
  tool.instance_variable_set(:@dialog,nil)
  tool.instance_variable_set(:@active_panel,nil)
  tool.instance_variable_set(:@placement_tool,nil)
  tool.instance_variable_set(:@settings,{'model_id'=>'TSM-NE19R','azimuth'=>180-index*30,'tilt'=>30+index*9})
  tool.show_dialog
  tool.instance_variable_get(:@dialog).callbacks['ready'].call(nil)
end
d1,d2=panel_tools.map{|tool|tool.instance_variable_get(:@dialog)}
p1,p2=[d1,d2].map{|d|d.receive('PV.receive')}
check(!p1['placement_only'] && p2['placement_only'],'Panel versions lost their integrated/separate layouts')
check(p1['settings']['azimuth']==180 && p2['settings']['azimuth']==150,'Panel settings crossed between versions')
check(d1.options[:preferences_key]!=d2.options[:preferences_key],'Panel window preferences collide')
module Sketchup;class ComponentInstance;end;end
class MetadataProbe < Sketchup::ComponentInstance
  attr_accessor :name
  def initialize;@data={};end
  def set_attribute(dictionary,key,value);@data[[dictionary,key]]=value;end
  def get_attribute(dictionary,key);@data[[dictionary,key]];end
end
probe=MetadataProbe.new
SuPvPanelTool1.apply_metadata(probe,p1['settings'],p1['values'],p1['annual_kwh'],SuPvPanelTool1.panel_spec)
check(SuPvPredictionTool.panel?(probe),'toolbar2 cannot recognize a toolbar1 panel')
check(d1.callbacks.key?('export_csv') && !d2.callbacks.key?('export_csv'),'Panel export is in the wrong version')
d1.callbacks['export_csv'].call(nil,JSON.generate({'settings'=>p1['settings']}))
check(d1.receive('PV.exported')['cancelled'],'toolbar1 panel CSV callback failed')
d1.close
check(SuPvPanelTool.instance_variable_get(:@dialog).equal?(d2) && d2.visible?,'Closing toolbar1 closed toolbar2 panel')

array_tools=[SuPvArrayTool1,SuPvArrayTool]
array_tools.each_with_index do |tool,index|
  panel_tool=panel_tools[index]
  tool.define_singleton_method(:make_plan) do |settings|
    @spec=panel_tool.panel_spec(settings['model_id'])
    SuPvArrayLayout.plan(12000,8000,[[1,0,0],[0,1,0],[0,0,1]],@spec,settings)
  end
  tool.instance_variable_set(:@model,model)
  tool.instance_variable_set(:@dialog,nil)
  tool.instance_variable_set(:@tool,nil)
  tool.instance_variable_set(:@target,{label:'test'})
  tool.instance_variable_set(:@target_id,index+1)
  tool.instance_variable_set(:@params,panel_tool.settings.merge('gap_x_mm'=>100,'gap_y_mm'=>500))
  tool.show_dialog
  tool.instance_variable_get(:@dialog).callbacks['ready'].call(nil)
end
a1,a2=array_tools.map{|tool|tool.instance_variable_get(:@dialog)}
r1,r2=[a1,a2].map{|d|d.receive('PVArray.receive')}
check(!r1['layout_only'] && r2['layout_only'],'Array versions lost integrated/separate forecasts')
check(a1.options[:preferences_key]!=a2.options[:preferences_key],'Array window preferences collide')
check(a1.callbacks.key?('export_csv') && !a2.callbacks.key?('export_csv'),'Array export is in the wrong version')
a1.callbacks['export_csv'].call(nil,JSON.generate({'settings'=>r1['settings'],
  'context'=>{'target_id'=>r1['target_id'],'count'=>r1['count'],'branch'=>'baseline'},'values'=>r1['prediction']['values']}))
check(a1.receive('PV.exported')['cancelled'],'toolbar1 array CSV callback failed')
a1.close
check(SuPvArrayTool.instance_variable_get(:@dialog).equal?(a2) && a2.visible?,'Closing toolbar1 closed toolbar2 array')
if ENV['PV_DUAL_FIXTURE']
  File.write(ENV['PV_DUAL_FIXTURE'],JSON.generate({'panel1'=>p1,'panel2'=>p2,'array1'=>r1,'array2'=>r2}))
end

# Known previous registrations append only the native-input button and retain Command references.
[[SuPvToolbar1,3,4,'substation_pv_toolbar1_v1'],[SuPvToolbar2,4,5,'substation_pv_toolbar2_v1']].each do |version,old_count,new_count,old_schema|
  old_commands=UI.toolbars[version==SuPvToolbar1 ? 1 : 0].items.first(old_count)
  old_bar=UI::Toolbar.new('upgrade check')
  old_menu=UI::Menu.new
  old_menu.add_item('显示工具栏')
  old_commands.each { |c| old_bar.add_item(c);old_menu.add_item(c) }
  version.instance_variable_set(:@toolbar,old_bar)
  version.instance_variable_set(:@menu,old_menu)
  version.instance_variable_set(:@commands,old_commands.dup)
  version.instance_variable_set(:@registration_schema,old_schema)
  total=UI.toolbars.length
  check(version.setup && old_bar.length==new_count,'Native button additive upgrade failed')
  check(old_bar.items.first(old_count)==old_commands && UI.toolbars.length==total,'Upgrade replaced registered commands or toolbar')
  check(old_menu.items.length==new_count+1,'Upgrade duplicated menu entries')
  check(old_bar.items.last.tooltip=='平铺排布','Wrong native-input command was appended')
  old_bar.items[2].tooltip='stale tooltip'
  old_bar.items[2].status_bar_text='stale hint'
  version.setup
  check(old_bar.length==new_count && old_menu.items.length==new_count+1,'Reload duplicated native-input command')
  label=version==SuPvToolbar1 ? '阵列与出力' : '光伏阵列'
  check(old_bar.items[2].tooltip==label && old_bar.items[2].status_bar_text.start_with?('选择安装面'),'Reload did not refresh the registered array command')
end
