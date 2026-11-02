# encoding: UTF-8
load File.expand_path('check_plugin.rb',__dir__)
settings={'azimuth'=>180,'tilt'=>30,'model_id'=>'TSM-NE19R','clearance_mm'=>100}
single=SuPvDesignRecommendations.panel(settings)
exact=SuPvPanelTool.energy_for(SuPvPanelTool.panel_spec, single['settings']['azimuth'],single['settings']['tilt']).sum/1000.0
check((single['annual_kwh']-exact).abs<1e-6,'Recommendation annual total differs from hourly CSV')
check(single['settings']['clearance_mm']==100,'Advice changed mounting clearance without an objective')
target={width:4000.0,height:5000.0,u:Geom::Vector3d.new(1,0,0),v:Geom::Vector3d.new(0,Math.sqrt(3)/2,0.5),normal:Geom::Vector3d.new(0,-0.5,Math.sqrt(3)/2),region:SuPvRoofRegion.prepare([[[0,0],[4000,0],[4000,5000],[0,5000]]])}
params=settings.merge('gap_x_mm'=>100,'gap_y_mm'=>500)
array=SuPvDesignRecommendations.array(params,target)
check(array['count']>0 && array['annual_kwh']>0,'Array advice is empty')
spec=SuPvPanelTool.panel_spec
plan=SuPvArrayLayout.plan(target[:width],target[:height],target.values_at(:u,:v,:normal).map(&:to_a),spec,array['settings'],target[:region],optimize:false)
check(plan['count']==array['count'],'Advice used a different layout from its stated centred-grid objective')
target[:v]=Geom::Vector3d.new(0,Math.sqrt(3)/2,-0.5)
target[:normal]=Geom::Vector3d.new(0,0.5,Math.sqrt(3)/2)
north=SuPvDesignRecommendations.array(params,target)
check(north['settings']['azimuth']==0 && north['annual_kwh']>0,'Delivered northern data was not available to design advice')
puts 'CSV annual optimum, array objective, preserved clearance and full-azimuth recommendations passed.'
