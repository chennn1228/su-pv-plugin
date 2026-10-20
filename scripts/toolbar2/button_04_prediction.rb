# encoding: UTF-8
require 'sketchup.rb'
require 'json'
load File.expand_path('support/forecast_snapshot.rb', __dir__)

module SuPvPredictionTool
  def self.panel?(entity)
    entity.is_a?(Sketchup::ComponentInstance) && entity.get_attribute('SuPvPanelTool', 'model_id')
  end

  def self.array?(entity)
    entity.respond_to?(:entities) && entity.get_attribute('SuPvArrayTool', 'settings')
  end

  def self.activate
    @model = Sketchup.active_model
    raise '请退出组件编辑后再选择预测对象。' if @model.active_path
    selected = @model.selection.to_a
    if selected.length == 1 && (panel?(selected.first) || array?(selected.first))
      select_target(selected.first)
    else
      pick_target
    end
  end

  def self.pick_target
    @target = nil
    @dialog.execute_script("window.PVArray.waitForSelection();") if @dialog
    @tool = SelectionTool.new(@model)
    @model.select_tool(@tool)
  end

  def self.records
    raise '活动模型已改变，请重新打开预测。' unless @model == Sketchup.active_model
    raise '请退出组件编辑后再预测。' if @model.active_path
    raise '预测对象已删除，请重新选择。' unless @target && @target.valid?
    result = []
    collect = lambda do |entity, parent|
      transform = parent * entity.transformation
      if panel?(entity)
        result << { 'model_id'=>entity.get_attribute('SuPvPanelTool','model_id'),
          'origin_mm'=>transform.origin.to_a.map(&:to_mm),
          'axes'=>[transform.xaxis,transform.yaxis,transform.zaxis].map(&:to_a) }
      elsif array?(entity)
        entity.entities.each { |child| collect.call(child, transform) if panel?(child) || array?(child) }
      end
    end
    collect.call(@target, Geom::Transformation.new)
    result
  end

  def self.select_target(entity)
    @target = entity
    data = records
    @snapshot = SuPvForecastSnapshot.build(data)
    if array?(@target)
      normal=@target.transformation.zaxis.to_a
      normal=normal.map { |x| -x } if normal[2]<0
      @snapshot['roof_normal']=SuPvRoofAngles.limits(normal)['normal']
    end
    @fingerprint = JSON.generate(data)
    @target_id = (@target_id || 0) + 1
    @snapshot.merge!('target_id'=>@target_id, 'request_id'=>0,
      'catalog'=>SuPvPanelTool.panel_catalog,
      'prediction'=>SuPvArrayTool.prediction_for(@snapshot, @snapshot['spec']))
    @model.select_tool(nil) if @tool
    show_dialog
    send_data if @ready
  end

  def self.send_data
    @dialog.execute_script("window.PVArray.receive(#{JSON.generate(@snapshot)});") if @dialog && @snapshot
  end

  def self.show_dialog
    if @dialog && @dialog.visible?
      @dialog.bring_to_front
      return
    end
    dialog = UI::HtmlDialog.new(dialog_title:'toolbar2 · 预测出力', preferences_key:'SuPvPredictionTool.Window',
      width:1180, height:780, min_width:900, min_height:650,
      scrollable:false, resizable:true, style:UI::HtmlDialog::STYLE_DIALOG)
    @dialog, @ready = dialog, false
    dialog.add_action_callback('ready') do |_context|
      next unless @dialog.equal?(dialog)
      @ready = true
      send_data
    end
    dialog.add_action_callback('repick') { |_context| pick_target if @dialog.equal?(dialog) }
    SuPvGenerationExport.bind(dialog, current: -> { @dialog.equal?(dialog) }) do |data|
      raise '模型已改变，请重新选择后计算。' unless @fingerprint == JSON.generate(records)
      context = data.fetch('context')
      raise '预测对象已改变，请重新计算。' unless context.fetch('target_id') == @target_id && context.fetch('count') == @snapshot['count'] && data.fetch('settings') == @snapshot['settings']
      values, branch = data.fetch('values'), context.fetch('branch')
      raise '预测分支无效。' unless ['baseline','shade'].include?(branch)
      SuPvGenerationExport.validate_values(values)
      @snapshot['prediction'].fetch(:values).each_with_index do |original,index|
        tolerance = [1e-6,original.abs*1e-9].max
        valid = branch == 'baseline' ? (values[index]-original).abs <= tolerance : values[index] <= original+tolerance
        raise '出力结果已失效，请重新计算。' unless valid
      end
      {values:values, spec:@snapshot['spec'], settings:@snapshot['settings'], count:@snapshot['count'], branch:branch}
    end
    dialog.set_on_closed do
      next unless @dialog.equal?(dialog)
      @dialog, @ready = nil, false
      @model.select_tool(nil) if @tool && @model == Sketchup.active_model
    end
    dialog.set_file(SuPvPanelTool.project_path('ui/pv_array.html'))
    dialog.show
  end

  class SelectionTool
    def initialize(model); @model = model; end
    def activate; Sketchup.set_status_text('预测出力：点击光伏板或阵列；Esc取消。'); end
    def onLButtonDown(_flags,x,y,view)
      raise '活动模型已改变，请重新打开预测。' unless @model == Sketchup.active_model
      hit = @model.raytest(view.pickray(x,y),true)
      path = hit && hit[1]
      target = path && path.find { |e| SuPvPredictionTool.array?(e) || SuPvPredictionTool.panel?(e) }
      raise '请点击本插件生成的光伏板或阵列。' unless target
      # Forecast roots are selected outside component editing, so their world transform is complete.
      raise '请选择模型顶层的光伏板或阵列。' unless path.first.equal?(target)
      SuPvPredictionTool.select_target(target)
    rescue StandardError => error
      UI.messagebox(error.message)
    end
    def onCancel(_reason,_view); @model.select_tool(nil); end
    def deactivate(view)
      SuPvPredictionTool.instance_variable_set(:@tool,nil) if SuPvPredictionTool.instance_variable_get(:@tool).equal?(self)
      Sketchup.set_status_text('')
      view.invalidate
    end
  end
end
