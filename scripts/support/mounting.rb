# encoding: UTF-8
# Roof-normal clearance; support solids are schematic and stay inside each PV instance.
module SuPvMounting
  def self.clearance(settings)
    value=Float(settings.fetch('clearance_mm',100))
    raise '组件最低净空须为100—500 mm。' unless value.finite? && value>=100 && value<=500
    value
  end
  def self.dot(a,b);a.zip(b).inject(0.0) { |s,(x,y)| s+x*y };end
  def self.geometry(spec,axes,normal,settings)
    h=clearance(settings)
    n=axes.map { |axis| dot(axis,normal) }
    corners=[0.0,spec[:thickness_mm]].flat_map do |z|
      [[0,0,z],[spec[:width_mm],0,z],[spec[:width_mm],spec[:length_mm],z],[0,spec[:length_mm],z]]
    end
    lift=h-corners.map { |p| dot(p,n) }.min
    anchors=[0.25,0.75].flat_map do |y|
      [0.15,0.85].map { |x| [x*spec[:width_mm],y*spec[:length_mm],-20.0] }
    end
    feet=anchors.map { |p| p.zip(n).map { |v,c| v-(lift+dot(p,n))*c } }
    {lift:lift,normal:n,anchors:anchors,feet:feet,clearance_mm:h}
  end
  def self.prism(entities,from,to,size,color)
    delta=to.zip(from).map { |a,b| a-b };length=Math.sqrt(dot(delta,delta));return if length<0.01
    z=delta.map { |v| v/length };seed=z[2].abs<0.9 ? [0,0,1] : [1,0,0]
    x=[z[1]*seed[2]-z[2]*seed[1],z[2]*seed[0]-z[0]*seed[2],z[0]*seed[1]-z[1]*seed[0]]
    norm=Math.sqrt(dot(x,x));x=x.map { |v| v/norm }
    y=[z[1]*x[2]-z[2]*x[1],z[2]*x[0]-z[0]*x[2],z[0]*x[1]-z[1]*x[0]]
    points=[[-1,-1],[1,-1],[1,1],[-1,1]].map { |a,b| (0..2).map { |i| (from[i]+(x[i]*a+y[i]*b)*size/2).mm } }
    face=entities.add_face(points);raise '支架示意建面失败。' unless face
    direction=Geom::Vector3d.new(*z);face.reverse! if face.normal.dot(direction)<0
    face.pushpull(length.mm)
    entities.grep(Sketchup::Face).each { |f| f.material=color;f.back_material=color }
  end
  def self.definition(model,spec,axes,normal,settings)
    geo=geometry(spec,axes,normal,settings)
    signature=JSON.generate(['schematic-excluded-v2',spec[:id],spec.values_at(:width_mm,:length_mm,:thickness_mm),geo[:clearance_mm],geo[:normal].map { |v| v.round(8) }])
    found=model.definitions.find { |d| d.get_attribute('SuPvMounting','signature')==signature }
    return found if found
    definition=model.definitions.add("PV_mount_#{spec[:id]}_#{geo[:clearance_mm].round}mm")
    definition.entities.add_instance(SuPvPanelTool.panel_definition(model,spec),Geom::Transformation.new)
    support=definition.entities.add_group;support.name='支架示意（安装位置及截面未作结构校核）'
    support.set_attribute('SuPvMounting','exclude_from_shading',true)
    support.casts_shadows=false if support.respond_to?(:casts_shadows=)
    support.receives_shadows=false if support.respond_to?(:receives_shadows=)
    color=Sketchup::Color.new(158,174,185)
    [0.25,0.75].each do |y|
      prism(support.entities,[0,y*spec[:length_mm],-10],[spec[:width_mm],y*spec[:length_mm],-10],20,color)
    end
    geo[:feet].zip(geo[:anchors]).each { |from,to| prism(support.entities,from,to,22,color) }
    if Math.hypot(geo[:normal][0],geo[:normal][1])>0.01
      [0,1].each { |i| prism(support.entities,geo[:feet][i],geo[:anchors][i+2],16,color) }
    end
    definition.entities.each { |e| e.layer=model.layers[0] }
    support.entities.each { |e| e.layer=model.layers[0] }
    definition.set_attribute('SuPvMounting','signature',signature)
    definition.set_attribute('SuPvMounting','schematic_only',true)
    definition
  end
end
