# encoding: UTF-8
# 纯数值阵列规划，全部长度使用毫米；不依赖 SketchUp API。
load File.expand_path('roof_region.rb', __dir__)
load File.expand_path('roof_angles.rb', __dir__)

module SuPvArrayLayout
  LIMIT = 5000 unless const_defined?(:LIMIT, false)
  def self.dot(a, b)
    a.zip(b).inject(0.0) { |sum, pair| sum + pair[0] * pair[1] }
  end

  def self.plan(width, height, frame, spec, settings, region = nil)
    roof_angles=SuPvRoofAngles.limits(frame[2],settings.fetch('azimuth'))
    raise '当前方位角下没有可用倾角，请调整方位角或贴合屋面。' unless roof_angles['available']
    tilt=[[settings.fetch('tilt'),roof_angles['min_tilt']].max,roof_angles['max_tilt']].min
    settings=settings.merge('tilt'=>tilt)
    a = settings['azimuth'] * Math::PI / 180.0
    b = settings['tilt'] * Math::PI / 180.0
    axes = [[-Math.cos(a), Math.sin(a), 0.0],
            [-Math.cos(b) * Math.sin(a), -Math.cos(b) * Math.cos(a), Math.sin(b)],
            [Math.sin(b) * Math.sin(a), Math.sin(b) * Math.cos(a), Math.cos(b)]]
    corners = [0.0, spec[:thickness_mm]].flat_map do |z|
      [[0.0, 0.0, z], [spec[:width_mm], 0.0, z],
       [spec[:width_mm], spec[:length_mm], z], [0.0, spec[:length_mm], z]]
    end.map do |local|
      world = (0..2).map { |i| (0..2).inject(0.0) { |sum, j| sum + axes[j][i] * local[j] } }
      frame.map { |axis| dot(world, axis) }
    end
    min_x, max_x = corners.map { |p| p[0] }.minmax
    min_y, max_y = corners.map { |p| p[1] }.minmax
    footprint_w, footprint_h = max_x - min_x, max_y - min_y
    raise '组件投影退化，无法排布。' unless footprint_w > 1e-6 && footprint_h > 1e-6
    # Compact experiment range: at most one projected panel span,
    # also constrained by the room left for two panels. Quantize to 1 cm.
    # This is a UI/layout policy, not an engineering-standard spacing limit.
    max_gap_x = [0, ([footprint_w, width - 2.0 * footprint_w].min / 10.0 + 1e-8).floor * 10].max
    max_gap_y = [0, ([footprint_h, height - 2.0 * footprint_h].min / 10.0 + 1e-8).floor * 10].max
    gap_x = [[(settings['gap_x_mm'] / 10.0).round * 10, 0].max, max_gap_x].min
    gap_y = [[(settings['gap_y_mm'] / 10.0).round * 10, 0].max, max_gap_y].min
    settings = settings.merge('gap_x_mm' => gap_x, 'gap_y_mm' => gap_y)
    columns = ((width + gap_x + 1e-7) / (footprint_w + gap_x)).floor
    rows = ((height + gap_y + 1e-7) / (footprint_h + gap_y)).floor
    candidate_limit = region ? 50000 : LIMIT
    raise "候选网格超过#{candidate_limit}块，请增大间距或选择较小的面。" if columns * rows > candidate_limit
    footprint = region && SuPvRoofRegion.hull(corners.map { |p| p[0,2] })
    offset_x = (width - columns * footprint_w - [columns - 1, 0].max * gap_x) / 2.0
    offset_y = (height - rows * footprint_h - [rows - 1, 0].max * gap_y) / 2.0
    # 抬高到所有实体角点都在宿主平面正侧；法向位移不改变面内投影。
    lift = -corners.map { |p| p[2] }.min
    positions = []
    rows.times do |row|
      columns.times do |column|
        x = offset_x + column * (footprint_w + gap_x) - min_x
        y = offset_y + row * (footprint_h + gap_y) - min_y
        inside = corners.all? do |p|
          px, py = x + p[0], y + p[1]
          px >= -1e-6 && px <= width + 1e-6 && py >= -1e-6 && py <= height + 1e-6
        end
        if inside && region
          inside = SuPvRoofRegion.covered?(footprint.map { |px,py| [px+x,py+y] }, region)
        end
        positions << [x, y, lift] if inside
        raise "有效阵列超过#{LIMIT}块，请增大间距或选择较小的面。" if positions.length > LIMIT
      end
    end
    result = { 'positions' => positions, 'footprint' => corners.map { |p| p[0, 2] },
      'columns' => columns, 'rows' => rows, 'count' => positions.length,
      'width_mm' => width, 'height_mm' => height,
      'projected_width_mm' => footprint_w, 'projected_height_mm' => footprint_h,
      'gap_max_x_mm' => max_gap_x, 'gap_max_y_mm' => max_gap_y,
      'unit_corners' => corners, 'frame_axes' => frame,
      'capacity_kwp' => positions.length * spec[:power_w] / 1000.0,
      'settings' => settings, 'roof_normal'=>roof_angles['normal'], 'roof_angles'=>roof_angles }
    if region
      result['boundary'] = { 'outer' => region[:outer], 'holes' => region[:holes] }
      result['surface_area_m2'] = region[:area] / 1_000_000.0
    end
    result
  end
end
