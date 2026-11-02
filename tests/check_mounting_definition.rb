# encoding: UTF-8
load File.expand_path('check_plugin.rb',__dir__)
# Use the real support drawing adapter with a small in-memory entity graph.
load File.expand_path('../scripts/support/mounting.rb',__dir__)
class Sketchup::Face
 def normal
  a,b,c=points[0,3]
  Geom::Vector3d.new(*b.zip(a).map { |x,y| x-y }).cross(Geom::Vector3d.new(*c.zip(a).map { |x,y| x-y }))
 end
 def reverse!;@points.reverse!;end
end
class Sketchup::Group
 attr_accessor :name,:layer,:casts_shadows,:receives_shadows
 attr_reader :entities
 def initialize;@entities=Geometry.new;end
 def set_attribute(dict,key,value);(@attributes||={})[[dict,key]]=value;end
 def get_attribute(dict,key,fallback=nil);(@attributes||={}).fetch([dict,key],fallback);end
end
class Geometry
 def add_face(*points)
  points=points.first if points.length==1
  face=Sketchup::Face.new(points);self<<face;face
 end
 def add_instance(definition,tr);item=FakeInstance.new(nil,definition,tr);self<<item;item;end
 def add_group;item=Sketchup::Group.new;self<<item;item;end
end
model=CatalogModel.new(nil);spec=SuPvPanelTool.panel_spec
a=Math::PI/6;axes=[[1,0,0],[0,Math.cos(a),Math.sin(a)],[0,-Math.sin(a),Math.cos(a)]]
settings={'clearance_mm'=>100}
definition=SuPvMounting.definition(model,spec,axes,[0,0,1],settings)
check(definition.entities.length==2,'Mounted component should contain one body and one support group')
body=definition.entities.first.definition
check(body.get_attribute('SuPvPanelTool','model')==spec[:id],'Mount wrapper lost the reusable product body')
support=definition.entities.last
check(support.get_attribute('SuPvMounting','exclude_from_shading') && support.casts_shadows==false && support.receives_shadows==false,'Schematic support was not explicitly excluded from both calculation and native shadows')
check(support.entities.grep(Sketchup::Face).length==8,'Expected two rails, four legs and two braces')
check(support.entities.grep(Sketchup::Face).all? { |f| f.thickness>0 },'Support solids were not extruded')
check(SuPvMounting.definition(model,spec,axes,[0,0,1],settings).equal?(definition),'Support definition cache missed identical orientation and clearance')
higher=SuPvMounting.definition(model,spec,axes,[0,0,1],{'clearance_mm'=>500})
check(!higher.equal?(definition) && higher.entities.first.definition.equal?(body),'Changing height mutated a shared mount or duplicated the body')
parallel=SuPvMounting.definition(model,spec,[[1,0,0],[0,1,0],[0,0,1]],[0,0,1],settings)
check(parallel.entities.last.entities.grep(Sketchup::Face).length==6,'Flush support unexpectedly has inclined braces')
puts 'Mounted component nesting, extruded supports and definition reuse passed.'
