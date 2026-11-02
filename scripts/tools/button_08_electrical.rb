# encoding: UTF-8
load File.expand_path('../support/electrical_design.rb',__dir__)
module SuPvElectricalTool
  def self.activate
    @model=Sketchup.active_model
    raise '请退出组件编辑后选择光伏阵列。' unless Array(@model.active_path).empty?
    @dialog.close if @dialog
    @dialog=nil
    paths=@model.selection.to_a.select { |e| SuPvPredictionTool.array?(e) || SuPvSceneSnapshot.panel?(e) }.map { |e| [e] }
    @tool=SelectionTool.new(@model,paths,action:'电气配置')
    @model.select_tool(@tool)
  end
  def self.records
    raise SuPvElectricalDesign::ValidationError,'活动模型已切换，请重新选择。' unless Sketchup.active_model==@model
    raise SuPvElectricalDesign::ValidationError,'请退出组件编辑后重试。' unless Array(@model.active_path).empty?
    raise SuPvElectricalDesign::ValidationError,'所选对象已删除。' unless @paths && @paths.flatten.all?(&:valid?)
    @paths.flat_map { |p| SuPvSceneSnapshot.panels_in(p) }.uniq { |r| r['key'] }
  end
  def self.selected(paths,model=@model)
    @model=model;@paths=paths;data=records
    raise '请选择一个同型号阵列，或同型号的一组光伏板。' if data.empty? || data.map { |r| r['model_id'] }.uniq.length!=1
    raise '最多支持5000块组件。' if data.length>5000
    @spec=SuPvPanelTool.panel_spec(data.first['model_id']);@snapshot_records=Marshal.load(Marshal.dump(data));@fingerprint=JSON.generate(data)
    @model.select_tool(nil);@ready=false
    dialog=UI::HtmlDialog.new(dialog_title:'电气配置',preferences_key:'SuPvElectricalTool.Window',width:1220,height:820,min_width:940,min_height:650,scrollable:false,resizable:true,style:UI::HtmlDialog::STYLE_DIALOG)
    @dialog=dialog
    SuPvFigureExport.bind(dialog,current:-> { @dialog.equal?(dialog) },filename:'pv_electrical_single_line.svg',
      validate:-> { raise '阵列已改变，请重新生成电气方案后导出。' unless SuPvElectricalDesign.same_geometry?(@snapshot_records,records) })
    dialog.add_action_callback('ready') do |_context|
      next unless @dialog.equal?(dialog)
      saved=JSON.parse(@model.get_attribute('SuPvElectricalTool','design','null')) rescue nil
      saved_records=(saved && JSON.parse(saved['fingerprint'])) rescue nil
      saved=nil unless saved && SuPvElectricalDesign.same_geometry?(@snapshot_records,saved_records)
      # Old uniform-length plans could leave panels disconnected. Keep their
      # verified device inputs, but regenerate a full plan in automatic mode.
      saved_input=saved && saved['input'].is_a?(Hash) && saved['input'].dup
      if saved_input && (!saved['result'].is_a?(Hash) || saved['result']['connected_count']!=data.length)
        saved_input['series_count']=0
      end
      @ready=true
      dialog.execute_script("window.PVElectrical.receive(#{JSON.generate({records:data,spec:@spec,presets:SuPvElectricalPresets.for_spec(@spec),module_errors:SuPvElectricalDesign.module_errors(@spec[:electrical],@spec[:power_w]),saved:saved_input || nil})});")
    end
    dialog.add_action_callback('calculate') { |_context,payload| calculate(dialog,payload,false) if @dialog.equal?(dialog) }
    dialog.add_action_callback('save') { |_context,payload| calculate(dialog,payload,true) if @dialog.equal?(dialog) }
    dialog.add_action_callback('repick') { |_context| activate if @dialog.equal?(dialog) }
    dialog.set_on_closed { @dialog=nil if @dialog.equal?(dialog) }
    dialog.set_file(SuPvPanelTool.project_path('ui/pv_electrical.html'));dialog.show
  end
  def self.calculate(dialog,payload,save)
    data=JSON.parse(payload);current=records
    raise SuPvElectricalDesign::ValidationError,'阵列已移动或修改，请重新选择后生成电气方案。' unless SuPvElectricalDesign.same_geometry?(@snapshot_records,current)
    result=SuPvElectricalDesign.calculate(current,@spec,data.fetch('input'))
    if save
      @model.start_operation('保存光伏电气配置',true)
      begin
        @model.set_attribute('SuPvElectricalTool','design',JSON.generate({fingerprint:@fingerprint,input:data['input'],result:result,losses_applied:false}))
        @model.commit_operation
      rescue StandardError
        @model.abort_operation;raise
      end
    end
    dialog.execute_script("window.PVElectrical.result(#{JSON.generate(result.merge(request_id:data['request_id'],saved:save))});")
  rescue StandardError=>error
    expected=error.is_a?(SuPvElectricalDesign::ValidationError)
    unless expected
      warn "[变电站光伏/电气配置] #{error.full_message}"
      begin
        # Keep the latest failure locally so the exact SU selection can be replayed.
        path=SuPvPanelTool.project_path('output/electrical_error.json')
        Dir.mkdir(File.dirname(path)) unless Dir.exist?(File.dirname(path))
        File.write(path,JSON.generate({error:error.full_message,records:current,spec:@spec,input:data && data['input']}))
      rescue StandardError=>diagnostic_error
        warn "[变电站光伏/电气诊断] #{diagnostic_error.message}"
      end
    end
    message=expected ? error.message : '电气计算异常，已记录诊断信息。'
    kind=expected ? 'constraint' : 'internal'
    dialog.execute_script("window.PVElectrical.fail(#{JSON.generate(message)},#{JSON.generate(data && data['request_id'])},#{JSON.generate(kind)});") if @dialog.equal?(dialog)
  end
  class SelectionTool < SuPvPredictionTool::SelectionTool
    # Remove the previous override as well when this script is reloaded in SU.
    remove_method(:onKeyDown) if instance_methods(false).include?(:onKeyDown)
    def confirm_selection(paths);SuPvElectricalTool.selected(paths,@model);end
    def deactivate(view)
      super
      SuPvElectricalTool.instance_variable_set(:@tool,nil) if SuPvElectricalTool.instance_variable_get(:@tool).equal?(self)
    end
  end
end
