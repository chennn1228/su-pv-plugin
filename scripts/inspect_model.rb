# encoding: UTF-8
# 任务二修正：只读取当前模型最外层的组件实例，形成表格。
# load 'D:/Administrator Files/SEU/12.Project/260911_SU PV plugin/project/scripts/inspect_model.rb'

module SuPvModelInspect
  # 控制台使用等宽字体时，常见中文按两个字符宽度对齐。
  def self.cell_width(text)
    text.each_char.inject(0) { |width, char| width + (char.ascii_only? ? 1 : 2) }
  end

  def self.inspect_model
    model = Sketchup.active_model

    # 只读 model.entities，既不递归，也不遍历组件定义库。
    # Group、散装边面、组件内部的对象均不加入清单。
    components = model.entities.grep(Sketchup::ComponentInstance)
    headers = ['序号', 'EntityID', '实例名称', '组件定义', 'Tag',
               '原点X(m)', '原点Y(m)', '原点Z(m)', '实体自身隐藏']
    rows = components.each_with_index.map do |component, index|
      origin = component.transformation.origin
      [index + 1, component.entityID, component.name, component.definition.name,
       component.layer.name, format('%.6f', origin.x.to_m),
       format('%.6f', origin.y.to_m), format('%.6f', origin.z.to_m),
       component.hidden? ? '是' : '否']
    end

    puts "\n=== 第一层组件清单：#{model.title} ==="
    puts "模型文件：#{model.path.empty? ? '(尚未保存)' : model.path}"
    table = [headers] + rows.map do |row|
      cells = row.map { |value| value.to_s.gsub(/[\r\n\t]/, ' ') }
      cells[2] = '(未命名)' if cells[2].empty?
      cells
    end
    widths = headers.each_index.map { |i| table.map { |row| cell_width(row[i]) }.max }
    border = '+' + widths.map { |width| '-' * (width + 2) }.join('+') + '+'
    print_row = lambda do |row|
      cells = row.each_with_index.map { |text, i| text + ' ' * (widths[i] - cell_width(text)) }
      puts '| ' + cells.join(' | ') + ' |'
    end
    puts border
    print_row.call(headers)
    puts border
    table.drop(1).each { |row| print_row.call(row) }
    puts border
    puts "第一层组件实例共 #{rows.length} 个（包含隐藏实例）。"
    puts 'Tag 为组件自身标签；原点坐标为模型世界坐标，单位 m。'
    puts '隐藏列只记录实体自身 hidden? 状态，不代表 Tag 或场景的最终可见性。'
    puts '=== 检查结束；模型未修改或保存 ==='
    rows.length
  end
end

SuPvModelInspect.inspect_model
