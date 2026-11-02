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
  lowest=plan['unit_corners'].map { |p| p[2] }.min
  check(plan['positions'].all? { |p| (p[2]+lowest-100).abs<1e-7 },'Fitted board did not preserve the default 100 mm minimum clearance')
  transform=SuPvPanelTool.panel_transform(Geom::Point3d.new(0,0,0),plan['settings'])
  check(transform.axes[2].to_a.zip(frame[2]).all? { |a,b| (a-b).abs<1e-9 },'Generated component does not match the fitted roof normal')
end
# A north-facing roof must stay north-facing even if a payload requests south.
r=30*Math::PI/180
frame=[[1,0,0],[0,Math.cos(r),-Math.sin(r)],[0,Math.sin(r),Math.cos(r)]]
aligned=SuPvArrayLayout.plan(12000,8000,frame,spec,{'azimuth'=>180,'tilt'=>30,'gap_x_mm'=>100,'gap_y_mm'=>500})
check(aligned['settings']['azimuth']==0 && aligned['azimuth_locked'],'Sloped roof accepted the opposite azimuth')
check(aligned['unit_corners'].first(4).all? { |p| p[2].abs<1e-7 },'Minimum tilt is not coplanar on the north-facing roof')
limited=SuPvArrayLayout.plan(12000,8000,frame,spec,{'azimuth'=>180,'tilt'=>90,'gap_x_mm'=>100,'gap_y_mm'=>500})
check(limited['settings']['azimuth']==0 && limited['settings']['tilt']==90,'Slope-locked azimuth incorrectly locked the editable tilt')
[15,30,45,60,75].product((0..355).step(5).to_a).each do |slope,azimuth|
  r=slope*Math::PI/180;normal=[0,Math.sin(r),Math.cos(r)];bounds=SuPvRoofAngles.limits(normal,azimuth)
  next unless bounds['available']
  a,b=azimuth*Math::PI/180,bounds['max_tilt']*Math::PI/180
  panel=[Math.sin(b)*Math.sin(a),Math.sin(b)*Math.cos(a),Math.cos(b)]
  check(panel.zip(normal).inject(0.0){|sum,(p,n)|sum+p*n}>=-1e-9,'An allowed upper endpoint overturned the panel relative to the installation')
end
check(!SuPvRoofAngles.limits([0,Math.sin(Math::PI/3),Math.cos(Math::PI/3)],180)['available'],'Incompatible steep-roof bounds were not rejected')
check(SuPvPanelTool.energy_for(spec,151.2,27.4).nil?,'Untabulated fitted angles must not use a neighbouring forecast')
check(SuPvPanelTool.energy_for(spec,0,30)&.length==8760,'Delivered northern grid data is missing')
SuPvArrayTool.instance_variable_set(:@target_id,1)
SuPvArrayTool.instance_variable_set(:@params,{'model_id'=>spec[:id]})
angles,_=SuPvArrayTool.settings_from(JSON.generate({'target_id'=>1,'model_id'=>spec[:id],'azimuth'=>150,'tilt'=>27.4,'gap_x_mm'=>100,'gap_y_mm'=>500}))
check(angles['azimuth']==150 && angles['tilt']==27.4,'Array callback changed supported azimuth or actual roof tilt')
[151.2,359.2].each do |azimuth|
  rejected=false
  begin
    SuPvArrayTool.settings_from(JSON.generate({'target_id'=>1,'model_id'=>spec[:id],'azimuth'=>azimuth,'tilt'=>30,'gap_x_mm'=>100,'gap_y_mm'=>500}))
  rescue RuntimeError => error
    rejected=error.message.include?('步长1')
  end
  check(rejected,'Array callback accepted azimuth without lookup data')
end
check(SuPvArrayTool.data_azimuth(55)==55 && SuPvArrayTool.data_azimuth(315)==315 && SuPvArrayTool.data_azimuth(151.2)==151 && SuPvArrayTool.data_azimuth(360)==0,'Initial azimuth did not follow the complete one-degree grid')
angle=55*Math::PI/180;slope=30*Math::PI/180
normal=Geom::Vector3d.new(Math.sin(slope)*Math.sin(angle),Math.sin(slope)*Math.cos(angle),Math.cos(slope))
SuPvArrayTool.instance_variable_set(:@target,{normal:normal,flush_only:false})
locked,_=SuPvArrayTool.settings_from(JSON.generate({'target_id'=>1,'model_id'=>spec[:id],'azimuth'=>180,'tilt'=>45,'gap_x_mm'=>100,'gap_y_mm'=>500}))
check((locked['azimuth']-55).abs<1e-7 && locked['tilt']==45,'Sloped-roof callback did not preserve the actual aspect with editable tilt')
check(SuPvPanelTool.energy_for(spec,locked['azimuth'],locked['tilt'])&.length==8760,'Supported northern roof aspect lost delivered lookup data')
SuPvArrayTool.instance_variable_set(:@target,nil)
r=27.4*Math::PI/180
y=30*Math::PI/180
frame=[[Math.cos(y),Math.sin(y),0],[-Math.sin(y)*Math.cos(r),Math.cos(y)*Math.cos(r),Math.sin(r)],
  [Math.sin(y)*Math.sin(r),-Math.cos(y)*Math.sin(r),Math.cos(r)]]
plan=SuPvArrayLayout.plan(12000,8000,frame,spec,{'model_id'=>spec[:id],'azimuth'=>180,'tilt'=>0,'gap_x_mm'=>100,'gap_y_mm'=>500})
fixture_path=ENV['PV_ROOF_FIXTURE'] || File.expand_path('../output/checks/roof_fixture.json',__dir__)
begin
  roof=SuPvRoofAngles.limits(frame[2])
  fitted=SuPvArrayLayout.plan(12000,8000,frame,spec,plan['settings'].merge('azimuth'=>roof['azimuth_deg'],'tilt'=>roof['slope_deg']))
  fitted=fitted.merge('target_id'=>1,'request_id'=>0,'layout_only'=>false,'spec'=>spec,'catalog'=>SuPvPanelTool.panel_catalog,
    'prediction'=>SuPvArrayTool.prediction_for(fitted,spec))
  opposite_frame=[[1,0,0],[0,Math.cos(Math::PI/6),-Math.sin(Math::PI/6)],[0,Math.sin(Math::PI/6),Math.cos(Math::PI/6)]]
  opposing=SuPvArrayLayout.plan(12000,8000,opposite_frame,spec,plan['settings'].merge('azimuth'=>180,'tilt'=>30))
  opposing=opposing.merge('target_id'=>2,'request_id'=>0,'layout_only'=>false,'spec'=>spec,'catalog'=>SuPvPanelTool.panel_catalog,
    'prediction'=>SuPvArrayTool.prediction_for(opposing,spec))
  File.write(fixture_path,JSON.generate(plan.merge('target_id'=>1,'request_id'=>0,'layout_only'=>false,
    'spec'=>spec,'catalog'=>SuPvPanelTool.panel_catalog,'prediction'=>SuPvArrayTool.prediction_for(plan,spec),'fitted_plan'=>fitted,'opposing_plan'=>opposing)))
end
