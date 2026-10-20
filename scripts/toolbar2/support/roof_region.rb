# encoding: UTF-8
# Orthogonal roof regions in millimetres. Void rectangles form an exact partition
# of everything outside the roof but inside its bounding rectangle.
module SuPvRoofRegion
  EPS = 0.01 unless const_defined?(:EPS, false)

  def self.dot(a, b)
    a.zip(b).inject(0.0) { |sum, pair| sum + pair[0] * pair[1] }
  end

  def self.cross(a, b)
    [a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0]]
  end

  def self.unit(a)
    length = Math.sqrt(dot(a, a))
    raise '屋面存在退化边界。' if length < 1e-9
    a.map { |value| value / length }
  end

  # Derive the plane from transformed world points, including mirrored/scaled instances.
  def self.project(world_loops)
    outer = world_loops.first
    raise '请选择有完整外轮廓的屋面。' unless outer && outer.length >= 4
    base = outer.first
    u = unit(outer[1].zip(base).map { |a,b| a-b })
    normal = outer.drop(2).map { |p| cross(u, p.zip(base).map { |a,b| a-b }) }.
      find { |n| Math.sqrt(dot(n,n)) > EPS }
    raise '屋面外轮廓退化。' unless normal
    normal = unit(normal)
    normal = normal.map { |value| -value } if normal[2] < -1e-8
    v = unit(cross(normal, u))
    local = world_loops.map do |ring|
      ring.map do |point|
        d = point.zip(base).map { |a,b| a-b }
        raise '屋面边界不共面。' if dot(d,normal).abs > EPS
        [dot(d,u), dot(d,v)]
      end
    end
    min_x = local.first.map(&:first).min
    min_y = local.first.map(&:last).min
    local = local.map { |ring| ring.map { |x,y| [x-min_x,y-min_y] } }
    region = prepare(local)
    origin = (0..2).map { |i| base[i] + u[i]*min_x + v[i]*min_y }
    { origin: origin, u: u, v: v, normal: normal, region: region,
      width: region[:width], height: region[:height] }
  end

  def self.area(polygon)
    return 0.0 if polygon.length < 3
    polygon.each_with_index.inject(0.0) do |sum,(p,i)|
      q = polygon[(i+1)%polygon.length]
      sum + p[0]*q[1]-q[0]*p[1]
    end.abs / 2.0
  end

  def self.prepare(rings)
    raise '屋面轮廓缺失。' if rings.empty?
    # Snap only numerical noise; do not turn diagonal roof edges into right angles.
    coordinates = (0..1).map do |axis|
      rings.flatten(1).map { |p| Float(p[axis]) }.sort.each_with_object([]) do |value, values|
        raise '屋面坐标无效。' unless value.finite?
        values << value if values.empty? || value-values.last > EPS
      end
    end
    loops = rings.map do |ring|
      points = ring.map { |p| (0..1).map { |axis| coordinates[axis].min_by { |value| (value-p[axis]).abs } } }
      points = points.each_with_object([]) { |p,list| list << p if list.empty? || p != list.last }
      points.pop if points.first == points.last
      loop do
        remove = points.each_index.find do |i|
          a,b,c = points[(i-1)%points.length],points[i],points[(i+1)%points.length]
          (a[0]==b[0] && b[0]==c[0]) || (a[1]==b[1] && b[1]==c[1])
        end
        break unless remove && points.length > 3
        points.delete_at(remove)
      end
      raise '屋面轮廓不足四个有效顶点。' if points.length < 4
      points.each_with_index do |a,i|
        b = points[(i+1)%points.length]
        raise '安装面含有非正交边界，暂无法排布。' unless (a[0]==b[0]) != (a[1]==b[1])
      end
      points
    end
    raise '屋面局部原点必须位于外轮廓包围框左下角。' unless loops.first.map(&:first).min.abs <= EPS && loops.first.map(&:last).min.abs <= EPS
    width = loops.first.map(&:first).max
    height = loops.first.map(&:last).max
    raise '屋面尺寸过小。' unless width > EPS && height > EPS
    raise '孔洞超出屋面外轮廓范围。' unless loops.flatten(1).all? { |x,y| x>=-EPS && y>=-EPS && x<=width+EPS && y<=height+EPS }
    xs = loops.flatten(1).map(&:first).uniq.sort
    edges = loops.flat_map { |ring| ring.each_with_index.map { |p,i| [p,ring[(i+1)%ring.length]] } }
    solids, voids = [], []
    xs.each_cons(2) do |left,right|
      mid = (left+right)/2.0
      cuts = edges.filter_map do |a,b|
        a[1] if a[1]==b[1] && mid>[a[0],b[0]].min && mid<[a[0],b[0]].max
      end.sort
      raise '屋面轮廓相交或孔洞无效。' unless cuts.length.even?
      cursor = 0.0
      cuts.each_slice(2) do |bottom,top|
        voids << [left,cursor,right,bottom] if bottom-cursor > EPS
        solids << [left,bottom,right,top] if top-bottom > EPS
        cursor = top
      end
      voids << [left,cursor,right,height] if height-cursor > EPS
    end
    roof_area = area(loops.first)-loops.drop(1).inject(0.0) { |sum,ring| sum+area(ring) }
    tile_area = solids.inject(0.0) { |sum,r| sum+(r[2]-r[0])*(r[3]-r[1]) }
    raise '屋面轮廓或孔洞拓扑无效。' unless roof_area > EPS && (roof_area-tile_area).abs <= [0.01,roof_area*1e-9].max
    { outer: loops.first, holes: loops.drop(1), width: width, height: height,
      area: roof_area, voids: voids }
  end

  def self.hull(points)
    sorted = points.uniq.sort
    cross2 = lambda { |a,b,c| (b[0]-a[0])*(c[1]-a[1])-(b[1]-a[1])*(c[0]-a[0]) }
    lower,upper = [],[]
    [ [sorted,lower], [sorted.reverse,upper] ].each do |list,chain|
      list.each do |p|
        chain.pop while chain.length>=2 && cross2.call(chain[-2],chain[-1],p)<=1e-8
        chain << p
      end
    end
    lower[0...-1]+upper[0...-1]
  end

  # Sutherland-Hodgman clipping against an axis-aligned void rectangle.
  def self.clipped_area(polygon, rectangle)
    result = polygon
    [[0,rectangle[0],1],[0,rectangle[2],-1],[1,rectangle[1],1],[1,rectangle[3],-1]].each do |axis,bound,sign|
      return 0.0 if result.length < 3
      next_points = []
      previous = result.last
      previous_in = (previous[axis]-bound)*sign >= 0
      result.each do |point|
        inside = (point[axis]-bound)*sign >= 0
        if inside != previous_in
          t = (bound-previous[axis])/(point[axis]-previous[axis])
          next_points << [previous[0]+t*(point[0]-previous[0]),previous[1]+t*(point[1]-previous[1])]
        end
        next_points << point if inside
        previous,previous_in = point,inside
      end
      result = next_points
    end
    area(result)
  end

  def self.covered?(polygon, region)
    xs,ys = polygon.map(&:first),polygon.map(&:last)
    min_x,max_x,min_y,max_y = xs.min,xs.max,ys.min,ys.max
    return false if min_x < -1e-6 || min_y < -1e-6 || max_x > region[:width]+1e-6 || max_y > region[:height]+1e-6
    tolerance = [1e-5,area(polygon)*1e-10].max
    region[:voids].none? do |r|
      max_x>r[0] && min_x<r[2] && max_y>r[1] && min_y<r[3] && clipped_area(polygon,r)>tolerance
    end
  end
end
