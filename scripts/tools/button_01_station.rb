# encoding: UTF-8
# 按钮1：进入标准变电站逐面插入工具。几何实现保留在实验脚本中。
require 'sketchup.rb'

module SuPvStationTool
  def self.activate
    require_relative '../insert_model_faces'
    SuPvFaces.insert
  rescue StandardError => error
    UI.messagebox(error.message)
    false
  end
end
