# encoding: UTF-8
module SuPvAccessPicker
  def self.local_ray(origin,direction,target)
    dot=SuPvRoofRegion.method(:dot);n=target[:normal].to_a
    denominator=dot.call(direction,n)
    raise '当前视线与安装面平行，请调整视角。' if denominator.abs<1e-9
    delta=target[:origin].to_a.zip(origin).map { |a,b| a-b }
    t=dot.call(delta,n)/denominator
    raise '安装面位于视线后方。' if t<0
    p=origin.each_with_index.map { |v,i| v+t*direction[i]-target[:origin].to_a[i] }
    [dot.call(p,target[:u].to_a)*25.4,dot.call(p,target[:v].to_a)*25.4]
  end
  def self.world(p,target)
    Geom::Point3d.new((0..2).map { |i| target[:origin].to_a[i]+(p[0]*target[:u].to_a[i]+p[1]*target[:v].to_a[i])/25.4 })
  end
  def self.entry(p,region)
    SuPvAccessLayout.edges(region[:outer]).map { |a,b| SuPvAccessLayout.nearest(p,a,b) }.
      min_by { |q| Math.hypot(q[0]-p[0],q[1]-p[1]) }
  end
  class Tool
    def initialize(target,mode,&done)
      @target,@mode,@done=target,mode,done;@first=nil;@finished=false
    end
    def activate
      Sketchup.set_status_text(@mode=='entry' ? '选择屋面外边线或角点作为入口；Esc返回。' : '选择禁布区两个对角，矩形沿屋面边线方向；Esc返回。')
    end
    def candidate(x,y,view)
      raise '活动模型已改变，请返回重新选择。' unless Sketchup.active_model==@target[:model]
      ray=view.pickray(x,y);p=SuPvAccessPicker.local_ray(ray[0].to_a,ray[1].to_a,@target)
      if @mode=='entry'
        q=SuPvAccessPicker.entry(p,@target[:region])
        screen=view.screen_coords(SuPvAccessPicker.world(q,@target))
        # Deliberate selection near an edge only, not a remote interior click.
        raise '请靠近屋面外边线或角点选择入口。' if Math.hypot(screen.x-x,screen.y-y)>14
        corner=@target[:region][:outer].min_by do |v|
          s=view.screen_coords(SuPvAccessPicker.world(v,@target));Math.hypot(s.x-x,s.y-y)
        end
        s=view.screen_coords(SuPvAccessPicker.world(corner,@target));q=corner if Math.hypot(s.x-x,s.y-y)<=10
        raise '入口位置不可用。' unless SuPvAccessLayout.boundary_entry?(q,@target[:region])
        q
      else
        raise '请在选定屋面内取点，避开孔洞。' unless SuPvAccessLayout.on_roof?(p,@target[:region])
        if @first
          box=[[@first[0],p[0]].min,[@first[1],p[1]].min,[@first[0],p[0]].max,[@first[1],p[1]].max]
          raise '禁布区须完整位于屋面内。' unless SuPvRoofRegion.covered?(SuPvAccessLayout.rectangle(box),@target[:region])
        end
        p
      end
    end
    def onMouseMove(_flags,x,y,view)
      @hover=candidate(x,y,view);view.tooltip=@mode=='entry' ? '屋面入口' : (@first ? '选择第二个对角' : '选择第一个对角');view.invalidate
    rescue StandardError=>error
      @hover=nil;view.tooltip=error.message;view.invalidate
    end
    def onLButtonDown(_flags,x,y,view)
      p=candidate(x,y,view)
      if @mode=='entry'
        finish(p)
      elsif @first
        r=[[@first[0],p[0]].min,[@first[1],p[1]].min,[@first[0],p[0]].max,[@first[1],p[1]].max]
        raise '禁布区尺寸过小，请重新选择第二个对角。' if r[2]-r[0]<1 || r[3]-r[1]<1
        finish(r)
      else
        @first=p;view.invalidate
      end
    rescue StandardError=>error
      view.tooltip=error.message;Sketchup.set_status_text(error.message)
    end
    def draw(view)
      view.drawing_color=Sketchup::Color.new(55,128,106);view.line_width=2
      @target[:world_loops].each { |ring| view.draw(GL_LINE_LOOP,ring) }
      return unless @hover
      if @mode=='exclude' && @first
        a,b=@first,@hover
        view.draw(GL_LINE_LOOP,[a,[b[0],a[1]],b,[a[0],b[1]]].map { |p| SuPvAccessPicker.world(p,@target) })
      else
        view.draw_points([SuPvAccessPicker.world(@hover,@target)],10,3,Sketchup::Color.new(55,128,106))
      end
    end
    def finish(value)
      return if @finished
      @finished=true;@done.call(value)
    end
    def onCancel(_reason,_view);finish(nil);end
    def deactivate(view)
      Sketchup.set_status_text('');view.invalidate
      UI.start_timer(0,false) { finish(nil) } unless @finished
    end
  end
end
