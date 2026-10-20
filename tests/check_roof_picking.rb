# encoding: UTF-8
load File.expand_path('check_plugin.rb',__dir__)
root=File.expand_path('..',__dir__)
load "#{root}/scripts/toolbar2/button_03_pv_array.rb"
class Numeric
 def to_mm;self*25.4;end
end
class Geom::Transformation
 def initialize(matrix=nil);@matrix=matrix || Array.new(4){|i|Array.new(4){|j|i==j ? 1.0 : 0.0}};end
 def matrix;@matrix;end
 def *(other)
  self.class.new(Array.new(4){|i|Array.new(4){|j|(0..3).inject(0.0){|sum,k|sum+matrix[i][k]*other.matrix[k][j]}}})
 end
 def apply(p);(0..2).map{|i|(0..2).inject(matrix[i][3]){|sum,j|sum+matrix[i][j]*p[j]}};end
end
class Geom::Point3d
 def to_a;@coords;end
 def transform(tr);self.class.new(tr.apply(@coords));end
 def distance(other);Math.sqrt(@coords.zip(other.to_a).inject(0.0){|sum,(a,b)|sum+(a-b)**2});end
end
class Sketchup::ComponentInstance
 attr_reader :transformation,:name
 def initialize(tr,name);@transformation,@name=tr,name;end
 def valid?;true;end
 def locked?;false;end
end
class LoopStub
 Vertex=Struct.new(:position)
 attr_reader :vertices
 def initialize(points);@vertices=points.map{|p|Vertex.new(Geom::Point3d.new(p))};end
end
class RoofFaceStub < Sketchup::Face
 attr_reader :loops,:outer_loop
 def initialize(rings);@loops=rings.map{|r|LoopStub.new(r)};@outer_loop=@loops.first;end
 def valid?;true;end
end
c,s=Math.cos(0.4),Math.sin(0.4)
outer_tr=Geom::Transformation.new([[c,-s,0,100],[s,c,0,200],[0,0,1,300],[0,0,0,1]])
inner_tr=Geom::Transformation.new([[-1.2,0,0,50],[0,0.8,0,20],[0,0,1,-10],[0,0,0,1]])
outer=[[0,0,0],[500,0,0],[500,500,0],[300,500,0],[300,300,0],[200,300,0],[200,500,0],[0,500,0]]
hole=[[50,50,0],[100,50,0],[100,100,0],[50,100,0]]
face=RoofFaceStub.new([outer,hole])
path=[Sketchup::ComponentInstance.new(outer_tr,'station'),Sketchup::ComponentInstance.new(inner_tr,'roof'),face]
target=SuPvArrayTool.frame_from_path(path)
check(target[:region][:outer].length==8 && target[:region][:holes].length==1,'Picking lost the notch or the hole')
expected=[c*50-s*20+100,s*50+c*20+200,290]
check(target[:world_loops][0][0].to_a.zip(expected).all?{|a,b|(a-b).abs<1e-9},'Nested component transform order is wrong')
check((target[:region][:area]-(250000-20000-2500)*25.4**2*0.96).abs<0.01,'Picking area failed under mirrored nonuniform scale')
SuPvArrayTool.instance_variable_set(:@target,target)
SuPvArrayTool.instance_variable_set(:@model,Sketchup.active_model)
SuPvArrayTool.validate_target
face.loops[1].vertices.each{|vertex|p=vertex.position.to_a;vertex.position=Geom::Point3d.new(p[0]+1,p[1],p[2])}
rejected=false
begin;SuPvArrayTool.validate_target;rescue RuntimeError;rejected=true;end
check(rejected,'Moving a hole did not invalidate the planned installation surface')
# The same entry accepts a plain rectangular installation face as well.
rect=RoofFaceStub.new([[[0,0,0],[500,0,0],[500,300,0],[0,300,0]]])
rect_path=[Sketchup::ComponentInstance.new(outer_tr,'rectangle'),rect]
rect_target=SuPvArrayTool.frame_from_path(rect_path)
check(rect_target[:region][:holes].empty? && rect_target[:region][:outer].length==4,'Unified entry rejected the rectangle')
check((rect_target[:width]*rect_target[:height]-150000*25.4**2).abs<0.01,'Rectangular installation dimensions changed')
invalid=RoofFaceStub.new([[[0,0,0],[500,0,0],[450,300,0],[0,300,0]]])
rejected=false
begin;SuPvArrayTool.frame_from_path([rect_path.first,invalid]);rescue RuntimeError;rejected=true;end
check(rejected,'Unified entry accepted a nonorthogonal boundary')
puts 'Picking checks passed: rectangle, nested mirrored roof, holes, changed holes and nonorthogonal rejection.'
class UI::HtmlDialog
 STYLE_DIALOG=0
 attr_reader :callbacks,:closed,:options
 def initialize(**options);@options=options;@callbacks={};@visible=false;end
 def add_action_callback(name,&block);@callbacks[name]=block;end
 def set_on_closed(&block);@closed=block;end
 def set_file(path);end
 def show;@visible=true;end
 def visible?;@visible;end
 def bring_to_front;end
 def close;@visible=false;end
 def execute_script(script);end
end
SuPvArrayTool.instance_variable_set(:@dialog,nil)
SuPvArrayTool.show_dialog
old_dialog=SuPvArrayTool.instance_variable_get(:@dialog)
old_dialog.close
SuPvArrayTool.instance_variable_set(:@dialog,nil)
SuPvArrayTool.activate
new_tool=SuPvArrayTool.instance_variable_get(:@tool)
SuPvArrayTool.show_dialog
new_dialog=SuPvArrayTool.instance_variable_get(:@dialog)
check(new_dialog.options[:dialog_title].include?('光伏阵列'),'Unified dialog title mismatch')
old_dialog.closed.call
old_dialog.callbacks['ready'].call(nil)
old_dialog.callbacks['preview'].call(nil,'invalid payload from closed window')
check(SuPvArrayTool.instance_variable_get(:@dialog).equal?(new_dialog),'Delayed old-window close cleared the new dialog')
check(SuPvArrayTool.instance_variable_get(:@tool).equal?(new_tool),'Delayed old-window callback canceled the new selection tool')
new_dialog.closed.call
check(SuPvArrayTool.instance_variable_get(:@dialog).nil?,'Closing the current dialog did not clean up')

class Geom::Point3d
 def offset(axis,distance);self.class.new(to_a.zip(axis.to_a).map{|p,v|p+v*distance});end
end
# Reproduce selecting a component after native Move/Rotate, then rotating it again and reselecting.
[[SuPvArrayTool,SuPvPanelTool],[SuPvArrayTool1,SuPvPanelTool1]].each do |tool,panels|
 original_dialog=tool.method(:show_dialog)
 tool.define_singleton_method(:show_dialog){}
 begin
  [0,35,180,250].each do |yaw|
   a=yaw*Math::PI/180;b=30*Math::PI/180
   parent=Sketchup::ComponentInstance.new(Geom::Transformation.new([[Math.cos(a),-Math.sin(a),0,1000],[Math.sin(a),Math.cos(a),0,2000],[0,0,1,3000],[0,0,0,1]]),'station')
   child=Sketchup::ComponentInstance.new(Geom::Transformation.new,'roof')
   installation=RoofFaceStub.new([[[0,0,0],[500,0,0],[500,300,0],[0,300,0]]])
   [1,-1].each do |direction|
    child.instance_variable_set(:@transformation,Geom::Transformation.new([[1,0,0,20],[0,Math.cos(b),-direction*Math.sin(b),30],[0,direction*Math.sin(b),Math.cos(b),40],[0,0,0,1]]))
    target=tool.frame_from_path([parent,child,installation])
    expected=[direction*Math.sin(a)*Math.sin(b),-direction*Math.cos(a)*Math.sin(b),Math.cos(b)]
    check(target[:normal].to_a.zip(expected).all?{|x,y|(x-y).abs<1e-9},'Moved/rotated component world normal is reversed or stale')
    p0=[1000+20*Math.cos(a)-30*Math.sin(a),2000+20*Math.sin(a)+30*Math.cos(a),3040]
    check(target[:world_loops][0][0].to_a.zip(p0).all?{|x,y|(x-y).abs<1e-9},'Moved component world position is stale')
    tool.instance_variable_set(:@ready,false);tool.instance_variable_set(:@params,panels.settings.merge('azimuth'=>180,'tilt'=>30,'gap_x_mm'=>100,'gap_y_mm'=>500))
    tool.select_target(target)
    settings=tool.instance_variable_get(:@params);spec=panels.panel_spec(settings['model_id'])
    plan=SuPvArrayLayout.plan(target[:width],target[:height],target.values_at(:u,:v,:normal).map(&:to_a),spec,settings,target[:region])
    check(plan['count']>0 && plan['unit_corners'].first(4).all?{|p|p[2].abs<1e-7},'Initial selected-roof layout does not fit the plane')
    plan['positions'].first(3).each do |position|
     transform=panels.panel_transform(tool.world_origin(position),plan['settings'])
     [[0,0],[spec[:width_mm],0],[spec[:width_mm],spec[:length_mm]],[0,spec[:length_mm]]].each do |x,y|
      point=transform.origin.to_a.each_with_index.map{|p,i|p+transform.axes[0].to_a[i]*x.mm+transform.axes[1].to_a[i]*y.mm}
      signed=point.zip(p0,expected).inject(0.0){|sum,(p,base,n)|sum+(p-base)*n}
      check(signed.abs<1e-7,'SU preview/component underside does not lie on the transformed installation plane')
     end
    end
   end
  end
 ensure
  tool.define_singleton_method(:show_dialog,original_dialog)
 end
end
