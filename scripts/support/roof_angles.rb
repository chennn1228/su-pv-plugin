# encoding: UTF-8
module SuPvRoofAngles
  def self.limits(normal, azimuth = nil)
    length=Math.sqrt(normal.inject(0.0) { |sum,x| sum+x*x })
    raise '屋面法向无效。' unless length.finite? && length>1e-9
    n=normal.map { |x| x/length }
    slope=Math.atan2(Math.sqrt(n[0]**2+n[1]**2),n[2])*180/Math::PI
    raise '请选择朝上的屋面。' if slope>90+1e-7
    slope=slope.round if (slope-slope.round).abs<1e-9
    aspect=(Math.atan2(n[0],n[1])*180/Math::PI+360)%360
    maximum=90.0
    if azimuth
      a=azimuth*Math::PI/180
      facing=n[0]*Math.sin(a)+n[1]*Math.cos(a)
      maximum=Math.atan2([n[2],0].max,-facing)*180/Math::PI if facing < -1e-9
    end
    maximum=maximum.round if (maximum-maximum.round).abs<1e-9
    { 'normal'=>n,'slope_deg'=>slope,'azimuth_deg'=>aspect,'min_tilt'=>slope,'max_tilt'=>maximum,
      'available'=>maximum+1e-7>=slope }
  end

  def self.validate_angles(data)
    a,b=data.values_at('azimuth','tilt')
    unless [a,b].all? { |v| v.is_a?(Numeric) && v.finite? } && (0..360).cover?(a) && (0..90).cover?(b)
      raise '方位角须为0—360°，板面倾角须为0—90°。'
    end
    { 'azimuth'=>a%360,'tilt'=>b }
  end
end
