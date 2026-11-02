# encoding: UTF-8
# Read visible native geometry once on the SU thread; numerical shading runs in a worker.
module SuPvSceneSnapshot
  def self.panel?(entity)
    entity.is_a?(Sketchup::ComponentInstance) && entity.get_attribute('SuPvPanelTool','model_id')
  end
  def self.shading_excluded?(entity)
    return true if entity.respond_to?(:get_attribute) && entity.get_attribute('SuPvMounting','exclude_from_shading',false)
    entity.respond_to?(:definition) && entity.definition.get_attribute('SuPvMounting','exclude_from_shading',false)
  end
  def self.children(entity)
    return entity.definition.entities if entity.is_a?(Sketchup::ComponentInstance)
    entity.respond_to?(:entities) ? entity.entities : nil
  end
  def self.key(path); path.map(&:persistent_id).join('/'); end
  def self.visible?(model,path)
    return false if path.any? { |e| e.respond_to?(:hidden?) && e.hidden? || e.respond_to?(:layer) && !e.layer.visible? }
    path.each do |e|
      folder=e.respond_to?(:layer) && e.layer.respond_to?(:folder) ? e.layer.folder : nil
      while folder
        return false unless folder.visible?
        folder=folder.folder
      end
    end
    # SU <=2025 raises when this API's last element is a group/instance.
    return true if children(path.last)
    !model.respond_to?(:drawing_element_visible?) || model.drawing_element_visible?(Sketchup::InstancePath.new(path))
  end
  def self.record(entity,transform,path)
    {'model_id'=>entity.get_attribute('SuPvPanelTool','model_id'),
     'origin_mm'=>transform.origin.to_a.map(&:to_mm),
     'axes'=>[transform.xaxis,transform.yaxis,transform.zaxis].map(&:to_a), 'key'=>key(path)}
  end
  def self.panels_in(path)
    result=[]
    parent=path[0...-1].inject(Geom::Transformation.new) { |t,e| t*e.transformation }
    walk=lambda do |entity,tr,ancestors|
      next unless entity.valid?
      full=ancestors+[entity]
      tr=tr*entity.transformation
      if panel?(entity)
        result << record(entity,tr,full)
      elsif (entities=children(entity))
        entities.each { |child| walk.call(child,tr,full) if panel?(child) || children(child) }
      end
    end
    walk.call(path.last,parent,path[0...-1])
    result
  end
  def self.attach(plan,model,origin_mm,excluded=[])
    triangles=[]; panels=[]; excluded=excluded.to_h { |key| [key,true] }
    walk=lambda do |entities,tr,path|
      entities.each do |entity|
        next if shading_excluded?(entity)
        next unless entity.is_a?(Sketchup::Face) || children(entity)
        next unless entity.valid? && visible?(model,path+[entity])
        full=path+[entity]
        if panel?(entity)
          panels << record(entity,tr*entity.transformation,full) unless excluded[key(full)]
        elsif (nested=children(entity))
          walk.call(nested,tr*entity.transformation,full)
        elsif entity.is_a?(Sketchup::Face)
          mesh=entity.mesh(0)
          mesh.polygons.each do |indices|
            points=indices.map { |i| mesh.point_at(i.abs).transform(tr).to_a.map(&:to_mm).zip(origin_mm).map { |a,b| a-b } }
            (1...points.length-1).each { |i| triangles << [points[0],points[i],points[i+1]] }
          end
        end
      end
    end
    walk.call(model.entities,Geom::Transformation.new,[])
    plan['environment']=triangles
    plan['occluder_panels']=panels.map do |panel|
      spec=SuPvPanelTool.panel_spec(panel['model_id'])
      panel.merge('origin'=>panel['origin_mm'].zip(origin_mm).map { |a,b| a-b },'spec'=>spec)
    end
    plan
  end
end
