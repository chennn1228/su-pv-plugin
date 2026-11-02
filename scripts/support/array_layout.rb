# encoding: UTF-8
# 纯数值阵列规划，全部长度使用毫米；不依赖 SketchUp API。
load File.expand_path('roof_region.rb', __dir__)
load File.expand_path('roof_angles.rb', __dir__)
load File.expand_path('access_layout.rb', __dir__)

module SuPvArrayLayout
  LIMIT = 5000 unless const_defined?(:LIMIT, false)
  def self.dot(a, b)
    a.zip(b).inject(0.0) { |sum, pair| sum + pair[0] * pair[1] }
  end

  # Candidate phases are deterministic and bounded; no global packing optimum
  # is claimed. The legacy centred grid is always included in the comparison.
  def self.phase_values(pitch,centred,events,limit)
    candidates=[centred,0.0,pitch/4,pitch/2,3*pitch/4]
    events.each { |value| candidates.concat([value,value-0.01,value+0.01]) }
    values=candidates.map { |value| value%pitch }.each_with_object([]) do |value,out|
      out<<value unless out.any? { |v| (v-value).abs<0.005 }
    end
    return values if values.length<=limit
    # Keep the baseline and evenly sample event alignments, so long lists of
    # vertices cannot crowd out every event near the end of the roof.
    fixed=values.first(2);rest=values.drop(2);slots=limit-fixed.length
    fixed+(0...slots).map { |i| rest[(i*(rest.length-1).to_f/[slots-1,1].max).round] }
  end

  def self.plan(width, height, frame, spec, settings, region = nil, options = {})
    optimize=options.fetch(:optimize,true);phase=options[:phase]
    access=SuPvAccessLayout.normalize(settings['access'])
    access_enabled=!settings['_flush'] && frame[2][2]>1e-6
    raise '通道与退让仅用于屋面。' if !access_enabled && SuPvAccessLayout.active?(access)
    access_region=region || SuPvRoofRegion.prepare([[[0,0],[width,0],[width,height],[0,height]]])
    access_plan=SuPvAccessLayout.prepare(access,access_region)
    settings=settings.merge('access'=>access)
    roof=SuPvRoofAngles.limits(frame[2])
    slope_locked=roof['slope_deg']>1e-7 && !settings['_flush']
    settings=settings.merge('azimuth'=>roof['azimuth_deg']) if slope_locked
    roof_angles=SuPvRoofAngles.limits(frame[2],settings.fetch('azimuth'))
    raise '当前方位角下没有可用倾角，请调整方位角或贴合屋面。' unless roof_angles['available']
    tilt=[[settings.fetch('tilt'),roof_angles['min_tilt']].max,roof_angles['max_tilt']].min
    settings=settings.merge('tilt'=>tilt)
    a = settings['azimuth'] * Math::PI / 180.0
    b = settings['tilt'] * Math::PI / 180.0
    axes = [[-Math.cos(a), Math.sin(a), 0.0],
            [-Math.cos(b) * Math.sin(a), -Math.cos(b) * Math.cos(a), Math.sin(b)],
            [Math.sin(b) * Math.sin(a), Math.sin(b) * Math.cos(a), Math.cos(b)]]
    axes = frame if settings['_flush']
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
    fence_overhang=settings['_fence'] && settings['_flush'] && footprint_h>height+1e-6
    usable_width=[width-2*access['edge_mm'],0].max
    usable_height=fence_overhang ? footprint_h : [height-2*access['edge_mm'],0].max
    max_gap_x = [0, ([footprint_w, usable_width - 2.0 * footprint_w].min / 10.0 + 1e-8).floor * 10].max
    max_gap_y = [0, ([footprint_h, usable_height - 2.0 * footprint_h].min / 10.0 + 1e-8).floor * 10].max
    gap_x = [[(settings['gap_x_mm'] / 10.0).round * 10, 0].max, max_gap_x].min
    gap_y = [[(settings['gap_y_mm'] / 10.0).round * 10, 0].max, max_gap_y].min
    settings = settings.merge('gap_x_mm' => gap_x, 'gap_y_mm' => gap_y)
    columns = [((usable_width + gap_x + 1e-7) / (footprint_w + gap_x)).floor,0].max
    rows = [((usable_height + gap_y + 1e-7) / (footprint_h + gap_y)).floor,0].max
    candidate_limit = region ? 50000 : LIMIT
    raise "候选网格超过#{candidate_limit}块，请增大间距或选择较小的面。" if columns * rows > candidate_limit
    footprint = SuPvRoofRegion.hull(corners.map { |p| p[0,2] })
    offset_x = (width - columns * footprint_w - [columns - 1, 0].max * gap_x) / 2.0
    offset_y = (usable_height - rows * footprint_h - [rows - 1, 0].max * gap_y) / 2.0 + access['edge_mm']
    pitch_x,pitch_y=footprint_w+gap_x,footprint_h+gap_y
    if phase
      offset_x=access['edge_mm']+phase[0]%pitch_x
      offset_y=access['edge_mm']+phase[1]%pitch_y
      columns=[((width-access['edge_mm']-footprint_w-offset_x+1e-7)/pitch_x).floor+1,0].max
      rows=[((height-access['edge_mm']-footprint_h-offset_y+1e-7)/pitch_y).floor+1,0].max
    end
    # 抬高到所有实体角点都在宿主平面正侧；法向位移不改变面内投影。
    clearance=Float(settings.fetch('clearance_mm',100))
    raise '组件最低净空须为100—500 mm。' unless clearance.finite? && clearance>=100 && clearance<=500
    settings=settings.merge('clearance_mm'=>clearance)
    lift = clearance-corners.map { |p| p[2] }.min
    positions = []
    rows.times do |row|
      columns.times do |column|
        x = offset_x + column * (footprint_w + gap_x) - min_x
        y = offset_y + row * (footprint_h + gap_y) - min_y
        inside = corners.all? do |p|
          px, py = x + p[0], y + p[1]
          px >= -1e-6 && px <= width + 1e-6 && py >= -1e-6 && py <= (fence_overhang ? footprint_h : height) + 1e-6
        end
        if inside && region
          polygon=footprint.map { |px,py| [px+x, fence_overhang ? [py+y,height].min : py+y] }
          inside = SuPvRoofRegion.covered?(polygon, region)
        end
        inside &&= SuPvAccessLayout.allowed?(footprint.map { |px,py| [px+x,py+y] },access_plan) if inside && SuPvAccessLayout.active?(access)
        positions << [x, y, lift] if inside
        raise "有效阵列超过#{LIMIT}块，请增大间距或选择较小的面。" if positions.length > LIMIT
      end
    end
    result = { 'positions' => positions, 'footprint' => corners.map { |p| p[0, 2] },
      'columns' => columns, 'rows' => rows, 'count' => positions.length,
      'width_mm' => width, 'height_mm' => height,
      'projected_width_mm' => footprint_w, 'projected_height_mm' => footprint_h,
      'gap_max_x_mm' => max_gap_x, 'gap_max_y_mm' => max_gap_y,
      'unit_corners' => corners, 'frame_axes' => frame, 'panel_axes'=>axes,
      'flush_only'=>!!settings['_flush'], 'azimuth_locked'=>slope_locked, 'fence_overhang'=>!!fence_overhang,
      'capacity_kwp' => positions.length * spec[:power_w] / 1000.0,
      'settings' => settings, 'roof_normal'=>roof_angles['normal'], 'roof_angles'=>roof_angles }
    result['grid_phase_mm']=[(offset_x-access['edge_mm'])%pitch_x,(offset_y-access['edge_mm'])%pitch_y]
    result['access_enabled']=access_enabled
    result['access_validation']=access_plan[:validation]
    if region
      result['boundary'] = { 'outer' => region[:outer], 'holes' => region[:holes] }
      result['surface_area_m2'] = region[:area] / 1_000_000.0
    end
    complex=(region && (region[:outer].length>4 || !region[:holes].empty?)) || !access['exclusions'].empty? || !access['paths'].empty?
    return result unless optimize && !phase && complex && !settings['_flush'] && columns>0 && rows>0
    events=[[],[]]
    [[access_region[:outer],access['edge_mm']],*access_region[:holes].map { |ring| [ring,access['hole_mm']] }].each do |ring,clearance|
      ring.each do |p|
        [footprint_w,footprint_h].each_with_index { |span,k| events[k].concat([p[k]-clearance,p[k]+clearance,p[k]-clearance-span,p[k]+clearance-span].map { |v| v-access['edge_mm'] }) }
      end
    end
    access['exclusions'].each do |rect|
      clearance=access['hole_mm']
      [footprint_w,footprint_h].each_with_index { |span,k| events[k].concat([rect[k]-clearance-span-access['edge_mm'],rect[k+2]+clearance-access['edge_mm']]) }
    end
    access['paths'].each do |path|
      path.each { |p| [footprint_w,footprint_h].each_with_index { |span,k| r=access['width_mm']/2;events[k].concat([p[k]-r-span-access['edge_mm'],p[k]+r-access['edge_mm']]) } }
    end
    limit=[14,[(30000.0/[columns*rows,1].max)**0.5,3].max.floor].min
    centred=result['grid_phase_mm'];phases=[pitch_x,pitch_y].each_with_index.map { |pitch,k| phase_values(pitch,centred[k],events[k],limit) }
    best=result;checked={};evaluated=1
    evaluate=lambda do |candidate_phase|
      key=candidate_phase.map { |v| (v*10000).round };next if checked[key]
      checked[key]=true
      candidate=plan(width,height,frame,spec,settings,region,optimize:false,phase:candidate_phase)
      evaluated+=1;best=candidate if candidate['count']>best['count']
    end
    phases[0].product(phases[1]).each { |p| evaluate.call(p) }
    # Refine locally without accumulating translations or changing panel pitch.
    if columns*rows*evaluated<60000
      origin=best['grid_phase_mm']
      [-1,0,1].product([-1,0,1]).each { |x,y| evaluate.call([(origin[0]+x*pitch_x/32)%pitch_x,(origin[1]+y*pitch_y/32)%pitch_y]) }
    end
    best.merge('layout_search'=>{'evaluated'=>evaluated,'centred_count'=>result['count'],'gain'=>best['count']-result['count'],'scope'=>'uniform_grid'})
  end
end
