# encoding: UTF-8
# Native API doubles: reopen saved arrays, preserve identity, atomic replacement.
load File.expand_path('check_plugin.rb',__dir__)
load File.expand_path('../scripts/tools/button_03_array.rb',__dir__)
load File.expand_path('../scripts/tools/button_07_constraints.rb',__dir__)
class Numeric;def to_mm;self*25.4;end;end
class Geom::Vector3d;def to_a;[x,y,z];end;end
class Geom::Point3d
 def to_a;@coords;end
 def transform(tr);self.class.new(tr.apply(to_a));end
 def distance(p);Math.sqrt(to_a.zip(p.to_a).sum { |a,b| (a-b)**2 });end
 def offset(axis,d);self.class.new(to_a.zip(axis.to_a).map { |a,b| a+b*d });end
end
class Geom::Transformation
 def initialize(matrix=nil);@matrix=matrix || Array.new(4) { |i| Array.new(4) { |j| i==j ? 1.0 : 0.0 } };end
 attr_reader :matrix
 def self.axes(origin,*axes)
  m=Array.new(4) { |i| Array.new(4) { |j| i==j ? 1.0 : 0.0 } }
  3.times { |i| 3.times { |j| m[i][j]=axes[j].to_a[i] };m[i][3]=origin.to_a[i] }
  new(m)
 end
 def *(b);self.class.new(Array.new(4) { |i| Array.new(4) { |j| (0..3).sum { |k| matrix[i][k]*b.matrix[k][j] } } });end
 def apply(p);(0..2).map { |i| matrix[i][3]+(0..2).sum { |j| matrix[i][j]*p[j] } };end
 def inverse
  m=Array.new(4) { |i| Array.new(4) { |j| i==j ? 1.0 : 0.0 } }
  3.times { |i| 3.times { |j| m[i][j]=matrix[j][i] };m[i][3]=-(0..2).sum { |j| m[i][j]*matrix[j][3] } };self.class.new(m)
 end
end
class Sketchup::ComponentInstance < FakeInstance
 def get_attribute(dict,key);attrs[key];end
 def persistent_id;object_id;end
end
class Sketchup::Group
 attr_accessor :name,:layer,:transformation,:locked,:hidden
 attr_reader :entities,:attributes,:definition,:unique_count
 def initialize
  @entities=ArrayEntities.new;@attributes={};@transformation=Geom::Transformation.new
  @definition=Struct.new(:entities,:instances).new(@entities,[self]);@unique_count=0
 end
 def valid?;true;end
 def persistent_id;object_id;end
 def locked?;!!@locked;end
 def hidden?;!!@hidden;end
 def get_attribute(dict,key);@attributes[key];end
 def set_attribute(dict,key,value);@attributes[key]=value;end
 def make_unique;@unique_count+=1;end
end
class ArrayEntities < Array
 attr_accessor :fail_after
 def add_group;group=Sketchup::Group.new;self<<group;group;end
 def add_instance(definition,tr)
  raise 'injected component failure' if @fail_after && length>=@fail_after
  item=Sketchup::ComponentInstance.new(nil,definition,tr);self<<item;item
 end
 def erase_entities(items);items.each { |item| delete(item) };end
end
class ArrayModel < FakeModel
 attr_reader :selection
 def initialize(signature)
  super;@entities=ArrayEntities.new;@selection=[]
  @selection.define_singleton_method(:add) { |entity| self<<entity }
 end
 def entities;@entities;end
 def start_operation(*args)
  super
  @before=entities.grep(Sketchup::Group).to_h { |group| [group,[group.entities.dup,group.attributes.dup]] }
 end
 def abort_operation
  super
  @before.each { |group,(items,attributes)| group.entities.replace(items);group.attributes.replace(attributes) }
 end
end
spec=SuPvPanelTool.panel_spec('TSM-NE19R')
model=ArrayModel.new([spec[:length_mm],spec[:width_mm],spec[:thickness_mm]].join('x'));Sketchup.instance_variable_set(:@model,model)
roof=Sketchup::Group.new;face=Sketchup::Face.new([])
face.define_singleton_method(:valid?) { true };face.define_singleton_method(:persistent_id) { object_id }
roof.entities<<face;model.entities<<roof
settings={'model_id'=>spec[:id],'azimuth'=>180,'tilt'=>30,'gap_x_mm'=>150.0,'gap_y_mm'=>450.0,
 'access'=>SuPvAccessLayout.defaults.merge('edge_mm'=>350.0,'hole_mm'=>550.0,'entry'=>[5000.0,0.0],'exclusions'=>[[1000.0,2000.0,2500.0,3500.0]])}
target={model:model,path:[roof,face],origin:Geom::Point3d.new(0,0,0),u:Geom::Vector3d.new(1,0,0),v:Geom::Vector3d.new(0,1,0),
 normal:Geom::Vector3d.new(0,0,1),width:10000,height:8000,region:SuPvRoofRegion.prepare([[[0,0],[10000,0],[10000,8000],[0,8000]]]),kind:'roof',label:'roof'}
group=model.entities.add_group
group.set_attribute('SuPvArrayTool','source_path',[roof.persistent_id,face.persistent_id]);group.set_attribute('SuPvArrayTool','settings',JSON.generate(settings))
old=group.entities.add_instance(model,Geom::Transformation.new);old.set_attribute('SuPvPanelTool','model_id',spec[:id])
SuPvArrayTool.define_singleton_method(:frame_from_path) { |path| check(path==[roof,face],'Source occurrence changed');target }
SuPvArrayTool.define_singleton_method(:validate_target) { target }
SuPvArrayTool.define_singleton_method(:show_dialog) {}
SuPvArrayTool.open_existing([group])
check(SuPvArrayTool.instance_variable_get(:@params)==settings.merge('clearance_mm'=>100.0),'Saved angles, product, gaps or constraints were discarded')
check(SuPvArrayTool.instance_variable_get(:@resume_access),'Existing array did not enter the constraints tab')
check(model.operations.empty?,'Opening the boundary workspace changed model geometry')

# Buttons select by the actual hit path, including when a PV component was hit.
view=Object.new;def view.pickray(*args);[];end
model.define_singleton_method(:raytest) { |*args| [nil,[group,old]] }
picker=SuPvConstraintsTool::SelectionTool.new(model)
check(picker.pick(view,0,0)==[group],'Clicking a PV did not resolve its generated array')
model.define_singleton_method(:raytest) { |*args| [nil,[roof,face]] }
begin;picker.pick(view,0,0);raise 'Accepted a host instead of an array';rescue RuntimeError=>e;raise if e.message=='Accepted a host instead of an array';end

# Boundary previews must not load prediction series or inspect scene occluders.
sent=nil
SuPvSceneSnapshot.define_singleton_method(:panels_in) { |*args| raise 'Boundary tool inspected shading panels' }
SuPvSceneSnapshot.define_singleton_method(:attach) { |*args| raise 'Boundary tool collected scene occluders' }
dialog=Object.new;dialog.define_singleton_method(:execute_script) { |script| sent=script }
dialog.define_singleton_method(:close) {}
SuPvArrayTool.instance_variable_set(:@dialog,dialog)
lookup=SuPvPanelTool.method(:energy_for)
begin
 SuPvPanelTool.define_singleton_method(:energy_for) { |*args| raise 'Boundary preview loaded hourly data' }
 SuPvArrayTool.send_preview(settings,0)
ensure
 SuPvPanelTool.define_singleton_method(:energy_for,lookup)
end
preview=JSON.parse(sent.sub('window.PVArray.receive(','').sub(/\);\z/,''))
check(preview['constraints_only'] && preview['editing_existing'] && !preview.key?('prediction') && !preview.key?('environment'),'Boundary preview retained forecast or scene data')

SuPvArrayTool.pick_access(JSON.generate(settings.merge('target_id'=>SuPvArrayTool.instance_variable_get(:@target_id),'pick_mode'=>'entry')))
native=SuPvArrayTool.instance_variable_get(:@tool)
check(group.hidden?,'Editing array stayed visible during entrance picking')
native.finish([4500,0]);check(!group.hidden?,'Entrance picking did not restore the edited array')
check(SuPvArrayTool.instance_variable_get(:@edit_path)==[group] && SuPvArrayTool.instance_variable_get(:@params)['access']['entry']==[4500.0,0.0],'Returning from SU picking lost the edited array or its new entrance')
SuPvArrayTool.instance_variable_set(:@dialog,dialog)
SuPvArrayTool.send_preview(SuPvArrayTool.instance_variable_get(:@params),1)
route=JSON.parse(sent.sub('window.PVArray.receive(','').sub(/\);\z/,''))
check(route['settings']['access']['automatic'] && !route['settings']['access']['paths'].empty? && route['access_validation']['valid'],'Entrance selection returned a preview without a traversable route')
check(route['settings']['access']['exclusions']==settings['access']['exclusions'],'Entrance selection discarded existing exclusion previews')

# A subsequent native rectangle pick must retain and reroute the same draft.
pick_params=SuPvArrayTool.instance_variable_get(:@params).merge('target_id'=>SuPvArrayTool.instance_variable_get(:@target_id),'pick_mode'=>'exclude')
SuPvArrayTool.pick_access(JSON.generate(pick_params))
check(group.hidden?,'Editing array stayed visible during exclusion picking')
SuPvArrayTool.instance_variable_get(:@tool).finish([7000,5000,8000,6000])
check(!group.hidden?,'Exclusion picking did not restore the edited array')
SuPvArrayTool.instance_variable_set(:@dialog,dialog)
SuPvArrayTool.send_preview(SuPvArrayTool.instance_variable_get(:@params),2)
combined=JSON.parse(sent.sub('window.PVArray.receive(','').sub(/\);\z/,''))
check(combined['settings']['access']['exclusions'].length==2 && !combined['settings']['access']['paths'].empty? && combined['access_validation']['valid'],'Native exclusion pick lost the route or rectangle preview')

id=SuPvArrayTool.instance_variable_get(:@target_id);failures=[]
SuPvArrayTool.define_singleton_method(:fail_ui) { |error| failures<<error.message }
before_count=model.entities.length
updated=settings.merge('access'=>settings['access'].merge('hole_mm'=>800.0))
SuPvArrayTool.build(JSON.generate(updated.merge('target_id'=>id,'request_id'=>1)))
check(failures.empty?,"Array update failed: #{failures.inspect}")
check(model.entities.length==before_count && model.entities.include?(group),'Updating created another group or lost the selected group')
check(!group.entities.include?(old) && group.entities.length>0 && group.entities.all? { |panel| panel.layer==:pv },'Old panels remain or PV tag was lost')
check(JSON.parse(group.get_attribute('SuPvArrayTool','settings'))['access']['hole_mm']==800,'Updated constraints were not persisted')
check(group.unique_count==1 && model.operations==[:start,:commit],'Group identity/uniqueness or transaction changed')
check(sent.include?('"editing_existing":true'),'Build callback lost edit status')

# Failure during population rolls back, retaining all previous panels/settings.
previous=group.entities.dup;attributes=group.attributes.dup;group.entities.fail_after=previous.length+1
SuPvArrayTool.build(JSON.generate(updated.merge('target_id'=>id,'request_id'=>2)))
check(model.operations.last==:abort && group.entities==previous && group.attributes==attributes,'Failed array update was not atomic')
group.entities.fail_after=nil

# Independent move, lock, and deleted source must never silently reset the array.
group.transformation=Geom::Transformation.axes(Geom::Point3d.new(10,0,0),target[:u],target[:v],target[:normal])
begin;SuPvArrayTool.validate_existing;raise 'Moved array accepted';rescue RuntimeError=>e;raise if e.message=='Moved array accepted';end
group.transformation=Geom::Transformation.new;group.locked=true
begin;SuPvArrayTool.validate_existing;raise 'Locked array accepted';rescue RuntimeError=>e;raise if e.message=='Locked array accepted';end
group.locked=false
# A nested unique parent is supported using the cumulative world transform;
# editing an ancestor with multiple instances is rejected before any mutation.
ancestor=model.entities.add_group;model.entities.delete(group);ancestor.entities<<group
ancestor.transformation=Geom::Transformation.axes(Geom::Point3d.new(10,20,0),target[:u],target[:v],target[:normal])
group.transformation=ancestor.transformation.inverse
SuPvArrayTool.instance_variable_set(:@edit_path,[ancestor,group]);SuPvArrayTool.validate_existing
SuPvArrayTool.build(JSON.generate(updated.merge('target_id'=>id,'request_id'=>3)))
check(model.operations.last==:commit && model.selection==[ancestor],'Nested array update failed or selected an entity outside the active context')
ancestor.definition.instances<<Object.new
begin;SuPvArrayTool.validate_existing;raise 'Shared ancestor accepted';rescue RuntimeError=>e;raise if e.message=='Shared ancestor accepted';end
ancestor.definition.instances.pop;ancestor.entities.delete(group);model.entities<<group;group.transformation=Geom::Transformation.new
SuPvArrayTool.instance_variable_set(:@edit_path,[group])
roof.entities.clear
begin;SuPvArrayTool.source_path([roof.persistent_id,face.persistent_id]);raise 'Deleted face accepted';rescue RuntimeError=>e;raise if e.message=='Deleted face accepted';end

# Hot reload migrates the six-button session without adding duplicate menus.
commands=SuPvToolbar.instance_variable_get(:@commands)
boundary=commands.find { |command| command.tooltip=='边界约束' }
toolbar=SuPvToolbar.instance_variable_get(:@toolbar);menu=SuPvToolbar.instance_variable_get(:@menu)
toolbar.items.delete(boundary);menu.items.delete(boundary)
SuPvToolbar.instance_variable_set(:@commands,commands-[boundary]);SuPvToolbar.instance_variable_set(:@schema,'unified_20261023_csv_svg')
SuPvToolbar.setup
check(SuPvToolbar.instance_variable_get(:@toolbar).length==8 && menu.items.length==8,'Toolbar migration duplicated commands or menu items')
SuPvToolbar.setup
check(menu.items.length==8,'Repeated reload appended the boundary command again')
puts 'Constraints tool verified: source occurrence, saved settings, native click, shading exclusions, identity-preserving update, rollback and invalid target guards.'
