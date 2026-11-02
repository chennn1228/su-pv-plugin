# encoding: UTF-8
load File.expand_path('check_plugin.rb',__dir__)
load File.expand_path('../scripts/support/scene_snapshot.rb',__dir__)
module Sketchup;class ComponentInstance;end;end
class ExcludedSupport
  attr_reader :entities
  def initialize;@entities=[];end
  def get_attribute(dict,key,fallback=nil);dict=='SuPvMounting' && key=='exclude_from_shading' ? true : fallback;end
  def valid?;true;end
  def transformation;raise 'Excluded support transform/mesh was visited';end
end
class ShadingTriangle < Sketchup::Face
  def initialize;end
  def valid?;true;end
  def mesh(_flags);self;end
  def polygons;[[1,2,3]];end
  def point_at(i);Geom::Point3d.new([[0,0,10],[10,0,10],[0,10,10]][i-1]);end
end
model=Object.new
model.define_singleton_method(:entities) { [ExcludedSupport.new,ShadingTriangle.new] }
plan=SuPvSceneSnapshot.attach({},model,[0,0,0])
check(plan['environment'].length==1 && plan['occluder_panels'].empty?,'Support exclusion removed real geometry or entered environment triangles')
puts 'Detached schematic supports are skipped before transforms and meshing; external roof/obstacle faces are retained.'
