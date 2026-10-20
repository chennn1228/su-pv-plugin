# encoding: UTF-8
# toolbar1 按钮3：在安装面上排布光伏阵列并查询出力。
require 'sketchup.rb'
require 'json'
load File.expand_path('../toolbar2/support/array_layout.rb', __dir__)

module SuPvArrayTool1
  def self.activate
    model = Sketchup.active_model
    raise '请退出组件编辑后再选择阵列面。' if model.active_path
    @model = model
    @target, @plan = nil, nil
    @spec = SuPvPanelTool1.panel_spec
    @tool = FaceTool.new(model)
    model.select_tool(@tool)
  end

  def self.face_description
    '安装面'
  end

  def self.frame_from_path(path)
    raise "请选择组件内的#{face_description}。" unless path && path.last.is_a?(Sketchup::Face) && path.any? { |e| e.is_a?(Sketchup::ComponentInstance) }
    raise '所选对象已失效。' unless path.all?(&:valid?)
    raise '所选组件已锁定。' if path.any? { |e| e.respond_to?(:locked?) && e.locked? }
    face = path.last
    transform = path[0...-1].inject(Geom::Transformation.new) do |tr, entity|
      entity.respond_to?(:transformation) ? tr * entity.transformation : tr
    end
    loops = [face.outer_loop] + face.loops.reject { |loop| loop == face.outer_loop }
    world_loops = loops.map { |loop| loop.vertices.map { |vertex| vertex.position.transform(transform) } }
    points = world_loops.first
    projected = SuPvRoofRegion.project(world_loops.map { |ring| ring.map { |point| point.to_a.map(&:to_mm) } })
    origin = Geom::Point3d.new(projected[:origin].map(&:mm))
    u,v,normal = projected.values_at(:u,:v,:normal).map { |axis| Geom::Vector3d.new(*axis) }
    width,height,region = projected.values_at(:width,:height,:region)
    raise '安装面的尺寸过小。' unless width > 1.0 && height > 1.0
    component = path.reverse.find { |entity| entity.is_a?(Sketchup::ComponentInstance) }
    label = component.name.to_s.empty? ? component.definition.name : component.name
    { path: path.dup, face: face, origin: origin, u: u, v: v, normal: normal,
      width: width, height: height, points: points, world_loops: world_loops, region: region,
      label: label, model: Sketchup.active_model }
  end

  def self.pick(view, x, y)
    hit = @model.raytest(view.pickray(x, y), true)
    raise "请点击组件中的#{face_description}。" unless hit
    frame_from_path(hit[1])
  end

  def self.validate_target
    raise "请先选择组件中的#{face_description}。" unless @target
    raise '活动模型已改变，请重新选择面。' unless Sketchup.active_model == @target[:model]
    raise '请退出组件编辑后再生成阵列。' if @model.active_path
    current = frame_from_path(@target[:path])
    before = @target[:world_loops] || [@target[:points]]
    after = current[:world_loops] || [current[:points]]
    unless after.length == before.length && after.zip(before).all? { |a,b| a.length == b.length && a.zip(b).all? { |p,q| p.distance(q).to_mm < 0.01 } }
      raise '所选面已移动或改变，请重新选择。'
    end
    current
  end

  def self.settings_from(payload)
    data = JSON.parse(payload)
    raise '目标面已改变，请等待新面预览后再操作。' unless data['target_id'] == @target_id
    angles = SuPvRoofAngles.validate_angles(data)
    angles['model_id'] = SuPvPanelTool1.panel_spec(data.fetch('model_id', @params['model_id']))[:id]
    ['gap_x_mm', 'gap_y_mm'].each do |key|
      value = Float(data.fetch(key))
      raise '间距须为非负有限毫米数值。' unless value.finite? && value >= 0 && value <= 1e9
      angles[key] = value
    end
    [angles, data['request_id']]
  end

  def self.select_target(target)
    @target, @plan = target, nil
    @target_id = (@target_id || 0) + 1
    @params ||= SuPvPanelTool1.settings.merge('gap_x_mm' => 100.0, 'gap_y_mm' => 500.0)
    unless SuPvPanelTool1.panel_catalog.any? { |spec| spec[:id] == @params['model_id'] }
      @params = @params.merge('model_id' => SuPvPanelTool1.settings['model_id'])
    end
    roof=SuPvRoofAngles.limits(target[:normal].to_a)
    @params=@params.merge('tilt'=>roof['slope_deg'],
      'azimuth'=>roof['slope_deg']>1e-7 ? roof['azimuth_deg'] : @params['azimuth'])
    show_dialog
    send_preview(@params, 0) if @ready
  end

  def self.make_plan(settings)
    target = validate_target
    @spec = SuPvPanelTool1.panel_spec(settings['model_id'])
    SuPvArrayLayout.plan(target[:width], target[:height],
      [target[:u], target[:v], target[:normal]].map(&:to_a), @spec, settings, target[:region])
  end

  def self.send_preview(settings, request_id)
    @plan = make_plan(settings)
    @params = @plan['settings']
    data = @plan.merge('target_id' => @target_id, 'request_id' => request_id, 'layout_only' => false,
      'target_name' => @target[:label], 'spec' => @spec, 'catalog' => SuPvPanelTool1.panel_catalog,
      'prediction' => prediction_for(@plan, @spec))
    @dialog.execute_script("window.PVArray.receive(#{JSON.generate(data)});") if @dialog
    @model.active_view.invalidate
  end

  # 与单板使用相同的8760小时序列；按实际通过边界筛选的板数逐时累加。
  def self.prediction_for(plan, spec)
    settings = plan.fetch('settings')
    single = SuPvPanelTool1.energy_for(spec, settings['azimuth'], settings['tilt'])
    values = single && single.map { |value| value * plan.fetch('count') }
    { settings: settings, spec: spec, catalog: SuPvPanelTool1.panel_catalog,
      values: values, data_available: !values.nil?,
      peak_wh: values && values.max,
      annual_kwh: values && values.inject(0.0) { |sum, value| sum + value } / 1000.0 }
  end

  def self.preview(payload)
    params, request_id = settings_from(payload)
    send_preview(params, request_id)
  rescue StandardError => error
    fail_ui(error)
  end

  def self.world_origin(position)
    @target[:origin].offset(@target[:u], position[0].mm).
      offset(@target[:v], position[1].mm).offset(@target[:normal], position[2].mm)
  end

  def self.build(payload)
    params, request_id = settings_from(payload)
    plan = make_plan(params)
    params = plan['settings']
    raise '当前参数没有能完整放入的组件，请调整角度或间距。' if plan['count'] == 0
    # 事务前完成数据读取和校核，失败时不创建空群组。
    values = SuPvPanelTool1.energy_for(@spec, params['azimuth'], params['tilt'])
    annual = values && values.inject(0.0) { |sum, value| sum + value } / 1000.0
    frame = Geom::Transformation.axes(@target[:origin], @target[:u], @target[:v], @target[:normal])
    inverse = frame.inverse
    @model.start_operation('在安装面上生成光伏阵列', true)
    begin
      definition = SuPvPanelTool1.panel_definition(@model, @spec)
      group = @model.entities.add_group
      group.name = "PV_array_#{@target[:label]}"
      group.layer = @model.layers[0]
      group.transformation = frame
      layer = @model.layers['PV_panel'] || @model.layers.add('PV_panel')
      plan['positions'].each do |position|
        transform = inverse * SuPvPanelTool1.panel_transform(world_origin(position), params)
        instance = group.entities.add_instance(definition, transform)
        instance.layer = layer
        SuPvPanelTool1.apply_metadata(instance, params, values, annual, @spec)
      end
      group.set_attribute('SuPvArrayTool', 'source_path', @target[:path].map(&:persistent_id))
      group.set_attribute('SuPvArrayTool', 'settings', JSON.generate(params))
      group.set_attribute('SuPvArrayTool', 'count', plan['count'])
      @model.commit_operation
    rescue StandardError
      @model.abort_operation
      raise
    end
    @plan = nil
    @model.selection.clear
    @model.selection.add(group)
    @model.select_tool(nil) if @tool
    @dialog.execute_script("window.PVArray.built(#{JSON.generate({ count: plan['count'], request_id: request_id })});") if @dialog
    @model.active_view.invalidate
  rescue StandardError => error
    fail_ui(error)
  end

  def self.fail_ui(error)
    warn "[光伏阵列] #{error.class}: #{error.message}"
    if @dialog
      @dialog.execute_script("window.PVArray.fail(#{JSON.generate(error.message)});")
    else
      UI.messagebox(error.message)
    end
  end

  def self.show_dialog
    if @dialog && @dialog.visible?
      @dialog.bring_to_front
      return
    end
    title = 'toolbar1 · 阵列与出力'
    dialog = UI::HtmlDialog.new(dialog_title: title, preferences_key: 'SuPvArrayTool1.Window',
      width: 1120, height: 780, min_width: 900, min_height: 650,
      scrollable: false, resizable: true, style: UI::HtmlDialog::STYLE_DIALOG)
    @dialog = dialog
    @ready = false
    dialog.add_action_callback('ready') do |_context|
      next unless @dialog.equal?(dialog)
      begin
        @ready = true
        send_preview(@params, 0)
      rescue StandardError => error
        fail_ui(error)
      end
    end
    dialog.add_action_callback('preview') { |_context, payload| preview(payload) if @dialog.equal?(dialog) }
    dialog.add_action_callback('build') { |_context, payload| build(payload) if @dialog.equal?(dialog) }
    dialog.add_action_callback('repick') do |_context|
      next unless @dialog.equal?(dialog)
      begin
        activate
      rescue StandardError => error
        fail_ui(error)
      end
    end
    SuPvGenerationExport.bind(dialog, current: -> { @dialog.equal?(dialog) }) do |data|
      context = data.fetch('context')
      params, _request_id = settings_from(JSON.generate(data.fetch('settings').merge('target_id' => context.fetch('target_id'))))
      raise '方案已改变，请等待出力更新后再导出。' unless params == @params
      plan = make_plan(params)
      raise '阵列数量已改变，请重新预览。' unless context.fetch('count') == plan['count']
      branch = context.fetch('branch')
      raise '出力分支不正确。' unless ['baseline', 'shade'].include?(branch)
      values = data.fetch('values')
      SuPvGenerationExport.validate_values(values)
      single = SuPvPanelTool1.energy_for(@spec, params['azimuth'], params['tilt'])
      raise '暂无出力数据。' unless single
      single.each_with_index do |value, index|
        original = value * plan['count']
        tolerance = [1e-6, original.abs * 1e-9].max
        valid = branch == 'baseline' ? (values[index] - original).abs <= tolerance : values[index] <= original + tolerance
        raise '导出出力与当前阵列不一致，请重新计算。' unless valid
      end
      { values: values, spec: @spec, settings: params, count: plan['count'], branch: branch }
    end
    dialog.set_on_closed do
      next unless @dialog.equal?(dialog)
      @dialog = nil
      @ready = false
      @plan = nil
      @model.select_tool(nil) if @tool && @model == Sketchup.active_model
    end
    dialog.set_file(SuPvPanelTool1.project_path('ui/pv_array.html'))
    dialog.show
  end

  class FaceTool
    def initialize(model)
      @model = model
    end
    def activate
      Sketchup.set_status_text("光伏阵列：点击组件中的#{SuPvArrayTool1.face_description}；Esc取消。")
    end
    def onMouseMove(_flags, x, y, view)
      @hover = SuPvArrayTool1.pick(view, x, y)
      view.tooltip = "安装面 · #{(@hover[:width] / 1000.0).round(2)} × #{(@hover[:height] / 1000.0).round(2)} m"
      view.invalidate
    rescue StandardError => error
      @hover = nil
      view.tooltip = error.message
      view.invalidate
    end
    def onLButtonDown(_flags, x, y, view)
      raise '活动模型已改变，请重新选面。' unless @model == Sketchup.active_model
      SuPvArrayTool1.select_target(SuPvArrayTool1.pick(view, x, y))
      view.invalidate
    rescue StandardError => error
      SuPvArrayTool1.fail_ui(error)
    end
    def draw(view)
      target = @hover || SuPvArrayTool1.instance_variable_get(:@target)
      return unless target && target[:model] == @model
      view.drawing_color = Sketchup::Color.new(33, 102, 172)
      view.line_width = 2
      (target[:world_loops] || [target[:points]]).each { |ring| view.draw(GL_LINE_LOOP, ring) }
      plan = SuPvArrayTool1.instance_variable_get(:@plan)
      return unless plan
      w, l = SuPvArrayTool1.instance_variable_get(:@spec).values_at(:width_mm, :length_mm).map(&:mm)
      view.line_width = 1
      plan['positions'].first(500).each do |position|
        transform = SuPvPanelTool1.panel_transform(SuPvArrayTool1.world_origin(position), plan['settings'])
        points = [[0,0,0],[w,0,0],[w,l,0],[0,l,0]].map { |p| Geom::Point3d.new(p).transform(transform) }
        view.draw(GL_LINE_LOOP, points)
      end
    end
    def onCancel(_reason, _view)
      SuPvArrayTool1.instance_variable_get(:@dialog)&.close
      @model.select_tool(nil)
    end
    def deactivate(view)
      SuPvArrayTool1.instance_variable_set(:@tool, nil) if SuPvArrayTool1.instance_variable_get(:@tool).equal?(self)
      Sketchup.set_status_text('')
      view.invalidate
    end
  end
end
