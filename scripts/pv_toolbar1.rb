# encoding: UTF-8
# toolbar1：放置与出力集成，附原生参数框平铺排布。
# load 'D:/Administrator Files/SEU/12.Project/260911_SU PV plugin/project/scripts/pv_toolbar.rb'
require 'sketchup.rb'
load File.expand_path('toolbar2/button_01_insert_station.rb', __dir__)
load File.expand_path('toolbar1/button_02_pv_panel.rb', __dir__)
load File.expand_path('toolbar1/button_03_pv_array.rb', __dir__)
load File.expand_path('toolbar2/button_05_flush_array.rb', __dir__)
SuPvPanelTool1.retire_legacy_toolbar

module SuPvToolbar1
  def self.schema
    'substation_pv_toolbar1_flush_v1'
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
    return false unless @registration_schema == schema && @toolbar && @toolbar.length == 4
    UI.start_timer(0.1, false) { @toolbar.show }
    true
  end

  def self.create_command(label, tool, icon, hint)
    small = File.expand_path("../icons/#{icon}_24.png", __dir__)
    large = File.expand_path("../icons/#{icon}_32.png", __dir__)
    [small, large].each { |path| raise "图标文件不存在：#{path}" unless File.file?(path) }
    command = UI::Command.new(label) { SuPvToolbar1.run(tool) }
    command.small_icon = small
    command.large_icon = large
    command.tooltip = label
    command.status_bar_text = hint
    command
  end

  def self.setup
    buttons = [
      ['插入标准变电站', SuPvStationTool, 'insert_station', '逐面重建标准变电站；点击放置，Esc取消。'],
      ['光伏板与出力', SuPvPanelTool1, 'pv_panel', '放置光伏板、调整角度、查询出力并导出CSV。'],
      ['阵列与出力', SuPvArrayTool1, 'pv_array', '选择安装面排布阵列，查看预测、互遮挡并导出CSV。'],
      ['平铺排布',SuPvFlushTool,'pv_flush','选择安装面，用原生参数小窗设置平铺阵列。']
    ]
    if @toolbar
      if @registration_schema=='substation_pv_toolbar1_v1' && @toolbar.length==3 && @commands.is_a?(Array) && @commands.length==3 && @menu
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
    toolbar = UI::Toolbar.new('变电站光伏 · toolbar1')
    commands.each { |command| toolbar.add_item(command) }
    menu = UI.menu('Extensions').add_submenu('变电站光伏 · toolbar1')
    menu.add_item('显示工具栏') { SuPvToolbar1.show }
    commands.each { |command| menu.add_item(command) }
    @commands, @toolbar, @menu = commands, toolbar, menu
    @registration_schema = schema
    true
  end
end

if SuPvToolbar1.setup
  SuPvToolbar1.show
  puts 'toolbar1 已加载4个按钮：变电站、光伏板与出力、阵列与出力、平铺排布。重复load不会追加按钮。'
end
