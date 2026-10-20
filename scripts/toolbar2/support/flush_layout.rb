# encoding: UTF-8
load File.expand_path('roof_region.rb',__dir__)
load File.expand_path('roof_angles.rb',__dir__)

module SuPvFlushLayout
  def self.plan(width,height,region,spec,landscape,gap_x_mm,gap_y_mm,clearance_mm)
    w,l=spec.values_at(:width_mm,:length_mm)
    px,py=landscape ? [l,w] : [w,l]
    gx,gy,h=[gap_x_mm,gap_y_mm,clearance_mm].map { |v| Float(v) }
    raise ArgumentError,'净距和离屋面高度须为非负有限数值。' unless [gx,gy,h].all? { |v| v.finite? && v>=0 }
    raise ArgumentError,'请按1 cm的精度输入。' unless [gx,gy,h].all? { |v| (v/10.0-(v/10.0).round).abs<1e-8 }
    max_x=[0,([px,width-2*px].min/10.0+1e-8).floor*10].max
    max_y=[0,([py,height-2*py].min/10.0+1e-8).floor*10].max
    raise ArgumentError,"横向净距上限#{(max_x/10).to_i} cm，纵向净距上限#{(max_y/10).to_i} cm。" if gx>max_x || gy>max_y
    columns=((width+gx+1e-7)/(px+gx)).floor
    rows=((height+gy+1e-7)/(py+gy)).floor
    raise ArgumentError,'候选网格超过50000块，请增大净距或选择较小的面。' if columns*rows>50000
    ox=(width-columns*px-[columns-1,0].max*gx)/2.0
    oy=(height-rows*py-[rows-1,0].max*gy)/2.0
    positions=[]
    rows.times do |row|
      columns.times do |col|
        x,y=ox+col*(px+gx),oy+row*(py+gy)
        rectangle=[[x,y],[x+px,y],[x+px,y+py],[x,y+py]]
        next unless SuPvRoofRegion.covered?(rectangle,region)
        positions << [landscape ? x+l : x,y,h]
        raise ArgumentError,'有效阵列超过5000块，请增大净距或选择较小的面。' if positions.length>5000
      end
    end
    raise ArgumentError,'当前参数放不下一块完整光伏板，请更换板型或调整净距。' if positions.empty?
    {positions:positions,axes:landscape ? [[0,1,0],[-1,0,0],[0,0,1]] : [[1,0,0],[0,1,0],[0,0,1]],
      count:positions.length,columns:columns,rows:rows}
  end
end
