# encoding: UTF-8
stdlib='C:/Program Files/SketchUp/SketchUp 2022/Tools/RubyStdLib'
$LOAD_PATH.unshift(stdlib,"#{stdlib}/platform_specific")
require 'enc/encdb'
require 'enc/trans/transdb'
require 'json'
require 'fileutils'
FileUtils.mkdir_p(File.expand_path('../output/checks',__dir__))
def check(value,message);raise message unless value;end
root=File.expand_path('..',__dir__)
load "#{root}/scripts/support/mounting.rb"
load "#{root}/scripts/support/electrical_design.rb"
load "#{root}/scripts/support/electrical_presets.rb"
load "#{root}/scripts/support/array_layout.rb"
spec={id:'TSM-NE19R',width_mm:1134.0,length_mm:2382.0,thickness_mm:30.0,power_w:630.0}
axes=[[1,0,0],[0,Math.cos(Math::PI/6),Math.sin(Math::PI/6)],[0,-Math.sin(Math::PI/6),Math.cos(Math::PI/6)]]
[[[0,0,1],100],[[0,-0.5,Math.sqrt(3)/2],500],[[1,0,0],100]].each do |normal,h|
 g=SuPvMounting.geometry(spec,axes,normal,{'clearance_mm'=>h})
 corners=[0,30].flat_map { |z| [[0,0,z],[1134,0,z],[1134,2382,z],[0,2382,z]] }
 check((corners.map { |p| g[:lift]+SuPvMounting.dot(p,g[:normal]) }.min-h).abs<1e-6,'Actual board clearance differs from requested normal distance')
 check(g[:feet].all? { |p| (g[:lift]+SuPvMounting.dot(p,g[:normal])).abs<1e-6 },'Support feet do not land on installation plane')
end
[nil,99,501,Float::NAN].each do |value|
 begin;SuPvMounting.clearance({'clearance_mm'=>value});raise 'Invalid clearance accepted';rescue RuntimeError,ArgumentError,TypeError=>e;raise if e.message=='Invalid clearance accepted';end
end
settings={'azimuth'=>180,'tilt'=>30,'gap_x_mm'=>100,'gap_y_mm'=>500}
a=SuPvArrayLayout.plan(12000,10000,[[1,0,0],[0,1,0],[0,0,1]],spec,settings.merge('clearance_mm'=>100))
b=SuPvArrayLayout.plan(12000,10000,[[1,0,0],[0,1,0],[0,0,1]],spec,settings.merge('clearance_mm'=>500))
check(a['count']==b['count'] && a['positions'].zip(b['positions']).all? { |x,y| x[0,2]==y[0,2] && (y[2]-x[2]-400).abs<1e-6 },'Clearance changed packing or used wrong displacement')
records=100.times.map { |i| {'key'=>i.to_s,'model_id'=>spec[:id],'origin_mm'=>[(i%10)*1234,(i/10)*2500,100],'axes'=>[[1,0,0],[0,1,0],[0,0,1]]} }
check(SuPvElectricalDesign.same_geometry?(records,records.reverse),'Enumeration order changed geometry identity')
shifted=Marshal.load(Marshal.dump(records));shifted[0]['origin_mm'][0]+=0.001
check(!SuPvElectricalDesign.same_geometry?(records,shifted),'Actual submillimetre movement was ignored')
rotated=Marshal.load(Marshal.dump(records));rotated[0]['axes'][0][1]+=1e-5
check(!SuPvElectricalDesign.same_geometry?(records,rotated),'Actual axis change was ignored')
check(!SuPvElectricalDesign.same_geometry?(records,records.drop(1)),'Removed component was ignored')
check(!SuPvElectricalDesign.same_geometry?(records,[records.first]*records.length),'Duplicate component identities were accepted')
input={'voc'=>50.3,'vmp'=>42,'isc'=>15.94,'imp'=>15.01,'beta_voc'=>-0.24,'beta_vmp'=>-0.30,'module_max'=>1500,'tmin'=>-10,'tmax'=>70,'isc_factor'=>1.25,'dc_max'=>1100,'mppt_min'=>200,'mppt_max'=>1000,'mppt_current'=>40,'mppt_isc'=>50,'port_current'=>25,'port_isc'=>30,'mppts'=>4,'ports'=>2,'ac_kw'=>40,'dc_kw'=>60,'dc_ac_max'=>1.3,'series_count'=>0}
result=SuPvElectricalDesign.calculate(records,spec,input)
check(result[:connected_count]==100 && result[:unassigned].empty?,'Automatic feasible series allocation left avoidable panels')
assigned=result[:strings].flat_map { |s| s['panels'] }
check(assigned.uniq.length==100 && assigned.sort==records.map { |r| r['key'] }.sort,'Duplicate/missing panel assignment')
check(result[:inverters].all? { |inv| inv['power_w']<=52000+1e-6 && inv['mppts'].length<=4 && inv['mppts'].all? { |m| m['strings'].length<=2 } },'Inverter or MPPT capacity exceeded')
check(result[:series_count]*result[:voc_cold]<1100 && result[:series_count]*result[:vmp_hot]>=200,'Voltage constraint violated')
explicit=SuPvElectricalDesign.calculate(records,spec,input.merge('series_count'=>19))
check(explicit[:connected_count]==100 && explicit[:unassigned].empty? && explicit[:series_sizes].length==2,'Manual upper bound did not rebalance all panels')
check(explicit[:candidates]==result[:candidates],'Manual selection lost the other feasible string designs')
check(result[:candidates].all? { |c| c[:connected_count]>0 && c[:string_sizes].sum { |size| size[:series_count]*size[:string_count] }==records.length && c[:connected_count]+c[:unassigned]==records.length },'Curve candidates are not complete integer strings')
mixed=Marshal.load(Marshal.dump(records));mixed.last(50).each { |r| r['axes']=[[1,0,0],[0,0,1],[0,-1,0]] }
split=SuPvElectricalDesign.calculate(mixed,spec,input.merge('series_count'=>10))
split[:strings].each do |s|
 orientations=s['panels'].map { |key| mixed.find { |r| r['key']==key }['axes'][2] }.uniq
 check(orientations.length==1,'One string mixed orientations')
end
small_groups=SuPvElectricalDesign.calculate(mixed.first(6)+mixed.last(6),spec,input)
check(small_groups[:candidates].all? { |c| c[:string_sizes].all? { |size| size[:series_count]==6 } && c[:connected_count]==12 },'Orientation fragments produced empty string candidates')
limited=SuPvElectricalDesign.calculate(records,spec,input.merge('dc_kw'=>5))
check(limited[:candidates].all? { |c| c[:string_sizes].all? { |size| size[:series_count]*spec[:power_w]<=5000 } },'Curve includes strings above device DC capacity')
bad=[input.merge('vmp'=>55),input.merge('imp'=>17),input.merge('port_current'=>10),input.merge('series_count'=>result[:range][1]+1),input.merge('beta_vmp'=>nil),input.merge('dc_kw'=>4)]
bad.each do |params|
 begin;SuPvElectricalDesign.calculate(records,spec,params);raise 'Invalid electrical configuration accepted';rescue RuntimeError=>e;raise if e.message=='Invalid electrical configuration accepted';end
end
# Check strict equality at absolute maximum is rejected.
strict=SuPvElectricalDesign.calculate(records,spec,input.merge('dc_max'=>result[:voc_cold]*20))
check(strict[:range][1]<=19,'Absolute voltage equality was accepted')
fixture_spec=spec.merge(manufacturer:'天合光能',model:spec[:id],electrical:input.slice('voc','vmp','isc','imp'))
presets=SuPvElectricalPresets.for_spec(fixture_spec)
check(presets[:module_values]['beta_voc']==-0.24 && presets[:module_values]['module_max']==1500,'Exact NE19R profile not applied')
check(SuPvElectricalPresets.for_spec(fixture_spec.merge(power_w:620))[:module_source].nil?,'Wrong power bin reused factory defaults')
defaults=presets[:module_values].merge(presets[:design]['values']).merge(presets[:inverters].first['values'])
defaults['beta_vmp']=defaults['gamma_p']-defaults['alpha_isc']
default_result=SuPvElectricalDesign.calculate(records,spec,defaults)
check(default_result[:connected_count]>0 && default_result[:inverters].all? { |inv| inv['power_w']<=60000 && inv['mppts'].all? { |m| m['strings'].length*15.01<=32 } },'Factory/device defaults exceed conservative electrical limits')
records173=173.times.map { |i| records[i%records.length].merge('key'=>i.to_s,'origin_mm'=>[(i%10)*1234,(i/10)*2500,500]) }
default173=SuPvElectricalDesign.calculate(records173,spec,defaults)
check(default173[:connected_count]==173 && default173[:unassigned].empty? && default173[:inverters].length==2,'173-panel case did not connect every panel on two inverters')
check(default173[:series_sizes].map { |s| [s[:series_count],s[:string_count]] }==[[18,3],[17,7]],'173-panel string lengths differ from the balanced full allocation')
# Check actual panel conservation and every MPPT, not only the plan summary.
def verify_electrical_allocation(result,records,input,spec)
  strings=result[:strings];by_id=strings.to_h { |s| [s['id'],s] };by_panel=records.to_h { |r| [r['key'],r] }
  keys=strings.flat_map { |s| s['panels'] }
  check(keys.uniq.length==records.length && keys.sort==by_panel.keys.sort,'Duplicate or omitted panel in full allocation')
  strings.each do |str|
    n=str['panels'].length
    check(n==str['series_count'] && n.between?(*result[:range]),'Actual string length violates sizing range')
    check(n*result[:voc_cold]<[input['dc_max'],input['module_max']].min && n*result[:vmp_hot]>=input['mppt_min']-1e-8 && n*result[:vmp_cold]<=input['mppt_max']+1e-8,'Actual string violates temperature-adjusted voltage')
  end
  result[:inverters].each do |inv|
    check(inv['mppts'].length<=input['mppts'] && inv['power_w']<=result[:dc_capacity_w]+1e-8,'Inverter capacity/MPPT count exceeded')
    power=0
    inv['mppts'].each do |slot|
      connected=slot['strings'].map { |id| by_id.fetch(id) }
      check(connected.all? { |str| str['inverter']==inv['id'] && str['mppt']==slot['id'] },'MPPT references wrong inverter/string')
      check(connected.map { |str| str['panels'].length }.uniq==[slot['series_count']],'Unequal strings shared an MPPT')
      check(connected.flat_map { |str| str['panels'] }.map { |key| by_panel[key]['axes'][2] }.uniq.length==1,'MPPT mixed roof normals')
      check(connected.length<=input['ports'] && connected.length*input['imp']<=input['mppt_current']+1e-8 && connected.length*input['isc']*input['isc_factor']<=input['mppt_isc']+1e-8,'MPPT current/port constraint exceeded')
      power+=connected.sum { |str| str['panels'].length*spec[:power_w] }
    end
    check((power-inv['power_w']).abs<1e-8,'Inverter power omitted or duplicated strings')
  end
end
verify_electrical_allocation(default173,records173,defaults,spec)
[97,101,173,199,218,499,5000].each do |count|
  sample=count.times.map { |i| records[i%records.length].merge('key'=>i.to_s,'origin_mm'=>[(i%30)*1234,(i/30)*2500,100]) }
  sample.last(count/3).each { |r| r['axes']=[[1,0,0],[0,0,1],[0,-1,0]] } unless count==5000
  started=Process.clock_gettime(Process::CLOCK_MONOTONIC)
  allocation=SuPvElectricalDesign.calculate(sample,spec,defaults)
  verify_electrical_allocation(allocation,sample,defaults,spec)
  puts "Full allocation: #{count} panels, #{allocation[:strings].length} strings, #{allocation[:inverters].length} inverters (#{(Process.clock_gettime(Process::CLOCK_MONOTONIC)-started).round(3)}s)"
end
begin
  SuPvElectricalDesign.calculate(mixed.first(4)+mixed.last(50),spec,input)
  raise 'Undervoltage orientation fragment was silently omitted'
rescue RuntimeError=>error
  raise if error.message=='Undervoltage orientation fragment was silently omitted'
  check(error.message.include?('少于最短'),'Infeasible orientation did not explain the voltage minimum')
end
records216=216.times.map { |i| records[i%records.length].merge('key'=>i.to_s,'origin_mm'=>[(i%18)*1234,(i/18)*2500,100]) }
default216=SuPvElectricalDesign.calculate(records216,spec,defaults)
verify_electrical_allocation(default216,records216,defaults,spec)
records230=230.times.map { |i| records[i%records.length].merge('key'=>i.to_s,'origin_mm'=>[(i%18)*1234,(i/18)*2500,100]) }
default230=SuPvElectricalDesign.calculate(records230,spec,defaults)
verify_electrical_allocation(default230,records230,defaults,spec)
check(default230[:selection][:global_optimal]==false && default230[:selection][:recommended_series_count]==19,'Automatic selection scope or recommended limit is misleading')
check(default230[:candidates].min_by { |c| [c[:inverter_count],c[:string_count],c[:string_sizes].length,c[:mppt_count],-c[:series_count]] }[:series_count]==default230[:selection][:recommended_series_count],'Declared recommendation differs from ranking')
targets=%w[inverters strings balanced].to_h do |objective|
  allocation=SuPvElectricalDesign.calculate(records230,spec,defaults.merge('objective'=>objective))
  verify_electrical_allocation(allocation,records230,defaults,spec)
  check(allocation[:selection][:objective]==objective,'Selected objective was not applied')
  [objective,allocation]
end
check(targets['strings'][:strings].length<=targets['inverters'][:strings].length,'Fewest-strings objective increased string count')
counts=targets['balanced'][:inverters].map { |inv| inv['mppts'].sum { |slot| slot['strings'].length } }
check(counts.uniq.length==1 && counts==[5,5,5],'Balanced objective did not balance 230 panels across three inverters')
check(targets['balanced'][:strings].length==15 && targets['inverters'][:strings].length==13,'Objectives do not produce distinct valid plans')
check(targets['balanced'][:inverters].length==targets['inverters'][:inverters].length,'Balancing added avoidable inverters')
begin;SuPvElectricalDesign.calculate(records230,spec,defaults.merge('objective'=>'energy'));raise 'Unsupported objective accepted';rescue RuntimeError=>error;raise if error.message=='Unsupported objective accepted';end
records186=186.times.map do |i|
  record=records[i%records.length].merge('key'=>i.to_s,'origin_mm'=>[(i%18)*1234,(i/18)*2500,100])
  record['axes']=[[1,0,0],[0,0,1],[0,-1,0]] if i>=60
  record
end
tradeoff=%w[inverters strings balanced].to_h do |goal|
  allocation=SuPvElectricalDesign.calculate(records186,spec,defaults.merge('objective'=>goal))
  verify_electrical_allocation(allocation,records186,defaults,spec)
  [goal,allocation]
end
check([tradeoff['inverters'][:inverters].length,tradeoff['inverters'][:strings].length]==[2,12],'Inverters-first objective did not use two inverters in the trade-off case')
check([tradeoff['strings'][:inverters].length,tradeoff['strings'][:strings].length]==[3,11],'Strings-first objective did not prefer fewer strings over fewer inverters')
# Reported 232-panel selection: all goals and each manual curve point must
# produce complete, constraint-compliant connections, including short roof groups.
records232=232.times.map { |i| records[i%records.length].merge('key'=>i.to_s,'origin_mm'=>[(i%18)*1234,(i/18)*2500,100]) }
targets232=%w[inverters strings balanced].to_h do |goal|
  params=defaults.merge('objective'=>goal)
  plan=SuPvElectricalDesign.calculate(records232,spec,params)
  verify_electrical_allocation(plan,records232,params,spec)
  plan[:candidates].each do |candidate|
    manual=SuPvElectricalDesign.calculate(records232,spec,params.merge('series_count'=>candidate[:series_count]))
    verify_electrical_allocation(manual,records232,params,spec)
  end
  [goal,plan]
end
fragmented232=Marshal.load(Marshal.dump(records232))
fragmented232.first(7).each { |r| r['axes']=[[1,0,0],[0,0,1],[0,-1,0]] }
fragment_plan=SuPvElectricalDesign.calculate(fragmented232,spec,defaults)
verify_electrical_allocation(fragment_plan,fragmented232,defaults,spec)
check(fragment_plan[:candidates].none? { |candidate| candidate[:series_count]<7 },'Short orientation produced an empty candidate')
begin
  SuPvElectricalDesign.calculate(fragmented232,spec,defaults.merge('series_count'=>5))
  raise 'Infeasible manual upper limit accepted'
rescue SuPvElectricalDesign::ValidationError=>error
  check(error.message.include?('当前每串上限'),'Invalid upper limit was reported as a program exception')
end
# SU extensions can override Array#sum to return nil (including for block sums).
# The electrical solver must stay isolated from that process-wide modification.
records1820=1820.times.map { |i| records[i%records.length].merge('key'=>i.to_s,'origin_mm'=>[(i%52)*1234,(i/52)*2500,100],'axes'=>[[1,0,0],[0,Math.sqrt(0.5),Math.sqrt(0.5)],[0,-Math.sqrt(0.5),Math.sqrt(0.5)]]) }
native_array_sum=Array.instance_method(:sum)
compatibility={}
begin
  Array.send(:define_method,:sum) { |*_args,&_block| nil }
  %w[inverters strings balanced].each do |goal|
    compatibility[goal]=SuPvElectricalDesign.calculate(records1820,spec,defaults.merge('objective'=>goal))
  end
ensure
  Array.send(:define_method,:sum,native_array_sum)
end
compatibility.each_value { |plan| verify_electrical_allocation(plan,records1820,defaults,spec) }
File.write("#{root}/output/checks/electrical_fixture.json",JSON.generate({records:records,spec:fixture_spec,presets:presets,module_errors:[],input:input,result:result,explicit_result:explicit,explicit18_result:SuPvElectricalDesign.calculate(records,spec,input.merge('series_count'=>18)),default_input:defaults,default_result:default_result,case173:{records:records173,result:default173},case186:{records:records186,targets:tradeoff},case216:{records:records216,result:default216},case1820:{records:records1820,targets:compatibility},case232:{records:records232,targets:targets232},case230:{records:records230,result:default230,manual10:SuPvElectricalDesign.calculate(records230,spec,defaults.merge('series_count'=>10)),targets:targets}}))
puts 'Mount clearance, roof feet, electrical voltage/current/capacity, full mixed-length strings and orientation checks passed.'
