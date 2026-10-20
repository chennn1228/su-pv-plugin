# encoding: UTF-8
require 'sketchup.rb'
require 'json'
load File.expand_path('support/flush_layout.rb',__dir__)

module SuPvFlushTool
  def self.panels; defined?(SuPvPanelTool) ? SuPvPanelTool : SuPvPanelTool1; end
  def self.faces; defined?(SuPvArrayTool) ? SuPvArrayTool : SuPvArrayTool1; end

  def self.activate
    model=Sketchup.active_model
    raise '请退出组件编辑后再选择屋面。' if model.active_path
    selected=model.selection.to_a
    if selected.length==1 && selected.first.is_a?(Sketchup::ComponentInstance)
      component=selected.first
      face_list=component.definition.entities.grep(Sketchup::Face)
      return input_and_build(faces.frame_from_path([component,face_list.first])) if face_list.length==1
    end
    model.select_tool(FaceTool.new(model))
  end

  def self.input_and_build(target)
    catalog=panels.panel_catalog
    labels=catalog.map { |s| "#{s[:manufacturer]}－#{s[:material]}－#{s[:power_w].to_i} W" }
    defaults=@defaults || [labels.first,'长边沿屋面纵向',10,50,0]
    defaults[0]=labels.first unless labels.include?(defaults[0])
    slope=SuPvRoofAngles.limits(target[:normal].to_a)['slope_deg'].round(1)
    title="平铺排布 · 屋面#{slope}° / 板面#{slope}°"
    loop do
      answer=UI.inputbox(['板型','排布方向','横向净距（cm）','纵向净距（cm）','离屋面高度（cm）'],
        defaults,[labels.join('|'),'长边沿屋面纵向|长边沿屋面横向','','',''],title)
      return false unless answer
      defaults=answer
      begin
        index=labels.index(answer[0])
        raise ArgumentError,'请选择有效板型。' unless index
        spec=catalog[index]
        raise ArgumentError,'请选择有效排布方向。' unless ['长边沿屋面纵向','长边沿屋面横向'].include?(answer[1])
        gx,gy,height=answer.drop(2).map { |v| Float(v)*10 }
        plan=SuPvFlushLayout.plan(target[:width],target[:height],target[:region],spec,answer[1]=='长边沿屋面横向',gx,gy,height)
      rescue ArgumentError,TypeError => error
        UI.messagebox(error.message)
        next
      end
      build(target,spec,plan,gx,gy,height)
      @defaults=answer
      return true
    end
  end

  def self.build(target,spec,plan,gx,gy,height)
    model=Sketchup.active_model
    raise '活动模型已改变，请重新选择屋面。' unless model==target[:model] && !model.active_path
    current=faces.frame_from_path(target[:path])
    before,after=target[:world_loops],current[:world_loops]
    valid=before.length==after.length && before.zip(after).all? { |a,b| a.length==b.length && a.zip(b).all? { |p,q| p.distance(q).to_mm<0.01 } }
    raise '屋面已改变，请重新选择。' unless valid
    normal=target[:normal]
    tilt=Math.atan2(Math.sqrt(normal.x**2+normal.y**2),normal.z)*180/Math::PI
    azimuth=tilt<1e-7 ? 180.0 : (Math.atan2(normal.x,normal.y)*180/Math::PI+360)%360
    angles={'model_id'=>spec[:id],'azimuth'=>azimuth.round(6),'tilt'=>tilt.round(6)}
    a,b=(azimuth/5).round*5,(tilt/3).round*3
    values=if (azimuth-a).abs<1e-6 && (tilt-b).abs<1e-6 && (90..270).cover?(a) && (0..90).cover?(b)
      panels.energy_for(spec,a,b)
    end
    annual=values && values.inject(0.0,:+)/1000.0
    frame=Geom::Transformation.axes(target[:origin],target[:u],target[:v],normal)
    local_axes=plan[:axes].map { |axis| Geom::Vector3d.new(*axis) }
    model.start_operation('平铺排布光伏板',true)
    begin
      definition=panels.panel_definition(model,spec)
      group=model.entities.add_group
      group.name='PV_array_flush'
      group.layer=model.layers[0]
      group.transformation=frame
      layer=model.layers['PV_panel'] || model.layers.add('PV_panel')
      plan[:positions].each do |position|
        transform=Geom::Transformation.axes(Geom::Point3d.new(position.map(&:mm)),*local_axes)
        instance=group.entities.add_instance(definition,transform)
        instance.layer=layer
        panels.apply_metadata(instance,angles,values,annual,spec)
      end
      settings=angles.merge('layout'=>'flush','gap_x_mm'=>gx,'gap_y_mm'=>gy,'clearance_mm'=>height)
      group.set_attribute('SuPvArrayTool','settings',JSON.generate(settings))
      group.set_attribute('SuPvArrayTool','count',plan[:count])
      group.set_attribute('SuPvArrayTool','source_path',target[:path].map(&:persistent_id))
      model.commit_operation
    rescue StandardError
      model.abort_operation
      raise
    end
    model.selection.clear
    model.selection.add(group)
    model.active_view.invalidate
  end

  class FaceTool
    def initialize(model);@model=model;end
    def activate;Sketchup.set_status_text('平铺排布：点击组件中的平屋面或斜屋面；Esc取消。');end
    def pick(view,x,y)
      raise '活动模型已改变，请重新启动平铺排布。' unless Sketchup.active_model==@model
      hit=@model.raytest(view.pickray(x,y),true)
      raise '请点击组件中的安装面。' unless hit
      SuPvFlushTool.faces.frame_from_path(hit[1])
    end
    def onMouseMove(_flags,x,y,view)
      @hover=pick(view,x,y);view.tooltip='平铺排布';view.invalidate
    rescue StandardError => error
      @hover=nil;view.tooltip=error.message;view.invalidate
    end
    def draw(view)
      return unless @hover
      view.drawing_color=Sketchup::Color.new(33,102,172);view.line_width=2
      @hover[:world_loops].each { |ring| view.draw(GL_LINE_LOOP,ring) }
    end
    def onLButtonDown(_flags,x,y,view)
      SuPvFlushTool.input_and_build(pick(view,x,y))
      @model.select_tool(nil)
    rescue StandardError => error
      UI.messagebox(error.message)
    end
    def onCancel(_reason,_view);@model.select_tool(nil);end
    def deactivate(view);Sketchup.set_status_text('');view.invalidate;end
  end
end
