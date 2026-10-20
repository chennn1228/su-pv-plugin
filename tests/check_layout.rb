# encoding: UTF-8
stdlib = 'C:/Program Files/SketchUp/SketchUp 2022/Tools/RubyStdLib'
$LOAD_PATH.unshift(stdlib, "#{stdlib}/platform_specific")
require 'json'
root = File.expand_path('..', __dir__)
Dir.glob("#{root}/scripts/**/*.rb").each { |file| RubyVM::InstructionSequence.compile_file(file) }
load "#{root}/scripts/toolbar2/support/array_layout.rb"
def check(condition, message)
  raise message unless condition
end
spec = {model: 'TSM-NE19R', manufacturer: '天合光能', power_w: 630.0,
        width_mm: 1134.0, length_mm: 2382.0, thickness_mm: 30.0}
flat = [[1.0,0.0,0.0],[0.0,1.0,0.0],[0.0,0.0,1.0]]
settings = {'azimuth'=>180,'tilt'=>0,'gap_x_mm'=>100.0,'gap_y_mm'=>500.0}
plan = SuPvArrayLayout.plan(10000.0,8000.0,flat,spec,settings)
check(plan['count']==16 && plan['columns']==8 && plan['rows']==2,'Known flat roof layout must be 8x2')
exact = SuPvArrayLayout.plan(2368.0,5264.0,flat,spec,settings)
check(exact['count']==4,'Exact boundary fit must keep four panels')
small = SuPvArrayLayout.plan(1000.0,2000.0,flat,spec,settings)
check(small['count']==0,'A panel larger than the host must not be placed')
c=Math.cos(Math::PI/4);s=Math.sin(Math::PI/4)
frames=[flat,[[1.0,0.0,0.0],[0.0,c,s],[0.0,-s,c]],[[1.0,0.0,0.0],[0.0,0.0,1.0],[0.0,-1.0,0.0]]]
cases=0
frames.each do |frame|
 (90..270).step(5) do |a|
  (0..90).step(3) do |b|
   params=settings.merge('azimuth'=>a,'tilt'=>b)
   p=SuPvArrayLayout.plan(10000.0,8000.0,frame,spec,params)
   # Independently rotate the eight physical box corners with Rx then Rz.
   theta=(180-a)*Math::PI/180.0;beta=p['settings']['tilt']*Math::PI/180.0
   co,si,cb,sb=Math.cos(theta),Math.sin(theta),Math.cos(beta),Math.sin(beta)
   corners=[0.0,1134.0].product([0.0,2382.0],[0.0,30.0]).map do |x,y,z|
    ry,rz=cb*y-sb*z,sb*y+cb*z
    world=[co*x-si*ry,si*x+co*ry,rz]
    frame.map{|axis| axis.zip(world).inject(0.0){|sum,v|sum+v[0]*v[1]}}
   end
   p['positions'].each do |origin|
    corners.each do |corner|
     x,y,z=origin.zip(corner).map{|o,q|o+q}
     check(x>=-1e-5 && x<=10000.0+1e-5 && y>=-1e-5 && y<=8000.0+1e-5,'Projection outside rectangle')
     check(z>=-1e-5,'Panel intersects the host plane')
    end
   end
   check((p['capacity_kwp']-p['count']*0.63).abs<1e-8,'Capacity mismatch')
   cases+=1
  end
 end
end
# Gap bounds must be finite, depend on the true footprint, and retain two panels at the upper limit.
wide=SuPvArrayLayout.plan(10000.0,8000.0,flat,spec,settings.merge('gap_x_mm'=>999999.0,'gap_y_mm'=>999999.0))
check(wide['columns']>=2 && wide['rows']>=2,'Upper gap limit must retain two rows/columns')
check(wide['settings']['gap_x_mm']==wide['gap_max_x_mm'],'Gap X was not clamped to its footprint bound')
check(wide['gap_max_x_mm']==1130 && wide['gap_max_y_mm']==2380,'Known footprint-dependent bounds mismatch')
single=SuPvArrayLayout.plan(1800.0,3000.0,flat,spec,settings)
check(single['columns']==1 && single['rows']==1 && single['gap_max_x_mm']==0 && single['gap_max_y_mm']==0,'Single row/column spacing must be inapplicable')
puts "Ruby syntax and #{cases} world-coordinate layout checks passed."
