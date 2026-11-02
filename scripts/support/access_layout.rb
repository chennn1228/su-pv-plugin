# encoding: UTF-8
# Roof-plane millimetres. Exact distances to the physical panel footprint,
# boundary segments and round-ended corridor centrelines; no raster sampling.
module SuPvAccessLayout
  EPS = 1e-6 unless const_defined?(:EPS, false)
  def self.defaults
    {'edge_mm'=>0.0,'hole_mm'=>0.0,'width_mm'=>800.0,'span_mm'=>15000.0,'automatic'=>false,'entry'=>nil,'paths'=>[],'exclusions'=>[]}
  end
  def self.normalize(value)
    raise '通道参数格式无效。' unless value.nil? || value.is_a?(Hash)
    data=defaults.merge(value || {})
    result={}
    %w[edge_mm hole_mm width_mm span_mm].each do |key|
      x=data[key]
      raise '退让与通道宽度须为有限毫米数值。' unless x.is_a?(Numeric) && x.finite? && x>=0 && x<=1e6
      raise '通道净宽及分区尺度须大于零。' if %w[width_mm span_mm].include?(key) && x<=0
      result[key]=x.to_f
    end
    point=lambda do |p|
      raise '通道坐标无效。' unless p.is_a?(Array) && p.length==2 && p.all? { |x| x.is_a?(Numeric) && x.finite? && x.abs<=1e9 }
      p.map(&:to_f)
    end
    raise '自动通道参数无效。' unless [true,false].include?(data['automatic'])
    result['automatic']=data['automatic']
    result['entry']=data['entry'] && point.call(data['entry'])
    paths=data['paths'];rects=data['exclusions']
    raise '通道或禁布区数量过多。' unless paths.is_a?(Array) && paths.length<=50 && rects.is_a?(Array) && rects.length<=100
    result['paths']=paths.map do |path|
      raise '每条通道须有2至100个点。' unless path.is_a?(Array) && (2..100).cover?(path.length)
      vertices=path.map { |p| point.call(p) }
      raise '通道中有重合的相邻点。' if vertices.each_cons(2).any? { |a,b| Math.hypot(a[0]-b[0],a[1]-b[1])<EPS }
      vertices
    end
    raise '通道节点数量过多。' if result['paths'].inject(0) { |n,path| n+path.length }>500
    result['exclusions']=rects.map do |r|
      raise '禁布区坐标无效。' unless r.is_a?(Array) && r.length==4
      a,b=point.call(r[0,2]),point.call(r[2,2])
      xs=[a[0],b[0]].minmax;ys=[a[1],b[1]].minmax
      raise '禁布区须有实际面积。' if xs[1]-xs[0]<EPS || ys[1]-ys[0]<EPS
      [xs[0],ys[0],xs[1],ys[1]]
    end
    result
  end
  def self.active?(data)
    data['edge_mm']>0 || data['hole_mm']>0 || data['entry'] || !data['paths'].empty? || !data['exclusions'].empty?
  end
  def self.edges(ring)
    ring.each_with_index.map { |p,i| [p,ring[(i+1)%ring.length]] }
  end
  def self.point_distance(p,a,b)
    dx,dy=b[0]-a[0],b[1]-a[1];length=dx*dx+dy*dy
    t=length<EPS*EPS ? 0 : [[((p[0]-a[0])*dx+(p[1]-a[1])*dy)/length,0].max,1].min
    Math.hypot(p[0]-a[0]-t*dx,p[1]-a[1]-t*dy)
  end
  def self.segment_distance(a,b,c,d)
    cross=lambda { |p,q,r| (q[0]-p[0])*(r[1]-p[1])-(q[1]-p[1])*(r[0]-p[0]) }
    overlap=(0..1).all? { |i| [a[i],b[i]].max>=[c[i],d[i]].min && [c[i],d[i]].max>=[a[i],b[i]].min }
    return 0.0 if overlap && cross.call(a,b,c)*cross.call(a,b,d)<=0 && cross.call(c,d,a)*cross.call(c,d,b)<=0
    [point_distance(a,c,d),point_distance(b,c,d),point_distance(c,a,b),point_distance(d,a,b)].min
  end
  def self.contains?(point,polygon)
    return true if edges(polygon).any? { |a,b| point_distance(point,a,b)<=EPS }
    inside=false
    edges(polygon).each do |a,b|
      inside=!inside if (a[1]>point[1])!=(b[1]>point[1]) && point[0]<(b[0]-a[0])*(point[1]-a[1])/(b[1]-a[1])+a[0]
    end
    inside
  end
  def self.on_roof?(point,region)
    contains?(point,region[:outer]) && region[:holes].none? { |ring| contains?(point,ring) }
  end
  def self.polygon_segment_distance(polygon,a,b)
    return 0.0 if contains?(a,polygon) || contains?(b,polygon)
    edges(polygon).map { |c,d| segment_distance(a,b,c,d) }.min
  end
  def self.rectangle(r)
    [[r[0],r[1]],[r[2],r[1]],[r[2],r[3]],[r[0],r[3]]]
  end
  def self.bounds(points)
    xs,ys=points.map(&:first),points.map(&:last)
    [xs.min,ys.min,xs.max,ys.max]
  end
  def self.near_bounds?(a,b,padding=0)
    a[2]>=b[0]-padding && a[0]<=b[2]+padding && a[3]>=b[1]-padding && a[1]<=b[3]+padding
  end
  def self.nearest(p,a,b)
    dx,dy=b[0]-a[0],b[1]-a[1];l=dx*dx+dy*dy
    t=l<EPS ? 0 : [[((p[0]-a[0])*dx+(p[1]-a[1])*dy)/l,0].max,1].min
    [a[0]+t*dx,a[1]+t*dy]
  end
  def self.boundary_entry?(p,region)
    p && outer_distance(p,region)<=0.01 && on_roof?(p,region)
  end
  def self.outer_distance(p,region)
    edges(region[:outer]).map { |a,b| point_distance(p,a,b) }.min
  end
  # Only the short entrance connector may open onto its incident outer edges.
  # All other segments retain their full round-ended clear width on the roof.
  def self.safe_segment?(a,b,data,region,entrance=false)
    radius=data['width_mm']/2.0;entry=data['entry']
    return false unless on_roof?(a,region) && on_roof?(b,region)
    return false unless on_roof?([(a[0]+b[0])/2,(a[1]+b[1])/2],region)
    if entrance
      landing=[a,b].find { |p| !entry || Math.hypot(p[0]-entry[0],p[1]-entry[1])>EPS }
      return false unless landing && safe_segment?(landing,landing,data,region)
    end
    edges(region[:outer]).each do |c,d|
      next if entrance && entry && point_distance(entry,c,d)<=0.01
      return false if segment_distance(a,b,c,d)<radius-EPS
    end
    return false if region[:holes].any? { |ring| edges(ring).any? { |c,d| segment_distance(a,b,c,d)<radius-EPS } }
    return false if data['exclusions'].any? { |r| polygon_segment_distance(rectangle(r),a,b)<radius-EPS }
    true
  end
  def self.prepare(data,region)
    outer=edges(region[:outer]);holes=region[:holes].flat_map { |ring| edges(ring) }
    segments=data['paths'].flat_map.with_index { |path,i| path.each_cons(2).map { |a,b| [a,b,i] } }
    radius=data['width_mm']/2.0;errors=[]
    errors << '入口须位于屋面外边界或角点。' if data['entry'] && !boundary_entry?(data['entry'],region)
    errors << '入口不能位于禁布区内。' if data['entry'] && data['exclusions'].any? { |r| contains?(data['entry'],rectangle(r)) }
    errors << '请先选择屋面入口。' if data['automatic'] && !data['entry']
    unless data['paths'].empty?
      errors << '请先标记屋面入口位置。' unless data['entry']
      unsafe=segments.any? do |a,b,_|
        incident=data['entry'] && [a,b].any? { |p| Math.hypot(p[0]-data['entry'][0],p[1]-data['entry'][1])<=EPS }
        !safe_segment?(a,b,data,region,incident)
      end
      errors << '通道净宽不足或穿越孔洞、边界及禁布区，请调整路线或宽度。' if unsafe
      if data['entry']
        entry=data['entry']
        entry_safe=on_roof?(entry,region) && data['exclusions'].none? { |r| contains?(entry,rectangle(r)) }
        errors << '入口须位于屋面可通行区域内。' unless entry_safe
        reached=segments.filter_map { |a,b,i| i if point_distance(entry,a,b)<=radius+EPS }.uniq
        loop do
          added=segments.filter_map do |a,b,i|
            i if !reached.include?(i) && segments.any? { |c,d,j| reached.include?(j) && segment_distance(a,b,c,d)<=EPS }
          end.uniq
          break if added.empty?
          reached.concat(added)
        end
        errors << '有通道未连接入口，请将支路接到已有通道。' if reached.length<data['paths'].length
      end
    end
    {data:data,outer:outer,holes:holes,outer_boxes:outer.map { |a,b| bounds([a,b]) },hole_boxes:holes.map { |a,b| bounds([a,b]) },
     segments:segments,corridor_boxes:segments.map { |a,b,_| bounds([a,b]) },radius:radius,
     validation:{'valid'=>errors.empty?,'errors'=>errors}}
  end
  def self.allowed?(polygon,prepared)
    data=prepared[:data]
    box=bounds(polygon)
    [[prepared[:outer],prepared[:outer_boxes],data['edge_mm']],[prepared[:holes],prepared[:hole_boxes],data['hole_mm']]].each do |boundary,boxes,clearance|
      next if clearance<=0
      return false if boundary.each_with_index.any? { |(a,b),i| near_bounds?(box,boxes[i],clearance) && polygon_segment_distance(polygon,a,b)<clearance-EPS }
    end
    tolerance=[1e-5,SuPvRoofRegion.area(polygon)*1e-10].max
    return false if data['exclusions'].any? { |r| near_bounds?(box,r) && SuPvRoofRegion.clipped_area(polygon,r)>tolerance }
    clearance=data['hole_mm']
    return false if clearance>0 && data['exclusions'].any? do |r|
      near_bounds?(box,r,clearance) && edges(rectangle(r)).any? { |a,b| polygon_segment_distance(polygon,a,b)<clearance-EPS }
    end
    return false if prepared[:segments].each_with_index.any? { |(a,b,_),i| near_bounds?(box,prepared[:corridor_boxes][i],prepared[:radius]) && polygon_segment_distance(polygon,a,b)<prepared[:radius]-EPS }
    true
  end
end
