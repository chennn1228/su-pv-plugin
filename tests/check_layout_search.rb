# encoding: UTF-8
load File.expand_path('check_plugin.rb',__dir__)
frame=[[1,0,0],[0,1,0],[0,0,1]]
spec={width_mm:1000.0,length_mm:2000.0,thickness_mm:30.0,power_w:400.0}
settings={'azimuth'=>180,'tilt'=>0,'gap_x_mm'=>0,'gap_y_mm'=>0,
 'access'=>{'exclusions'=>[[2000,0,2500,6500]]}}
region=SuPvRoofRegion.prepare([[[0,0],[6500,0],[6500,6500],[0,6500]]])
legacy=SuPvArrayLayout.plan(6500,6500,frame,spec,settings,region,optimize:false)
best=SuPvArrayLayout.plan(6500,6500,frame,spec,settings,region)
check(legacy['count']==12 && best['count']==15,'Known exclusion-strip example must recover three panels by grid translation')
check(best['layout_search']['gain']==3 && best['layout_search']['evaluated']>1,'Grid search did not expose its comparison basis')
check(SuPvArrayLayout.plan(6500,6500,frame,spec,best['settings'],region)['positions']==best['positions'],'Preview/build recomputation moved the winning phase')
check(best['settings']==legacy['settings'],'Origin search changed angles, pitch or reservation settings')
prepared=SuPvAccessLayout.prepare(best['settings']['access'],region)
best['positions'].each do |origin|
 polygon=SuPvRoofRegion.hull(best['footprint'].map { |p| [origin[0]+p[0],origin[1]+p[1]] })
 check(SuPvRoofRegion.covered?(polygon,region) && SuPvAccessLayout.allowed?(polygon,prepared),'Recovered board overlaps a boundary or forbidden region')
end
# A corridor comparison must use the same final grid, not independently
# optimized no-corridor and with-corridor layouts.
class Geom::Vector3d;def to_a;[x,y,z];end;end
target={width:10000,height:8000,u:Geom::Vector3d.new(1,0,0),v:Geom::Vector3d.new(0,1,0),normal:Geom::Vector3d.new(0,0,1),
 region:SuPvRoofRegion.prepare([[[0,0],[10000,0],[10000,8000],[0,8000]]]),kind:'roof',flush_only:false}
parameters={'model_id'=>'TSM-NE19R','azimuth'=>180,'tilt'=>0,'gap_x_mm'=>100,'gap_y_mm'=>500,
 'access'=>{'entry'=>[3000,0],'paths'=>[[[3000,0],[3000,500],[3000,7500]]],'exclusions'=>[[2000,1000,2500,6000]]}}
original=SuPvArrayTool.method(:validate_target)
begin
 SuPvArrayTool.define_singleton_method(:validate_target) { target }
 result=SuPvArrayTool.make_plan(parameters)
 without=result['settings'].merge('access'=>result['settings']['access'].merge('paths'=>[]))
 before=SuPvArrayLayout.plan(10000,8000,frame,SuPvPanelTool.panel_spec('TSM-NE19R'),without,target[:region],optimize:false,phase:result['grid_phase_mm'])
 check(result['access_baseline_count']==before['count'] && result['access_removed_count']==before['count']-result['count'],'Corridor-loss metric compares different grid phases')
 check(result['access_removed_count']>=0 && result['access_validation']['valid'],'Repacking broke corridor validity')
ensure
 SuPvArrayTool.define_singleton_method(:validate_target,original)
end
File.write(File.expand_path('../output/checks/layout_search_result.json',__dir__),JSON.pretty_generate({centred:legacy['count'],optimized:best['count'],gain:best['layout_search']['gain'],candidates:best['layout_search']['evaluated'],phase_mm:best['grid_phase_mm']}))
