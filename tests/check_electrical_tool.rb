# encoding: UTF-8
load File.expand_path('check_plugin.rb',__dir__)
SuPvElectricalTool::SelectionTool.class_eval { define_method(:onKeyDown) { |*_args| false } }
load File.expand_path('../scripts/tools/button_08_electrical.rb',__dir__)
check(SuPvElectricalTool::SelectionTool.instance_method(:onKeyDown).owner==SuPvPredictionTool::SelectionTool,'Reload kept the obsolete electrical Enter handler')
class UI::HtmlDialog
 STYLE_DIALOG=0
 attr_reader :callbacks,:scripts,:file
 def initialize(**options);@callbacks={};@scripts=[];end
 def add_action_callback(name,&block);@callbacks[name]=block;end
 def execute_script(script);@scripts<<script;end
 def set_on_closed(&block);@closed=block;end
 def set_file(path);@file=path;end
 def show;end
 def close;@closed.call if @closed;end
end
class ElectricalModel < FakeModel
 def get_attribute(dict,key,fallback=nil);(@attributes||={}).fetch([dict,key],fallback);end
 def set_attribute(dict,key,value);(@attributes||={})[[dict,key]]=value;end
end
fixture=JSON.parse(File.read(File.expand_path('../output/checks/electrical_fixture.json',__dir__),encoding:'UTF-8'))
model=ElectricalModel.new(nil);Sketchup.instance_variable_set(:@model,model)
data=fixture['records']
SuPvElectricalTool.instance_variable_set(:@model,model)
native_records=SuPvElectricalTool.method(:records)
native_panels=SuPvSceneSnapshot.method(:panels_in)
path_object=Object.new;path_object.define_singleton_method(:valid?) { true }
SuPvElectricalTool.instance_variable_set(:@paths,[[path_object]])
edit_path=nil;model.define_singleton_method(:active_path) { edit_path }
SuPvSceneSnapshot.define_singleton_method(:panels_in) { |_path| data }
check(native_records.call==data,'Root model cannot provide electrical selection')
edit_path=[]
check(native_records.call==data,'Empty root edit path was mistaken for a changed model')
edit_path=[path_object]
begin;native_records.call;raise 'Nested edit accepted';rescue RuntimeError=>error;check(error.message=='请退出组件编辑后重试。','Editing context was mislabeled as a model switch');end
edit_path=nil;Sketchup.instance_variable_set(:@model,ElectricalModel.new(nil))
begin;native_records.call;raise 'Other model accepted';rescue RuntimeError=>error;check(error.message=='活动模型已切换，请重新选择。','Actual model switch was not rejected');end
Sketchup.instance_variable_set(:@model,model)
SuPvSceneSnapshot.define_singleton_method(:panels_in,native_panels)
SuPvElectricalTool.define_singleton_method(:records) { data }
timers=[];native_timer=UI.method(:start_timer)
UI.define_singleton_method(:start_timer) { |*_args,&callback| timers<<callback }
picker=SuPvElectricalTool::SelectionTool.new(model,[[:dummy]],action:'电气配置')
edit_path=[:native_component_edit] unless picker.onKeyDown(13,1,0,nil)==true
picker.onKeyDown(13,2,0,nil)
check(edit_path.nil? && timers.empty?,'Electrical Enter-down opened native component editing')
edit_path=[:native_component_edit] unless picker.onKeyUp(13,1,0,nil)==true
picker.onKeyUp(13,1,0,nil)
check(edit_path.nil? && timers.length==1,'Electrical key cycle was not consumed exactly once')
timers.shift.call
UI.define_singleton_method(:start_timer,native_timer)
dialog=SuPvElectricalTool.instance_variable_get(:@dialog)
check(File.basename(dialog.file)=='pv_electrical.html','Wrong electrical workspace')
dialog.callbacks['ready'].call(nil)
check(dialog.scripts.last.include?('window.PVElectrical.receive('),'Selection did not populate electrical form')
input={'input'=>fixture['input'],'request_id'=>3}
dialog.callbacks['calculate'].call(nil,JSON.generate(input))
check(dialog.scripts.last.include?('window.PVElectrical.result(') && model.operations.empty?,'Preview altered the model')
# The native API can enumerate the same instances in a different order and
# return equivalent transforms with tiny floating tails. Neither is a move.
data=data.reverse.map { |r| Marshal.load(Marshal.dump(r)) }
data.first['origin_mm'][0]+=1e-7;data.first['axes'][0][1]+=1e-10
dialog.callbacks['calculate'].call(nil,JSON.generate(input))
check(dialog.scripts.last.include?('window.PVElectrical.result('),'Equivalent selection order / transform tails invalidated the plan')
dialog.callbacks['save'].call(nil,JSON.generate(input))
saved=JSON.parse(model.get_attribute('SuPvElectricalTool','design'))
check(saved['result']['connected_count']==100 && saved['losses_applied']==false,'Saved plan misstates connected capacity or generation effects')
check(model.operations==[:start,:commit],'Configuration save is not one undoable operation')
data=Marshal.load(Marshal.dump(data));data.first['origin_mm'][0]+=100
dialog.callbacks['save'].call(nil,JSON.generate(input))
check(dialog.scripts.last.include?('window.PVElectrical.fail(') && model.operations==[:start,:commit],'Changed array accepted a stale electrical plan')
check(JSON.parse(model.get_attribute('SuPvElectricalTool','design'))==saved,'Rejected save overwrote the existing plan')
dialog.close
dialog.callbacks['save'].call(nil,JSON.generate(input))
check(model.operations==[:start,:commit],'Obsolete dialog callback mutated model state')
# Reopening an old saved selection recalculates a complete mixed-length plan.
data=fixture['case173']['records']
SuPvElectricalTool.selected([[path_object]],model)
dialog=SuPvElectricalTool.instance_variable_get(:@dialog)
dialog.callbacks['ready'].call(nil)
dialog.callbacks['save'].call(nil,JSON.generate('input'=>fixture['default_input'],'request_id'=>5))
full=JSON.parse(model.get_attribute('SuPvElectricalTool','design'))
check(full['result']['connected_count']==173 && full['result']['unassigned'].empty?,'Saved mixed plan omitted the former remainder')
check(full['result']['inverters'].length==2 && full['result']['strings'].sum { |str| str['panels'].length }==173,'Saved inverter/string graph differs from the full plan')
check(full['result']['inverters'].flat_map { |inv| inv['mppts'] }.all? { |slot| slot['series_count'].between?(17,18) },'Saved MPPTs lost their actual string lengths')
# A legacy saved partial plan must not reopen with an infeasible fixed tail.
legacy=Marshal.load(Marshal.dump(full));legacy['input']['series_count']=5;legacy['result']['connected_count']=170
model.set_attribute('SuPvElectricalTool','design',JSON.generate(legacy))
SuPvElectricalTool.selected([[path_object]],model)
dialog=SuPvElectricalTool.instance_variable_get(:@dialog)
dialog.callbacks['ready'].call(nil)
restored=JSON.parse(dialog.scripts.last.sub(/\Awindow\.PVElectrical\.receive\(/,'').sub(/\);\z/,''))
check(restored['saved']['series_count']==0 && restored['saved']['ac_kw']==legacy['input']['ac_kw'],'Legacy partial plan did not restore device inputs in full automatic mode')
dialog.callbacks['save'].call(nil,JSON.generate('input'=>fixture['default_input'].merge('objective'=>'balanced'),'request_id'=>8))
goal_saved=JSON.parse(model.get_attribute('SuPvElectricalTool','design'))
check(goal_saved['input']['objective']=='balanced' && goal_saved['result']['selection']['objective']=='balanced','Saved goal differs from the solver objective')
puts 'Electrical selection, preview, atomic save, unchanged output basis and stale-object guards passed.'

# Unexpected Ruby failures are diagnostic errors, never infeasible-design claims.
native_calculate=SuPvElectricalDesign.method(:calculate)
diagnostics=[]
native_project_path=SuPvPanelTool.method(:project_path)
diagnostic_path=File.expand_path('../output/checks/electrical_error_test.json',__dir__)
SuPvPanelTool.define_singleton_method(:project_path) { |path| path=='output/electrical_error.json' ? diagnostic_path : native_project_path.call(path) }
SuPvElectricalTool.define_singleton_method(:warn) { |message| diagnostics<<message }
begin
  SuPvElectricalDesign.define_singleton_method(:calculate) { |*_args| nil-1 }
  previous= model.get_attribute('SuPvElectricalTool','design')
  previous_operations=model.operations.dup
  dialog.callbacks['save'].call(nil,JSON.generate('input'=>fixture['default_input'],'request_id'=>9))
  failed=JSON.parse('['+dialog.scripts.last.sub(/\Awindow\.PVElectrical\.fail\(/,'').sub(/\);\z/,'')+']')
  check(failed==['电气计算异常，已记录诊断信息。',9,'internal'],'Raw Ruby exception leaked or was labeled infeasible')
  check(diagnostics.length==1 && diagnostics.first.include?('NoMethodError') && diagnostics.first.include?(__FILE__),'Full internal diagnostic was lost')
  diagnostic=JSON.parse(File.read(diagnostic_path))
  check(diagnostic['records']==data && diagnostic['input']==fixture['default_input'] && diagnostic['error'].include?('NoMethodError'),'Exact failed selection was not preserved for reproduction')
  check(model.operations==previous_operations && model.get_attribute('SuPvElectricalTool','design')==previous,'Failed calculation mutated the saved design')
ensure
  SuPvElectricalDesign.define_singleton_method(:calculate,native_calculate)
  SuPvElectricalTool.singleton_class.send(:remove_method,:warn)
  SuPvPanelTool.define_singleton_method(:project_path,native_project_path)
end
dialog.callbacks['calculate'].call(nil,JSON.generate('input'=>fixture['default_input'].merge('port_current'=>1),'request_id'=>10))
failed=JSON.parse('['+dialog.scripts.last.sub(/\Awindow\.PVElectrical\.fail\(/,'').sub(/\);\z/,'')+']')
check(failed[0].include?('单串电流') && failed[2]=='constraint','Expected constraint failure was mislabeled as a program exception')
