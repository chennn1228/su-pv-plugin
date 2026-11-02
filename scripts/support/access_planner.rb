# encoding: UTF-8
# Bounded rectilinear routing in roof coordinates. Candidate paths are checked
# with exact segment clearances; the search grid is not used for containment.
module SuPvAccessPlanner
  A=SuPvAccessLayout unless const_defined?(:A,false)
  def self.push(heap,item)
    i=heap.length;heap<<item
    while i>0
      p=(i-1)/2;break if heap[p][0]<=item[0]
      heap[i]=heap[p];i=p
    end
    heap[i]=item
  end
  def self.pop(heap)
    top=heap[0];last=heap.pop;return top if heap.empty?
    i=0
    while i*2+1<heap.length
      j=i*2+1;j+=1 if j+1<heap.length && heap[j+1][0]<heap[j][0]
      break if last[0]<=heap[j][0]
      heap[i]=heap[j];i=j
    end
    heap[i]=last;top
  end
  def self.shortest(graph,seeds,removed=0,penalty=0)
    dist=Array.new(graph.length,Float::INFINITY);prev=Array.new(graph.length);heap=[]
    seeds.each { |i| dist[i]=0;push(heap,[0,i]) }
    until heap.empty?
      cost,i=pop(heap);next if cost>dist[i]
      graph[i].each do |j,length,mask|
        value=cost+length+penalty*(mask & ~removed).to_s(2).count('1')
        next unless value<dist[j]-1e-7
        dist[j]=value;prev[j]=i;push(heap,[value,j])
      end
    end
    [dist,prev]
  end
  def self.plan(base,region,trace=nil)
    cfg=A.normalize(base['settings']['access']);entry=cfg['entry'];cfg['paths']=[]
    raise '请先在SU中选择屋面外边界上的入口。' unless A.boundary_entry?(entry,region)
    r=cfg['width_mm']/2.0;span=cfg['span_mm']
    trace.replace({'partition_span_mm'=>span,'seed_count'=>base['count'],'zones'=>[],'candidates'=>[]}) if trace
    raise '分区尺度不得小于通道净宽。' if span<2*r
    roots=[-2,-1,0,1,2].product([-2,-1,0,1,2]).map { |x,y| [entry[0]+x*r,entry[1]+y*r] }.
      select { |p| p!=entry && A.safe_segment?(p,p,cfg,region) && A.safe_segment?(entry,p,cfg,region,true) }.
      sort_by { |p| Math.hypot(p[0]-entry[0],p[1]-entry[1]) }
    raise '入口内侧无法容纳当前净宽，请换一个入口或调整通道宽度。' if roots.empty?
    root=roots.first
    rings=[region[:outer],*region[:holes],*cfg['exclusions'].map { |v| A.rectangle(v) }]
    # Boundary-offset lines preserve narrow necks; panel gap centres favour
    # routes that reuse existing spacing. Regular lines bound search density.
    axes=[region[:width],region[:height]].each_with_index.map do |extent,k|
      step=[2000.0,span/3.0].min
      lines=[root[k],r,extent-r]
      lines.concat((1...(extent/step).ceil).map { |i| extent*i/(extent/step).ceil })
      rings.each { |ring| ring.each { |p| lines.concat([p[k]-r,p[k]+r]) } }
      edges=base['positions'].flat_map { |p| base['footprint'].map { |q| p[k]+q[k] } }.sort.uniq
      edges.each_cons(2) { |a,b| lines << (a+b)/2 if b-a>=2*r-1e-6 }
      lines.select { |v| v>=r-1e-6 && v<=extent-r+1e-6 }.sort.each_with_object([]) { |v,out| out<<v if out.empty? || v-out.last>0.01 }
    end
    raise '通道候选过多，请缩小安装面或增大分区尺度。' if axes[0].length*axes[1].length>14000
    points=[];index={}
    axes[0].each_with_index do |x,i|
      axes[1].each_with_index do |y,j|
        p=[x,y];next unless A.safe_segment?(p,p,cfg,region)
        index[[i,j]]=points.length;points<<p
      end
    end
    root_id=points.each_index.min_by { |i| Math.hypot(points[i][0]-root[0],points[i][1]-root[1]) }
    raise '当前屋面无法形成通道。' unless root_id && Math.hypot(points[root_id][0]-root[0],points[root_id][1]-root[1])<0.01
    polygons=base['positions'].map { |p| SuPvRoofRegion.hull(base['footprint'].map { |q| [p[0]+q[0],p[1]+q[1]] }) }
    raise '当前没有可排组件，请先调整退让或排布参数。' if polygons.empty?
    raise '通道候选规模过大，请选择较小的安装面。' if points.length*polygons.length>5_000_000
    boxes=polygons.map { |p| A.bounds(p) }
    mask_for=lambda do |a,b|
      box=A.bounds([a,b]);mask=0
      polygons.each_with_index { |p,i| mask|=(1<<i) if A.near_bounds?(box,boxes[i],r) && A.polygon_segment_distance(p,a,b)<r-A::EPS }
      mask
    end
    graph=Array.new(points.length) { [] }
    index.each do |(i,j),id|
      [[i+1,j],[i,j+1]].each do |key|
        other=index[key];next unless other
        a,b=points[id],points[other];next unless A.safe_segment?(a,b,cfg,region)
        length=Math.hypot(a[0]-b[0],a[1]-b[1]);mask=mask_for.call(a,b)
        graph[id]<<[other,length,mask];graph[other]<<[id,length,mask]
      end
    end
    reachable,_=shortest(graph,[root_id])
    # Each occupied roof-local span x span cell is a maintenance subdivision.
    # Route to an actual panel-neighbouring node, never to a void-cell centroid.
    zones={}
    polygons.each do |poly|
      p=[poly.inject(0) { |sum,p| sum+p[0] }/poly.length,poly.inject(0) { |sum,p| sum+p[1] }/poly.length]
      nearest=points.each_index.min_by { |i| Math.hypot(points[i][0]-p[0],points[i][1]-p[1]) }
      raise '有排板区域无法从入口按当前净宽连通，请调整禁布区、入口或通道净宽。' unless nearest && reachable[nearest].finite?
      key=[(p[0]/span).floor,(p[1]/span).floor]
      (zones[key]||=[])<<nearest
    end
    terminals=zones.map do |key,ids|
      centre=[ids.inject(0) { |sum,i| sum+points[i][0] }/ids.length,ids.inject(0) { |sum,i| sum+points[i][1] }/ids.length]
      chosen=ids.uniq.min_by { |i| Math.hypot(points[i][0]-centre[0],points[i][1]-centre[1]) }
      trace['zones']<<{'column'=>key[0],'row'=>key[1],'target_mm'=>points[chosen]} if trace
      chosen
    end.uniq
    raise '检修分区过多，请增大分区尺度。' if terminals.length>45
    results=[0.5,4.0].map do |weight|
      paths=[[entry,root]];network=[root_id];removed=mask_for.call(entry,root)
      remaining=terminals-[root_id]
      until remaining.empty?
        costs,prev=shortest(graph,network,removed,weight*(region[:width]+region[:height]))
        goal=remaining.min_by { |i| costs[i] }
        raise '检修分区无法连通。' unless costs[goal].finite?
        ids=[goal];ids<<prev[ids.last] while prev[ids.last]
        ids.each_cons(2) { |a,b| removed|=graph[a].find { |e| e[0]==b }[2] }
        network|=ids;remaining-=network
        line=ids.reverse.map { |i| points[i] }
        compact=[];line.each do |p|
          compact.pop while compact.length>1 && ((compact[-1][0]-compact[-2][0])*(p[1]-compact[-1][1])-(compact[-1][1]-compact[-2][1])*(p[0]-compact[-1][0])).abs<1e-6
          compact<<p
        end
        paths<<compact if compact.length>1
      end
      candidate=cfg.merge('automatic'=>true,'paths'=>paths)
      validation=A.prepare(candidate,region)[:validation]
      raise validation['errors'].join(' ') unless validation['valid']
      length=paths.inject(0) { |sum,line| sum+line.each_cons(2).inject(0) { |length,(a,b)| length+Math.hypot(a[0]-b[0],a[1]-b[1]) } }
      [candidate,removed.to_s(2).count('1'),length]
    end
    selected=results.each_index.min_by { |i| [results[i][1],results[i][2]] }
    if trace
      trace['candidates']=results.each_with_index.map { |(_,loss,length),i| {'removed_seed_panels'=>loss,'length_mm'=>length,'selected'=>i==selected} }
      trace['route_length_mm']=results[selected][2]
    end
    results[selected].first
  end
end
