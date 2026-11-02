# encoding: UTF-8
module SuPvElectricalPresets
  def self.catalog
    path=File.expand_path('../../data/electrical_presets.json',__dir__)
    stamp=[File.size(path),File.mtime(path).to_f]
    if @stamp!=stamp
      @catalog=JSON.parse(File.read(path,encoding:'UTF-8'));@stamp=stamp
    end
    @catalog
  end
  def self.for_spec(spec)
    data=catalog
    profile=data.fetch('modules',{})[spec[:id]]
    profile=nil if profile && profile['power_w']!=spec[:power_w]
    module_values=spec[:electrical].dup
    module_values.merge!(profile.fetch('values')) if profile
    {module_values:module_values,module_source:profile && profile['source'],design:data.fetch('design'),inverters:data.fetch('inverters')}
  end
end
