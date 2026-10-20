# encoding: UTF-8
stdlib='C:/Program Files/SketchUp/SketchUp 2022/Tools/RubyStdLib'
$LOAD_PATH.unshift(stdlib,"#{stdlib}/platform_specific")
require 'enc/encdb'
require 'enc/trans/transdb'
$LOADED_FEATURES << 'sketchup.rb'
def check(condition,message);raise message unless condition;end
class Numeric
 def degrees;self*Math::PI/180.0;end
 def mm;self/25.4;end
end
module Geom
 class Vector3d
  attr_reader :x,:y,:z
  def initialize(x,y,z);@x,@y,@z=x,y,z;end
  def cross(b);self.class.new(y*b.z-z*b.y,z*b.x-x*b.z,x*b.y-y*b.x);end
 end
 class Point3d
  def initialize(*args);@coords=args.flatten;end
 end
 class Transformation
  attr_reader :origin,:axes
  def self.axes(origin,*axes);value=new;value.instance_variable_set(:@origin,origin);value.instance_variable_set(:@axes,axes);value;end
 end
end
module UI
 class Command
  attr_accessor :small_icon,:large_icon,:tooltip,:status_bar_text
  attr_reader :action
  def initialize(name,&block);@action=block;end
 end
 class Toolbar
  attr_reader :items,:name
  def initialize(name);@name=name;@items=[];UI.toolbars<<self;end
  def length;@items.length;end
  def add_item(item);@items<<item;end
  def show;end
  def hide;end
 end
 class Menu
  attr_reader :items
  def initialize;@items=[];end
  def add_submenu(name);sub=self.class.new;@items<<sub;sub;end
  def add_item(item,&block);@items<<item;end
 end
 def self.toolbars;@toolbars||=[];end
 def self.menu(name);@menu||=Menu.new;end
 def self.start_timer(*args);yield;end
 def self.messagebox(text);raise text;end
end
module Sketchup
 class InputPoint;end
 def self.active_model;@model;end
 def self.set_status_text(*args);end
end
class FakeInstance
 attr_accessor :name,:layer,:transformation
 attr_reader :attrs,:model,:definition
 def initialize(model,definition,transformation);@model,@definition,@transformation=model,definition,transformation;@attrs={};end
 def valid?;true;end
 def locked?;false;end
 def set_attribute(dict,key,value);@attrs[key]=value;end
 def delete_attribute(dict,key);@attrs.delete(key);end
end
class FakeModel
 attr_reader :instances,:layers,:operations
 def initialize(signature)
  @signature=signature;@instances=[];@layers={0=>:untagged,'PV_panel'=>:pv};@operations=[]
 end
 def active_path;nil;end
 def definitions;[self];end
 def get_attribute(dict,key);{'signature'=>@signature,'model'=>'TSM-NE19R','power_w'=>630.0}[key];end
 def entities;self;end
 def add_instance(definition,tr);instance=FakeInstance.new(self,definition,tr);@instances<<instance;instance;end
 def start_operation(name,*args);@operations<<:start;end
 def commit_operation;@operations<<:commit;end
 def abort_operation;@operations<<:abort;end
 def select_tool(tool);@tool=tool;end
 def active_view;self;end
 def invalidate;end
end
root=File.expand_path('..',__dir__)
load "#{root}/scripts/pv_toolbar.rb"
load "#{root}/scripts/pv_toolbar.rb"
check(UI.toolbars.length==2 && UI.toolbars.first.items.length==5,'Reload duplicated toolbar or buttons')
check(UI.toolbars.first.name=='变电站光伏 · toolbar2','Toolbar still has the experimental name')
check(!File.exist?("#{root}/scripts/pv_panel_tool.rb"),'Duplicate entry still present')
spec=SuPvPanelTool.panel_spec
check(spec[:length_mm]==2382.0 && spec[:width_mm]==1134.0 && spec[:power_w]==630.0,'Real CSV spec mismatch')
model=FakeModel.new([spec[:length_mm],spec[:width_mm],spec[:thickness_mm]].join('x'))
Sketchup.instance_variable_set(:@model,model)
# The explicit UI payload, rather than a previous global angle, determines the tool and placed component.
SuPvPanelTool.start_placement(JSON.generate({'azimuth'=>150,'tilt'=>39}))
tool=SuPvPanelTool.instance_variable_get(:@placement_tool)
check(tool.instance_variable_get(:@angles)=={'azimuth'=>150,'tilt'=>39,'model_id'=>'TSM-NE19R'},'Placement dropped explicit UI angles')
instance=SuPvPanelTool.create_panel(Geom::Point3d.new(0,0,0),{'azimuth'=>120,'tilt'=>12},spec)
check(instance.attrs['azimuth_deg']==120 && instance.attrs['tilt_deg']==12,'Placed component metadata uses stale settings')
check((instance.transformation.axes[1].z-Math.sin(12.degrees)).abs<1e-10,'Actual transform uses stale tilt')
check(instance.layer==:pv && instance.definition.equal?(model),'Component definition or layer mismatch')
check(model.operations==[:start,:commit],'Placement transaction mismatch')
check(SuPvPanelTool.settings=={'azimuth'=>150,'tilt'=>39,'model_id'=>'TSM-NE19R'},'Explicit create unexpectedly reset window settings')
# Ensure Ruby block closures dispatch to their own button, not the last entry in the loop.
$dispatch=[]
[SuPvStationTool,SuPvPanelTool,SuPvArrayTool,SuPvPredictionTool,SuPvFlushTool].each_with_index do |tool,index|
 tool.define_singleton_method(:activate){$dispatch<<index+1}
end
UI.toolbars.first.items.each{|command|command.action.call}
check($dispatch==[1,2,3,4,5],'Toolbar dispatch mismatch')

# Already registered legacy commands require restart; never append a replacement toolbar.
commands=SuPvToolbar2.instance_variable_get(:@commands)
check(commands.map{|c|File.basename(c.small_icon)}==%w[insert_station_24.png pv_panel_24.png pv_array_24.png pv_prediction_24.png pv_flush_24.png], 'Icon paths mismatch')
SuPvToolbar2.instance_variable_set(:@registration_schema,'legacy')
count=UI.toolbars.length
check(SuPvToolbar2.setup==false,'Legacy registration must request restart')
check(UI.toolbars.length==count && UI.toolbars.first.length==5,'Legacy load appended buttons')
check(SuPvToolbar2.show==false,'Legacy toolbar must not be shown')

# encoding: UTF-8
class Geom::Vector3d
 def to_a;[x,y,z];end
end
module Sketchup
 class Color
  def initialize(*args);end
 end
 class Face
  attr_accessor :material,:back_material
  attr_reader :points,:thickness
  def initialize(points);@points=points;end
  def normal;Geom::Vector3d.new(0,0,1);end
  def pushpull(value);@thickness=value;end
  def layer=(value);end
 end
end
class Definition
 attr_reader :entities,:name,:attrs
 def initialize(name);@name=name;@attrs={};@entities=Geometry.new;end
 def get_attribute(dict,key);@attrs[key];end
 def set_attribute(dict,key,value);@attrs[key]=value;end
end
class Geometry < Array
 def add_face(*points);face=Sketchup::Face.new(points);self<<face;face;end
end
class Definitions < Array
 def add(name);definition=Definition.new(name);self<<definition;definition;end
end
class CatalogModel < FakeModel
 def definitions;@definitions||=Definitions.new;end
end
catalog=SuPvPanelTool.panel_catalog
check(catalog.length==5,'Only the five supported products may be exposed')
check(catalog.all?{|spec|spec[:efficiency_pct]>0 && spec[:efficiency_pct]<=100},'Panel efficiency metadata is missing')
check(catalog.select{|spec|spec[:data_available]}.map{|spec|spec[:id]}.sort==['TSM-NE19R','LR7-60HVDDF 560M','S6-505','XXGD-S-480','RS-M072BZ'].sort,'Forecast availability must match the five imported products')
model=CatalogModel.new(nil);Sketchup.instance_variable_set(:@model,model)
SuPvPanelTool.instance_variable_set(:@placement_tool,nil)
class CaptureDialog
 attr_reader :data
 def execute_script(script);@data=JSON.parse(script.sub(/\Awindow.PV.receive\(/,'').sub(/\);\z/,''));end
end
dialog=CaptureDialog.new;SuPvPanelTool.instance_variable_set(:@dialog,dialog)
catalog.each do |spec|
 id=spec[:id];angles={'azimuth'=>180,'tilt'=>30,'model_id'=>id}
 instance=SuPvPanelTool.create_panel(Geom::Point3d.new(0,0,0),angles,spec)
 definition=instance.definition
 check(definition.attrs['model']==id && definition.attrs['power_w']==spec[:power_w],'Model identity lost in component')
 body=definition.entities.first
 check((body.points[2][0]*25.4-spec[:width_mm]).abs<1e-7 && (body.points[2][1]*25.4-spec[:length_mm]).abs<1e-7,'Model geometry dimensions differ from CSV')
 check((body.thickness*25.4-spec[:thickness_mm]).abs<1e-7,'Model thickness differs from CSV')
 check(instance.layer==:pv,'All panel instances must retain PV_panel tag')
 check(instance.attrs['data_available']==spec[:data_available],'Model forecast availability mismatch')
 check(spec[:data_available] ? instance.attrs['annual_kwh']>0 : !instance.attrs.key?('annual_kwh'),'Missing data must never be stored as zero or copied')
 check(SuPvPanelTool.panel_definition(model,spec).equal?(definition),'Repeated placement must reuse the correct product definition')
 # Switch the tool to this product without reading another product\'s time series.
 SuPvPanelTool.instance_variable_set(:@active_panel,nil)
 SuPvPanelTool.change_angles(JSON.generate(angles.merge('request_id'=>7)))
 check(dialog.data['spec']['id']==id && dialog.data['catalog'].length==5,'Dialog catalogue/selection mismatch')
 check(spec[:data_available] ? dialog.data['values'].length==8760 : dialog.data.values_at('values','annual_kwh','peak_wh')==[nil,nil,nil],'Missing forecast was fabricated')
end
check(model.definitions.length==5,'Products with equal geometry must have separate definitions')
SuPvPanelTool.instance_variable_set(:@dialog,nil)
SuPvArrayTool.define_singleton_method(:validate_target) do
 {width:10000.0,height:8000.0,u:Geom::Vector3d.new(1,0,0),v:Geom::Vector3d.new(0,1,0),normal:Geom::Vector3d.new(0,0,1)}
end
array_fixtures={}
catalog.each do |spec|
 params={'azimuth'=>180,'tilt'=>30,'model_id'=>spec[:id],'gap_x_mm'=>100.0,'gap_y_mm'=>500.0}
 plan=SuPvArrayTool.make_plan(params)
 check(SuPvArrayTool.instance_variable_get(:@spec)[:id]==spec[:id],'Array planner used a stale product')
 check((plan['capacity_kwp']-plan['count']*spec[:power_w]/1000.0).abs<1e-8,'Array capacity used a stale rated power')
 array_fixtures[spec[:id]]=plan.merge('spec'=>spec,'catalog'=>catalog,'target_id'=>1,'request_id'=>0,'target_name'=>'roof_rectangle')
end
known=catalog.select{|spec|spec[:data_available]}
first_pass=known.map{|spec|SuPvPanelTool.energy_for(spec,180,30)}
known.reverse.each_with_index do |spec,i|
 check(SuPvPanelTool.energy_for(spec,180,30)==first_pass[known.length-1-i],'Switching product reused another product cache')
end
check(first_pass.uniq.length==known.length,'Imported products unexpectedly share identical series')
puts 'Five supported component identities/geometry, datasets, placement, toolbar and array checks passed.'

# Rejected models must not return through parameter lookup or a stale console/window selection.
rejected = false
begin
 SuPvPanelTool.panel_spec('JAM54D50 GR')
rescue RuntimeError
 rejected = true
end
check(rejected,'An inactive product remained available to the tools')
SuPvPanelTool.instance_variable_set(:@settings,{'azimuth'=>180,'tilt'=>30,'model_id'=>'JAM54D50 GR'})
check(SuPvPanelTool.settings['model_id']=='TSM-NE19R','Stale inactive selection did not reset')
load "#{root}/scripts/pv_csv.rb"
SuPvCsv.read
check(SuPvCsv.products.map{|spec|spec[:model]}.sort==catalog.map{|spec|spec[:id]}.sort,'CSV experiment still includes inactive products')

# Previous three-button sessions must restart; no replacement toolbar or extra commands.
legacy = UI::Toolbar.new('变电站光伏')
original = commands.first(3)
original.each { |command| legacy.add_item(command) }
SuPvToolbar2.instance_variable_set(:@toolbar,legacy)
SuPvToolbar2.instance_variable_set(:@commands,original)
SuPvToolbar2.instance_variable_set(:@registration_schema,'substation_pv_three_v2')
count = UI.toolbars.length
check(!SuPvToolbar2.setup && !SuPvToolbar2.show,'Previous three-button session must request restart')
check(legacy.length==3 && UI.toolbars.length==count,'Migration duplicated or altered registered commands')
check(!File.exist?("#{root}/scripts/toolbar2/button_04_roof_array.rb"),'Redundant fourth entry remains')
