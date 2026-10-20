# encoding: UTF-8
load File.expand_path('check_plugin.rb',__dir__)
spec=SuPvPanelTool.panel_spec('TSM-NE19R')
[0,27,27.4,30,45,89.9].each do |slope|
  r=slope*Math::PI/180
  frame=[[1,0,0],[0,Math.cos(r),Math.sin(r)],[0,-Math.sin(r),Math.cos(r)]]
  limit=SuPvRoofAngles.limits(frame[2])
  check((limit['min_tilt']-slope).abs<1e-9 && limit['max_tilt']==90,'Roof-dependent angle bounds are wrong')
  plan=SuPvArrayLayout.plan(10000,8000,frame,spec,{'model_id'=>spec[:id],'azimuth'=>180,'tilt'=>0,'gap_x_mm'=>100,'gap_y_mm'=>500})
  check((plan['settings']['tilt']-slope).abs<1e-9,'Actual roof slope was rounded to a lookup angle')
  check(plan['settings']['azimuth']==180,'Changing tilt must not overwrite independent azimuth')
  check(plan['unit_corners'].all? { |c| c[2]+plan['positions'].first[2]>=-1e-7 },'Roof constraint removed collision protection') unless plan['positions'].empty?
end
# Fitting uses the actual world normal, including roof aspects outside the simulation grid.
[0,27.4,30,45].product([0,28.8,90,180,250]).each do |slope,yaw|
  r,y=slope*Math::PI/180,yaw*Math::PI/180
  frame=[[Math.cos(y),Math.sin(y),0],[-Math.sin(y)*Math.cos(r),Math.cos(y)*Math.cos(r),Math.sin(r)],
    [Math.sin(y)*Math.sin(r),-Math.cos(y)*Math.sin(r),Math.cos(r)]]
  limit=SuPvRoofAngles.limits(frame[2])
  params={'model_id'=>spec[:id],'azimuth'=>limit['azimuth_deg'],'tilt'=>limit['slope_deg'],'gap_x_mm'=>100,'gap_y_mm'=>500}
  plan=SuPvArrayLayout.plan(12000,8000,frame,spec,params)
  check(plan['unit_corners'].first(4).all? { |p| p[2].abs<1e-7 },'Fitted board underside is not coplanar with the installation face')
  check(plan['positions'].all? { |p| p[2].abs<1e-7 },'Fitted board was unnecessarily lifted off the roof')
  transform=SuPvPanelTool.panel_transform(Geom::Point3d.new(0,0,0),plan['settings'])
  check(transform.axes[2].to_a.zip(frame[2]).all? { |a,b| (a-b).abs<1e-9 },'Generated component does not match the fitted roof normal')
end
# Opposite aspects explain the reported 30-degree case; equal tilts alone are not a fit.
r=30*Math::PI/180
frame=[[1,0,0],[0,Math.cos(r),-Math.sin(r)],[0,Math.sin(r),Math.cos(r)]]
independent=SuPvArrayLayout.plan(12000,8000,frame,spec,{'azimuth'=>180,'tilt'=>30,'gap_x_mm'=>100,'gap_y_mm'=>500})
check(independent['settings']['azimuth']==180 && independent['unit_corners'].first(4).any? { |p| p[2].abs>1 },'Independent azimuth was silently forced to the roof aspect')
check(SuPvRoofAngles.limits(frame[2],180)['max_tilt']==60,'Opposing a 30-degree roof must limit absolute tilt to 60 degrees')
limited=SuPvArrayLayout.plan(12000,8000,frame,spec,{'azimuth'=>180,'tilt'=>90,'gap_x_mm'=>100,'gap_y_mm'=>500})
check(limited['settings']['tilt']==60,'The array planner exceeded the installation-normal limit')
[15,30,45,60,75].product((0..355).step(5).to_a).each do |slope,azimuth|
  r=slope*Math::PI/180;normal=[0,Math.sin(r),Math.cos(r)];bounds=SuPvRoofAngles.limits(normal,azimuth)
  next unless bounds['available']
  a,b=azimuth*Math::PI/180,bounds['max_tilt']*Math::PI/180
  panel=[Math.sin(b)*Math.sin(a),Math.sin(b)*Math.cos(a),Math.cos(b)]
  check(panel.zip(normal).inject(0.0){|sum,(p,n)|sum+p*n}>=-1e-9,'An allowed upper endpoint overturned the panel relative to the installation')
end
check(!SuPvRoofAngles.limits([0,Math.sin(Math::PI/3),Math.cos(Math::PI/3)],180)['available'],'Incompatible steep-roof bounds were not rejected')
check(SuPvPanelTool.energy_for(spec,151.2,27.4).nil?,'Untabulated fitted angles must not use a neighbouring forecast')
check(SuPvPanelTool1.energy_for(spec,0,30).nil?,'Out-of-range roof aspects must not borrow another azimuth')
SuPvArrayTool.instance_variable_set(:@target_id,1)
SuPvArrayTool.instance_variable_set(:@params,{'model_id'=>spec[:id]})
angles,_=SuPvArrayTool.settings_from(JSON.generate({'target_id'=>1,'model_id'=>spec[:id],'azimuth'=>151.2,'tilt'=>27.4,'gap_x_mm'=>100,'gap_y_mm'=>500}))
check(angles['azimuth']==151.2 && angles['tilt']==27.4,'Array callback rejected exact fitted angles')
r=27.4*Math::PI/180
y=28.8*Math::PI/180
frame=[[Math.cos(y),Math.sin(y),0],[-Math.sin(y)*Math.cos(r),Math.cos(y)*Math.cos(r),Math.sin(r)],
  [Math.sin(y)*Math.sin(r),-Math.cos(y)*Math.sin(r),Math.cos(r)]]
plan=SuPvArrayLayout.plan(12000,8000,frame,spec,{'model_id'=>spec[:id],'azimuth'=>180,'tilt'=>0,'gap_x_mm'=>100,'gap_y_mm'=>500})
if ENV['PV_ROOF_FIXTURE']
  roof=SuPvRoofAngles.limits(frame[2])
  fitted=SuPvArrayLayout.plan(12000,8000,frame,spec,plan['settings'].merge('azimuth'=>roof['azimuth_deg'],'tilt'=>roof['slope_deg']))
  fitted=fitted.merge('target_id'=>1,'request_id'=>0,'layout_only'=>false,'spec'=>spec,'catalog'=>SuPvPanelTool.panel_catalog,
    'prediction'=>SuPvArrayTool.prediction_for(fitted,spec))
  opposite_frame=[[1,0,0],[0,Math.cos(Math::PI/6),-Math.sin(Math::PI/6)],[0,Math.sin(Math::PI/6),Math.cos(Math::PI/6)]]
  opposing=SuPvArrayLayout.plan(12000,8000,opposite_frame,spec,plan['settings'].merge('azimuth'=>180,'tilt'=>30))
  opposing=opposing.merge('target_id'=>2,'request_id'=>0,'layout_only'=>false,'spec'=>spec,'catalog'=>SuPvPanelTool.panel_catalog,
    'prediction'=>SuPvArrayTool.prediction_for(opposing,spec))
  File.write(ENV['PV_ROOF_FIXTURE'],JSON.generate(plan.merge('target_id'=>1,'request_id'=>0,'layout_only'=>false,
    'spec'=>spec,'catalog'=>SuPvPanelTool.panel_catalog,'prediction'=>SuPvArrayTool.prediction_for(plan,spec),'fitted_plan'=>fitted,'opposing_plan'=>opposing)))
end
