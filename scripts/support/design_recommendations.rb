# encoding: UTF-8
# Baseline energy recommendation from the delivered CSV, without claiming an electrical optimum.
module SuPvDesignRecommendations
  DAYS=[31,28,31,30,31,30,31,31,30,31,30,31].freeze unless const_defined?(:DAYS,false)
  def self.rows(spec)
    indexed=SuPvPanelTool.prepare_index(spec)
    if indexed[:annual_kwh]
      return indexed[:offsets].keys.each_with_index.map do |(a,b),i|
        {'azimuth'=>a,'tilt'=>b,'annual_kwh'=>indexed[:annual_kwh][i]}
      end
    end
    entry=SuPvPanelTool.generation_index.fetch('models').fetch(spec[:id])
    path=SuPvPanelTool.generation_path(entry.fetch('monthly_hourly'))
    stamp=[path,File.size(path),File.mtime(path).to_f]
    @cache||={};return @cache[stamp] if @cache.key?(stamp)
    values=[]
    File.open(path,'rb') do |file|
      header=CSV.parse_line(file.gets.to_s.force_encoding('UTF-8').sub(/\A\uFEFF/,''))
      raise '月平均逐时数据表头不正确。' unless header && header.length==290 && header[0,2]==%w[azimuth_deg tilt_deg]
      while (line=file.gets)
        next if line.strip.empty?
        fields=CSV.parse_line(line.force_encoding('UTF-8'))
        raise '月平均逐时数据格式不正确。' unless fields.length==290
        annual=fields.drop(2).each_with_index.inject(0.0) { |s,(v,i)| s+Float(v)*DAYS[i/24] }
        values<<{'azimuth'=>Float(fields[0]),'tilt'=>Float(fields[1]),'annual_kwh'=>annual/1000.0}
      end
    end
    raise '建议数据不完整。' unless values.map { |r| [r['azimuth'],r['tilt']] }.sort==SuPvPanelTool.generation_angles.sort &&
      values.all? { |r| r['annual_kwh'].finite? && r['annual_kwh']>=0 }
    @cache.delete_if { |key,_| key[0]==path };@cache[stamp]=values
  end
  def self.panel(settings)
    spec=SuPvPanelTool.panel_spec(settings['model_id'])
    best=rows(spec).max_by { |r| r['annual_kwh'] }
    {'settings'=>settings.merge(best.slice('azimuth','tilt').transform_values { |v| v.to_i }),
     'annual_kwh'=>best['annual_kwh'],'count'=>1,
     'scope'=>'当前型号、CSV已有角度内的单板基准年电量最大值；不含空间遮挡、电气失配及支架结构优化。'}
  end
  def self.array(settings,target)
    raise '立面与围墙采用固定贴合姿态，无可调角度建议。' if target[:flush_only]
    spec=SuPvPanelTool.panel_spec(settings['model_id'])
    frame=target.values_at(:u,:v,:normal).map(&:to_a)
    roof=SuPvRoofAngles.limits(frame[2]);fixed=SuPvArrayTool.fixed_azimuth(target)
    candidates=rows(spec).select do |r|
      (!fixed || (r['azimuth']-fixed).abs<1e-7) && r['tilt']>=roof['slope_deg']-1e-7
    end
    raise '当前安装朝向或倾角暂无基准数据，无法生成建议。' if candidates.empty?
    # All available angle pairs on a fixed centred grid. This bounds cost and
    # leaves the existing phase optimiser and corridor planner for the chosen candidate.
    raise '安装面过大，建议先分区后进行参数比较。' if candidates.length*target[:width]*target[:height]/(spec[:width_mm]*spec[:length_mm])>2_000_000
    best=nil
    candidates.each do |row|
      params=settings.merge(row.slice('azimuth','tilt'))
      begin
        plan=SuPvArrayLayout.plan(target[:width],target[:height],frame,spec,params,target[:region],optimize:false)
      rescue StandardError=>error
        next if error.message.include?('超过') || error.message.include?('投影退化')
        raise
      end
      energy=plan['count']*row['annual_kwh']
      best=[energy,row,plan] if !best || energy>best[0]
    end
    raise '当前约束下没有可排组件。' unless best && best[2]['count']>0
    {'settings'=>settings.merge(best[1].slice('azimuth','tilt')),'annual_kwh'=>best[0],'count'=>best[2]['count'],
     'scope'=>'固定型号、间距及当前禁布范围/通道，比较CSV全部可用角度的居中网格基准年电量；应用后按现有算法重排、重算通道。未计遮挡及电气损失，不是全局最优。'}
  end
end
