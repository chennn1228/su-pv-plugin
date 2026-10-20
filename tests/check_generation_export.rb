# encoding: UTF-8
stdlib = 'C:/Program Files/SketchUp/SketchUp 2022/Tools/RubyStdLib'
$LOAD_PATH.unshift(stdlib, "#{stdlib}/platform_specific")
require 'enc/encdb'
require 'enc/trans/transdb'
load File.expand_path('../scripts/toolbar2/support/generation_export.rb', __dir__)
def check(value, message); raise message unless value; end
module UI
  class << self; attr_accessor :destination, :save_args; end
  def self.savepanel(*args); self.save_args = args; destination; end
end
values = (0...8760).map { |i| i / 10.0 }
rows = CSV.parse(SuPvGenerationExport.matrix(values))
check(rows.length == 366 && rows.all? { |row| row.length == 25 }, 'Matrix dimensions')
check(rows[0][1] == '00:00-01:00_Wh' && rows[0][-1] == '23:00-24:00_Wh', 'Hour intervals')
check(rows[60][0] == '03-01' && rows[-1][0] == '12-31', 'Calendar boundaries')
check(rows.drop(1).flat_map { |row| row.drop(1).map(&:to_f) } == values, 'Lost or reordered energy')
spec = {id: 'TSM-NE19R', power_w: 630}
settings = {'azimuth'=>180, 'tilt'=>30, 'gap_x_mm'=>100, 'gap_y_mm'=>500}
options = {values: values, spec: spec, settings: settings, count: 12, branch: 'shade'}
check(SuPvGenerationExport.filename(spec, settings, 12, 'shade').include?('_n12_g10-50_shade'), 'Array scheme filename')
check(SuPvGenerationExport.save(**options)[:cancelled], 'Cancel must not write')
destination = File.expand_path('../output/.export_check.csv', __dir__)
begin
  UI.destination = destination
  check(!SuPvGenerationExport.save(**options)[:cancelled], 'Save result')
  content = File.binread(destination)
  check(content.start_with?("\xEF\xBB\xBF".b), 'Excel UTF-8 BOM')
  check(CSV.parse(content.byteslice(3..-1).force_encoding('UTF-8')) == rows, 'Saved matrix differs')
ensure
  File.delete(destination) if File.exist?(destination)
end
[values[0...-1], values.dup.tap { |v| v[1] = -1 }, values.dup.tap { |v| v[1] = Float::NAN }].each do |invalid|
  begin
    SuPvGenerationExport.matrix(invalid)
    raise 'Invalid data accepted'
  rescue RuntimeError => error
    raise if error.message == 'Invalid data accepted'
  end
end
class ExportDialog
  attr_reader :callback, :response
  def add_action_callback(_name, &block); @callback = block; end
  def execute_script(script); @response = script; end
end
dialog = ExportDialog.new
SuPvGenerationExport.bind(dialog, current: -> {true}) { |_data| raise Errno::EACCES }
dialog.callback.call(nil, '{}')
check(dialog.response.include?('Excel'), 'Occupied file error must be shown')
