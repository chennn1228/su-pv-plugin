# encoding: UTF-8
# Model API contract only; SketchUp is not launched.
load File.expand_path('check_prediction.rb',__dir__)
load File.expand_path('../scripts/toolbar2/button_05_flush_array.rb',__dir__)
class Geom::Transformation
  def self.axes(origin,*axes);new(origin.to_a,axes.map(&:to_a));end
end
class Geom::Point3d
  def distance(other);Math.sqrt(to_a.zip(other.to_a).inject(0.0){|s,(a,b)|s+(a-b)**2});end
end
class FlushInstance
  attr_accessor :name,:layer
  attr_reader :transformation,:attributes
  def initialize(transform);@transformation=transform;@attributes={};end
  def set_attribute(dictionary,key,value);@attributes[[dictionary,key]]=value;end
  def delete_attribute(dictionary,key);@attributes.delete([dictionary,key]);end
end
class FlushGroup
  attr_accessor :name,:layer,:transformation
  attr_reader :instances,:attributes
  def initialize;@instances=[];@attributes={};end
  def entities;self;end
  def add_instance(definition,transform);instance=FlushInstance.new(transform);@instances<<instance;instance;end
  def set_attribute(dictionary,key,value);@attributes[[dictionary,key]]=value;end
end
class FlushModel < FakeModel
  attr_reader :groups,:selected
  def initialize;super(nil);@groups=[];@selected=[];end
  def add_group;group=FlushGroup.new;@groups<<group;group;end
  def selection;@selected;end
end
model=FlushModel.new;Sketchup.instance_variable_set(:@model,model)
def model.selection
  @selection_proxy ||= Object.new.tap do |proxy|
    selected=@selected
    proxy.define_singleton_method(:clear){selected.clear}
    proxy.define_singleton_method(:add){|item|selected<<item}
  end
end
spec=SuPvPanelTool.panel_spec('TSM-NE19R')
region=SuPvRoofRegion.prepare([[[0,0],[12000,0],[12000,8000],[0,8000]]])
angle=23.7*Math::PI/180;yaw=31*Math::PI/180
u=Geom::Vector3d.new(Math.cos(yaw),Math.sin(yaw),0)
v=Geom::Vector3d.new(-Math.sin(yaw)*Math.cos(angle),Math.cos(yaw)*Math.cos(angle),Math.sin(angle))
n=u.cross(v);origin=Geom::Point3d.new(100,200,300)
target={origin:origin,u:u,v:v,normal:n,width:12000,height:8000,region:region,model:model,
  path:[Struct.new(:persistent_id).new(12)],world_loops:[[origin]]}
source=Object.new
source.define_singleton_method(:frame_from_path){|path|target}
SuPvFlushTool.define_singleton_method(:faces){source}
SuPvPanelTool.define_singleton_method(:panel_definition){|_model,_spec|:prototype}
[false,true].each do |landscape|
  plan=SuPvFlushLayout.plan(12000,8000,region,spec,landscape,100,500,20)
  SuPvFlushTool.build(target,spec,plan,100,500,20)
  group=model.groups.last
  check(group.instances.length==plan[:count],'Generated count differs from flat layout')
  check(group.instances.all?{|i|i.layer==:pv},'Panels left PV_panel tag')
  check(group.layer==:untagged,'Array group changed host tag')
  group.instances.each do |instance|
    transform=group.transformation*instance.transformation
    check(transform.zaxis.to_a.zip(n.to_a).all?{|a,b|(a-b).abs<1e-9},'A board is not parallel to the sloped roof')
    normal_distance=transform.origin.to_a.zip(origin.to_a).map{|a,b|a-b}.zip(n.to_a).inject(0.0){|sum,(a,b)|sum+a*b}.to_mm
    check((normal_distance-20).abs<1e-7,'Clearance is not measured along the roof normal')
    check(instance.attributes[['SuPvPanelTool','tilt_deg']]==23.7,'Roof slope was rounded to the lookup grid')
    check(!instance.attributes[['SuPvPanelTool','data_available']],'Off-grid slope fabricated output data')
  end
end
check(model.operations==[:start,:commit,:start,:commit],'Generation is not undoable')
def UI.inputbox(*args);@flush_input=args;false;end
count=model.groups.length
check(!SuPvFlushTool.input_and_build(target) && model.groups.length==count,'Cancel created an array')
check(UI.instance_variable_get(:@flush_input).last.include?('屋面23.7° / 板面23.7°'),'Native inputbox roof/panel angles are missing')
