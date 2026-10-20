# encoding: UTF-8
stdlib='C:/Program Files/SketchUp/SketchUp 2022/Tools/RubyStdLib'
$LOAD_PATH.unshift(stdlib,"#{stdlib}/platform_specific")
load File.expand_path('../scripts/toolbar2/support/flush_layout.rb',__dir__)
def check(value,message);raise message unless value;end
spec={width_mm:1134.0,length_mm:2382.0}
outer=[[0,0],[15000,0],[15000,9000],[10000,9000],[10000,6000],[8000,6000],[8000,9000],[0,9000]]
hole=[[4000,2000],[7000,2000],[7000,5000],[4000,5000]]
region=SuPvRoofRegion.prepare([outer,hole])
[false,true].each do |landscape|
  plan=SuPvFlushLayout.plan(15000,9000,region,spec,landscape,100,500,20)
  check(plan[:count]>0 && plan[:count]<plan[:columns]*plan[:rows],'Concavity and hole did not filter the grid')
  check(plan[:positions].all?{|p|p[2]==20},'Roof clearance changed')
  plan[:positions].each do |origin|
    polygon=[[0,0],[1134,0],[1134,2382],[0,2382]].map do |x,y|
      [origin[0]+x*plan[:axes][0][0]+y*plan[:axes][1][0],origin[1]+x*plan[:axes][0][1]+y*plan[:axes][1][1]]
    end
    check(SuPvRoofRegion.covered?(polygon,region),'A board crosses the roof edge/hole')
    # Independent test for this rectangular hole: positive XY overlap is forbidden.
    xs,ys=polygon.map(&:first),polygon.map(&:last)
    overlap_x=[xs.max,7000].min-[xs.min,4000].max
    overlap_y=[ys.max,5000].min-[ys.min,2000].max
    check(overlap_x<=1e-6 || overlap_y<=1e-6,'A board covers a roof hole')
  end
end
[[100.5,500,0],[-10,0,0],[0,Float::NAN,0],[10000,0,0]].each do |gx,gy,h|
  rejected=false
  begin;SuPvFlushLayout.plan(15000,9000,region,spec,false,gx,gy,h);rescue ArgumentError;rejected=true;end
  check(rejected,'Invalid native input accepted')
end
rectangle=SuPvRoofRegion.prepare([[[0,0],[5000,0],[5000,5000],[0,5000]]])
plain=SuPvFlushLayout.plan(5000,5000,rectangle,spec,false,0,0,0)
check(plain[:count]==8,'Plain roof packing count changed')
