# encoding: UTF-8
# 任务三 / CSV 小实验。仅操作表格文件，不修改 SketchUp 模型。
# load 'D:/Administrator Files/SEU/12.Project/260911_SU PV plugin/project/scripts/pv_csv.rb'
# 然后执行 SuPvCsv.read 和 SuPvCsv.export。
# 输入：../data/PV panel.csv；输出：../output/PV_export.csv。
require 'csv'
require 'json'

module SuPvCsv
  def self.source_path
    File.expand_path('../data/PV panel.csv', __dir__)
  end

  # 读取 UTF-8（含 BOM）或中文 GBK/GB18030 编码的 CSV。
  def self.read
    @table = @products = nil
    bytes = File.binread(source_path)
    text = bytes.dup.force_encoding('UTF-8')
    encoding_name = 'UTF-8'
    unless text.valid_encoding?
      text = bytes.force_encoding('GB18030').encode('UTF-8')
      encoding_name = 'GBK / GB18030'
    end
    text = text.sub(/\A\uFEFF/, '')
    table = CSV.parse(text, headers: true, skip_blanks: true)
    if table.headers.include?(nil) || table.headers.uniq.length != table.headers.length
      raise 'CSV 表头存在空列名或重复列名，请检查原表。'
    end
    required = ['材料', '类型', '生产商', '型号', '尺寸', 'STC-Pmax(W)']
    missing = required - table.headers
    raise "CSV 缺少字段：#{missing.join(', ')}" unless missing.empty?
    raise 'CSV 没有组件记录。' if table.size.zero?

    index_path = File.expand_path('../data/pv_generation/index.json', __dir__)
    active_ids = JSON.parse(File.read(index_path, encoding: 'UTF-8')).fetch('models').keys
    table.delete_if { |row| !active_ids.include?(row['型号'].to_s.strip) }
    raise '当前板型索引与参数表没有匹配的组件。' if table.size.zero?
    products = table.each_with_index.map do |row, index|
      raise "第 #{index + 2} 行列数不正确。" unless row.fields.length == table.headers.length
      size = row['尺寸'].to_s.strip
      match = /\A(\d+(?:\.\d+)?)\s*[×xX*]\s*(\d+(?:\.\d+)?)\s*[×xX*]\s*(\d+(?:\.\d+)?)\s*mm\z/i.match(size)
      raise "第 #{index + 2} 行尺寸无法识别：#{size}" unless match
      dimensions = match.captures.map { |value| Float(value) }
      power = Float(row['STC-Pmax(W)'])
      unless dimensions.all? { |value| value.finite? && value > 0 } && power.finite? && power > 0
        raise "第 #{index + 2} 行尺寸或额定功率必须为正数。"
      end
      raise "第 #{index + 2} 行缺少型号。" if row['型号'].to_s.strip.empty?
      {
        material: row['材料'], type: row['类型'], manufacturer: row['生产商'],
        model: row['型号'], length_mm: dimensions[0], width_mm: dimensions[1],
        thickness_mm: dimensions[2], pmax_w: power
      }
    end

    @table = table
    @products = products
    puts "\n读取成功：#{source_path}"
    puts "编码：#{encoding_name}；#{table.headers.length} 个字段，#{products.length} 种组件。"
    puts "字段：#{table.headers.join(' | ')}"
    products.each_with_index do |product, index|
      puts "#{index + 1}. #{product[:manufacturer]} / #{product[:model]} / " \
           "#{product[:length_mm]} × #{product[:width_mm]} × #{product[:thickness_mm]} mm / #{product[:pmax_w]} W"
    end
    puts '尺寸的三个值按原表顺序解释为长、宽、厚。原表中的空值和反斜杠保持原样。'
    puts '下一步：SuPvCsv.export'
    products.length
  end

  # 获取已转成数值的参数；例如 SuPvCsv.products.first[:length_mm]。
  def self.products
    raise '请先执行 SuPvCsv.read。' unless @products
    @products
  end

  # 原始字段全部保留，新增三个尺寸数值列；每次覆盖本实验的导出文件。
  def self.export
    products
    path = File.expand_path('../output/PV_export.csv', __dir__)
    Dir.mkdir(File.dirname(path)) unless Dir.exist?(File.dirname(path))
    # Windows 下用二进制模式，避免系统把已有的 CRLF 再转换为 CRCRLF。
    File.open(path, 'wb:UTF-8') do |file|
      file.write("\uFEFF")
      csv = CSV.new(file, row_sep: "\r\n")
      csv << @table.headers + ['长(mm)', '宽(mm)', '厚(mm)']
      @table.each_with_index do |row, index|
        product = @products[index]
        csv << row.fields + product.values_at(:length_mm, :width_mm, :thickness_mm)
      end
    end
    puts "导出成功：#{path}"
    puts "共 #{@products.length} 种组件；原始 #{@table.headers.length} 列 + 3 列尺寸数值；编码 UTF-8 BOM。"
    true
  end
end

puts 'CSV 脚本已加载。读取：SuPvCsv.read；导出：SuPvCsv.export'
