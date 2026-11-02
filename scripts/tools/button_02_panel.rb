# encoding: UTF-8
# 多型号组件建模、绝对角度控制；仅有对应时序数据的型号显示出力。
# 单板放置与出力集成界面。
require 'sketchup.rb'
require 'csv'
require 'json'
load File.expand_path('../support/generation_export.rb', __dir__)
load File.expand_path('../support/mounting.rb', __dir__)
load File.expand_path('../support/design_recommendations.rb', __dir__)
load File.expand_path('../support/electrical_presets.rb', __dir__)

module SuPvPanelTool
  def self.project_path(relative)
    File.expand_path("../../#{relative}", __dir__)
  end

  # The CSV owns panel identity/geometry; the bundled data index owns time-series availability.
  def self.panel_catalog
    bytes = File.binread(project_path('data/PV panel.csv'))
    text = bytes.dup.force_encoding('UTF-8')
    text = bytes.force_encoding('GB18030').encode('UTF-8') unless text.valid_encoding?
    rows = CSV.parse(text.sub(/\A\uFEFF/, ''), headers: true, skip_blanks: true)
    active_ids = generation_index.fetch('models', {}).keys
    rows.delete_if { |row| !active_ids.include?(row['型号'].to_s.strip) }
    specs = rows.map do |row|
      size = /\A(\d+(?:\.\d+)?)\s*[×xX*]\s*(\d+(?:\.\d+)?)\s*[×xX*]\s*(\d+(?:\.\d+)?)\s*mm\z/i.match(row['尺寸'].to_s.strip)
      raise "组件尺寸格式不正确：#{row['型号']}" unless size
      dimensions = size.captures.map { |v| Float(v) }
      power = Float(row['STC-Pmax(W)'])
      id = row['型号'].to_s.strip
      raise '型号不能为空，尺寸和功率须为正数。' if id.empty? || !dimensions.all? { |v| v.finite? && v > 0 } || !power.finite? || power <= 0
      entry = generation_index.fetch('models', {})[id]
      available = entry && entry['manufacturer'] == row['生产商'] && entry['power_w'] == power && entry['dimensions_mm'] == dimensions &&
        File.file?(generation_path(entry['hourly'])) && File.file?(generation_path(entry['monthly_hourly']))
      { id: id, model: id, manufacturer: row['生产商'], material: row['材料'], type: row['类型'], efficiency_pct: Float(row['组件效率(%)']), power_w: power,
        length_mm: dimensions[0], width_mm: dimensions[1], thickness_mm: dimensions[2], data_available: !!available,
        electrical: {'vmp'=>Float(row['Vmpp(V)']), 'imp'=>Float(row['Impp(A)']), 'voc'=>Float(row['Voc(V)']), 'isc'=>Float(row['Isc(A)']), 'gamma_p'=>Float(row['Pmax-温度系数(%/℃)'])} }
    end
    raise '当前板型索引没有可用组件，或型号重复。' if specs.empty? || specs.map { |spec| spec[:id] }.uniq.length != specs.length
    specs.each do |spec|
      spec[:electrical]=SuPvElectricalPresets.for_spec(spec)[:module_values]
    end
    specs
  end

  def self.panel_spec(id = nil)
    id ||= settings['model_id'] || 'TSM-NE19R'
    panel_catalog.find { |spec| spec[:id] == id } || (raise "没有此组件型号：#{id}")
  end

  def self.generation_index
    path = File.join(generation_root, 'index.json')
    return {} unless File.file?(path)
    stamp = [path, File.size(path), File.mtime(path).to_f]
    if @generation_stamp != stamp
      data = JSON.parse(File.read(path, encoding: 'UTF-8'))
      raise '内置出力索引格式不正确。' unless data['schema'] == 1 && data['unit'] == 'Wh' && data['models'].is_a?(Hash) &&
        data['angle_grid'] == {'azimuth_min'=>0,'azimuth_max'=>359,'azimuth_step'=>1,'tilt_min'=>0,'tilt_max'=>90,'tilt_step'=>1}
      @generation_index, @generation_stamp = data, stamp
    end
    @generation_index
  end

  def self.generation_root
    project_path('data/pv_generation/stride_1-1')
  end

  def self.generation_angles
    (0..359).flat_map { |a| (0..90).map { |b| [a,b] } }
  end

  def self.generation_path(relative)
    raise '内置数据路径缺失。' unless relative.is_a?(String) && !relative.empty?
    root = generation_root
    path = File.expand_path(relative, root)
    raise '内置数据路径超出数据目录。' unless path.start_with?(root + '/')
    path
  end

  def self.energy_for(spec, azimuth, tilt)
    return nil unless spec[:data_available]
    return nil unless [azimuth,tilt].all? { |v| v.is_a?(Numeric) && v.finite? }
    actual=azimuth%360
    a,b=actual.round,tilt.round
    return nil unless (0..90).cover?(b) && (actual-a).abs<1e-7 && (tilt-b).abs<1e-7
    a%=360
    energy_row(a,b,spec)
  end

  # Only describe a lookup that has already failed; orientation does not ban installation.
  def self.missing_data_message(azimuth)
    '暂无出力数据'
  end

  def self.energy_path(spec = nil)
    spec ||= panel_spec
    entry = generation_index.fetch('models', {})[spec[:id]]
    raise "#{spec[:model]} 暂无出力数据。" unless entry
    generation_path(entry['hourly'])
  end

  # Cache row offsets by dataset, and include dataset identity in every numeric cache key.
  def self.prepare_index(spec)
    path = energy_path(spec)
    raise "找不到内置出力数据：#{path}" unless File.file?(path)
    entry=generation_index.fetch('models').fetch(spec[:id])
    sidecar=generation_path(entry.fetch('row_index'))
    raise '找不到出力行位置索引，请重新合并数据。' unless File.file?(sidecar)
    csv_bytes=File.size(path)
    stamp = [csv_bytes, File.mtime(path).to_f, File.size(sidecar), File.mtime(sidecar).to_f]
    @row_indexes ||= {}
    cached = @row_indexes[path]
    return cached if cached && cached[:stamp] == stamp
    data=JSON.parse(File.read(sidecar,encoding:'UTF-8'))
    rows=data['rows']
    raise '出力行位置索引与CSV不匹配。' unless data['schema']==1 && data['csv_bytes']==csv_bytes &&
      data['csv_sha256']==entry['hourly_sha256'] && rows.is_a?(Array) && rows.length==entry['angle_rows']
    offsets = {};previous=0
    File.open(path, 'rb') do |file|
      header = file.gets.to_s.force_encoding('UTF-8').sub(/\A\uFEFF/, '')
      fields = CSV.parse_line(header)
      unless fields && fields.length == 8762 && fields[0, 2] == ['azimuth_deg', 'tilt_deg'] &&
             fields[2] == '01-01_00:00-01:00_Wh' && fields[-1] == '12-31_23:00-24:00_Wh'
        raise '内置出力CSV的列数、单位或时间范围不正确。'
      end
      header_end=file.pos
      rows.each do |row|
        raise '出力行位置索引格式不正确。' unless row.is_a?(Array) && row.length==3 && row.all? { |v| v.is_a?(Integer) }
        a,b,offset=row;key=[a,b]
        raise '出力行位置索引存在重复角度或无效位置。' if offsets.key?(key) || offset<header_end || offset<=previous || offset>=csv_bytes
        offsets[key] = offset
        previous=offset
      end
    end
    expected = generation_angles
    raise '内置出力CSV的角度组合不完整。' unless offsets.keys.sort == expected.sort
    annual=data['annual_kwh']
    if annual
      raise '出力年电量索引不完整。' unless annual.is_a?(Array) && annual.length==rows.length &&
        annual.all? { |v| v.is_a?(Numeric) && v.finite? && v>=0 }
    end
    @row_indexes[path] = { path: path, stamp: stamp, offsets: offsets, annual_kwh: annual }
  end

  def self.energy_row(azimuth, tilt, spec = nil)
    spec ||= panel_spec
    index = prepare_index(spec)
    angle = [azimuth, tilt]
    key = [index[:path], index[:stamp], azimuth, tilt]
    @energy_cache ||= {}
    return @energy_cache[key] if @energy_cache.key?(key)
    offset = index[:offsets][angle]
    raise "没有方位角#{azimuth}°、倾角#{tilt}°的数据。" unless offset
    line = File.open(index[:path], 'rb') { |file| file.seek(offset); file.gets }
    row = CSV.parse_line(line.force_encoding('UTF-8'))
    raise '出力角度行读取错误。' unless row && row.length == 8762 && row[0, 2].map { |v| Integer(v) } == angle
    values = row.drop(2).map { |value| Float(value) }
    raise '出力数据含缺失、负数或无效数值。' unless values.all? { |v| v.finite? && v >= 0 }
    @energy_cache.shift if @energy_cache.length >= 12
    @energy_cache[key] = values
  end

  def self.settings
    @settings ||= { 'azimuth' => 180, 'tilt' => 30, 'model_id' => 'TSM-NE19R' }
    @settings['clearance_mm'] ||= 100.0
    active_ids = generation_index.fetch('models', {}).keys
    if !active_ids.empty? && !active_ids.include?(@settings['model_id'])
      @settings = @settings.merge('model_id' => (active_ids.include?('TSM-NE19R') ? 'TSM-NE19R' : active_ids.first))
      @active_panel = @spec = nil
      previous_tool, @placement_tool = @placement_tool, nil
      Sketchup.active_model.select_tool(nil) if previous_tool
    end
    @settings
  end

  def self.validate_settings(payload)
    data = JSON.parse(payload)
    azimuth, tilt = data.values_at('azimuth', 'tilt')
    unless azimuth.is_a?(Integer) && (0..359).cover?(azimuth) &&
           tilt.is_a?(Integer) && (0..90).cover?(tilt)
      raise '方位角要求0—359°；倾角要求0—90°；步长均为1°。'
    end
    { 'azimuth' => azimuth, 'tilt' => tilt, 'clearance_mm'=>SuPvMounting.clearance(data), 'model_id' => panel_spec(data.fetch('model_id', settings['model_id'] || 'TSM-NE19R'))[:id] }
  end

  # 北为世界+Y，东为+X；倾角为板面相对水平面的夹角。
  # 局部原点是低边角点，X为短边，Y为向上倾斜的长边，Z为板正面。
  def self.panel_transform(origin, angles = settings)
    a = angles['azimuth'].degrees
    b = angles['tilt'].degrees
    u = Geom::Vector3d.new(-Math.cos(a), Math.sin(a), 0)
    v = Geom::Vector3d.new(-Math.cos(b) * Math.sin(a), -Math.cos(b) * Math.cos(a), Math.sin(b))
    normal = u.cross(v)
    Geom::Transformation.axes(origin, u, v, normal)
  end

  def self.active_panel
    return nil unless @active_panel && @active_panel.valid? && @active_panel.model == Sketchup.active_model
    @active_panel
  end

  def self.apply_metadata(instance, angles, values, annual_kwh = nil, spec = nil)
    spec ||= panel_spec(angles['model_id'])
    instance.name = "#{spec[:model]} #{spec[:power_w]}W A#{angles['azimuth']} T#{angles['tilt']}"
    instance.set_attribute('SuPvPanelTool', 'model_id', spec[:id])
    instance.set_attribute('SuPvPanelTool', 'power_w', spec[:power_w])
    instance.set_attribute('SuPvPanelTool', 'azimuth_deg', angles['azimuth'])
    instance.set_attribute('SuPvPanelTool', 'tilt_deg', angles['tilt'])
    instance.set_attribute('SuPvPanelTool', 'north', 'world_+Y')
    instance.set_attribute('SuPvPanelTool', 'clearance_mm', SuPvMounting.clearance(angles))
    instance.set_attribute('SuPvPanelTool', 'data_available', !values.nil?)
    if values
      instance.set_attribute('SuPvPanelTool', 'annual_kwh', annual_kwh || values.inject(0.0) { |sum, v| sum + v } / 1000.0)
      instance.set_attribute('SuPvPanelTool', 'lookup', File.basename(File.dirname(energy_path(spec))) + '_8760h')
    else
      instance.delete_attribute('SuPvPanelTool', 'annual_kwh')
      instance.delete_attribute('SuPvPanelTool', 'lookup')
    end
  end

  def self.panel_definition(model, spec = nil)
    spec ||= @spec || panel_spec
    signature = [spec[:length_mm], spec[:width_mm], spec[:thickness_mm]].join('x')
    found = model.definitions.find do |definition|
      definition.get_attribute('SuPvPanelTool', 'signature') == signature &&
        definition.get_attribute('SuPvPanelTool', 'model') == spec[:model] &&
        definition.get_attribute('SuPvPanelTool', 'power_w') == spec[:power_w]
    end
    return found if found
    definition = model.definitions.add("PV_#{spec[:model]}_#{spec[:power_w]}W_#{signature}mm")
    width, length, thickness = spec.values_at(:width_mm, :length_mm, :thickness_mm).map(&:mm)
    entities = definition.entities
    face = entities.add_face([0, 0, 0], [width, 0, 0], [width, length, 0], [0, length, 0])
    raise '光伏板建面失败。' unless face
    face.reverse! if face.normal.z < 0
    face.pushpull(thickness)
    frame_color = Sketchup::Color.new(174, 186, 198)
    entities.grep(Sketchup::Face).each { |f| f.material = frame_color; f.back_material = frame_color }
    margin = 20.mm
    front = entities.add_face([margin, margin, thickness], [width - margin, margin, thickness],
                              [width - margin, length - margin, thickness], [margin, length - margin, thickness])
    raise '光伏板正面建面失败。' unless front
    front.reverse! if front.normal.z < 0
    front.material = Sketchup::Color.new(24, 78, 138)
    front.back_material = Sketchup::Color.new(24, 78, 138)
    entities.each { |entity| entity.layer = model.layers[0] }
    definition.set_attribute('SuPvPanelTool', 'signature', signature)
    spec.each { |key, value| definition.set_attribute('SuPvPanelTool', key.to_s, value) }
    definition
  end

  def self.mount_pose(origin,angles,spec,normal=[0,0,1])
    axes=panel_transform(origin,angles)
    geo=SuPvMounting.geometry(spec,[axes.xaxis,axes.yaxis,axes.zaxis].map(&:to_a),normal,angles)
    lifted=origin.offset(Geom::Vector3d.new(*normal),geo[:lift].mm)
    [panel_transform(lifted,angles),geo]
  end

  def self.create_panel(origin, angles = settings, spec = nil, normal=[0,0,1])
    model = Sketchup.active_model
    raise '请退出组件编辑后再放置光伏板。' if model.active_path
    angles = angles.dup
    spec ||= @spec || panel_spec
    values = energy_for(spec, angles['azimuth'], angles['tilt'])
    model.start_operation('放置光伏板', true)
    begin
      transform,_geo=mount_pose(origin,angles,spec,normal)
      definition = SuPvMounting.definition(model,spec,[transform.xaxis,transform.yaxis,transform.zaxis].map(&:to_a),normal,angles)
      instance = model.entities.add_instance(definition, transform)
      instance.layer = model.layers['PV_panel'] || model.layers.add('PV_panel')
      apply_metadata(instance, angles, values, nil, spec)
      instance.set_attribute('SuPvMounting','anchor_mm',origin.to_a.map(&:to_mm))
      instance.set_attribute('SuPvMounting','normal',normal)
      instance.set_attribute('SuPvMounting','local_anchor_mm',origin.transform(transform.inverse).to_a.map(&:to_mm))
      instance.set_attribute('SuPvMounting','local_normal',[transform.xaxis,transform.yaxis,transform.zaxis].map { |axis| SuPvMounting.dot(axis.to_a,normal) })
      model.commit_operation
      @active_panel = instance
    rescue StandardError
      model.abort_operation
      raise
    end
    instance
  end

  def self.change_angles(payload)
    candidate = validate_settings(payload)
    spec = panel_spec(candidate['model_id'])
    values = energy_for(spec, candidate['azimuth'], candidate['tilt'])
    if spec[:id] != (@spec || panel_spec)[:id]
      @active_panel = nil
      @settings, @spec = candidate, spec
      Sketchup.active_model.select_tool(nil) if @placement_tool
    end
    @spec = spec
    if (instance = active_panel)
      raise '当前光伏板已锁定，无法修改角度。' if instance.locked?
      model = Sketchup.active_model
      raise '请退出组件编辑后再修改角度。' if model.active_path
      model.start_operation('调整光伏板角度', true)
      begin
        anchor=instance.get_attribute('SuPvMounting','local_anchor_mm')
        raise '该组件缺少安装基准点，请重新放置。' unless anchor
        old=instance.transformation
        lengths=[old.xaxis,old.yaxis,old.zaxis].map(&:length)
        raise '组件已缩放，请恢复真实尺寸或重新放置。' unless lengths.all? { |v| (v-1).abs<1e-6 }
        origin=Geom::Point3d.new(anchor.map(&:mm)).transform(old)
        normal=Geom::Vector3d.new(*instance.get_attribute('SuPvMounting','local_normal')).transform(old).normalize.to_a
        transform,_geo=mount_pose(origin,candidate,spec,normal)
        instance.definition=SuPvMounting.definition(model,spec,[transform.xaxis,transform.yaxis,transform.zaxis].map(&:to_a),normal,candidate)
        instance.transformation=transform
        instance.set_attribute('SuPvMounting','local_anchor_mm',origin.transform(transform.inverse).to_a.map(&:to_mm))
        instance.set_attribute('SuPvMounting','local_normal',[transform.xaxis,transform.yaxis,transform.zaxis].map { |axis| SuPvMounting.dot(axis.to_a,normal) })
        apply_metadata(instance, candidate, values, nil, spec)
        model.commit_operation
      rescue StandardError
        model.abort_operation
        raise
      end
    end
    @settings = candidate
    @placement_tool.update_angles(candidate) if @placement_tool
    Sketchup.active_model.active_view.invalidate
    send_data(JSON.parse(payload)['request_id'])
  rescue StandardError => error
    report_error(error)
  end

  def self.send_data(request_id = nil)
    @spec = panel_spec(settings['model_id'])
    values = energy_for(@spec, settings['azimuth'], settings['tilt'])
    data = { settings: settings, spec: @spec, catalog: panel_catalog, values: values, request_id: request_id, placement_only: false,
             data_available: !values.nil?, missing_data_message: values ? nil : missing_data_message(settings['azimuth']),
             panel_placed: !active_panel.nil?, placement_active: !@placement_tool.nil?,
             peak_wh: values && values.max, annual_kwh: values && values.inject(0.0) { |sum, value| sum + value } / 1000.0 }
    @dialog.execute_script("window.PV.receive(#{JSON.generate(data)});") if @dialog
  end

  def self.report_error(error)
    warn "[光伏板实验] #{error.class}: #{error.message}"
    if @dialog
      @dialog.execute_script("window.PV.fail(#{JSON.generate(error.message)}, #{JSON.generate(settings)});")
    else
      UI.messagebox(error.message)
    end
  end

  class PlacementTool
    def initialize(model, spec, angles)
      @model, @spec, @angles = model, spec, angles.dup
      @point = Sketchup::InputPoint.new
    end

    def update_angles(angles)
      @angles = angles.dup
    end

    def activate
      Sketchup.set_status_text("#{@spec[:model]}：点击低边角点放置；窗口调整方位角和倾角；Esc取消。")
    end

    def onMouseMove(_flags, x, y, view)
      @point.pick(view, x, y)
      view.tooltip = @point.tooltip if @point.valid?
      view.invalidate
    end

    def corners
      return [] unless @point.valid?
      w, l, t = @spec.values_at(:width_mm, :length_mm, :thickness_mm).map(&:mm)
      transform,_geo = SuPvPanelTool.mount_pose(@point.position,@angles,@spec,normal)
      [[0, 0, 0], [w, 0, 0], [w, l, 0], [0, l, 0],
       [0, 0, t], [w, 0, t], [w, l, t], [0, l, t]].map { |p| Geom::Point3d.new(p).transform(transform) }
    end

    def draw(view)
      @point.draw(view) if @point.display?
      points = corners
      return if points.empty?
      view.drawing_color = Sketchup::Color.new(25, 118, 210)
      view.line_width = 2
      view.draw(GL_LINE_LOOP, points[0, 4])
      view.draw(GL_LINE_LOOP, points[4, 4])
      view.draw(GL_LINES, (0..3).flat_map { |i| [points[i], points[i + 4]] })
    end

    def getExtents
      bounds = Geom::BoundingBox.new
      corners.each { |point| bounds.add(point) }
      bounds
    end

    def onLButtonDown(_flags, x, y, view)
      @point.pick(view, x, y)
      return unless @point.valid?
      raise '活动模型已改变，请重新启动放置工具。' unless @model == Sketchup.active_model
      SuPvPanelTool.create_panel(@point.position, @angles, @spec,normal)
      SuPvPanelTool.send_data
      @model.select_tool(nil)
    rescue StandardError => error
      SuPvPanelTool.report_error(error)
    end

    def onCancel(_reason, _view)
      @model.select_tool(nil)
    end

    def normal
      face=@point.face
      return [0,0,1] unless face
      points=face.outer_loop.vertices.map { |v| v.position.transform(@point.transformation) }
      first=points[1]-points[0]
      n=points.drop(2).map { |p| first.cross(p-points[0]) }.find { |v| v.length>1e-8 }
      return [0,0,1] unless n
      n.normalize!;n.reverse! if n.z<0
      n.to_a
    end

    def deactivate(view)
      SuPvPanelTool.tool_finished(self)
      Sketchup.set_status_text('')
      view.invalidate
    end
  end

  def self.tool_finished(tool)
    if @placement_tool.equal?(tool)
      @placement_tool = nil
      send_data if @dialog
    end
  rescue StandardError => error
    report_error(error)
  end

  def self.start_placement(payload = nil)
    model = Sketchup.active_model
    raise '请退出组件编辑后再放置光伏板。' if model.active_path
    candidate = payload && !payload.empty? ? validate_settings(payload) : settings.dup
    @spec = panel_spec(candidate['model_id'])
    energy_for(@spec, candidate['azimuth'], candidate['tilt'])
    @settings = candidate
    @active_panel = nil
    @placement_tool = PlacementTool.new(model, @spec, candidate)
    model.select_tool(@placement_tool)
    send_data
  rescue StandardError => error
    report_error(error)
  end

  def self.show_dialog
    if @dialog && @dialog.visible?
      @dialog.bring_to_front
      return
    end
    @spec = panel_spec
    html = project_path('ui/pv_panel.html')
    raise "找不到界面：#{html}" unless File.file?(html)
    dialog = UI::HtmlDialog.new(dialog_title: '光伏板与出力',
                                preferences_key: 'SuPvPanelTool.Window',
                                width: 1180, height: 780, min_width: 900, min_height: 650,
                                scrollable: false, resizable: true, style: UI::HtmlDialog::STYLE_DIALOG)
    @dialog = dialog
    SuPvFigureExport.bind(dialog, current: -> { @dialog.equal?(dialog) })
    dialog.add_action_callback('ready') do |_context|
      begin
        send_data(0)
      rescue StandardError => error
        report_error(error)
      end
    end
    dialog.add_action_callback('angles') { |_context, payload| change_angles(payload) }
    dialog.add_action_callback('place') { |_context, payload| start_placement(payload) }
    dialog.add_action_callback('recommend') do |_context,payload|
      begin
        candidate=validate_settings(payload)
        recommendation=SuPvDesignRecommendations.panel(candidate)
        dialog.execute_script("window.PVDesignAdvice.receive(#{JSON.generate(recommendation)});") if @dialog.equal?(dialog)
      rescue StandardError=>error
        dialog.execute_script("window.PVDesignAdvice.fail(#{JSON.generate(error.message)});") if @dialog.equal?(dialog)
      end
    end
    SuPvGenerationExport.bind(dialog, current: -> { @dialog.equal?(dialog) }) do |data|
      candidate = validate_settings(JSON.generate(data.fetch('settings')))
      raise '方案已改变，请等待出力更新后再导出。' unless candidate == settings
      spec = panel_spec(candidate['model_id'])
      values = energy_for(spec, candidate['azimuth'], candidate['tilt'])
      { values: values, spec: spec, settings: candidate, count: 1, branch: 'panel' }
    end
    dialog.set_on_closed do
      @dialog = nil
      Sketchup.active_model.select_tool(nil) if @placement_tool
    end
    dialog.set_file(html)
    dialog.show
  rescue StandardError => error
    warn "[光伏板实验] #{error.message}"
    UI.messagebox(error.message)
  end

  # 统一工具栏通过 activate 调用；保留 show_dialog 便于控制台调试。
  def self.activate
    show_dialog
  end

  # 当前 SU 会话可能仍持有旧版独立工具栏；仅隐藏旧工具栏，不触碰模型。
  def self.retire_legacy_toolbar
    @toolbar.hide if @toolbar
  end
end
