# encoding: UTF-8
stdlib = 'C:/Program Files/SketchUp/SketchUp 2022/Tools/RubyStdLib'
$LOAD_PATH.unshift(stdlib, "#{stdlib}/platform_specific")
require 'enc/encdb'
require 'enc/trans/transdb'
load File.expand_path('../scripts/support/generation_export.rb', __dir__)
def check(value, message); raise message unless value; end
module UI
  class << self; attr_accessor :destination, :save_args, :overwrite; end
  def self.savepanel(*args); self.save_args = args; destination; end
  def self.messagebox(*args); overwrite; end
end
MB_YESNO=4 unless defined?(MB_YESNO)
IDYES=6 unless defined?(IDYES)
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

# CAD output shares the selected stem and preserves actual millimetres and text.
svg='<svg xmlns="http://www.w3.org/2000/svg" height="200" data-cad-scale="2" data-cad-origin-x="100" data-cad-origin-y="400"><rect width="300" height="200" fill="white"/><g stroke="black" fill="none" data-cad-layer="PV_COMPONENT"><polygon points="10,20 577,20 577,1211 10,1211"/><path d="M0 0H20v10l5 5Z M30 20L40 20" stroke-dasharray="3 4"/><circle cx="10" cy="10" r="2"/><line x1="0" y1="0" x2="5" y2="6"/><text x="20" y="50" font-size="14" text-anchor="middle">组件 &amp; MPPT 1</text></g></svg>'
cad=SuPvCadExport.from_svg(svg)
native_array_sum=Array.instance_method(:sum)
begin
  Array.send(:define_method,:sum) { |*_args,&_block| nil }
  cad_with_sum_conflict=SuPvCadExport.from_svg(svg)
ensure
  Array.send(:define_method,:sum,native_array_sum)
end
check(cad_with_sum_conflict==cad,'Installed extension sum override corrupted the DXF dashed-line length')
tags=cad.lines.map(&:chomp).each_slice(2).to_a
check(tags.include?(['1','AC1021']) && tags.each_cons(2).any? { |a,b| a==['9','$INSUNITS'] && b==['70','4'] },'DXF version or millimetre units missing')
check(tags.include?(['1','组件 & MPPT 1']) && tags.include?(['7','PV_CHINESE']),'CAD text was rasterized or escaped incorrectly')
check(tags.include?(['10','120.000000000']) && tags.include?(['20','360.000000000']),'SVG-to-world coordinate transform failed')
check(tags.include?(['2','PV_DASH_1']) && tags.include?(['49','-8.000000000']),'Dashed series connection lost')
check(tags.include?(['0','CIRCLE']) && tags.include?(['0','LINE']),'Circuit primitives missing')
directory=File.expand_path('../output',__dir__);stem=File.join(directory,'.cad_pair_check')
svg_file="#{stem}.svg";dxf_file="#{stem}.dxf"
begin
  UI.destination=stem;UI.overwrite=IDYES
  check(!SuPvFigureExport.save(body:svg)[:cancelled] && UI.save_args.first=='导出 SVG + DXF','Pair export did not use one save panel')
  check(File.binread(svg_file)==svg.b && File.binread(dxf_file)==cad.b,'SVG/DXF pair differs from source')
  UI.destination=svg_file;UI.overwrite=7
  check(SuPvFigureExport.save(body:svg.sub('MPPT 1','MPPT 2'))[:cancelled],'Existing companion overwritten without confirmation')
  check(File.binread(dxf_file)==cad.b,'Declined overwrite changed a companion')
  UI.destination=nil
  check(SuPvFigureExport.save(body:svg)[:cancelled],'Cancel did not cancel both formats')
  # A failure during the second install restores both previously existing files.
  native_rename=File.method(:rename)
  begin
    File.define_singleton_method(:rename) do |from,to|
      raise Errno::EACCES,'locked CAD' if from.end_with?('.tmp') && to==dxf_file
      native_rename.call(from,to)
    end
    begin;SuPvFigureExport.write_pair(svg_file=>'new svg',dxf_file=>'new cad');raise 'Pair failure was ignored';rescue Errno::EACCES;end
    check(File.binread(svg_file)==svg.b && File.binread(dxf_file)==cad.b,'Partial export damaged original files')
  ensure
    File.define_singleton_method(:rename,native_rename)
  end
ensure
  [svg_file,dxf_file].each { |file| File.delete(file) if File.exist?(file) }
end
check(Dir.glob("#{stem}.*.tmp").empty? && Dir.glob("#{stem}.*.bak").empty?,'Pair export left staging files')
['<svg><!DOCTYPE x></svg>','<svg><g transform="rotate(10)"><path d="M0 0L1 1" stroke="black"/></g></svg>','<svg><path d="M0 0C1 1 2 2 3 3" stroke="black"/></svg>'].each do |invalid|
  begin;SuPvCadExport.from_svg(invalid);raise 'Unsupported CAD input accepted';rescue RuntimeError=>e;raise if e.message=='Unsupported CAD input accepted';end
end
puts 'CSV and paired SVG/DXF export, metric coordinates, Chinese text, cancellation, overwrite and rollback checks passed.'
