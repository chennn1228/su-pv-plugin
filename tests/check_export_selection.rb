# encoding: UTF-8
load File.expand_path('check_prediction.rb',__dir__)
load File.expand_path('../scripts/tools/button_04_prediction.rb',__dir__)
COPY_MODIFIER_MASK=4 unless defined?(COPY_MODIFIER_MASK)
class ExportSelectionProbe
  attr_reader :items
  def initialize;@items=[:old_selection];end
  def clear;@items.clear;end
  def add(item);@items<<item;end
  def to_a;@items;end
end
class ExportViewProbe
  def pickray(x,y);[x,y];end
  def invalidate;end
end
calls=[]
original_lookup=SuPvPanelTool.method(:energy_for)
SuPvGenerationExport.define_singleton_method(:save) { |**options| calls << [:csv,options];{cancelled:true} }
SuPvFigureExport.define_singleton_method(:save) { |**options| calls << [:svg,options];{cancelled:true} }
SuPvPredictionTool.define_singleton_method(:show_dialog) { raise 'Export opened the prediction dialog' }
SuPvSceneSnapshot.define_singleton_method(:attach) { |*args| raise 'Export unnecessarily captured the scene' }
model=FakeModel.new(nil);Sketchup.instance_variable_set(:@model,model)
selection=ExportSelectionProbe.new
model.define_singleton_method(:selection) { selection }
model.define_singleton_method(:select_tool) { |tool| @tool=tool;tool.activate if tool }
panel=RecordPanel.new(Geom::Transformation.new([100,200,300],axes_for(180,30)))
panel.define_singleton_method(:definition) { Struct.new(:entities).new([]) }
model.define_singleton_method(:raytest) { |*args| [nil,[panel]] }
view=ExportViewProbe.new
SuPvPredictionTool.instance_variable_set(:@dialog,nil)
%w[csv svg].each_with_index do |format,index|
  selection.items << :old_selection
  SuPvPredictionTool.activate(format)
  tool=model.instance_variable_get(:@tool)
  check(selection.items.empty?,'The toolbar reused the previous model selection')
  check(calls.length==index,'Export ran before choosing any PV')
  tool.onLButtonDown(0,10,20,view)
  check(selection.items==[panel] && calls.length==index,'A click exported before Enter')
  tool.onKeyDown(65,0,0,view)
  check(calls.length==index,'A non-Enter key exported')
  if format=='svg'
    SuPvPanelTool.define_singleton_method(:energy_for) { |*args| raise 'SVG tried to load hourly data' }
  end
  check(tool.onKeyDown(13,1,0,view)==true,'Export Enter-down was not consumed')
  check(calls.length==index && model.instance_variable_get(:@tool).equal?(tool),'Export replaced the tool while Enter was held')
  check(tool.onKeyUp(13,1,0,view)==true,'Export Enter-up was not consumed')
  check(model.instance_variable_get(:@tool).nil?,'The selection tool remained active while saving')
  check(calls.length==index+1 && calls.last.first.to_s==format,'Enter did not directly save the chosen format')
end
check(calls[0][1][:count]==1 && calls[0][1][:values].length==8760,'CSV did not use the newly selected PV')
body=calls[1][1][:body]
check(body.scan('<polygon').length==1 && body.include?('N ↑'),'SVG omitted the selected panel or horizontal directions')
points=body[/points="([^"]+)"/,1].split.map { |point| point.split(',').map(&:to_f) }
width=points.map(&:first).max-points.map(&:first).min
height=points.map(&:last).max-points.map(&:last).min
check((width/height-1134.0/(2382*Math.cos(30*Math::PI/180))).abs<1e-5,'SVG projected perpendicular to the roof instead of world Z')
cad=SuPvCadExport.from_svg(body)
entities=cad.split("\r\nENTITIES\r\n",2).last.lines.map(&:chomp).each_slice(2).to_a
x=entities.select { |code,_value| code=='10' }.first(4).map { |_code,value| value.to_f }
y=entities.select { |code,_value| code=='20' }.first(4).map { |_code,value| value.to_f }
check((x.max-x.min-1134).abs<1e-5 && (y.max-y.min-2382*Math.cos(30*Math::PI/180)).abs<1e-5,'CAD changed physical projected millimetres')
check((x.first-2540).abs<1e-5 && (y.first-5080).abs<1e-5,'CAD lost the original world coordinate or north direction')
qa=File.expand_path('../output/checks',__dir__)
if Dir.exist?(qa)
  File.binwrite("#{qa}/pv_horizontal_plan.svg",body)
  File.binwrite("#{qa}/pv_horizontal_plan.dxf",cad)
end
check(model.operations.empty?,'Selecting/exporting modified model geometry')
SuPvPanelTool.define_singleton_method(:energy_for,original_lookup)
SuPvPredictionTool.instance_variable_set(:@export_format,'csv')
begin
  SuPvPredictionTool.export_selected([{'model_id'=>'TSM-NE19R','origin_mm'=>[0,0,0],'axes'=>axes_for(0.2,90)}])
  raise 'Missing fractional-angle data was exported'
rescue RuntimeError => error
  check(error.message=='暂无出力数据，暂无法导出总出力。','Native CSV warning did not explain missing off-grid data')
end
check(calls.length==2,'A missing-data export opened the save dialog')

# Toolbar dispatch and inline controls share the native selection flow.
load File.expand_path('../scripts/tools/button_05_export_csv.rb',__dir__)
load File.expand_path('../scripts/tools/button_06_export_svg.rb',__dir__)
formats=[]
SuPvPredictionTool.define_singleton_method(:activate) { |format=nil| formats << format }
SuPvCsvExportTool.activate
SuPvSvgExportTool.activate
check(formats==%w[csv svg],'Export buttons dispatched to the same format')

class ExportDialogProbe
  attr_reader :callbacks,:result,:closed
  def initialize;@callbacks={};end
  def add_action_callback(name,&block);@callbacks[name]=block;end
  def close;@closed=true;end
  def execute_script(script)
    @result=JSON.parse(script.sub('window.PV.exported(','').sub(/\);\z/,''))
  end
end
def UI.savepanel(*args);nil;end
dialog=ExportDialogProbe.new
SuPvFigureExport.bind(dialog,current: -> {true})
dialog.callbacks['export_figure'].call(nil,JSON.generate('format'=>'svg','body'=>'<svg xmlns="http://www.w3.org/2000/svg"><path d="M0 0L1 1"/></svg>','kind'=>'plan'))
check(dialog.result['cancelled'],'SVG no longer reaches the native save dialog')
dialog.callbacks['export_figure'].call(nil,JSON.generate('format'=>'png','body'=>'unused'))
check(dialog.result['error'].include?('仅支持SVG'),'PNG export backend is still enabled')

# Inline CSV/SVG controls must enter the same native selection tool.
%w[csv svg].each do |format|
  source=ExportDialogProbe.new
  SuPvGenerationExport.bind(source,current: -> {true}) { raise 'Inline export bypassed selection' }
  source.callbacks['select_export'].call(nil,format)
  check(source.closed && formats.last==format,'Inline button did not close its window and start PV selection')
end
