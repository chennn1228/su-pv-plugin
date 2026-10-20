# encoding: UTF-8
# Uses real model datasets and the actual retained layout count, without launching SketchUp.
load File.expand_path('check_plugin.rb', __dir__)
load File.expand_path('../scripts/toolbar2/button_03_pv_array.rb', __dir__)
frame = [[1,0,0],[0,1,0],[0,0,1]]
SuPvPanelTool.panel_catalog.each do |spec|
  settings = { 'model_id' => spec[:id], 'azimuth' => 180, 'tilt' => 30,
    'gap_x_mm' => 100, 'gap_y_mm' => 500 }
  region = SuPvRoofRegion.prepare([[[0,0],[12000,0],[12000,8000],[0,8000]],
    [[4000,2000],[6000,2000],[6000,4000],[4000,4000]]])
  [nil, region].each do |boundary|
    plan = SuPvArrayLayout.plan(12000,8000,frame,spec,settings,boundary)
    result = SuPvArrayTool.prediction_for(plan,spec)
    single = SuPvPanelTool.energy_for(spec,180,30)
    check(result[:values].length == 8760, 'Array forecast lost hours')
    check(result[:values].zip(single).all? { |a,b| a == b * plan['count'] }, 'Forecast does not use retained panel count')
    expected = single.inject(0.0,:+) * plan['count'] / 1000.0
    check((result[:annual_kwh]-expected).abs < 1e-7, 'Array annual energy mismatch')
    check(result[:peak_wh] == single.max * plan['count'], 'Array peak mismatch')
    zero = SuPvArrayTool.prediction_for(plan.merge('count'=>0),spec)
    check(zero[:values].all?(&:zero?) && zero[:annual_kwh] == 0, 'Empty array is not zero')
  end
  missing = SuPvArrayTool.prediction_for({'settings'=>settings,'count'=>10},spec.merge(data_available:false))
  check(missing[:values].nil? && !missing[:data_available], 'Missing data fabricated')
end
