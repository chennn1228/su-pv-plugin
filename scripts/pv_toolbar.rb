# encoding: UTF-8
require 'sketchup.rb'
load File.expand_path('tools/button_01_station.rb', __dir__)
load File.expand_path('tools/button_02_panel.rb', __dir__)
load File.expand_path('tools/button_03_array.rb', __dir__)
load File.expand_path('tools/button_04_prediction.rb', __dir__)
SuPvPanelTool.retire_legacy_toolbar
[defined?(SuPvToolbar1) && SuPvToolbar1, defined?(SuPvToolbar2) && SuPvToolbar2].each do |legacy|
  legacy.instance_variable_get(:@toolbar)&.hide if legacy
end
load File.expand_path('tools/button_05_export_csv.rb', __dir__)
load File.expand_path('tools/button_06_export_svg.rb', __dir__)
load File.expand_path('tools/button_07_constraints.rb', __dir__)
load File.expand_path('tools/button_08_electrical.rb', __dir__)
module SuPvToolbar
  def self.run(tool)
    tool.activate
  rescue StandardError, LoadError => error
    warn "[变电站光伏] #{error.full_message}"
    UI.messagebox(error.message)
  end
  def self.setup
    existing=Array(@commands).to_h { |command| [command.tooltip,command] }
    existing['导出 SVG / DXF'] ||= existing['导出 SVG']
    buttons = [
      ['标准变电站', SuPvStationTool, 'insert_station'],
      ['光伏板与出力', SuPvPanelTool, 'pv_panel'],
      ['阵列与出力', SuPvArrayTool, 'pv_array'],
      ['边界约束', SuPvConstraintsTool, 'pv_constraints'],
      ['电气配置', SuPvElectricalTool, 'pv_electrical'],
      ['预测出力', SuPvPredictionTool, 'pv_prediction'],
      ['导出 CSV', SuPvCsvExportTool, 'pv_export_csv'],
      ['导出 SVG / DXF', SuPvSvgExportTool, 'pv_export_svg']
    ]
    if @toolbar && @schema != 'unified_20261027_cad'
      @toolbar.hide
      @retired_toolbars ||= []
      @retired_toolbars << @toolbar
      @retired_commands ||= []
      @retired_commands.concat(Array(@commands))
      @toolbar = nil
    end
    unless @toolbar
      new_commands=[]
      @commands = buttons.map do |label, tool, icon|
        if existing[label]
          existing[label].tooltip=label
          existing[label].status_bar_text=label
          next existing[label]
        end
        command = UI::Command.new(label) { SuPvToolbar.run(tool) }
        command.tooltip = label
        command.status_bar_text = label
        command.small_icon = File.expand_path("../icons/#{icon}_24.png", __dir__)
        command.large_icon = File.expand_path("../icons/#{icon}_32.png", __dir__)
        new_commands<<command
        command
      end
      @toolbar = UI::Toolbar.new('变电站光伏')
      @menu ||= UI.menu('Extensions').add_submenu('变电站光伏')
      @commands.each { |command| @toolbar.add_item(command) }
      new_commands.each { |command| @menu.add_item(command) }
      @schema = 'unified_20261027_cad'
    end
    UI.start_timer(0.1, false) { @toolbar.show }
  end
end
SuPvToolbar.setup
puts '变电站光伏：标准变电站、光伏板与出力、阵列与出力、边界约束、电气配置、预测出力、导出CSV、导出SVG/DXF。'
