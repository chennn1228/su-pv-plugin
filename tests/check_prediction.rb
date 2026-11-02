# encoding: UTF-8
load File.expand_path('check_plugin.rb',__dir__)
load File.expand_path('../scripts/tools/button_04_prediction.rb',__dir__)
def axes_for(a,b)
  a,b=a*Math::PI/180,b*Math::PI/180
  [[-Math.cos(a),Math.sin(a),0],[-Math.cos(b)*Math.sin(a),-Math.cos(b)*Math.cos(a),Math.sin(b)],
   [Math.sin(b)*Math.sin(a),Math.sin(b)*Math.cos(a),Math.cos(b)]]
end
axes=axes_for(180,30)
record={'model_id'=>'TSM-NE19R','origin_mm'=>[10000.0,20000.0,5000.0],'axes'=>axes}
panels=[record,record.merge('origin_mm'=>[13000.0,20000.0,5000.0]),record.merge('origin_mm'=>[10000.0,24000.0,5000.0])]
plan=SuPvForecastSnapshot.build(panels)
check(plan['count']==3 && plan['forecast_only'],'Snapshot did not use actual panel count')
check(plan['settings']=={'model_id'=>'TSM-NE19R','azimuth'=>180,'tilt'=>30},'World angles changed')
check(plan['positions'][1][0]-plan['positions'][0][0]==3000,'Actual panel positions lost')
check(plan['positions'][2][1]-plan['positions'][0][1]==4000,'Missing-grid layout was regenerated')
rotated=SuPvForecastSnapshot.build([record.merge('axes'=>axes_for(130,36))])
check(rotated['settings']['azimuth']==130 && rotated['settings']['tilt']==36,'Actual rotated orientation ignored')
flat=SuPvForecastSnapshot.build([record.merge('axes'=>axes_for(90,0))])
check(flat['settings']['azimuth']==90 && flat['settings']['tilt']==0,'Flat panel orientation lost')
rolled_axes=[axes[1],axes[0].map{|x|-x},axes[2]]
rolled=SuPvForecastSnapshot.build([record.merge('axes'=>rolled_axes)])
check(rolled['settings']['azimuth']==180 && rolled['settings']['tilt']==30,'Flush in-plane orientation changed lookup angles')
check(rolled['panel_axes']==rolled_axes,'Actual flush board basis was lost')
off_grid=SuPvForecastSnapshot.build([record.merge('axes'=>axes_for(131.2,27.4))])
check((off_grid['settings']['azimuth']-131.2).abs<1e-7 && (off_grid['settings']['tilt']-27.4).abs<1e-7,'Snapshot rounded the actual fitted angles')
check(!SuPvArrayTool.prediction_for(off_grid,off_grid['spec'])[:data_available],'Off-grid snapshot fabricated prediction data')
check(off_grid['prediction'][:missing_data_message]=='暂无出力数据','A southern off-grid angle was mislabeled north-facing')
[0,55,85,275,355].each do |azimuth|
  north=SuPvForecastSnapshot.build([record.merge('axes'=>axes_for(azimuth,30))])
  check(north['prediction'][:data_available] && north['prediction'][:missing_data_message].nil?,'Complete northern 1-degree data was rejected')
  check(SuPvArrayTool.prediction_for(north,north['spec'])[:data_available],'Array preview rejected northern 1-degree data')
end
[0,1,89,90,181,270,359].each do |azimuth|
  boundary=SuPvForecastSnapshot.build([record.merge('axes'=>axes_for(azimuth,30))])
  check(boundary['prediction'][:data_available] && boundary['prediction'][:missing_data_message].nil?,'An east/west data boundary was labeled missing')
end
[[1,1],[179,31],[359,89],[0,90]].each do |a,b|
  fine=SuPvForecastSnapshot.build([record.merge('axes'=>axes_for(a,b))])
  check(fine['settings']['azimuth']==a && fine['settings']['tilt']==b,'One-degree physical angles changed before lookup')
  check(fine['prediction'][:values]&.length==8760,'A delivered one-degree pair did not return a full year')
end
check(SuPvPanelTool.energy_for(SuPvPanelTool.panel_spec,360,30)==SuPvPanelTool.energy_for(SuPvPanelTool.panel_spec,0,30),'360 degrees did not alias the 0-degree dataset')
mixed_north=SuPvForecastSnapshot.build([record,record.merge('axes'=>axes_for(0,30))])
check(mixed_north['prediction'][:data_available],'Mixed northern/southern selection did not aggregate delivered data')
mixed_missing=SuPvForecastSnapshot.build([record.merge('axes'=>axes_for(131.2,27.4)),record.merge('axes'=>axes_for(0,30))])
check(!mixed_missing['prediction'][:data_available] && mixed_missing['prediction'][:missing_data_message]=='暂无出力数据','Fractional off-grid data was silently filled')
# If a lookup succeeds, a northern orientation alone must never trigger a warning.
original_lookup=SuPvPanelTool.method(:energy_for)
begin
  SuPvPanelTool.define_singleton_method(:energy_for) { |*args| Array.new(8760,1.0) }
  future_north=SuPvForecastSnapshot.build([record.merge('axes'=>axes_for(0,30))])
  check(future_north['prediction'][:data_available] && future_north['prediction'][:missing_data_message].nil?,'Available northern data still displayed a warning')
ensure
  SuPvPanelTool.define_singleton_method(:energy_for,original_lookup)
end
[[],[record.merge('axes'=>axes.map{|a|a.map{|v|v*2}})],
].each do |invalid|
  rejected=false
  begin;SuPvForecastSnapshot.build(invalid);rescue StandardError;rejected=true;end
  check(rejected,'Invalid prediction geometry accepted')
end
prediction=SuPvArrayTool.prediction_for(plan,plan['spec'])
single=SuPvPanelTool.energy_for(plan['spec'],180,30)
check(prediction[:values]==single.map{|v|v*3},'Forecast does not use actual remaining panels')
check(SuPvGenerationExport.filename(plan['spec'],plan['settings'],3,'baseline').include?('_n3_baseline.csv'),'Snapshot export requires hypothetical gaps')

# Native API contract: combine the array frame and each actual child transformation.
class Numeric; def to_mm; self*25.4; end; end
class Geom::Point3d; def to_a; @coords; end; end
class Geom::Transformation
  def initialize(origin=[0,0,0],axes=[[1,0,0],[0,1,0],[0,0,1]]); @origin=Geom::Point3d.new(origin); @basis=axes; end
  def xaxis; Geom::Vector3d.new(*@basis[0]); end
  def yaxis; Geom::Vector3d.new(*@basis[1]); end
  def zaxis; Geom::Vector3d.new(*@basis[2]); end
  def vector(p); (0..2).map{|k| (0..2).inject(0.0){|s,j|s+p[j]*@basis[j][k]}}; end
  def *(other)
    origin=vector(other.origin.to_a).zip(@origin.to_a).map{|a,b|a+b}
    self.class.new(origin,[other.xaxis,other.yaxis,other.zaxis].map{|v|vector(v.to_a)})
  end
end
module Sketchup; class ComponentInstance; end; end
class RecordPanel < Sketchup::ComponentInstance
  attr_reader :transformation
  def initialize(transform); @transformation=transform; end
  def persistent_id;object_id;end
  def get_attribute(dictionary,key); key=='model_id' ? 'TSM-NE19R' : nil; end
  def valid?;true;end
end
class RecordArray
  attr_reader :entities,:transformation
  def initialize(children,transform);@entities,@transformation=children,transform;end
  def persistent_id;object_id;end
  def get_attribute(dictionary,key);dictionary=='SuPvArrayTool'&&key=='settings' ? '{}' : nil;end
  def valid?;true;end
end
model=FakeModel.new(nil);Sketchup.instance_variable_set(:@model,model)
child=RecordPanel.new(Geom::Transformation.new([10,20,30],axes))
group=RecordArray.new([child],Geom::Transformation.new([100,200,300]))
SuPvPredictionTool.instance_variable_set(:@model,model)
SuPvPredictionTool.instance_variable_set(:@paths,[[group]])
actual=SuPvPredictionTool.records
check(actual.length==1 && actual[0]['origin_mm']==[110,220,330].map(&:to_mm),'Forecast lost cumulative component transforms')
check(actual[0]['axes']==axes,'Forecast changed world orientation')
group.entities.clear
check(SuPvPredictionTool.records.empty?,'Deleted panels remained in the snapshot')
fixture_path=ENV['PV_PREDICTION_FIXTURE'] || File.expand_path('../output/checks/prediction_fixture.json',__dir__)
begin
  plan.merge!('prediction'=>prediction,'catalog'=>SuPvPanelTool.panel_catalog,'target_id'=>1,'request_id'=>0)
  File.write(fixture_path,JSON.generate(plan))
end

# A preselected object still requires Enter; nested/overlapping paths are deduplicated.
group.entities << child
SuPvPredictionTool.instance_variable_set(:@paths,[[group],[group,child]])
check(SuPvPredictionTool.records.length==1,'Selecting both parent and nested panel duplicated the PV')
confirmation=[]
previous=SuPvPredictionTool.method(:select_targets)
SuPvPredictionTool.define_singleton_method(:select_targets){|paths|confirmation << paths}
tool=SuPvPredictionTool::SelectionTool.new(model,[[group]])
timers=[];native_timer=UI.method(:start_timer)
UI.define_singleton_method(:start_timer) { |*_args,&callback| timers<<callback }
check(tool.onKeyDown(65,0,0,nil)==false,'Unrelated key was consumed')
check(confirmation.empty?,'Non-Enter key opened prediction')
check(tool.onKeyDown(13,1,0,nil)==true,'Enter down leaked to the native tool')
check(tool.onKeyDown(13,2,0,nil)==true,'Held Enter leaked to the native tool')
check(confirmation.empty? && timers.empty?,'Confirmation replaced the tool before Enter was released')
check(tool.onKeyUp(13,1,0,nil)==true,'Enter up leaked to the native tool')
tool.onKeyUp(13,1,0,nil)
check(confirmation.empty? && timers.length==1,'Enter did not schedule exactly one post-event confirmation')
timers.shift.call
check(confirmation==[[[group]]],'Enter did not confirm the chosen paths')
cancelled=SuPvPredictionTool::SelectionTool.new(model,[[group]])
cancelled.onKeyDown(13,1,0,nil);cancelled.onKeyUp(13,1,0,nil);cancelled.onCancel(0,nil)
timers.shift.call
check(confirmation.length==1,'Cancelled confirmation ran after the tool had exited')
UI.define_singleton_method(:start_timer,native_timer)
SuPvPredictionTool.define_singleton_method(:select_targets,previous)

# Array totals across all supported product models.
frame = [[1,0,0],[0,1,0],[0,0,1]]
SuPvPanelTool.panel_catalog.each do |spec|
  settings = { 'model_id' => spec[:id], 'azimuth' => 180, 'tilt' => 30,
    'gap_x_mm' => 100, 'gap_y_mm' => 500 }
  region = SuPvRoofRegion.prepare([[[0,0],[12000,0],[12000,8000],[0,8000]],
    [[4000,2000],[6000,2000],[6000,4000],[4000,4000]]])
  [nil, region].each do |boundary|
    plan = SuPvArrayLayout.plan(12000,8000,frame,spec,settings,boundary)
    result = SuPvArrayTool.prediction_for(plan,spec)
    single = SuPvPanelTool.energy_for(spec,180,30)
    check(result[:values].length == 8760, 'Array forecast lost hours')
    check(result[:values].zip(single).all? { |a,b| a == b * plan['count'] }, 'Forecast does not use retained panel count')
    expected = single.inject(0.0,:+) * plan['count'] / 1000.0
    check((result[:annual_kwh]-expected).abs < 1e-7, 'Array annual energy mismatch')
    check(result[:peak_wh] == single.max * plan['count'], 'Array peak mismatch')
    zero = SuPvArrayTool.prediction_for(plan.merge('count'=>0),spec)
    check(zero[:values].all?(&:zero?) && zero[:annual_kwh] == 0, 'Empty array is not zero')
  end
  missing = SuPvArrayTool.prediction_for({'settings'=>settings,'count'=>10},spec.merge(data_available:false))
  check(missing[:values].nil? && !missing[:data_available], 'Missing data fabricated')
end
