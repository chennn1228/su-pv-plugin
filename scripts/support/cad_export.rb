# encoding: UTF-8
require 'rexml/document'

# Converts the plugin's restricted vector vocabulary, not arbitrary SVG artwork.
module SuPvCadExport
  class Drawing
    def initialize(root)
      @entities=[];@handle=256;@linetypes={};@layers={'0'=>7,'PV_COMPONENT'=>5,'PV_BOUNDARY'=>8,'PV_CIRCUIT'=>7,'PV_TEXT'=>7,'PV_SUMMARY'=>8}
      @scale=number(root.attributes['data-cad-scale'] || 1)
      raise 'CAD比例无效。' unless @scale>0
      @ox=number(root.attributes['data-cad-origin-x'] || 0)
      @oy=number(root.attributes['data-cad-origin-y'] || root.attributes['height'] || 1100)
      visit(root,{'stroke'=>'none','fill'=>'black','font-size'=>'14','data-cad-layer'=>'PV_CIRCUIT'})
    end
    def number(value)
      n=Float(value);raise '图纸坐标无效。' unless n.finite? && n.abs<=1e12;n
    end
    def point(x,y);[@ox+number(x)*@scale,@oy-number(y)*@scale];end
    def handle;@handle+=1;@handle.to_s(16).upcase;end
    def pairs(*values);values.each_slice(2).map { |code,value| "#{code}\r\n#{value.is_a?(Float) ? format('%.9f',value) : value}\r\n" }.join;end
    def line_type(style)
      dash=style['stroke-dasharray'];return 'CONTINUOUS' unless dash && dash!='none'
      pattern=dash.split(/[ ,]+/).map { |n| number(n)*@scale }
      raise '图纸虚线参数无效。' unless pattern.length.between?(2,12) && pattern.all? { |n| n>0 }
      @linetypes[pattern] ||= "PV_DASH_#{@linetypes.length+1}"
    end
    def entity(type,subclass,style,*data)
      layer=style['data-cad-layer'];raise '图纸图层无效。' unless @layers.key?(layer)
      @entities<<pairs(0,type,5,handle,330,'1F',100,'AcDbEntity',8,layer,6,line_type(style),100,subclass,*data)
    end
    def polyline(points,closed,style)
      return if points.length<2
      vertices=points.flat_map { |x,y| [10,x,20,y] }
      entity('LWPOLYLINE','AcDbPolyline',style,90,points.length,70,closed ? 1 : 0,*vertices)
    end
    def path(value,style)
      raise 'CAD不支持此路径指令。' if value.gsub(/[MmLlHhVvZz0-9eE+.,\s-]/,'')!=''
      tokens=value.scan(/[MmLlHhVvZz]|[-+]?(?:\d*\.\d+|\d+\.?\d*)(?:[eE][-+]?\d+)?/)
      cursor=[0.0,0.0];start=nil;points=[];command=nil
      until tokens.empty?
        command=tokens.shift if tokens.first.match?(/\A[MmLlHhVvZz]\z/)
        raise '图纸路径无效。' unless command
        if command.downcase=='z'
          polyline(points,true,style);points=[];cursor=start;command=nil;next
        end
        count=%w[h v].include?(command.downcase) ? 1 : 2
        values=tokens.shift(count);raise '图纸路径坐标不足。' unless values.length==count
        values=values.map { |v| number(v) };relative=command==command.downcase
        if command.downcase=='m'
          polyline(points,false,style);points=[]
        end
        cursor=case command.downcase
        when 'h';[values[0]+(relative ? cursor[0] : 0),cursor[1]]
        when 'v';[cursor[0],values[0]+(relative ? cursor[1] : 0)]
        else;values.each_with_index.map { |n,i| n+(relative ? cursor[i] : 0) }
        end
        start=cursor.dup if command.downcase=='m'
        points<<point(*cursor);command=relative ? 'l' : 'L' if command.downcase=='m'
      end
      polyline(points,false,style)
    end
    def visit(node,inherited)
      return if %w[title desc].include?(node.name)
      raise 'CAD不支持图纸变换或内联样式。' if node.attributes['transform'] || node.attributes['style']
      style=inherited.merge(node.attributes.to_h.transform_values(&:value))
      case node.name
      when 'svg','g';node.elements.each { |child| visit(child,style) }
      when 'text'
        raise 'CAD文字含不支持的子元素。' unless node.elements.empty?
        content=node.texts.map(&:value).join.gsub(/[\r\n\t]/,' ')
        raise 'CAD单行文字过长。' if content.bytesize>250
        x,y=point(style['x']||0,style['y']||0);size=number(style['font-size'])*@scale
        raise 'CAD文字高度无效。' unless size>0
        align={'middle'=>1,'end'=>2}.fetch(style['text-anchor'],0)
        text_style=style.merge('data-cad-layer'=>'PV_TEXT','stroke-dasharray'=>'none')
        entity('TEXT','AcDbText',text_style,10,x,20,y,30,0,40,size,1,content,7,'PV_CHINESE',72,align,11,x,21,y,31,0,100,'AcDbText',73,0)
      else
        return if style['stroke']=='none'
        case node.name
        when 'polygon','polyline'
          values=style.fetch('points').split(/[ ,\s]+/).reject(&:empty?).map { |v| number(v) }
          raise '图纸多段线无效。' unless values.length.even?
          polyline(values.each_slice(2).map { |x,y| point(x,y) },node.name=='polygon',style)
        when 'rect'
          x=number(style['x']||0);y=number(style['y']||0);w=number(style.fetch('width'));h=number(style.fetch('height'))
          polyline([[x,y],[x+w,y],[x+w,y+h],[x,y+h]].map { |a,b| point(a,b) },true,style)
        when 'path';path(style.fetch('d'),style)
        when 'line'
          a=point(style['x1']||0,style['y1']||0);b=point(style['x2']||0,style['y2']||0)
          entity('LINE','AcDbLine',style,10,a[0],20,a[1],30,0,11,b[0],21,b[1],31,0)
        when 'circle'
          x,y=point(style['cx']||0,style['cy']||0);radius=number(style.fetch('r'))*@scale
          entity('CIRCLE','AcDbCircle',style,10,x,20,y,30,0,40,radius)
        else;raise "CAD不支持图元#{node.name}。"
        end
      end
    end
    def render
      ltypes=pairs(0,'LTYPE',5,'14',100,'AcDbSymbolTableRecord',100,'AcDbLinetypeTableRecord',2,'CONTINUOUS',70,0,3,'Solid line',72,65,73,0,40,0)
      @linetypes.each do |pattern,name|
        ltypes<<pairs(0,'LTYPE',5,handle,100,'AcDbSymbolTableRecord',100,'AcDbLinetypeTableRecord',2,name,70,0,3,'PV dashed',72,65,73,pattern.length,40,pattern.inject(0) { |sum,length| sum+length })
        pattern.each_with_index { |n,i| ltypes<<pairs(49,i.even? ? n : -n,74,0) }
      end
      layers=@layers.map { |name,color| pairs(0,'LAYER',5,handle,100,'AcDbSymbolTableRecord',100,'AcDbLayerTableRecord',2,name,70,0,62,color,6,'CONTINUOUS',370,25) }.join
      table=lambda { |name,content,count| pairs(0,'TABLE',2,name,5,handle,100,'AcDbSymbolTable',70,count)+content+pairs(0,'ENDTAB') }
      style=pairs(0,'STYLE',5,handle,100,'AcDbSymbolTableRecord',100,'AcDbTextStyleTableRecord',2,'PV_CHINESE',70,0,40,0,41,1,50,0,71,0,42,2.5,3,'simhei.ttf',4,'')
      blocks=pairs(0,'BLOCK_RECORD',5,'1F',100,'AcDbSymbolTableRecord',100,'AcDbBlockTableRecord',2,'*Model_Space',70,0)+pairs(0,'BLOCK_RECORD',5,'1E',100,'AcDbSymbolTableRecord',100,'AcDbBlockTableRecord',2,'*Paper_Space',70,0)
      tables=table.call('LTYPE',ltypes,@linetypes.length+1)+table.call('LAYER',layers,@layers.length)+table.call('STYLE',style,1)+table.call('BLOCK_RECORD',blocks,2)
      block_section=[['*Model_Space','1F'],['*Paper_Space','1E']].map do |name,owner|
        pairs(0,'BLOCK',5,handle,330,owner,100,'AcDbEntity',8,'0',100,'AcDbBlockBegin',2,name,70,0,10,0,20,0,30,0,3,name,1,'')+pairs(0,'ENDBLK',5,handle,330,owner,100,'AcDbEntity',8,'0',100,'AcDbBlockEnd')
      end.join
      header=pairs(9,'$ACADVER',1,'AC1021',9,'$DWGCODEPAGE',3,'ANSI_1252',9,'$INSUNITS',70,4,9,'$MEASUREMENT',70,1,9,'$LUNITS',70,2,9,'$HANDSEED',5,(@handle+100).to_s(16).upcase)
      pairs(0,'SECTION',2,'HEADER')+header+pairs(0,'ENDSEC',0,'SECTION',2,'TABLES')+tables+pairs(0,'ENDSEC',0,'SECTION',2,'BLOCKS')+block_section+pairs(0,'ENDSEC',0,'SECTION',2,'ENTITIES')+@entities.join+pairs(0,'ENDSEC',0,'EOF')
    end
  end
  def self.from_svg(body)
    raise 'SVG内容无效。' unless body.is_a?(String) && body.bytesize<=32*1024*1024 && !body.match?(/<!|<\?|\bon\w+\s*=|href\s*=/i)
    root=REXML::Document.new(body).root
    raise '图纸根节点无效。' unless root && root.name=='svg'
    Drawing.new(root).render
  end
end
