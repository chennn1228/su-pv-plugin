# encoding: UTF-8
require 'json'
require 'securerandom'
load File.expand_path('cad_export.rb',__dir__)
module SuPvFigureExport
  def self.write_pair(files)
    token=SecureRandom.hex(8);staged={};backups={};installed=[]
    begin
      files.each do |file,body|
        temp="#{file}.#{token}.tmp";staged[file]=temp;File.binwrite(temp,body)
      end
      files.each_key do |file|
        if File.exist?(file)
          backup="#{file}.#{token}.bak";File.rename(file,backup);backups[file]=backup
        end
        File.rename(staged.fetch(file),file);installed<<file
      end
    rescue StandardError
      installed.each { |file| File.delete(file) if File.exist?(file) }
      backups.each { |file,backup| File.rename(backup,file) }
      raise
    ensure
      staged.each_value { |temp| File.delete(temp) if File.exist?(temp) }
    end
    backups.each_value { |backup| File.delete(backup) }
  end
  def self.save(body:, filename:'pv_horizontal_plan.svg')
    raise '图片数据过大。' unless body.is_a?(String) && body.bytesize<=32*1024*1024
    raise 'SVG内容无效。' unless body.start_with?('<svg ') && body.end_with?('</svg>')
    tags=body.scan(/<\/?([A-Za-z][\w:-]*)/).flatten
    raise 'SVG含有不支持的内容。' unless (tags-%w[svg g polygon polyline path line rect circle text tspan title desc]).empty? && !body.match?(/\bon\w+\s*=|href\s*=|<!|<\?/i)
    cad=SuPvCadExport.from_svg(body)
    file=UI.savepanel('导出 SVG + DXF',File.expand_path('../../output',__dir__),filename)
    if file
      extension=File.extname(file).downcase
      stem=%w[.svg .dxf].include?(extension) ? file[0...-4] : file
      svg="#{stem}.svg";dxf="#{stem}.dxf"
      companion=extension=='.dxf' ? svg : dxf
      if File.exist?(companion)
        return {cancelled:true} unless UI.messagebox("同名#{File.extname(companion).upcase.delete('.')}文件已存在，是否同时覆盖？",MB_YESNO)==IDYES
      end
      write_pair(svg=>body,dxf=>cad)
    end
    {cancelled:!file}
  end
  def self.bind(dialog,current:,filename:'pv_horizontal_plan.svg',validate:nil)
    dialog.add_action_callback('export_figure') do |_context,payload|
      next unless current.call
      begin
        validate.call if validate
        data=JSON.parse(payload)
        type=data.fetch('format')
        raise '仅支持SVG矢量图。' unless type=='svg'
        result=save(body:data.fetch('body'),filename:filename)
      rescue StandardError => error
        result={error:error.message}
      end
      dialog.execute_script("window.PV.exported(#{JSON.generate(result)});") if current.call
    end
  end
end
