# encoding: UTF-8
require 'sketchup.rb'
require 'json'
load File.expand_path('../support/forecast_snapshot.rb', __dir__)
load File.expand_path('../support/scene_snapshot.rb', __dir__)
load File.expand_path('../support/horizontal_svg.rb', __dir__)

module SuPvPredictionTool
  def self.panel?(entity)
    entity.is_a?(Sketchup::ComponentInstance) && entity.get_attribute('SuPvPanelTool', 'model_id')
  end

  def self.array?(entity)
    entity.respond_to?(:entities) && entity.get_attribute('SuPvArrayTool', 'settings')
  end

  def self.activate(export_format=nil)
    @model=Sketchup.active_model
    raise '请退出组件编辑后再选择预测对象。' if @model.active_path
    raise '导出格式无效。' unless [nil,'csv','svg'].include?(export_format)
    @export_format=export_format
    pick_target
  end

  def self.pick_target(paths=[])
    @paths=[]
    @dialog.execute_script("window.PVArray.waitForSelection();") if @dialog
    @dialog.hide if @dialog && @dialog.visible?
    @tool=SelectionTool.new(@model,paths,action: @export_format ? "导出 #{@export_format.upcase}" : '预测出力')
    @model.select_tool(@tool)
  end

  def self.records
    raise '活动模型已改变，请重新选择。' unless @model==Sketchup.active_model && !@model.active_path
    raise '请选择光伏板。' unless @paths && !@paths.empty?
    raise '预测对象已删除，请重新选择。' unless @paths.flatten.all?(&:valid?)
    @paths.flat_map { |path| SuPvSceneSnapshot.panels_in(path) }.uniq { |p| p['key'] }
  end

  def self.select_targets(paths)
    @paths=paths
    data=records
    if @export_format
      @model.select_tool(nil)
      return export_selected(data)
    end
    @snapshot=SuPvForecastSnapshot.build(data)
    if @paths.length==1 && array?(@paths.first.last)
      tr=@paths.first.inject(Geom::Transformation.new) { |t,e| t*e.transformation }
      normal=tr.zaxis.to_a
      normal=normal.map { |v| -v } if normal[2]<0
      @snapshot['roof_normal']=SuPvRoofAngles.limits(normal)['normal']
    end
    SuPvSceneSnapshot.attach(@snapshot,@model,@snapshot['world_origin_mm'],data.map { |p| p['key'] })
    @fingerprint=JSON.generate(data)
    @target_id=(@target_id || 0)+1
    @snapshot.merge!('target_id'=>@target_id,'request_id'=>0,
      'catalog'=>SuPvPanelTool.panel_catalog)
    @model.select_tool(nil)
    show_dialog
    send_data if @ready
  end

  def self.export_selected(data)
    if @export_format=='svg'
      SuPvFigureExport.save(body:SuPvHorizontalSvg.render(data))
    elsif @export_format=='csv'
      snapshot=SuPvForecastSnapshot.build(data)
      prediction=snapshot.fetch('prediction')
      unless prediction[:data_available]
        reason = prediction[:missing_data_message] || '所选光伏板有暂缺出力数据的角度或型号'
        raise "#{reason}，暂无法导出总出力。"
      end
      SuPvGenerationExport.save(values:prediction.fetch(:values),spec:snapshot['spec'],
        settings:snapshot['settings'].merge('selection'=>true),count:snapshot['count'],branch:'baseline')
    else
      raise '导出格式无效。'
    end
  end

  def self.send_data
    @dialog.execute_script("window.PVArray.receive(#{JSON.generate(@snapshot)});") if @dialog && @snapshot
  end

  def self.show_dialog
    if @dialog
      @dialog.show
      @dialog.bring_to_front
      return
    end
    dialog = UI::HtmlDialog.new(dialog_title:'预测出力', preferences_key:'SuPvPredictionTool.Window',
      width:1180, height:780, min_width:900, min_height:650,
      scrollable:false, resizable:true, style:UI::HtmlDialog::STYLE_DIALOG)
    @dialog, @ready = dialog, false
    SuPvFigureExport.bind(dialog, current: -> { @dialog.equal?(dialog) })
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
      {values:values, spec:@snapshot['spec'], settings:@snapshot['settings'].merge('selection'=>true), count:@snapshot['count'], branch:branch}
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
    def initialize(model,paths=[],action:'预测出力'); @model=model;@paths=paths;@action=action;@confirming=false;@deactivated=false;end
    def activate; highlight;end
    def highlight
      @model.selection.clear
      @paths.map(&:first).uniq.each { |e| @model.selection.add(e) }
      count=@paths.flat_map { |path| SuPvSceneSnapshot.panels_in(path) }.uniq { |p| p['key'] }.length
      Sketchup.set_status_text("#{@action}：已选#{count}块；点击增减，Ctrl点选单板；Enter确认，Esc取消。")
    end
    def onLButtonDown(flags,x,y,view)
      raise '活动模型已改变。' unless @model==Sketchup.active_model
      hit=@model.raytest(view.pickray(x,y),true)
      path=hit && hit[1]
      raise '请点击光伏板或包含光伏板的群组。' unless path
      # Default picks the outer group; Ctrl selects an individual nested panel.
      panel_index=path.index { |e| SuPvSceneSnapshot.panel?(e) }
      target= if (flags & COPY_MODIFIER_MASK)!=0 && panel_index
        path[0..panel_index]
      else
        path.each_index.map { |i| path[0..i] }.find { |candidate| SuPvSceneSnapshot.children(candidate.last) && !SuPvSceneSnapshot.panels_in(candidate).empty? }
      end
      raise '该对象中没有光伏板。' unless target
      key=SuPvSceneSnapshot.key(target)
      existing=@paths.find { |p| SuPvSceneSnapshot.key(p)==key }
      if existing
        @paths.delete(existing)
      else
        @paths.reject! { |p| SuPvSceneSnapshot.key(p).start_with?(key+'/') }
        @paths << target unless @paths.any? { |p| key.start_with?(SuPvSceneSnapshot.key(p)+'/') }
      end
      highlight;view.invalidate
    rescue StandardError => error
      UI.messagebox(error.message)
    end
    def onKeyDown(key,_repeat,_flags,_view)
      return false unless key==13
      @confirmation_paths||=@paths.map(&:dup) unless @confirming || @deactivated
      true
    end
    def onKeyUp(key,_repeat,_flags,_view)
      return false unless key==13
      if @confirmation_paths && !@confirming && !@deactivated
        paths=@confirmation_paths;@confirmation_paths=nil;@confirming=true
        # Consume the whole key cycle before replacing the tool. Otherwise the
        # native Select tool can also interpret Enter as opening a component.
        UI.start_timer(0,false) do
          next if @deactivated
          begin
            confirm_selection(paths)
          rescue StandardError=>error
            @confirming=false
            UI.messagebox(error.message)
          end
        end
      end
      true
    end
    def confirm_selection(paths);SuPvPredictionTool.select_targets(paths);end
    def onCancel(_reason,_view);@deactivated=true;@confirmation_paths=nil;@model.select_tool(nil);end
    def deactivate(view)
      @deactivated=true;@confirmation_paths=nil
      SuPvPredictionTool.instance_variable_set(:@tool,nil) if SuPvPredictionTool.instance_variable_get(:@tool).equal?(self)
      Sketchup.set_status_text('');view.invalidate
    end
  end
end
