# encoding: UTF-8
stdlib='C:/Program Files/SketchUp/SketchUp 2022/Tools/RubyStdLib'
$LOAD_PATH.unshift(stdlib,"#{stdlib}/platform_specific")
require 'json'
root=File.expand_path('..',__dir__)
load "#{root}/scripts/toolbar2/support/array_layout.rb"
def check(value,message);raise message unless value;end
# Independent containment oracle: split every panel edge at every roof intersection,
# check interval midpoints, then test an interior point of each hole.
def in_ring(p,ring)
 inside=false
 ring.each_with_index do |a,i|
  b=ring[(i+1)%ring.length];dx,dy=b[0]-a[0],b[1]-a[1]
  cross=(p[0]-a[0])*dy-(p[1]-a[1])*dx
  return 0 if cross.abs<=1e-5*Math.hypot(dx,dy) && p[0]>=[a[0],b[0]].min-1e-5 && p[0]<=[a[0],b[0]].max+1e-5 && p[1]>=[a[1],b[1]].min-1e-5 && p[1]<=[a[1],b[1]].max+1e-5
  inside=!inside if (a[1]>p[1])!=(b[1]>p[1]) && p[0]<(b[0]-a[0])*(p[1]-a[1])/(b[1]-a[1])+a[0]
 end
 inside ? 1 : -1
end
def independently_covered?(poly,region)
 rings=[region[:outer]]+region[:holes]
 allowed=lambda{|p|in_ring(p,region[:outer])>=0 && region[:holes].none?{|h|in_ring(p,h)>0}}
 return false unless poly.all?{|p|allowed.call(p)}
 poly.each_with_index do |p,i|
  q=poly[(i+1)%poly.length];r=[q[0]-p[0],q[1]-p[1]];cuts=[0.0,1.0]
  rings.each do |ring|
   ring.each_with_index do |a,j|
    b=ring[(j+1)%ring.length];s=[b[0]-a[0],b[1]-a[1]];den=r[0]*s[1]-r[1]*s[0]
    next if den.abs<1e-8
    d=[a[0]-p[0],a[1]-p[1]];t=(d[0]*s[1]-d[1]*s[0])/den;u=(d[0]*r[1]-d[1]*r[0])/den
    cuts<<[[t,0].max,1].min if t>=-1e-10 && t<=1+1e-10 && u>=-1e-10 && u<=1+1e-10
   end
  end
  cuts.uniq.sort.each_cons(2) do |a,b|
   t=(a+b)/2.0
   return false unless allowed.call([p[0]+r[0]*t,p[1]+r[1]*t])
  end
 end
 region[:holes].each do |hole|
  signed=hole.each_with_index.inject(0.0){|sum,(a,i)|b=hole[(i+1)%hole.length];sum+a[0]*b[1]-b[0]*a[1]}
  a,b=hole[0],hole[1];dx,dy=b[0]-a[0],b[1]-a[1];len=Math.hypot(dx,dy);sign=signed>0 ? 1 : -1
  point=[(a[0]+b[0])/2-sign*dy/len*0.001,(a[1]+b[1])/2+sign*dx/len*0.001]
  return false if in_ring(point,poly)>0
 end
 true
end
outer=[[0,0],[10000,0],[10000,10000],[6000,10000],[6000,4000],[4000,4000],[4000,10000],[0,10000]]
region=SuPvRoofRegion.prepare([outer])
bridge=[[3000,3000],[7000,3000],[7000,8000],[3000,8000]]
check(bridge.all?{|p|in_ring(p,outer)>=0},'Adversarial notch fixture must have four inside corners')
check(!SuPvRoofRegion.covered?(bridge,region),'A panel bridging a concave cut-out was retained')
hole=[[4000,4000],[6000,4000],[6000,6000],[4000,6000]]
holed=SuPvRoofRegion.prepare([[[0,0],[10000,0],[10000,10000],[0,10000]],hole])
cover=[[3000,3000],[7000,3000],[7000,7000],[3000,7000]]
check(!SuPvRoofRegion.covered?(cover,holed),'A panel completely covering an enclosed hole was retained')
check(SuPvRoofRegion.covered?([[2000,4000],[4000,4000],[4000,6000],[2000,6000]],holed),'Boundary-touching panel must be retained')
rejected=false
begin;SuPvRoofRegion.prepare([[[0,0],[5000,0],[6000,4000],[0,4000]]]);rescue RuntimeError;rejected=true;end
check(rejected,'Diagonal roof edges must be rejected')
roof=JSON.parse(File.read("#{root}/data/standard_faces.json"))['faces'].find{|f|f['tag']=='roof'}
source_loops=[roof['outer']]+roof['holes'];source_loops=source_loops.map{|ring|ring.map{|p|p.map{|v|v*25.4}}}
spec={model:'TSM-NE19R',power_w:630.0,width_mm:1134.0,length_mm:2382.0,thickness_mm:30.0}
cases=panels=0
[false,true].each do |mirror|
 [0,27].each do |slope|
  yaw=35*Math::PI/180;b=slope*Math::PI/180
  transformed=source_loops.map{|ring|ring.map do |x,y,z|
   x*=mirror ? -1.2 : 1.2;y*=0.8
   yy=y*Math.cos(b)-z*Math.sin(b);zz=y*Math.sin(b)+z*Math.cos(b)
   [x*Math.cos(yaw)-yy*Math.sin(yaw)+50000,x*Math.sin(yaw)+yy*Math.cos(yaw)-30000,zz+10000]
  end}
  frame=SuPvRoofRegion.project(transformed);r=frame[:region]
  check(r[:outer].length==16,'Actual saved roof must retain its sixteen corners')
  [90,130,180,225,270].product([0,36,75]).each do |azimuth,tilt|
   settings={'azimuth'=>azimuth,'tilt'=>tilt,'gap_x_mm'=>100.0,'gap_y_mm'=>500.0}
   plan=SuPvArrayLayout.plan(frame[:width],frame[:height],frame.values_at(:u,:v,:normal),spec,settings,r)
   shape=SuPvRoofRegion.hull(plan['footprint'])
   plan['positions'].each do |x,y,z|
    polygon=shape.map{|px,py|[px+x,py+y]}
    check(independently_covered?(polygon,r),'Independent edge oracle found a panel over a concavity/hole')
    check(plan['unit_corners'].all?{|p|p[2]+z>=-1e-6},'Panel crosses its host plane')
    panels+=1
   end
   check(plan['count']>0,'The saved roof unexpectedly has no valid panels')
   cases+=1
  end
 end
end
# Concave roof with two independent holes: check that a real grid is filtered correctly.
shape=[[0,0],[30000,0],[30000,20000],[24000,20000],[24000,12000],[21000,12000],[21000,20000],[15000,20000],[15000,16000],[10000,16000],[10000,20000],[0,20000]]
holes=[[[4000,4000],[7000,4000],[7000,7000],[4000,7000]],[[16000,4000],[19500,4000],[19500,9000],[16000,9000]]]
r=SuPvRoofRegion.prepare([shape]+holes)
check((r[:area]-529500000.0).abs<1e-5,'Roof area excluding holes is wrong')
plan=SuPvArrayLayout.plan(r[:width],r[:height],[[1,0,0],[0,1,0],[0,0,1]],spec,{'azimuth'=>130,'tilt'=>36,'gap_x_mm'=>450,'gap_y_mm'=>850},r)
footprint=SuPvRoofRegion.hull(plan['footprint'])
check(plan['count']<plan['columns']*plan['rows'],'Voids did not remove any grid positions')
plan['positions'].each{|x,y,z|check(independently_covered?(footprint.map{|a,b|[a+x,b+y]},r),'A hole in the two-hole roof was covered')}
puts "#{cases} rotated/sloped/mirrored roof cases; #{panels} panels; notch bridges, enclosed holes, edge contact and two-hole grid passed."

# Explicit and inferred installation boundaries must produce identical positions.
rectangle=SuPvRoofRegion.prepare([[[0,0],[15000,0],[15000,10000],[0,10000]]])
[90,130,180,270].product([0,36,90]).each do |azimuth,tilt|
  settings={'azimuth'=>azimuth,'tilt'=>tilt,'gap_x_mm'=>450,'gap_y_mm'=>850}
  args=[15000,10000,[[1,0,0],[0,1,0],[0,0,1]],spec,settings]
  inferred=SuPvArrayLayout.plan(*args)
  explicit=SuPvArrayLayout.plan(*args,rectangle)
  check(explicit['positions']==inferred['positions'],'Explicit and inferred boundaries produced different layouts')
end
