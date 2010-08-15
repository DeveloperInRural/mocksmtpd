#!/usr/bin/env ruby
$:.unshift File.dirname(__FILE__) # for test/development

require 'optparse'
require 'pathname'
require 'erb'
require 'nkf'
require "time"
require "cgi"
require 'yaml'

TEMPLATE_DIR = Pathname.new(File.dirname(__FILE__)) + "templates"

include ERB::Util

def load_templates
  result = {}
  result[:index] = template("index")
  result[:index_entry] = template("index_entry")
  return result
end

def template(name)
  path = TEMPLATE_DIR + "#{name}.erb"
  src = path.read
  return ERB.new(src, nil, "%-")
end

def load_conf
  @conf_file = Pathname.new(@conf_file || "./mocksmtpd.conf")
  unless @conf_file.exist? && @conf_file.readable?
    opterror "Can't load config file: #{@conf_file}"
    exit 1
  end
  @conf_file = @conf_file.realpath
  
  @conf = {}
  YAML.load_file(@conf_file).each do |k,v|
    @conf[k.intern] = v
  end
  
  @inbox = resolve_conf_path(@conf[:InboxDir])
end

def resolve_conf_path(path)
  result = nil
  if path[0] == ?/
    result = Pathname.new(path)
  else
    result = @conf_file.parent + path
  end
  return result.cleanpath
end

# 削除するファイルを取得
qs = CGI.new
deleteFile = qs["delete_file"]

# テンプレートの取得
@templates = load_templates

# テンプレートを文字列として取得
htmlsrc = @templates[:index].result(binding)

# リスト部分の生成
add = "";

# index.html以外のすべてのHTMLを取得
load_conf
Dir::glob("#{@inbox}/*.html").sort.each{|f|
  if(File.basename(f) != "index.html")
    print File.basename(f)
    print deleteFile
    if(File.basename(f) == deleteFile)
      # 削除が指定されていた場合は削除
      File.delete(f)
    else
      # 文字列としてすべてを取得
      mailSrc = File.read(f)
      
      # 文字コード変換とHTMLタグの除去
      mailSrc = NKF.nkf("-wm", mailSrc)
      mailSrc = mailSrc.gsub(/<\/?[^>]*>/, "")
      
      # 送信者
      sender = mailSrc.match(/^From:\s*(.+)/i).to_a[1].to_s.strip
      
      # 受信者
      recipientString = mailSrc.match(/^To:\s*(.+)/i).to_a[1].to_s.strip
      
      # 表題
      subject = mailSrc.match(/^Subject:\s*(.+)/i).to_a[1].to_s.strip
      
      # 送信日
      date = mailSrc.match(/^Date:\s*(.+)/i).to_a[1].to_s.strip
      if date.empty?
        date = "*no date*"
      else
        date = Time.parse(date).strftime("%Y-%m-%d %H:%M:%S")
      end
      
      # 配列に格納
      mail = {
        :sender => sender,
        :recipientString => recipientString,
        :filePath => "inbox/" + File.basename(f),
        :fileBase => File.basename(f),
        :subject => subject,
        :date => date,
      }
      
      # 一件分のHTMLを生成
      add += @templates[:index_entry].result(binding)
    end
  end
}

# テンプレートの特定の部分に追加
htmlsrc.sub!(/<!-- ADD -->/, add)

# 書き出し
print "Content-Type: text/html\n\n";
print htmlsrc