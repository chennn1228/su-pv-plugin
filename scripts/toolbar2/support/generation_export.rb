# encoding: UTF-8
require 'csv'
require 'json'

module SuPvGenerationExport
  def self.validate_values(values)
    raise '全年出力数据须包含8760个有效非负数值。' unless values.is_a?(Array) && values.length == 8760 && values.all? { |v| v.is_a?(Numeric) && v.finite? && v >= 0 }
  end

  def self.matrix(values)
    validate_values(values)
    CSV.generate do |csv|
      csv << ['date'] + (0...24).map { |h| format('%02d:00-%02d:00_Wh', h, h + 1) }
      offset = 0
      [31,28,31,30,31,30,31,31,30,31,30,31].each_with_index do |days, month|
        (1..days).each do |day|
          csv << [format('%02d-%02d', month + 1, day)] + values.slice(offset, 24)
          offset += 24
        end
      end
    end
  end

  def self.filename(spec, settings, count, branch)
    id = spec.fetch(:id).gsub(/[^A-Za-z0-9_.-]+/, '_')
    stem = "#{id}_#{spec.fetch(:power_w).to_i}W_a#{settings.fetch('azimuth')}_t#{settings.fetch('tilt')}"
    if branch == 'panel'
      "#{stem}_panel.csv"
    else
      gaps = settings.key?('gap_x_mm') && settings.key?('gap_y_mm') ? "_g#{(settings['gap_x_mm'] / 10.0).round}-#{(settings['gap_y_mm'] / 10.0).round}" : ''
      "#{stem}_n#{count}#{gaps}_#{branch}.csv"
    end
  end

  def self.save(values:, spec:, settings:, count:, branch:)
    raise '当前方案没有可导出的组件。' unless count.is_a?(Integer) && count > 0
    body = matrix(values)
    folder = File.expand_path('../../../output', __dir__)
    path = UI.savepanel('导出全年出力 CSV', folder, filename(spec, settings, count, branch))
    return { cancelled: true } unless path
    path += '.csv' unless File.extname(path).downcase == '.csv'
    # Do not retry elsewhere when Excel locks the destination.
    File.write(path, "\uFEFF" + body, encoding: 'UTF-8')
    { cancelled: false }
  end

  def self.bind(dialog, current:, &resolve)
    dialog.add_action_callback('export_csv') do |_context, payload|
      next unless current.call
      begin
        options = resolve.call(JSON.parse(payload))
        result = save(**options)
      rescue Errno::EACCES, Errno::EPERM
        result = { error: '无法写入文件，请关闭可能占用它的 Excel 窗口，并检查目录权限后重试。' }
      rescue StandardError => error
        result = { error: error.message }
      end
      dialog.execute_script("window.PV.exported(#{JSON.generate(result)});") if current.call
    end
  end
end
