# encoding: UTF-8
load File.expand_path('check_plugin.rb',__dir__)
class Geom::Vector3d;def to_a;[x,y,z];end;end
class Geom::Point3d;def to_a;@coords;end;end
model=FakeModel.new(nil);Sketchup.instance_variable_set(:@model,model)
region=SuPvRoofRegion.prepare([[[0,0],[10000,0],[10000,8000],[0,8000]]])
target={model:model,flush_only:false,normal:Geom::Vector3d.new(0,0,1),u:Geom::Vector3d.new(1,0,0),v:Geom::Vector3d.new(0,1,0),
 origin:Geom::Point3d.new(0,0,0),region:region,width:10000,height:8000,kind:'roof'}
settings={'model_id'=>'TSM-NE19R','azimuth'=>180,'tilt'=>30,'gap_x_mm'=>100,'gap_y_mm'=>500,'access'=>SuPvAccessLayout.defaults.merge('edge_mm'=>650)}
original=[:validate_target,:show_dialog].map { |key| [key,SuPvArrayTool.method(key)] }.to_h
restores=[]
array=Class.new do
 attr_accessor :hidden
 def valid?;true;end
 def hidden?;!!@hidden;end
end.new
timers=[];timer_method=UI.method(:start_timer)
dialog=Class.new do
 attr_reader :closed
 def close;@closed=true;end
end
begin
 UI.define_singleton_method(:start_timer) { |_seconds,_repeat,&block| timers<<block }
 SuPvArrayTool.define_singleton_method(:validate_target) { target }
 SuPvArrayTool.define_singleton_method(:show_dialog) { restores << instance_variable_get(:@params) }
 setup=lambda do |mode|
  previous_hidden=array.hidden?
  d=dialog.new
  SuPvArrayTool.instance_variable_set(:@model,model);SuPvArrayTool.instance_variable_set(:@target,target)
  SuPvArrayTool.instance_variable_set(:@target_id,7);SuPvArrayTool.instance_variable_set(:@params,settings)
  SuPvArrayTool.instance_variable_set(:@edit_path,[array])
  SuPvArrayTool.instance_variable_set(:@dialog,d)
  SuPvArrayTool.pick_access(JSON.generate(settings.merge('target_id'=>7,'request_id'=>11,'pick_mode'=>mode)))
  check(d.closed,'SU2022 dialog not closed for native picking')
  picker=SuPvArrayTool.instance_variable_get(:@tool)
  check(SuPvArrayTool.instance_variable_get(:@access_pick_pending),'Native handoff was not deferred until window close')
  check(model.instance_variable_get(:@tool)!=picker,'Native picking started before HtmlDialog callback returned')
  check(array.hidden? == previous_hidden,'Array visibility changed before the window-close handoff finished')
  # The old face picker must ignore clicks during the window-close handoff.
  SuPvArrayTool::FaceTool.new(model).onLButtonDown(0,0,0,model)
  timers.shift.call
  check(model.instance_variable_get(:@tool)==picker,'Deferred native picker was not activated')
  check(array.hidden?,'Edited array was not hidden during native picking')
  picker
 end
 picker=setup.call('entry');picker.finish([5000,0])
 check(!array.hidden?,'Completed entrance picking kept the array hidden')
 cfg=restores.last['access'];check(cfg['entry']==[5000.0,0.0] && cfg['edge_mm']==650 && cfg['automatic'],'Picking an entrance did not restore settings and enable the route preview')
 check(SuPvArrayTool.instance_variable_get(:@tool).is_a?(SuPvArrayTool::FaceTool),'Native array preview tool was not restored')
 check(SuPvArrayTool.instance_variable_get(:@resume_access),'Returning dialog lost the access tab')
 picker=setup.call('exclude');picker.finish([1000,2000,4000,6000]);check(restores.last['access']['exclusions']==[[1000.0,2000.0,4000.0,6000.0]],'Exclusion callback did not reach canonical settings')
 check(!array.hidden?,'Completed exclusion picking kept the array hidden')
 picker=setup.call('exclude');picker.onCancel(0,model);check(restores.last['access']==settings['access'],'Esc changed pending settings')
 check(!array.hidden?,'Esc did not restore array visibility')
 picker=setup.call('entry');old=restores.length;SuPvArrayTool.instance_variable_set(:@target_id,8);picker.finish([0,0]);check(restores.length==old,'Stale picker reopened the old target')
 check(!array.hidden?,'A stale picker kept its array hidden')
 array.hidden=true;picker=setup.call('exclude');picker.onCancel(0,model)
 check(array.hidden?,'Picking changed an array that was already hidden')
 array.hidden=false
 stale=setup.call('entry');current=setup.call('entry');stale.finish([1000,0])
 check(array.hidden?,'A stale callback restored the new picker array too early')
 current.onCancel(0,model);check(!array.hidden?,'New picker lost its original visibility state')
 select_tool=model.method(:select_tool)
 begin
  model.define_singleton_method(:select_tool) do |tool|
   raise 'injected picker activation error' if tool.is_a?(SuPvAccessPicker::Tool)
   select_tool.call(tool)
  end
  SuPvArrayTool.instance_variable_set(:@dialog,dialog.new)
  SuPvArrayTool.pick_access(JSON.generate(settings.merge('target_id'=>7,'pick_mode'=>'entry')))
  timers.shift.call
  check(!array.hidden?,'Failed native activation left the array hidden')
  check(SuPvArrayTool.instance_variable_get(:@access_error)=='injected picker activation error','Native activation failure was swallowed')
 ensure
  model.define_singleton_method(:select_tool,select_tool)
 end
 check(model.operations.empty? && model.instances.empty?,'Native selection modified the model')
 picker=setup.call('exclude')
 old_dialog=dialog.new;SuPvArrayTool.instance_variable_set(:@dialog,old_dialog)
 SuPvArrayTool.reset_ui
 check(old_dialog.closed && SuPvArrayTool.instance_variable_get(:@dialog).nil?,'Reload kept an obsolete dialog and its callback bindings')
 check(SuPvArrayTool.instance_variable_get(:@tool).nil?,'Reload kept an obsolete native picker')
 check(!array.hidden?,'Reload or tool reset left the array hidden')
ensure
 UI.define_singleton_method(:start_timer,timer_method)
 original.each { |name,method| SuPvArrayTool.define_singleton_method(name,method) }
end
