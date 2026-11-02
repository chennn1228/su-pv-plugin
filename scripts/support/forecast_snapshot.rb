# encoding: UTF-8
# Pure numeric snapshot of actual panel instances; no model writes.
load File.expand_path('roof_angles.rb',__dir__)
load File.expand_path('roof_region.rb',__dir__)
module SuPvForecastSnapshot
  def self.component(panel)
    spec=SuPvPanelTool.panel_spec(panel.fetch('model_id'))
    axes=panel.fetch('axes');u,v,n=axes
    valid=axes.length==3 && axes.all? { |a| a.length==3 && a.all? { |x| x.is_a?(Numeric) && x.finite? } && (a.inject(0.0) { |s,x| s+x*x }-1).abs<1e-6 }
    cross=SuPvRoofRegion.cross(u,v)
    valid &&= cross.zip(n).all? { |x,y| (x-y).abs<1e-6 } && SuPvRoofRegion.dot(u,v).abs<1e-6
    raise '组件存在缩放或镜像，请使用原尺寸光伏板。' unless valid
    raise '组件坐标无效。' unless panel['origin_mm'].length==3 && panel['origin_mm'].all? { |x| x.is_a?(Numeric) && x.finite? }
    tilt=Math.atan2(Math.hypot(n[0],n[1]),n[2])*180/Math::PI
    azimuth=((tilt<1e-7 ? Math.atan2(u[1],-u[0]) : Math.atan2(n[0],n[1]))*180/Math::PI+360)%360
    a,b=azimuth.round,tilt.round
    azimuth=a if (azimuth-a).abs<1e-7
    tilt=b if (tilt-b).abs<1e-7
    settings=SuPvRoofAngles.validate_angles('azimuth'=>azimuth,'tilt'=>tilt).merge('model_id'=>spec[:id])
    panel.merge('spec'=>spec,'settings'=>settings)
  end
  def self.build(panels)
    raise '请选择本插件生成的光伏板或包含光伏板的群组。' if panels.empty?
    raise '预测一次最多支持5000块板。' if panels.length>5000
    components=panels.map { |p| component(p) }
    first=components.first;spec=first['spec'];axes=first['axes']
    world_corners=components.flat_map do |p|
      [[0,0],[p['spec'][:width_mm],0],[p['spec'][:width_mm],p['spec'][:length_mm]],[0,p['spec'][:length_mm]]].map do |x,y|
        (0..2).map { |k| p['origin_mm'][k]+x*p['axes'][0][k]+y*p['axes'][1][k] }
      end
    end
    low=(0..2).map { |k| world_corners.map { |p| p[k] }.min }
    high=(0..2).map { |k| world_corners.map { |p| p[k] }.max }
    components=components.map { |p| p.merge('origin'=>p['origin_mm'].zip(low).map { |a,b| a-b }) }
    groups=components.group_by { |p| [p['model_id'],p['settings']['azimuth'],p['settings']['tilt']] }
    series=[]
    summary=groups.map do |_,items|
      p=items.first;values=SuPvPanelTool.energy_for(p['spec'],p['settings']['azimuth'],p['settings']['tilt'])
      index=series.length;series << values
      items.each { |item| item['series_index']=index }
      {'model_id'=>p['model_id'],'manufacturer'=>p['spec'][:manufacturer],'power_w'=>p['spec'][:power_w],
       'azimuth'=>p['settings']['azimuth'],'tilt'=>p['settings']['tilt'],'count'=>items.length,'data_available'=>!values.nil?,
       'missing_data_message'=>values ? nil : SuPvPanelTool.missing_data_message(p['settings']['azimuth'])}
    end
    values=series.all? ? Array.new(8760) { |h| groups.values.each_with_index.inject(0.0) { |s,(items,i)| s+series[i][h]*items.length } } : nil
    missing_messages=summary.map { |item| item['missing_data_message'] }.compact.uniq
    prediction={settings:first['settings'],spec:spec,values:values,data_available:!values.nil?,
      missing_data_message:missing_messages.length>1 ? '部分角度或型号的出力数据暂缺' : missing_messages.first,
      peak_wh:values && values.max,annual_kwh:values && values.inject(0.0,:+)/1000.0}
    {'settings'=>first['settings'],'spec'=>spec,'count'=>components.length,'components'=>components,
     'series'=>series,'selection_summary'=>summary,'world_origin_mm'=>low,
     'positions'=>components.map { |p| p['origin'] },'frame_axes'=>[[1,0,0],[0,1,0],[0,0,1]],'panel_axes'=>axes,
     'width_mm'=>[high[0]-low[0],1.0].max,'height_mm'=>[high[1]-low[1],1.0].max,
     'capacity_kwp'=>components.inject(0.0) { |sum,p| sum+p['spec'][:power_w] }/1000.0,
     'prediction'=>prediction,'forecast_only'=>true}
  end
end
