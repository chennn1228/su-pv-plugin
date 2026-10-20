# encoding: UTF-8
# toolbar2：变电站、单板、阵列、预测出力、平铺排布。
# load 'D:/Administrator Files/SEU/12.Project/260911_SU PV plugin/project/scripts/pv_toolbar.rb'
require 'sketchup.rb'
load File.expand_path('toolbar2/button_01_insert_station.rb', __dir__)
load File.expand_path('toolbar2/button_02_pv_panel.rb', __dir__)
load File.expand_path('toolbar2/button_03_pv_array.rb', __dir__)
load File.expand_path('toolbar2/button_05_flush_array.rb', __dir__)
load File.expand_path('toolbar2/button_04_prediction.rb', __dir__)
SuPvPanelTool.retire_legacy_toolbar

module SuPvToolbar2
  def self.schema
    'substation_pv_toolbar2_flush_v1'
  end

  def self.run(tool)
    tool.activate
  rescue StandardError, LoadError => error
    warn "[变电站光伏] #{error.class}: #{error.message}"
    UI.messagebox("操作失败：#{error.message}")
  end

  def self.insert
    run(SuPvStationTool)
  end

  def self.show
    return false unless @registration_schema == schema && @toolbar && @toolbar.length == 5
    UI.start_timer(0.1, false) { @toolbar.show }
    true
  end

  def self.create_command(label, tool, icon, hint)
    small = File.expand_path("../icons/#{icon}_24.png", __dir__)
    large = File.expand_path("../icons/#{icon}_32.png", __dir__)
    [small, large].each { |path| raise "图标文件不存在：#{path}" unless File.file?(path) }
    command = UI::Command.new(label) { SuPvToolbar2.run(tool) }
    command.small_icon = small
    command.large_icon = large
    command.tooltip = label
    command.status_bar_text = hint
    command
  end

  def self.setup
    buttons = [
      ['插入标准变电站', SuPvStationTool, 'insert_station', '逐面重建标准变电站；点击放置，Esc取消。'],
      ['光伏板', SuPvPanelTool, 'pv_panel', '选择板型、调整角度并放置光伏板。'],
      ['光伏阵列', SuPvArrayTool, 'pv_array', '选择安装面，预览并生成光伏阵列。'],
      ['预测出力', SuPvPredictionTool, 'pv_prediction', '选择已放置的光伏板或阵列，查看预测、互遮挡及导出CSV。'],
      ['平铺排布', SuPvFlushTool, 'pv_flush', '选择安装面，用原生参数小窗设置平铺阵列。']
    ]
    if @toolbar
      if @registration_schema=='substation_pv_toolbar2_v1' && @toolbar.length==4 && @commands.is_a?(Array) && @commands.length==4 && @menu
        command=create_command(*buttons.last)
        @toolbar.add_item(command);@menu.add_item(command);@commands<<command
        @registration_schema=schema
      end
      if @registration_schema == schema && @toolbar.length == buttons.length
        buttons.zip(@commands).each do |button, command|
          command.tooltip = button[0]
          command.status_bar_text = button[3]
        end
        return true
      end
      # 已污染的旧会话不能用再次追加或新建同名工具栏修复。
      @toolbar.hide
      Array(@retired_toolbars).compact.each(&:hide)
      warn '检测到旧版工具栏注册。请关闭并重启SU，再加载本文件一次；本次未注册任何新按钮。'
      return false
    end
    # 永久保存Command的Ruby引用；避免丢失引用后原生UI状态异常。
    commands = buttons.map { |button| create_command(*button) }
    toolbar = UI::Toolbar.new('变电站光伏 · toolbar2')
    commands.each { |command| toolbar.add_item(command) }
    menu = UI.menu('Extensions').add_submenu('变电站光伏 · toolbar2')
    menu.add_item('显示工具栏') { SuPvToolbar2.show }
    commands.each { |command| menu.add_item(command) }
    @commands, @toolbar, @menu = commands, toolbar, menu
    @registration_schema = schema
    true
  end
end

if SuPvToolbar2.setup
  SuPvToolbar2.show
  puts 'toolbar2 已加载5个按钮：变电站、光伏板、光伏阵列、预测出力、平铺排布。重复load不会追加按钮。'
end
