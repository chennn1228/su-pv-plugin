# encoding: UTF-8
load File.expand_path('check_plugin.rb',__dir__)
load File.expand_path('../scripts/support/forecast_snapshot.rb',__dir__)
def axes_for(a,b)
  a,b=a*Math::PI/180,b*Math::PI/180
  [[-Math.cos(a),Math.sin(a),0],[-Math.cos(b)*Math.sin(a),-Math.cos(b)*Math.cos(a),Math.sin(b)],
   [Math.sin(b)*Math.sin(a),Math.sin(b)*Math.cos(a),Math.cos(b)]]
end
cases=[]
SuPvPanelTool.panel_catalog.each_with_index do |spec,i|
  a,b=[[90,0],[130,36],[180,30],[235,60],[270,90]][i]
  values=SuPvPanelTool.energy_for(spec,a,b)
  check(values && values.length==8760,'Actual Ruby lookup did not return 8760 values')
  cases << {settings:{'model_id'=>spec[:id],'azimuth'=>a,'tilt'=>b},spec:spec,catalog:SuPvPanelTool.panel_catalog,
    values:values,annual_kwh:values.inject(0.0,:+)/1000.0,peak_wh:values.max}
end
spec=SuPvPanelTool.panel_spec('TSM-NE19R')
settings={'model_id'=>spec[:id],'azimuth'=>180,'tilt'=>30,'gap_x_mm'=>100,'gap_y_mm'=>500}
region=SuPvRoofRegion.prepare([[[0,0],[12000,0],[12000,8000],[0,8000]],[[4000,2000],[6000,2000],[6000,4000],[4000,4000]]])
plan=SuPvArrayLayout.plan(12000,8000,[[1,0,0],[0,1,0],[0,0,1]],spec,settings,region)
plan.merge!('surface_kind'=>'roof','spec'=>spec,'catalog'=>SuPvPanelTool.panel_catalog,'prediction'=>SuPvArrayTool.prediction_for(plan,spec),'target_id'=>1,'request_id'=>0)
# Fence: only the top edge is relaxed. All board bottoms stay on the fence bottom.
fence_frame=[[1,0,0],[0,0,1],[0,-1,0]]
fence_region=SuPvRoofRegion.prepare([[[0,0],[6000,0],[6000,1800],[0,1800]]])
fence=SuPvArrayLayout.plan(6000,1800,fence_frame,spec,settings.merge('tilt'=>90,'_flush'=>true,'_fence'=>true),fence_region).merge('surface_kind'=>'fence')
check(fence['count']>0 && fence['fence_overhang'],'Fence overheight panels were rejected')
check(fence['positions'].all? { |p| p[1].abs<1e-6 && p[0]>=-1e-6 && p[0]+spec[:width_mm]<=6000+1e-6 },'Fence bottom or side boundary was relaxed')
wall=SuPvArrayLayout.plan(6000,1800,fence_frame,spec,settings.merge('tilt'=>90,'_flush'=>true,'_fence'=>false),fence_region)
check(wall['count']==0,'Wall incorrectly inherited fence overhang')
# Mixed products/orientations retain individual lookup keys and their sum.
records=[{'model_id'=>'TSM-NE19R','origin_mm'=>[0,0,0],'axes'=>axes_for(180,30)},
 {'model_id'=>'RS-M072BZ','origin_mm'=>[3000,0,0],'axes'=>axes_for(130,36)}]
mixed=SuPvForecastSnapshot.build(records)
check(mixed['selection_summary'].length==2 && mixed['series'].length==2,'Mixed selection was collapsed to one model')
check(mixed['prediction'][:values].each_with_index.all? { |v,h| (v-mixed['series'].inject(0.0) { |sum,row| sum+row[h] }).abs<1e-9 },'Mixed forecast does not sum actual component outputs')
rotated=records.first.merge('axes'=>axes_for(131.2,27.4))
check(!SuPvForecastSnapshot.build([rotated])['prediction'][:data_available],'Off-grid orientations fabricated data')
bad=records.first.merge('axes'=>axes_for(180,30).map { |a| a.map { |v| v*2 } })
begin;SuPvForecastSnapshot.build([bad]);raise 'Scaled panel accepted';rescue RuntimeError=>e;raise unless e.message.include?('缩放');end
folder=File.expand_path('../output/checks',__dir__)
Dir.mkdir(folder) unless Dir.exist?(folder)
payload=lambda { |layout,panel,id,kind| layout.merge('surface_kind'=>kind,'spec'=>panel,'catalog'=>SuPvPanelTool.panel_catalog,'prediction'=>SuPvArrayTool.prediction_for(layout,panel),'target_id'=>id,'request_id'=>0) }
long_spec=SuPvPanelTool.panel_spec('S6-505')
long_region=SuPvRoofRegion.prepare([[[0,0],[70500,0],[70500,1800],[0,1800]]])
long_fence=SuPvArrayLayout.plan(70500,1800,[[-1,0,0],[0,0,1],[0,1,0]],long_spec,
 settings.merge('azimuth'=>0,'tilt'=>90,'_flush'=>true,'_fence'=>true),long_region)
wall_region=SuPvRoofRegion.prepare([[[0,0],[6000,0],[6000,3000],[0,3000]]])
visible_wall=SuPvArrayLayout.plan(6000,3000,fence_frame,spec,settings.merge('tilt'=>90,'_flush'=>true,'_fence'=>false),wall_region)
File.write("#{folder}/ruby_fixtures.json",JSON.generate({cases:cases,array:plan,fence:payload.call(fence,spec,2,'fence'),
 mixed:mixed.merge('catalog'=>SuPvPanelTool.panel_catalog,'target_id'=>3,'request_id'=>0),
 wall:payload.call(visible_wall,spec,4,'wall'),long_fence:payload.call(long_fence,long_spec,5,'fence')}))
