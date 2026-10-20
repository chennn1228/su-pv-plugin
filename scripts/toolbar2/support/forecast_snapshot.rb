# encoding: UTF-8
# Pure numeric snapshot of actual panel instances; no model writes.
load File.expand_path('roof_angles.rb',__dir__)
module SuPvForecastSnapshot
  def self.build(panels)
    raise '请选择本插件生成的光伏板或阵列群组。' if panels.empty?
    raise '预测一次最多支持5000块板。' if panels.length > 5000
    first = panels.first
    spec = SuPvPanelTool.panel_spec(first.fetch('model_id'))
    axes = first.fetch('axes')
    u,v,n = axes
    valid_axes=axes.length==3 && axes.all? { |axis| axis.length==3 && axis.all? { |x| x.finite? } && (axis.inject(0.0) { |sum,x| sum+x*x }-1).abs<1e-6 }
    cross=[u[1]*v[2]-u[2]*v[1],u[2]*v[0]-u[0]*v[2],u[0]*v[1]-u[1]*v[0]]
    valid_axes &&= cross.zip(n).all? { |x,y| (x-y).abs<1e-6 } && u.zip(v).inject(0.0) { |sum,(x,y)| sum+x*y }.abs<1e-6
    raise '组件存在缩放或镜像，请使用原尺寸光伏板。' unless valid_axes
    tilt = Math.atan2(Math.sqrt(n[0]**2+n[1]**2),n[2])*180/Math::PI
    azimuth = ((tilt<1e-7 ? Math.atan2(u[1],-u[0]) : Math.atan2(n[0],n[1]))*180/Math::PI+360)%360
    azimuth=180.0 if tilt<1e-7 && ((azimuth/5).round*5-azimuth).abs>1e-4
    a,b = (azimuth / 5).round * 5, (tilt / 3).round * 3
    angles=(azimuth-a).abs<1e-7 && (tilt-b).abs<1e-7 ? {'azimuth'=>a,'tilt'=>b} : {'azimuth'=>azimuth,'tilt'=>tilt}
    settings = SuPvRoofAngles.validate_angles(angles).merge('model_id'=>spec[:id])
    expected = axes
    panels.each do |panel|
      raise '请选择同型号、同朝向的光伏阵列。' unless panel.fetch('model_id') == spec[:id]
      valid = panel.fetch('axes').flatten.zip(expected.flatten).all? { |x,y| x.finite? && (x-y).abs < 1e-6 }
      raise '组件存在缩放、镜像或不同朝向，请使用原尺寸、同朝向的光伏板。' unless valid
      raise '组件坐标无效。' unless panel.fetch('origin_mm').length == 3 && panel['origin_mm'].all?(&:finite?)
    end
    corners = [[0,0],[spec[:width_mm],0],[spec[:width_mm],spec[:length_mm]],[0,spec[:length_mm]]].map do |x,y|
      (0..2).map { |k| x*expected[0][k] + y*expected[1][k] }
    end
    world_corners = panels.flat_map { |p| corners.map { |c| c.zip(p['origin_mm']).map { |x,y| x+y } } }
    low = (0..2).map { |k| world_corners.map { |p| p[k] }.min }
    high = (0..2).map { |k| world_corners.map { |p| p[k] }.max }
    positions = panels.map { |p| p['origin_mm'].zip(low).map { |x,y| x-y } }
    { 'settings'=>settings, 'spec'=>spec, 'count'=>panels.length, 'positions'=>positions,
      'frame_axes'=>[[1,0,0],[0,1,0],[0,0,1]], 'panel_axes'=>axes, 'width_mm'=>[high[0]-low[0],1.0].max,
      'height_mm'=>[high[1]-low[1],1.0].max, 'capacity_kwp'=>spec[:power_w]*panels.length/1000.0,
      'forecast_only'=>true }
  end
end
