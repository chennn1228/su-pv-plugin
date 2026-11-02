# encoding: UTF-8
# Existing arrays share the same planner, settings and boundary workspace.
module SuPvConstraintsTool
  def self.activate
    model=Sketchup.active_model
    raise '请退出组件编辑后再选择阵列。' if model.active_path
    SuPvArrayTool.reset_ui
    @tool=SelectionTool.new(model)
    model.select_tool(@tool)
  end

  class SelectionTool
    def initialize(model);@model=model;end
    def activate
      Sketchup.set_status_text('边界约束：点击自动生成的光伏阵列；Esc取消。')
    end
    def pick(view,x,y)
      raise '活动模型已改变，请重新选择阵列。' unless @model==Sketchup.active_model
      hit=@model.raytest(view.pickray(x,y),true)
      path=hit && hit[1]
      index=path && (path.length-1).downto(0).find do |i|
        entity=path[i]
        entity.is_a?(Sketchup::Group) && entity.get_attribute('SuPvArrayTool','settings')
      end
      raise '请点击自动生成的光伏阵列。' unless index
      path[0..index]
    end
    def onMouseMove(_flags,x,y,view)
      pick(view,x,y)
      view.tooltip='边界约束 · 编辑此阵列'
    rescue StandardError=>error
      view.tooltip=error.message
    end
    def onLButtonDown(_flags,x,y,view)
      SuPvArrayTool.open_existing(pick(view,x,y))
    rescue StandardError=>error
      UI.messagebox(error.message)
    end
    def onCancel(_reason,_view);@model.select_tool(nil);end
    def deactivate(view);Sketchup.set_status_text('');view.invalidate;end
  end
end
