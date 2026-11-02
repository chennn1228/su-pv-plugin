# encoding: UTF-8
# World-Z orthographic drawing from the selected PV instance records.
module SuPvHorizontalSvg
  def self.render(records)
    raise '请先选择光伏板。' if records.empty?
    raise '一次最多导出5000块光伏板。' if records.length>5000
    polygons=records.map do |record|
      panel=SuPvForecastSnapshot.component(record)
      spec=panel['spec']; origin=panel['origin_mm'];u,v=panel['axes']
      [[0,0],[spec[:width_mm],0],[spec[:width_mm],spec[:length_mm]],[0,spec[:length_mm]]].map do |x,y|
        [origin[0]+u[0]*x+v[0]*y,origin[1]+u[1]*x+v[1]*y]
      end
    end
    points=polygons.flatten(1)
    low=(0..1).map { |k| points.map { |p| p[k] }.min }
    high=(0..1).map { |k| points.map { |p| p[k] }.max }
    dx,dy=high.zip(low).map { |a,b| a-b }
    scale=[1450.0/[dx,1.0].max,930.0/[dy,1.0].max].min
    out="<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"1600\" height=\"1100\" viewBox=\"0 0 1600 1100\" data-cad-scale=\"#{1.0/scale}\" data-cad-origin-x=\"#{low[0]+dx/2-800/scale}\" data-cad-origin-y=\"#{low[1]+dy/2+550/scale}\"><title>光伏水平俯视图</title><rect width=\"1600\" height=\"1100\" fill=\"white\"/><g data-cad-layer=\"PV_COMPONENT\" fill=\"#b7d3e8\" stroke=\"#2166ac\" stroke-width=\"1\">"
    polygons.each do |polygon|
      coordinates=polygon.map do |x,y|
        format('%.9f,%.9f',800+(x-low[0]-dx/2)*scale,550-(y-low[1]-dy/2)*scale)
      end.join(' ')
      out << "<polygon points=\"#{coordinates}\"/>"
    end
    out << "</g><g font-family=\"Microsoft YaHei, sans-serif\" fill=\"#27465e\"><text x=\"20\" y=\"42\" font-size=\"24\">水平俯视图 · #{records.length} 块</text>"
    out << format('<text x="20" y="1085" font-size="18">%.3f × %.3f m</text>',dx/1000,dy/1000)
    out << '<text x="1530" y="42" font-size="20">N ↑</text><text x="1530" y="68" font-size="16">E →</text></g></svg>'
  end
end
