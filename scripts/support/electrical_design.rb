# encoding: UTF-8
# Feasible string sizing and spatial attribution. No I/V or AC-yield simulation.
module SuPvElectricalDesign
  class ValidationError < RuntimeError;end
  def self.same_geometry?(before,after)
    return false unless before.is_a?(Array) && after.is_a?(Array) && before.length==after.length
    by_key=before.to_h { |record| [record['key'],record] }
    return false unless by_key.length==before.length && after.map { |r| r['key'] }.uniq.length==after.length
    after.all? do |record|
      old=by_key[record['key']]
      next false unless old && old['model_id']==record['model_id']
      vectors=[['origin_mm',1e-4],['axes',1e-7]]
      vectors.all? do |field,tolerance|
        a=old[field];b=record[field]
        next false unless a.is_a?(Array) && b.is_a?(Array)
        a=a.flatten;b=b.flatten
        a.length==b.length && a.zip(b).all? { |x,y| x.is_a?(Numeric) && y.is_a?(Numeric) && x.finite? && y.finite? && (x-y).abs<=tolerance }
      end
    end
  end
  def self.number(data,key,min,max)
    value=Float(data.fetch(key))
    raise ValidationError,"参数#{key}超出范围或无效。" unless value.finite? && value>=min && value<=max
    value
  rescue KeyError,ArgumentError,TypeError
    raise ValidationError,"请填写参数#{key}。"
  end
  def self.integer(data,key,min,max)
    value=number(data,key,min,max)
    raise ValidationError,"参数#{key}须为整数。" unless value==value.to_i
    value.to_i
  end
  def self.module_errors(data,power)
    errors=[]
    errors<<'Vmp必须小于Voc' unless data['vmp']<data['voc']
    errors<<'Imp必须小于或等于Isc' unless data['imp']<=data['isc']
    errors<<'Vmp×Imp与组件额定功率相差超过5%，请核对原表' if (data['vmp']*data['imp']-power).abs>power*0.05
    errors
  end
  # Avoid Array#sum: other installed extensions can replace this core method.
  def self.total(items)
    value=0
    items.each { |item| value+=block_given? ? yield(item) : item }
    value
  end
  def self.dot(a,b);a.zip(b).inject(0.0) { |s,(x,y)| s+x*y };end
  def self.calculate(records,spec,input)
    if input['curve_samples']
      curves=input['curve_samples']
      raise ValidationError,'导入曲线数据无效。' unless curves.is_a?(Array) && curves.length.between?(1,12)
      points=curves.flat_map do |curve|
        raise ValidationError,'导入曲线数据无效。' unless curve.is_a?(Hash) && curve['points'].is_a?(Array) && curve['points'].length>=3
        raise ValidationError,'导入曲线工况无效。' unless %w[g t].all? { |key| curve[key].nil? || curve[key].is_a?(Numeric) && curve[key].finite? } && (curve['g'].nil? || curve['g']>0)
        curve['points']
      end
      raise ValidationError,'导入曲线测点过多或无效。' unless points.length<=5000 && points.all? { |point| point.is_a?(Hash) && %w[v i p].all? { |key| point[key].is_a?(Numeric) && point[key].finite? && point[key]>=0 } }
      curves.each do |curve|
        raise ValidationError,'导入曲线电压须严格递增。' unless curve['points'].each_cons(2).all? { |a,b| a['v']<b['v'] }
      end
    end
    raise ValidationError,'请选择1—5000块同型号光伏组件。' unless records.length.between?(1,5000) && records.all? { |r| r['model_id']==spec[:id] }
    m=%w[voc vmp isc imp].to_h { |key| [key,number(input,key,0.001,3000)] }
    errors=module_errors(m,spec[:power_w]);raise ValidationError,errors.join('；') unless errors.empty?
    bvo=number(input,'beta_voc',-2,0)/100.0;bvm=number(input,'beta_vmp',-2,0)/100.0
    tmin=number(input,'tmin',-80,40);tmax=number(input,'tmax',25,120)
    raise ValidationError,'最低设计温度须低于最高电池温度。' unless tmin<tmax
    factor=number(input,'isc_factor',1,3)
    vmax=[number(input,'dc_max',1,3000),number(input,'module_max',1,3000)].min
    vlo=number(input,'mppt_min',1,3000);vhi=number(input,'mppt_max',1,3000)
    raise ValidationError,'MPPT电压下限须小于上限，且上限不得超过逆变器最大直流电压。' unless vlo<vhi && vhi<=number(input,'dc_max',1,3000)
    voc_cold=m['voc']*(1+bvo*(tmin-25));vmp_cold=m['vmp']*(1+bvm*(tmin-25));vmp_hot=m['vmp']*(1+bvm*(tmax-25))
    raise ValidationError,'温度修正后的组件电压无效，请核对温度系数。' unless [voc_cold,vmp_cold,vmp_hot].all? { |v| v>0 } && vmp_cold<voc_cold
    # Absolute voltage uses strict <; MPPT window allows equality.
    nmin=(vlo/vmp_hot-1e-10).ceil
    nmax=[(vhi/vmp_cold+1e-10).floor,(vmax/voc_cold).ceil-1,records.length].min
    raise ValidationError,'串联数量没有可行区间，请调整设备或核对设计温度。' unless nmax>=nmin && nmin>=1
    imax=number(input,'mppt_current',0.001,5000);iscmax=number(input,'mppt_isc',0.001,5000)
    port_current=number(input,'port_current',0.001,5000);port_isc=number(input,'port_isc',0.001,5000)
    raise ValidationError,'单串电流超过单输入端口允许值。' if m['imp']>port_current || m['isc']*factor>port_isc
    parallel=[(imax/m['imp']+1e-10).floor,(iscmax/(m['isc']*factor)+1e-10).floor,integer(input,'ports',1,64)].min
    raise ValidationError,'MPPT电流或端口数量不足以接入一串。' unless parallel>=1
    mppts=integer(input,'mppts',1,64);pac=number(input,'ac_kw',0.01,100000)
    dc_limits=[pac*number(input,'dc_ac_max',0.1,3)]
    dc_limits<<number(input,'dc_kw',0.01,150000) unless input['dc_kw'].nil? || input['dc_kw']==''
    dc_cap=dc_limits.min*1000
    objective=input.fetch('objective','inverters')
    raise ValidationError,'请选择有效的配置目标。' unless %w[inverters strings balanced].include?(objective)
    selected=integer(input,'series_count',0,5000)
    raise ValidationError,"每串数量须在#{nmin}—#{nmax}内。" if selected>0 && !selected.between?(nmin,nmax)
    groups=records.group_by do |r|
      axes=r.fetch('axes')
      raise ValidationError,'组件存在缩放或剪切，请先恢复真实尺寸。' unless axes.all? { |a| (dot(a,a)-1).abs<1e-5 } && dot(axes[0],axes[1]).abs<1e-5 && dot(axes[0],axes[2]).abs<1e-5 && dot(axes[1],axes[2]).abs<1e-5
      # Same front normal per MPPT; no mixing different roof orientations.
      axes[2].map { |v| v.round(7) }
    end.values
    groups=groups.map do |items|
      u,v=items.first.fetch('axes')[0,2]
      ordered=items.sort_by { |r| [dot(r['origin_mm'],v),dot(r['origin_mm'],u)] }
      # Cluster actual row coordinates, then serpentine through adjacent rows.
      rows=[];ordered.each do |r|
        y=dot(r['origin_mm'],v)
        if rows.empty? || (y-rows.last[0]).abs>spec[:length_mm]*0.15
          rows<<[y,[]]
        end
        rows.last[1]<<r
      end
      rows.each_with_index.flat_map { |(_,row),i| sorted=row.sort_by { |r| dot(r['origin_mm'],u) };i.odd? ? sorted.reverse : sorted }
    end
    # A selected value is an upper bound on string length, not a demand to
    # discard the remainder. Rebalance every orientation group into full strings.
    module_cap=(dc_cap/spec[:power_w]+1e-10).floor
    usable_max=[nmax,module_cap].min
    raise ValidationError,'当前逆变器容量不足以接入一串，请调整设备或容配比。' if usable_max<nmin
    short=groups.select { |g| g.length<nmin }.map(&:length)
    raise ValidationError,"有朝向分组仅#{short.join('、')}块，少于最短#{nmin}块；请调整设备或组件配置。" unless short.empty?
    cache={};candidates=[];best=nil;selected_plan=nil
    (nmin..usable_max).each do |limit|
      buckets=[];feasible=true
      groups.each_with_index do |group,gi|
        count=(group.length+limit-1)/limit
        length,extra=group.length.divmod(count)
        if length<nmin
          feasible=false;break
        end
        buckets<<[gi,length+1,extra] if extra>0
        buckets<<[gi,length,count-extra] if count>extra
      end
      next unless feasible && !buckets.empty?
      signature=buckets.flatten
      packed=cache[signature] ||= begin
        allocation=pack_strings(buckets,mppts,parallel,module_cap)
        objective=='balanced' ? balance_strings(allocation,mppts,parallel,module_cap) : allocation
      end
      raise 'Empty electrical candidate allocation' if packed.empty?
      per_inverter=packed.map { |inv| total(inv[:slots]) { |slot| slot[2] } }

      sizes=buckets.each_with_object(Hash.new(0)) { |(_,length,count),h| h[length]+=count }.sort.reverse.map { |length,count| {series_count:length,string_count:count} }
      candidate={series_count:limit,connected_count:records.length,unassigned:0,
                 string_count:total(sizes) { |size| size[:string_count] },string_sizes:sizes,
                 inverter_count:packed.length,mppt_count:total(packed) { |inv| inv[:slots].length },
                 inverter_string_counts:per_inverter,string_count_range:per_inverter.max-per_inverter.min,
                 string_count_imbalance:packed.length*total(per_inverter) { |count| count*count }-total(per_inverter)**2}
      candidates<<candidate
      plan={candidate:candidate,packed:packed}
      score=candidate_score(candidate,objective)
      best=plan.merge(score:score) if !best || (score<=>best[:score])<0
      selected_plan=plan if limit==selected
    end
    raise ValidationError,'当前设备无法让所有组件组成合规组串，请调整设备或组件配置。' unless best
    chosen=selected>0 ? selected_plan : best
    raise ValidationError,'当前每串上限无法让全部组件接入，请提高上限或使用自动配置。' unless chosen
    summary=chosen[:candidate];strings=[];positions=Array.new(groups.length,0)
    inverters=chosen[:packed].each_with_index.map do |packed,ii|
      slots=packed[:slots].each_with_index.map do |slot,mi|
        gi,length,count=slot
        ids=count.times.map do
          panels=groups[gi].slice(positions[gi],length);positions[gi]+=length
          id=strings.length+1
          strings<<{'id'=>id,'inverter'=>ii+1,'mppt'=>mi+1,'series_count'=>length,'panels'=>panels.map { |r| r['key'] }}
          id
        end
        {'id'=>mi+1,'series_count'=>length,'strings'=>ids}
      end
      {'id'=>ii+1,'power_w'=>packed[:modules]*spec[:power_w],'mppts'=>slots}
    end
    raise '组串分配未完整覆盖所选组件。' unless positions==groups.map(&:length)
    {series_count:summary[:series_count],series_sizes:summary[:string_sizes],parallel_max:parallel,
      inverters:inverters,strings:strings,unassigned:[],connected_count:records.length,
      dc_ac_ratio:records.length*spec[:power_w]/(inverters.length*pac*1000),
      range:[nmin,nmax],voc_cold:voc_cold,vmp_cold:vmp_cold,vmp_hot:vmp_hot,
      isc_design:m['isc']*factor,mppt_current:imax,mppt_isc:iscmax,dc_capacity_w:dc_cap,
      candidates:candidates,input:input,
      selection:{method:'balanced_best_fit',objective:objective,global_optimal:false,candidate_count:candidates.length,
                 recommended_series_count:best[:candidate][:series_count],
                 priority:objective_priority(objective)},
      scope:'按板面法向分组，全组件接入；同一MPPT并联等长，不同MPPT可采用不同串长。按所选目标比较候选，采用容量装箱及组串再平衡分配；非全年收益优化或施工走线图。'}
  end

  def self.objective_priority(objective)
    case objective
    when 'strings';%w[string_count inverter_count length_types mppt_count series_limit]
    when 'balanced';%w[inverter_count string_count_range string_count_imbalance string_count length_types mppt_count series_limit]
    else;%w[inverter_count string_count length_types mppt_count series_limit]
    end
  end
  def self.candidate_score(candidate,objective)
    values=candidate.merge(length_types:candidate[:string_sizes].length,series_limit:-candidate[:series_count])
    objective_priority(objective).map { |key| values.fetch(key.to_sym) }
  end
  def self.balance_strings(inverters,mppts,parallel,module_cap)
    # With inverter count fixed, move whole strings only when their count
    # dispersion strictly decreases and every MPPT/capacity constraint survives.
    loop do
      counts=inverters.map { |inv| total(inv[:slots]) { |slot| slot[2] } }
      moved=false
      counts.each_index.sort_by { |i| counts[i] }.each do |to|
        counts.each_index.sort_by { |i| -counts[i] }.each do |from|
          next if counts[from]-counts[to]<2
          donor=inverters[from];receiver=inverters[to]
          donor[:slots].sort_by { |gi,length,count| [-length,gi] }.each do |slot|
            gi,length=slot
            next if receiver[:modules]+length>module_cap
            target=receiver[:slots].find { |g,n,count| g==gi && n==length && count<parallel }
            next if !target && receiver[:slots].length>=mppts
            if target;target[2]+=1;else;receiver[:slots]<<[gi,length,1];end
            slot[2]-=1;donor[:slots].delete(slot) if slot[2]==0
            donor[:modules]-=length;receiver[:modules]+=length
            moved=true;break
          end
          break if moved
        end
        break if moved
      end
      break unless moved
    end
    inverters
  end

  def self.pack_strings(buckets,mppts,parallel,module_cap)
    # Best-fit packing of homogeneous MPPT slots. Separate normals and lengths
    # never share an MPPT; different independent MPPTs may have different lengths.
    inverters=[]
    buckets.sort_by { |gi,length,count| [-length,-count,gi] }.each do |gi,length,count|
      remaining=count
      while remaining>0
        feasible=inverters.each_with_index.filter_map do |inv,index|
          next if inv[:slots].length>=mppts
          take=[remaining,parallel,(module_cap-inv[:modules])/length].min
          next if take<1
          [index,take,module_cap-inv[:modules]-take*length]
        end
        choice=feasible.min_by { |index,take,left| [-take,left,index] }
        unless choice
          inverters<<{modules:0,slots:[]}
          choice=[inverters.length-1,[remaining,parallel,module_cap/length].min,0]
        end
        index,take=choice
        inv=inverters[index];inv[:slots]<<[gi,length,take];inv[:modules]+=length*take
        remaining-=take
      end
    end
    inverters
  end
end
