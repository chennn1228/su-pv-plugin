# encoding: UTF-8
# 按钮3：在安装面上排布光伏阵列并查询出力。
require 'sketchup.rb'
require 'json'
load File.expand_path('../support/array_layout.rb', __dir__)
load File.expand_path('../support/scene_snapshot.rb', __dir__)
load File.expand_path('../support/access_planner.rb', __dir__)
load File.expand_path('../support/access_picker.rb', __dir__)

module SuPvArrayTool
  def self.restore_access_array(owner=nil)
    state=@access_visibility
    return unless state && (!owner || state[:owner].equal?(owner))
    @access_visibility=nil
    group=state[:group]
    group.hidden=state[:hidden] if group.valid?
    @model.active_view.invalidate if @model && @model==Sketchup.active_model
  end

  def self.hide_access_array(owner)
    restore_access_array
    group=@edit_path && @edit_path.last
    raise '所选阵列已失效，请重新选择。' unless group && group.valid?
    @access_visibility={owner:owner,group:group,hidden:group.hidden?}
    group.hidden=true
    @model.active_view.invalidate
  end

  def self.reset_ui
    dialog=@dialog;@dialog=nil;@ready=false;@resume_access=false
    @access_pick_pending=false
    # Detach first: closing an obsolete window must not run its old teardown
    # against the new selection session.
    tool=@tool;@tool=nil
    restore_access_array
    @edit_path=nil
    @model.select_tool(nil) if tool && @model==Sketchup.active_model
    dialog.close if dialog
  end

  def self.activate
    model = Sketchup.active_model
    raise '请退出组件编辑后再选择阵列面。' if model.active_path
    reset_ui
    @model = model
    @target, @plan = nil, nil
    @spec = SuPvPanelTool.panel_spec
    @tool = FaceTool.new(model)
    model.select_tool(@tool)
  end

  def self.face_description
    '安装面'
  end

  # Resolve every occurrence in its owning collection; a face ID alone cannot
  # distinguish two instances of the same roof component.
  def self.source_path(ids)
    raise '该阵列没有保存安装面，请重新生成阵列。' unless ids.is_a?(Array) && !ids.empty?
    entities=@model.entities
    ids.each_with_index.map do |id,index|
      entity=entities.find { |item| item.persistent_id==id }
      raise '原安装面已删除或层级已改变，请重新生成阵列。' unless entity && entity.valid?
      entities=SuPvSceneSnapshot.children(entity) if index<ids.length-1
      raise '原安装面路径无效。' if index<ids.length-1 && !entities
      entity
    end
  end

  def self.validate_existing
    return unless @edit_path
    entities=@model.entities;transform=Geom::Transformation.new
    @edit_path.each_with_index do |entity,index|
      raise '阵列已删除或层级已改变，请重新选择。' unless entity.valid? && entities.include?(entity)
      raise '阵列或上级组件已锁定。' if entity.locked?
      if index<@edit_path.length-1 && entity.definition.instances.length>1
        raise '请先将阵列所在的上级群组或组件设为独立，再调整边界约束。'
      end
      transform=transform*entity.transformation
      entities=SuPvSceneSnapshot.children(entity)
    end
    group=@edit_path.last
    raise '请选择自动生成的光伏阵列群组。' unless group.is_a?(Sketchup::Group) && group.get_attribute('SuPvArrayTool','settings')
    raise '阵列内含手动修改的对象，请重新生成阵列后调整边界约束。' unless group.entities.all? { |entity| SuPvSceneSnapshot.panel?(entity) }
    expected=Geom::Transformation.axes(@target[:origin],@target[:u],@target[:v],@target[:normal])
    anchors=[[0,0,0],[1000.mm,0,0],[0,1000.mm,0],[0,0,1000.mm]]
    unless anchors.all? { |p| Geom::Point3d.new(p).transform(transform).distance(Geom::Point3d.new(p).transform(expected)).to_mm<0.01 }
      raise '阵列相对安装面的位置或比例已改变，请重新生成阵列后调整边界约束。'
    end
    group
  end

  def self.open_existing(path)
    reset_ui
    @model=Sketchup.active_model
    raise '请退出组件编辑后再选择阵列。' if @model.active_path
    @edit_path=path.dup
    group=path.last
    @target=frame_from_path(source_path(group.get_attribute('SuPvArrayTool','source_path')))
    raise '边界约束仅用于屋面阵列。' if @target[:flush_only] || @target[:normal].z<=1e-6
    validate_existing
    @target_id=(@target_id || 0)+1
    saved=JSON.parse(group.get_attribute('SuPvArrayTool','settings'))
    @params=saved
    @params,_=settings_from(JSON.generate(saved.merge('target_id'=>@target_id)))
    @plan=nil;@resume_access=true
    @tool=FaceTool.new(@model);@model.select_tool(@tool)
    show_dialog
  rescue StandardError
    @edit_path=nil
    raise
  end

  def self.data_azimuth(value)
    Float(value).round%360
  end

  def self.validate_azimuth!(value)
    unless (value-data_azimuth(value)).abs<1e-7
      raise '可调方位角要求0—359°，步长1°。'
    end
  end

  def self.fixed_azimuth(target)
    return nil unless target
    roof=SuPvRoofAngles.limits(target[:normal].to_a)
    roof['azimuth_deg'] if target[:flush_only] || roof['slope_deg']>1e-7
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
    effective_tag=path.reverse.find { |e| e.respond_to?(:layer) && !['Layer0','Untagged','未标记'].include?(e.layer.name) }&.layer&.name.to_s.downcase
    flush_only=['wall','fence'].include?(effective_tag)
    if flush_only && Math.hypot(projected[:normal][0],projected[:normal][1])>1e-8
      n=projected[:normal];u=SuPvRoofRegion.unit([-n[1],n[0],0.0]);v=SuPvRoofRegion.cross(n,u)
      world=world_loops.map { |ring| ring.map { |p| p.to_a.map(&:to_mm) } }
      base=world.first.first
      local=world.map { |ring| ring.map { |p| delta=p.zip(base).map { |a,b| a-b };[SuPvRoofRegion.dot(delta,u),SuPvRoofRegion.dot(delta,v)] } }
      minx=local.first.map(&:first).min;miny=local.first.map(&:last).min
      region=SuPvRoofRegion.prepare(local.map { |ring| ring.map { |x,y| [x-minx,y-miny] } })
      projected={origin:(0..2).map { |i| base[i]+u[i]*minx+v[i]*miny },u:u,v:v,normal:n,region:region,width:region[:width],height:region[:height]}
    end
    origin = Geom::Point3d.new(projected[:origin].map(&:mm))
    u,v,normal = projected.values_at(:u,:v,:normal).map { |axis| Geom::Vector3d.new(*axis) }
    width,height,region = projected.values_at(:width,:height,:region)
    raise '安装面的尺寸过小。' unless width > 1.0 && height > 1.0
    component = path.reverse.find { |entity| entity.is_a?(Sketchup::ComponentInstance) }
    label = component.name.to_s.empty? ? component.definition.name : component.name
    { path: path.dup, face: face, origin: origin, u: u, v: v, normal: normal,
      width: width, height: height, points: points, world_loops: world_loops, region: region,
      label: label, kind: %w[roof wall fence].include?(effective_tag) ? effective_tag : 'surface',
      flush_only: flush_only, fence: effective_tag=='fence' && v.z>1e-8, model: Sketchup.active_model }
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
    raise '安装面Tag已改变，请重新选择。' if current[:kind]!=@target[:kind] || current[:flush_only]!=@target[:flush_only] || current[:fence]!=@target[:fence]
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
    fixed=fixed_azimuth(@target)
    angles['azimuth']=fixed if fixed
    validate_azimuth!(angles['azimuth']) unless fixed
    angles['_flush']=true if @target && @target[:flush_only]
    angles['_fence']=!!@target[:fence] if @target && @target[:flush_only]
    angles['model_id'] = SuPvPanelTool.panel_spec(data.fetch('model_id', @params['model_id']))[:id]
    ['gap_x_mm', 'gap_y_mm'].each do |key|
      value = Float(data.fetch(key))
      raise '间距须为非负有限毫米数值。' unless value.finite? && value >= 0 && value <= 1e9
      angles[key] = value
    end
    angles['access']=SuPvAccessLayout.normalize(data['access'])
    angles['clearance_mm']=SuPvMounting.clearance(data)
    [angles, data['request_id']]
  end

  def self.select_target(target)
    @edit_path=nil
    @target, @plan = target, nil
    @target_id = (@target_id || 0) + 1
    @params ||= SuPvPanelTool.settings.merge('gap_x_mm' => 100.0, 'gap_y_mm' => 500.0)
    unless SuPvPanelTool.panel_catalog.any? { |spec| spec[:id] == @params['model_id'] }
      @params = @params.merge('model_id' => SuPvPanelTool.settings['model_id'])
    end
    roof=SuPvRoofAngles.limits(target[:normal].to_a)
    initial_azimuth=fixed_azimuth(target) || data_azimuth(@params['azimuth'])
    @params=@params.merge('tilt'=>roof['slope_deg'],'azimuth'=>initial_azimuth,'access'=>SuPvAccessLayout.defaults)
    show_dialog
    send_preview(@params, 0) if @ready
  end

  def self.make_plan(settings)
    target = validate_target
    validate_existing
    @spec = SuPvPanelTool.panel_spec(settings['model_id'])
    settings=settings.reject { |key,_| ['_flush','_fence'].include?(key) }
    settings=settings.merge('_flush'=>true,'_fence'=>target[:fence],
      'azimuth'=>SuPvRoofAngles.limits(target[:normal].to_a)['azimuth_deg'],
      'tilt'=>SuPvRoofAngles.limits(target[:normal].to_a)['slope_deg']) if target[:flush_only]
    fixed=fixed_azimuth(target)
    settings=settings.merge('azimuth'=>fixed) if fixed
    validate_azimuth!(settings['azimuth']) unless fixed
    args=[target[:width],target[:height],[target[:u],target[:v],target[:normal]].map(&:to_a),@spec]
    access=SuPvAccessLayout.normalize(settings['access'])
    base=SuPvArrayLayout.plan(*args,settings.merge('access'=>access.merge('paths'=>[])),target[:region])
    if access['automatic']
      raise '自动通道仅用于屋面。' unless base['access_enabled']
      begin
        access_trace={}
        access=SuPvAccessPlanner.plan(base,target[:region],access_trace)
      rescue StandardError=>error
        access=access.merge('paths'=>[])
        access_errors=[error.message]
      end
    end
    plan=SuPvArrayLayout.plan(*args,settings.merge('access'=>access),target[:region])
    plan['access_trace']=access_trace if access_trace
    plan['access_validation']={'valid'=>false,'errors'=>access_errors} if access_errors
    # Compare corridor loss at the very same grid phase. Independent searches
    # without/with a corridor would otherwise produce a misleading difference.
    without_paths=access['paths'].empty? ? plan : SuPvArrayLayout.plan(*args,
      settings.merge('access'=>access.merge('paths'=>[])),target[:region],optimize:false,phase:plan['grid_phase_mm'])
    plan.merge('surface_kind'=>target[:kind] || 'surface','access_baseline_count'=>without_paths['count'],
      'access_removed_count'=>without_paths['count']-plan['count'])
  end

  def self.pick_access(payload)
    raise '请使用边界约束按钮选择已生成的阵列。' unless @edit_path
    data=JSON.parse(payload);settings,_=settings_from(payload);target=validate_target
    mode=data['pick_mode'];raise '选取类型无效。' unless %w[entry exclude].include?(mode)
    raise '通道与退让仅用于屋面。' if target[:flush_only] || target[:normal].z<=1e-6
    @params=settings;token=@target_id;@resume_access=true;@access_pick_pending=true
    # SU2022 has no HtmlDialog#hide. Close the view while retaining canonical
    # settings; recreate callbacks and restore the access tab on return.
    dialog=@dialog;@dialog=nil;@ready=false;dialog.close if dialog
    picker=SuPvAccessPicker::Tool.new(target,mode) do |value|
      unless @tool.equal?(picker) && token==@target_id
        restore_access_array(picker)
        next
      end
      begin
        validate_target
        cfg=SuPvAccessLayout.normalize(@params['access'])
        if value
          if mode=='entry'
            cfg['entry']=value;cfg['paths']=[];cfg['automatic']=true
          else
            cfg['exclusions']<<value
          end
          @params=@params.merge('access'=>SuPvAccessLayout.normalize(cfg))
        end
      rescue StandardError=>error
        @access_error=error.message
      ensure
        restore_access_array(picker)
        @tool=nil
        if @model==Sketchup.active_model
          @tool=FaceTool.new(@model);@model.select_tool(@tool)
        end
        show_dialog
      end
    end
    @tool=picker
    # Let the HtmlDialog callback and window close finish before native input.
    UI.start_timer(0,false) do
      next unless @tool.equal?(picker) && token==@target_id
      @access_pick_pending=false
      begin
        hide_access_array(picker)
        @model.select_tool(picker)
      rescue StandardError=>error
        restore_access_array(picker)
        @access_error=error.message
        picker.finish(nil)
      end
    end
  rescue StandardError=>error
    @access_pick_pending=false
    fail_ui(error)
  end

  def self.send_preview(settings, request_id)
    @plan = make_plan(settings)
    @params = @plan['settings']
    # Boundary editing needs only roof geometry and panel footprints.
    # Avoid collecting scene occluders or reading time series for this tool.
    SuPvSceneSnapshot.attach(@plan,@model,@target[:origin].to_a.map(&:to_mm)) unless @edit_path
    data = @plan.merge('target_id' => @target_id, 'request_id' => request_id, 'layout_only' => false,
      'editing_existing'=>!!@edit_path,'constraints_only'=>!!@edit_path,
      'target_name' => @target[:label], 'spec' => @spec, 'catalog' => SuPvPanelTool.panel_catalog)
    data['prediction']=prediction_for(@plan,@spec) unless @edit_path
    @dialog.execute_script("window.PVArray.receive(#{JSON.generate(data)});") if @dialog
    @model.active_view.invalidate
  end

  # 与单板使用相同的8760小时序列；按实际通过边界筛选的板数逐时累加。
  def self.prediction_for(plan, spec)
    settings = plan.fetch('settings')
    single = SuPvPanelTool.energy_for(spec, settings['azimuth'], settings['tilt'])
    values = single && single.map { |value| value * plan.fetch('count') }
    { settings: settings, spec: spec, catalog: SuPvPanelTool.panel_catalog,
      values: values, data_available: !values.nil?,
      missing_data_message: values ? nil : SuPvPanelTool.missing_data_message(settings['azimuth']),
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

  def self.panel_transform(position,plan)
    axes=plan['panel_axes'].map { |a| Geom::Vector3d.new(*a) }
    Geom::Transformation.axes(world_origin(position),*axes)
  end

  def self.build(payload)
    params, request_id = settings_from(payload)
    plan = make_plan(params)
    params = plan['settings']
    raise plan['access_validation']['errors'].join(' ') unless plan['access_validation']['valid']
    raise '当前参数没有能完整放入的组件，请调整角度或间距。' if plan['count'] == 0
    # 事务前完成数据读取和校核，失败时不创建空群组。
    values = SuPvPanelTool.energy_for(@spec, params['azimuth'], params['tilt'])
    annual = values && values.inject(0.0) { |sum, value| sum + value } / 1000.0
    frame = Geom::Transformation.axes(@target[:origin], @target[:u], @target[:v], @target[:normal])
    inverse = frame.inverse
    editing=!!@edit_path
    group=validate_existing if editing
    @model.start_operation(editing ? '更新光伏阵列边界约束' : '在安装面上生成光伏阵列', true)
    begin
      definition = SuPvMounting.definition(@model,@spec,plan['panel_axes'],plan['frame_axes'][2],params)
      if editing
        group.make_unique
        previous=group.entities.to_a
      else
        group = @model.entities.add_group
        group.name = "PV_array_#{@target[:label]}"
        group.layer = @model.layers[0]
        group.transformation = frame
      end
      layer = @model.layers['PV_panel'] || @model.layers.add('PV_panel')
      plan['positions'].each do |position|
        transform = inverse * panel_transform(position,plan)
        instance = group.entities.add_instance(definition, transform)
        instance.layer = layer
        SuPvPanelTool.apply_metadata(instance, params, values, annual, @spec)
      end
      group.entities.erase_entities(previous) if editing && !previous.empty?
      group.set_attribute('SuPvArrayTool', 'source_path', @target[:path].map(&:persistent_id))
      group.set_attribute('SuPvArrayTool', 'settings', JSON.generate(params))
      group.set_attribute('SuPvArrayTool', 'count', plan['count'])
      @model.commit_operation
    rescue StandardError
      @model.abort_operation
      raise
    end
    @params=params
    @plan = nil
    @model.selection.clear
    @model.selection.add(editing ? @edit_path.first : group)
    @model.select_tool(nil) if @tool
    @dialog.execute_script("window.PVArray.built(#{JSON.generate({ count: plan['count'], request_id: request_id, editing_existing: editing })});") if @dialog
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
    title = @edit_path ? '边界约束' : '阵列与出力'
    dialog = UI::HtmlDialog.new(dialog_title: title, preferences_key: 'SuPvArrayTool.Window',
      width: 1120, height: 780, min_width: 900, min_height: 650,
      scrollable: false, resizable: true, style: UI::HtmlDialog::STYLE_DIALOG)
    @dialog = dialog
    @ready = false
    SuPvFigureExport.bind(dialog, current: -> { @dialog.equal?(dialog) }) unless @edit_path
    dialog.add_action_callback('ready') do |_context|
      next unless @dialog.equal?(dialog)
      begin
        @ready = true
        send_preview(@params, 0)
        if @resume_access
          @resume_access=false
          @dialog.execute_script("window.PVArray.selectView('access');")
        end
        if @access_error
          message=@access_error;@access_error=nil;fail_ui(StandardError.new(message))
        end
      rescue StandardError => error
        fail_ui(error)
      end
    end
    dialog.add_action_callback('preview') { |_context, payload| preview(payload) if @dialog.equal?(dialog) }
    dialog.add_action_callback('build') { |_context, payload| build(payload) if @dialog.equal?(dialog) }
    dialog.add_action_callback('recommend') do |_context,payload|
      next unless @dialog.equal?(dialog)
      begin
        params,_request=settings_from(payload)
        target=validate_target
        recommendation=SuPvDesignRecommendations.array(params,target)
        dialog.execute_script("window.PVDesignAdvice.receive(#{JSON.generate(recommendation)});")
      rescue StandardError=>error
        dialog.execute_script("window.PVDesignAdvice.fail(#{JSON.generate(error.message)});")
      end
    end
    if @edit_path
      dialog.add_action_callback('access_pick') { |_context,payload| pick_access(payload) if @dialog.equal?(dialog) }
    end
    dialog.add_action_callback('repick') do |_context|
      next unless @dialog.equal?(dialog)
      begin
        @edit_path ? SuPvConstraintsTool.activate : activate
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
      single = SuPvPanelTool.energy_for(@spec, params['azimuth'], params['tilt'])
      raise "#{SuPvPanelTool.missing_data_message(params['azimuth'])}。" unless single
      single.each_with_index do |value, index|
        original = value * plan['count']
        tolerance = [1e-6, original.abs * 1e-9].max
        valid = branch == 'baseline' ? (values[index] - original).abs <= tolerance : values[index] <= original + tolerance
        raise '导出出力与当前阵列不一致，请重新计算。' unless valid
      end
      { values: values, spec: @spec, settings: params, count: plan['count'], branch: branch }
    end unless @edit_path
    dialog.set_on_closed do
      next unless @dialog.equal?(dialog)
      @dialog = nil
      @ready = false
      @plan = nil
      @model.select_tool(nil) if @tool && @model == Sketchup.active_model
    end
    dialog.set_file(SuPvPanelTool.project_path('ui/pv_array.html'))
    dialog.show
  end

  class FaceTool
    def initialize(model)
      @model = model
    end
    def activate
      message=SuPvArrayTool.instance_variable_get(:@edit_path) ? '边界约束：调整参数后更新阵列；Esc退出。' : "光伏阵列：点击组件中的#{SuPvArrayTool.face_description}；Esc取消。"
      Sketchup.set_status_text(message)
    end
    def onMouseMove(_flags, x, y, view)
      return if SuPvArrayTool.instance_variable_get(:@access_pick_pending)
      return if SuPvArrayTool.instance_variable_get(:@edit_path)
      @hover = SuPvArrayTool.pick(view, x, y)
      view.tooltip = "安装面 · #{(@hover[:width] / 1000.0).round(2)} × #{(@hover[:height] / 1000.0).round(2)} m"
      view.invalidate
    rescue StandardError => error
      @hover = nil
      view.tooltip = error.message
      view.invalidate
    end
    def onLButtonDown(_flags, x, y, view)
      return if SuPvArrayTool.instance_variable_get(:@access_pick_pending)
      return if SuPvArrayTool.instance_variable_get(:@edit_path)
      raise '活动模型已改变，请重新选面。' unless @model == Sketchup.active_model
      SuPvArrayTool.select_target(SuPvArrayTool.pick(view, x, y))
      view.invalidate
    rescue StandardError => error
      SuPvArrayTool.fail_ui(error)
    end
    def draw(view)
      target = @hover || SuPvArrayTool.instance_variable_get(:@target)
      return unless target && target[:model] == @model
      view.drawing_color = Sketchup::Color.new(33, 102, 172)
      view.line_width = 2
      (target[:world_loops] || [target[:points]]).each { |ring| view.draw(GL_LINE_LOOP, ring) }
      plan = SuPvArrayTool.instance_variable_get(:@plan)
      return unless plan
      w, l = SuPvArrayTool.instance_variable_get(:@spec).values_at(:width_mm, :length_mm).map(&:mm)
      view.line_width = 1
      plan['positions'].first(500).each do |position|
        transform = SuPvArrayTool.panel_transform(position,plan)
        points = [[0,0,0],[w,0,0],[w,l,0],[0,l,0]].map { |p| Geom::Point3d.new(p).transform(transform) }
        view.draw(GL_LINE_LOOP, points)
      end
    end
    def onCancel(_reason, _view)
      SuPvArrayTool.instance_variable_get(:@dialog)&.close
      @model.select_tool(nil)
    end
    def deactivate(view)
      SuPvArrayTool.instance_variable_set(:@tool, nil) if SuPvArrayTool.instance_variable_get(:@tool).equal?(self)
      Sketchup.set_status_text('')
      view.invalidate
    end
  end
end

# Ruby load replaces methods, but does not replace callbacks in an existing
# HtmlDialog. Dispose that window so the next opening registers every action.
SuPvArrayTool.reset_ui
