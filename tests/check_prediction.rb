# encoding: UTF-8
load File.expand_path('check_plugin.rb',__dir__)
load File.expand_path('../scripts/toolbar2/button_04_prediction.rb',__dir__)
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
[[],[record.merge('axes'=>axes.map{|a|a.map{|v|v*2}})],
 [record,record.merge('axes'=>axes_for(180,36))],[record,record.merge('model_id'=>'RS-M072BZ')]].each do |invalid|
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
  def get_attribute(dictionary,key); key=='model_id' ? 'TSM-NE19R' : nil; end
  def valid?;true;end
end
class RecordArray
  attr_reader :entities,:transformation
  def initialize(children,transform);@entities,@transformation=children,transform;end
  def get_attribute(dictionary,key);dictionary=='SuPvArrayTool'&&key=='settings' ? '{}' : nil;end
  def valid?;true;end
end
model=FakeModel.new(nil);Sketchup.instance_variable_set(:@model,model)
child=RecordPanel.new(Geom::Transformation.new([10,20,30],axes))
group=RecordArray.new([child],Geom::Transformation.new([100,200,300]))
SuPvPredictionTool.instance_variable_set(:@model,model)
SuPvPredictionTool.instance_variable_set(:@target,group)
actual=SuPvPredictionTool.records
check(actual.length==1 && actual[0]['origin_mm']==[110,220,330].map(&:to_mm),'Forecast lost cumulative component transforms')
check(actual[0]['axes']==axes,'Forecast changed world orientation')
group.entities.clear
check(SuPvPredictionTool.records.empty?,'Deleted panels remained in the snapshot')
if ENV['PV_PREDICTION_FIXTURE']
  plan.merge!('prediction'=>prediction,'catalog'=>SuPvPanelTool.panel_catalog,'target_id'=>1,'request_id'=>0)
  File.write(ENV['PV_PREDICTION_FIXTURE'],JSON.generate(plan))
end
