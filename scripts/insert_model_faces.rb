# encoding: UTF-8
# 任务二 / 方法一：记录标准模型的面数据，再通过 add_face 逐面重建。
# load 'D:/Administrator Files/SEU/12.Project/260911_SU PV plugin/project/scripts/insert_model_faces.rb'
# 在原模型中执行 SuPvFaces.capture；在空白模型中执行 SuPvFaces.insert。
# 标准模型：../data/model.skp；标准面数据：../data/standard_faces.json。
require 'json'

module SuPvFaces
  def self.source_path
    File.expand_path('../data/model.skp', __dir__)
  end

  # 插入使用提取快照；源文件重新保存后，必须先重新提取。
  def self.check_snapshot!
    raise '请先在 data/model.skp 中执行 SuPvFaces.capture，更新标准面数据。' unless File.file?(data_path)
    if File.file?(source_path) && File.mtime(source_path) > File.mtime(data_path)
      raise 'data/model.skp 比标准面数据新。请在该模型中执行 SuPvFaces.capture，再使用按钮1插入。'
    end
  end

  # 脚本在 scripts，标准面数据在 data。
  def self.data_path
    File.expand_path('../data/standard_faces.json', __dir__)
  end

  # 第一步：只读原模型，把坐标、内外轮廓、面积和分类存成 JSON。
  def self.capture
    model = Sketchup.active_model
    raise '请先退出组件编辑，回到模型最外层。' if model.active_path
    source = source_path
    unless File.expand_path(model.path).casecmp(File.expand_path(source)).zero?
      raise '请先打开项目 data/model.skp，再记录标准面数据。'
    end

    records = []
    bounds = Geom::BoundingBox.new
    walk = lambda do |entities, transform, inherited_tag, name, depth|
      raise '组件嵌套超过 30 层，请检查模型结构。' if depth > 30
      entities.each do |entity|
        tag = entity.layer == model.layers[0] ? inherited_tag : entity.layer.name
        case entity
        when Sketchup::Face
          next unless ['roof', 'wall', 'fence'].include?(tag)
          loop_points = lambda do |loop|
            loop.vertices.map do |vertex|
              point = vertex.position.transform(transform)
              bounds.add(point)
              point.to_a.map(&:to_f)
            end
          end
          records << {
            'tag' => tag,
            'name' => name,
            'outer' => loop_points.call(entity.outer_loop),
            'holes' => entity.loops.reject(&:outer?).map { |loop| loop_points.call(loop) },
            # 该方向仅用来判断重建面的正反侧，不当作缩放后的精确单位法向。
            'front_hint' => entity.normal.transform(transform).to_a,
            'area_in2' => entity.area(transform)
          }
        when Sketchup::Group, Sketchup::ComponentInstance
          child_name = entity.name.empty? ? entity.definition.name : entity.name
          walk.call(entity.definition.entities, transform * entity.transformation,
                    tag, child_name, depth + 1)
        end
      end
    end
    walk.call(model.entities, Geom::Transformation.new, model.layers[0].name, '', 0)
    raise '没有找到 roof / wall / fence 分类下的面。' if records.empty?

    data = {
      'version' => 1, 'units' => 'inch', 'source' => model.path,
      'anchor' => bounds.min.to_a.map(&:to_f), 'faces' => records
    }
    File.write(data_path, JSON.pretty_generate(data), encoding: 'UTF-8')
    puts "已记录 #{records.length} 个面，孔洞共 #{records.sum { |r| r['holes'].length }} 个。"
    records.group_by { |r| r['tag'] }.each do |tag, rows|
      puts "  #{tag}: #{rows.length} 个面"
    end
    puts "插入基准点（原模型坐标，m）：#{bounds.min.to_a.map { |v| v.to_m.round(3) }.inspect}"
    puts "数据文件：#{data_path}"
    puts '标准面数据已更新（读取的是当前画面，包括尚未保存的修改；未保存 SKP）。'
    puts '下一步：切换到目标模型，使用按钮1，或执行 SuPvFaces.insert。源模型若再次保存，请重新 capture。'
    true
  end

  # 第二步：只读取 JSON，不读取 .skp；在新定义里一个个画面。
  def self.insert
    check_snapshot!
    model = Sketchup.active_model
    raise '请先退出组件编辑，回到模型最外层。' if model.active_path
    data = JSON.parse(File.read(data_path, encoding: 'UTF-8'))
    unless data['version'] == 1 && data['units'] == 'inch' && !data.fetch('faces').empty?
      raise '面数据版本或单位不正确，请重新记录。'
    end
    anchor = Geom::Point3d.new(data.fetch('anchor'))
    local_points = lambda do |points|
      points.map do |xyz|
        point = Geom::Point3d.new(xyz)
        [point.x - anchor.x, point.y - anchor.y, point.z - anchor.z]
      end
    end

    model.start_operation('逐面重建标准变电站', true)
    begin
      station = model.definitions.add('PV_标准变电站_逐面生成')
      data.fetch('faces').each_with_index do |record, index|
        label = "#{record.fetch('tag')}_#{index + 1}"
        definition = model.definitions.add(label)
        entities = definition.entities
        outer = entities.add_face(local_points.call(record.fetch('outer')))
        raise "#{label} 外轮廓建面失败。" unless outer

        # 先填入内轮廓，再删掉内面，保留孔洞边界。
        record.fetch('holes').each do |hole|
          inner = entities.add_face(local_points.call(hole))
          raise "#{label} 孔洞建面失败。" unless inner && inner != outer
          inner.erase!
        end

        faces = entities.grep(Sketchup::Face)
        raise "#{label} 重建后不止一个面。" unless faces.length == 1
        face = faces.first
        unless face.loops.length == record.fetch('holes').length + 1
          raise "#{label} 孔洞数量不一致。"
        end
        expected_area = record.fetch('area_in2')
        if (face.area - expected_area).abs > [expected_area * 1.0e-6, 0.001].max
          raise "#{label} 重建面积不一致，已取消本次生成。"
        end
        hint = Geom::Vector3d.new(record.fetch('front_hint'))
        face.reverse! if face.normal.dot(hint) < 0

        # 分类放在组件外壳，内部原始边面保持 Untagged。
        entities.each { |entity| entity.layer = model.layers[0] }
        instance = station.entities.add_instance(definition, Geom::Transformation.new)
        instance.name = record['name'].to_s.empty? ? label : record['name']
        instance.layer = model.layers[record['tag']] || model.layers.add(record['tag'])
      end
      raise '生成的模型为空。' if station.entities.length.zero?
      model.commit_operation
    rescue StandardError
      model.abort_operation
      raise
    end

    # 使用 SketchUp 原生组件放置工具，提供跟随鼠标的真实模型预览。
    model.place_component(station, false)
    puts "已逐面重建 #{data['faces'].length} 个面；在视图区点击一次插入，Esc 取消。"
    true
  end
end

puts '面生成脚本已加载。原模型：SuPvFaces.capture；空白模型：SuPvFaces.insert'
