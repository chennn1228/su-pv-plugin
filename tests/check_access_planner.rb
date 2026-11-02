# encoding: UTF-8
load File.expand_path('check_plugin.rb',__dir__)
spec=SuPvPanelTool.panel_spec('TSM-NE19R')
flat=[[1,0,0],[0,1,0],[0,0,1]]
settings={'model_id'=>spec[:id],'azimuth'=>180,'tilt'=>30,'gap_x_mm'=>100,'gap_y_mm'=>500}
outer=[[0,0],[44000,0],[44000,23000],[35000,23000],[35000,15000],[28000,15000],[28000,23000],[21000,23000],[21000,15000],[14000,15000],[14000,23000],[0,23000]]
hole=[[18000,4000],[23000,4000],[23000,8000],[18000,8000]]
region=SuPvRoofRegion.prepare([outer,hole])
config={'edge_mm'=>1000,'entry'=>[0,0],'width_mm'=>800,'exclusions'=>[[5000,5000,8000,8000]]}
base=SuPvArrayLayout.plan(44000,23000,flat,spec,settings.merge('access'=>config),region)
started=Process.clock_gettime(Process::CLOCK_MONOTONIC)
native_array_sum=Array.instance_method(:sum)
begin
  Array.send(:define_method,:sum) { |*_args,&_block| nil }
  trace={};access=SuPvAccessPlanner.plan(base,region,trace)
ensure
  Array.send(:define_method,:sum,native_array_sum)
end
final=SuPvArrayLayout.plan(44000,23000,flat,spec,settings.merge('access'=>access),region)
check(final['access_validation']['valid'],'Auto route must clear holes, exclusions and all boundary edges')
check(final['count']>0 && final['count']<base['count'],'Auto route must reserve physical corridor space')
check(access['paths'].length>2,'Large notched roof must serve multiple inspection subdivisions')
check(access['entry']==[0.0,0.0] && access['automatic'],'Corner entry or automatic mode lost')
check(trace['zones'].length>1 && trace['zones'].all? { |zone| SuPvAccessLayout.safe_segment?(zone['target_mm'],zone['target_mm'],access,region) },'Trace did not preserve the actual feasible subdivision access points')
check(trace['candidates'].length==2 && trace['candidates'].count { |c| c['selected'] }==1,'Candidate comparison trace is missing its selected result')
chosen=trace['candidates'].find { |c| c['selected'] }
check((chosen['length_mm']-access['paths'].sum { |line| line.each_cons(2).sum { |a,b| Math.hypot(a[0]-b[0],a[1]-b[1]) } }).abs<1e-6,'Trace length differs from the current route')
check(SuPvAccessLayout.normalize(access)==access,'Planner output exceeds canonical limits')
config['entry']=[22000,0];base2=SuPvArrayLayout.plan(44000,23000,flat,spec,settings.merge('access'=>config),region)
route2=SuPvAccessPlanner.plan(base2,region)
check(SuPvAccessLayout.prepare(route2,region)[:validation]['valid'],'Edge entry should connect through a full-width landing')
# A full-height obstacle disconnects a populated part: never silently omit it.
blocked=SuPvRoofRegion.prepare([[[0,0],[12000,0],[12000,8000],[0,8000]]])
b=SuPvArrayLayout.plan(12000,8000,flat,spec,settings.merge('access'=>{'entry'=>[0,4000],'exclusions'=>[[5500,0,6500,8000]]}),blocked)
begin
 SuPvAccessPlanner.plan(b,blocked);raise 'Disconnected inspection area accepted'
rescue RuntimeError=>e
 raise unless e.message.include?('无法从入口')
end
# Host transformation does not change native picker coordinates.
class Geom::Vector3d;def to_a;[x,y,z];end;end
class Geom::Point3d;def to_a;@coords;end;end
beta=30*Math::PI/180;alpha=37*Math::PI/180
u=[Math.cos(alpha),Math.sin(alpha),0]
v=[-Math.sin(alpha)*Math.cos(beta),Math.cos(alpha)*Math.cos(beta),Math.sin(beta)]
n=SuPvRoofRegion.cross(u,v)
target={origin:Geom::Point3d.new([31,52,17]),u:Geom::Vector3d.new(*u),v:Geom::Vector3d.new(*v),normal:Geom::Vector3d.new(*n)}
expected=[1632.4,5200.6];world=SuPvAccessPicker.world(expected,target).to_a
eye=world.each_with_index.map { |x,i| x+n[i]*100 }
actual=SuPvAccessPicker.local_ray(eye,n.map { |x| -x },target)
check(actual.zip(expected).all? { |a,b| (a-b).abs<1e-7 },'Rotated/sloped picking did not invert the actual roof frame')
rectangle=SuPvAccessLayout.rectangle([1000,2000,4000,6000]).map { |p| SuPvAccessPicker.world(p,target).to_a }
edges=rectangle.each_with_index.map { |p,i| rectangle[(i+1)%4].zip(p).map { |a,b| a-b } }
check(SuPvRoofRegion.dot(edges[0],edges[1]).abs<1e-7,'Native rectangle is not orthogonal on a pitched roof')
check(edges.all? { |e| SuPvRoofRegion.dot(e,n).abs<1e-7 },'Native rectangle left the selected roof plane')
check(SuPvAccessPicker.entry([100,3000],region)==[0,3000],'Entry did not snap to actual outer boundary')
check(!SuPvAccessLayout.prepare(SuPvAccessLayout.normalize({'entry'=>[1000,1000]}),region)[:validation]['valid'],'Interior entrance accepted')
fixture_path=ENV['PV_ACCESS_AUTO_FIXTURE'] || File.expand_path('../output/checks/access_auto_fixture.json',__dir__)
begin
 File.write(fixture_path,JSON.generate(final.merge('surface_kind'=>'roof','spec'=>spec,'catalog'=>SuPvPanelTool.panel_catalog,
 'prediction'=>SuPvArrayTool.prediction_for(final,spec),'target_id'=>8,'request_id'=>0,'access_trace'=>trace,'access_baseline_count'=>base['count'],'access_removed_count'=>base['count']-final['count'])))
end
File.write(File.expand_path('../output/checks/access_planner_result.json',__dir__),JSON.pretty_generate({baseline:base['count'],retained:final['count'],paths:access['paths'].length,seconds:Process.clock_gettime(Process::CLOCK_MONOTONIC)-started}))
