# encoding: UTF-8
load File.expand_path('check_plugin.rb',__dir__)
spec=SuPvPanelTool.panel_spec('TSM-NE19R')
flat=[[1,0,0],[0,1,0],[0,0,1]]
settings={'model_id'=>spec[:id],'azimuth'=>180,'tilt'=>0,'gap_x_mm'=>100,'gap_y_mm'=>500}
outer=[[0,0],[10000,0],[10000,8000],[0,8000]]
region=SuPvRoofRegion.prepare([outer])
base=SuPvArrayLayout.plan(10000,8000,flat,spec,settings,region)
check(base['count']==16 && base['access_validation']['valid'],'Default reservations changed the previous layout')
edge=SuPvArrayLayout.plan(10000,8000,flat,spec,settings.merge('access'=>{'edge_mm'=>500}),region)
check(edge['count']==14,'A setback should repack the usable bounding rectangle')
edge['positions'].each do |origin|
 edge['unit_corners'].each do |p|
  x,y=origin[0]+p[0],origin[1]+p[1]
  check(x>=500-1e-6 && x<=9500+1e-6 && y>=500-1e-6 && y<=7500+1e-6,'Setback did not clear all physical box corners')
 end
end
cfg={'entry'=>[5000,0],'paths'=>[[[5000,0],[5000,1000],[5000,7000]]]}
corridor=SuPvArrayLayout.plan(10000,8000,flat,spec,settings.merge('access'=>cfg),region)
check(corridor['access_validation']['valid'] && corridor['count']<base['count'],'A connected corridor was not applied')
corridor['positions'].each do |origin|
 xs=corridor['unit_corners'].map { |p| p[0]+origin[0] }
 check(xs.max<=4600+1e-6 || xs.min>=5400-1e-6,'A panel intrudes into the 800 mm corridor')
end
check(SuPvArrayLayout.plan(10000,8000,flat,spec,settings.merge('access'=>cfg.merge('paths'=>cfg['paths']*2)),region)['count']==corridor['count'],'Overlapping corridors removed area twice')
excluded=SuPvArrayLayout.plan(10000,8000,flat,spec,settings.merge('access'=>{'exclusions'=>[[0,0,5000,8000]]}),region)
check(excluded['count']==8,'Manual exclusion did not remove exactly half the known array')
# Internal setbacks apply equally to geometric holes and user-drawn exclusion
# boundaries; changing clearance never changes the physical exclusion rectangle.
rect=[4000,3000,6000,5000]
internal_plans=[0,300,1200].map do |clearance|
 layout=SuPvArrayLayout.plan(10000,8000,flat,spec,settings.merge('access'=>{'hole_mm'=>clearance,'exclusions'=>[rect]}),region)
 layout['positions'].each do |origin|
  polygon=SuPvRoofRegion.hull(layout['footprint'].map { |x,y| [x+origin[0],y+origin[1]] })
  distance=SuPvAccessLayout.edges(SuPvAccessLayout.rectangle(rect)).map { |a,b| SuPvAccessLayout.polygon_segment_distance(polygon,a,b) }.min
  check(distance>=clearance-1e-6,'Panel intruded into exclusion setback')
 end
 check(layout['settings']['access']['exclusions']==[rect],'Setback mutated the physical exclusion')
 layout
end
check(internal_plans.last['count']<internal_plans.first['count'],'Increasing the exclusion setback left the layout unchanged')
hole=[[4000,3000],[6000,3000],[6000,5000],[4000,5000]]
holed=SuPvRoofRegion.prepare([outer,hole])
hole_plan=SuPvArrayLayout.plan(10000,8000,flat,spec,settings.merge('access'=>{'hole_mm'=>500}),holed)
hole_plan['positions'].each do |origin|
 xs=hole_plan['unit_corners'].map { |p| p[0]+origin[0] };ys=hole_plan['unit_corners'].map { |p| p[1]+origin[1] }
 dx=[4000-xs.max,xs.min-6000,0].max;dy=[3000-ys.max,ys.min-5000,0].max
 check(Math.hypot(dx,dy)>=500-1e-6,'Hole setback is smaller than its requested physical clearance')
end
def access_check(cfg,region)
 SuPvAccessLayout.prepare(SuPvAccessLayout.normalize(cfg),region)[:validation]
end
check(!access_check({'paths'=>cfg['paths']},region)['valid'],'A corridor without an entrance was accepted')
check(!access_check(cfg.merge('paths'=>cfg['paths']+[[[8000,1000],[8000,7000]]]),region)['valid'],'An isolated branch was accepted')
check(access_check(cfg.merge('paths'=>cfg['paths']+[[[2000,4000],[8000,4000]]]),region)['valid'],'Intersecting corridor centrelines should connect')
check(!access_check(cfg,holed)['valid'],'A corridor crossing a hole was accepted')
check(!access_check(cfg.merge('paths'=>[[[100,1000],[100,7000]]]),region)['valid'],'The corridor width extends off the roof')
check(!access_check(cfg.merge('exclusions'=>[[4500,2000,5500,4000]]),region)['valid'],'A corridor crossing a forbidden equipment area was accepted')
# Exact round ends: retain a diagonal panel outside the radius even though its
# bounding box intersects the corridor bounding box; reject actual cap intrusion.
rounded=SuPvAccessLayout.prepare(SuPvAccessLayout.normalize({'entry'=>[1000,1000],'paths'=>[[[1000,1000],[2000,1000]]]}),region)
check(SuPvAccessLayout.allowed?([[2300,1300],[2500,1300],[2500,1500],[2300,1500]],rounded),'Corridor was approximated by its bounding rectangle')
check(!SuPvAccessLayout.allowed?([[2300,900],[2500,900],[2500,1100],[2300,1100]],rounded),'The end of a corridor did not reserve its full radius')
check(SuPvAccessLayout.allowed?([[2400,900],[2500,900],[2500,1100],[2400,1100]],rounded),'Exact clearance contact should remain valid')
%w[edge_mm hole_mm width_mm].each do |key|
 [Float::NAN,Float::INFINITY,-1,'800'].each do |value|
  begin;SuPvAccessLayout.normalize({key=>value});raise 'Invalid access input accepted';rescue RuntimeError=>e;raise if e.message=='Invalid access input accepted';end
 end
end
begin;SuPvAccessLayout.normalize({'paths'=>Array.new(51) { [[0,0],[1,1]] }});raise 'Too many routes accepted';rescue RuntimeError=>e;raise if e.message=='Too many routes accepted';end
# Reservations are invariant under a rigid world rotation of a pitched roof.
beta=30*Math::PI/180
frame=[[1,0,0],[0,Math.cos(beta),Math.sin(beta)],[0,-Math.sin(beta),Math.cos(beta)]]
slope=SuPvArrayLayout.plan(10000,8000,frame,spec,settings.merge('tilt'=>30,'access'=>cfg),region)
check(slope['access_validation']['valid'],'A valid corridor on a pitched roof was rejected')
frame2=frame.map { |p| [-p[1],p[0],p[2]] }
rotated=SuPvArrayLayout.plan(10000,8000,frame2,spec,settings.merge('tilt'=>30,'access'=>cfg),region)
check(rotated['count']==slope['count'],'World azimuth changed roof-plane reservation distances')
check(JSON.parse(JSON.generate(corridor['settings']))['access']==corridor['settings']['access'],'Saved scheme lost its reservations')
# Native build must reject disconnected routes before starting a model operation,
# even when a caller bypasses the disabled HTML button.
native_model=FakeModel.new(nil)
SuPvArrayTool.instance_variable_set(:@model,native_model)
SuPvArrayTool.instance_variable_set(:@target,nil)
SuPvArrayTool.instance_variable_set(:@target_id,77)
SuPvArrayTool.instance_variable_set(:@params,settings)
original_plan=SuPvArrayTool.method(:make_plan);original_failure=SuPvArrayTool.method(:fail_ui);failures=[]
begin
 SuPvArrayTool.define_singleton_method(:make_plan) { |params| corridor.merge('settings'=>params,'access_validation'=>{'valid'=>false,'errors'=>['有通道未连接入口']}) }
 SuPvArrayTool.define_singleton_method(:fail_ui) { |error| failures << error.message }
 SuPvArrayTool.build(JSON.generate(settings.merge('target_id'=>77,'access'=>cfg)))
 check(native_model.operations.empty? && failures==['有通道未连接入口'],'Native build bypassed corridor validation')
ensure
 SuPvArrayTool.define_singleton_method(:make_plan,original_plan)
 SuPvArrayTool.define_singleton_method(:fail_ui,original_failure)
end
fixture_path=ENV['PV_ACCESS_FIXTURE'] || File.expand_path('../output/checks/access_fixtures.json',__dir__)
begin
 fixture=lambda do |config,id|
  layout=SuPvArrayLayout.plan(10000,8000,flat,spec,settings.merge('tilt'=>30,'access'=>config),region)
  layout.merge('surface_kind'=>'roof','spec'=>spec,'catalog'=>SuPvPanelTool.panel_catalog,
    'prediction'=>SuPvArrayTool.prediction_for(layout,spec),'target_id'=>id,'request_id'=>0)
 end
 File.write(fixture_path,JSON.generate({'base'=>fixture.call({},1),'connected'=>fixture.call(cfg,1),
  'disconnected'=>fixture.call(cfg.merge('paths'=>cfg['paths']+[[[8000,1000],[8000,7000]]]),1),
  'setback'=>fixture.call({'edge_mm'=>500,'hole_mm'=>300},2),
  'combined'=>fixture.call(cfg.merge('exclusions'=>[[1000,1000,3000,2500]]),1),
  'slope'=>slope.merge('surface_kind'=>'roof','spec'=>spec,'catalog'=>SuPvPanelTool.panel_catalog,'prediction'=>SuPvArrayTool.prediction_for(slope,spec),'target_id'=>3,'request_id'=>0)}))
end
puts 'Access layout verified: setbacks, holes, exact round corridors, connectivity, exclusions, rigid transforms and input validation.'
