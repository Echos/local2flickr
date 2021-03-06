#! /opt/local/bin/ruby
# -*- coding: utf-8 -*-

require 'rubygems'
require 'optparse'
#require 'mechanize'
require 'httpclient'
require 'pit'
require 'ostruct'
require 'digest/md5'
require 'nokogiri'
require 'find'
require 'logger'

@agent = nil

@l = Logger.new(STDOUT)
@l.level = Logger::DEBUG

#コマンドラインオプション
def checkoption
  opt = OptionParser.new
  #オプション情報保持用
  options = OpenStruct.new
  begin
    #コマンドラインオプション定義
    opt.on('-h','--help','USAGEを表示。')   {|v| puts opt.help;exit }
    opt.on('-f FILE', '--file=FILE' ,'アップロードするファイル')    {|v| options.file = v }
    opt.on('-P PHOTOSET', '--photoset=PHOTOSET' ,'登録するフォトセット名称')    {|v| options.photoset = v }
    opt.on('-t TITLE', '--title=TITLE', 'ファイルのタイトル。') {|v| options.title = v}
    opt.on('-d DESCRIPTION', '--DESCRIPTION=DESCRIPTION', 'ファイルの説明') {|v| options.description = v}
    opt.on('-T  TAGS','--tags=TAGS', Array, "登録するタグ（複数可能） (カンマ区切り)") {|v| options.tags = v}
    opt.on('-p','--is-private', 'プライベート設定')                 {|v| options.private =v}
    opt.on('--friend', '--friends', '友達参照可')      { |v| options.friend = v }
    opt.on('--family', '家族参照可')                   { |v| options.family = v }
    opt.on('--delete', 'アップロードに成功したファイルを削除する')                   { |v| options.delete = v }
    opt.on('--dir=DIR', '指定したディレクトリ配下の画像ファイルをまとめて処理する')                   { |v| options.dir = v }
    #オプションのパース
    opt.parse!(ARGV)

    if(options.file==nil && options.dir==nil)
      puts opt.help
      exit
    end

    return options
  rescue
    #指定外のオプションが存在する場合はUsageを表示
    puts opt.help
    exit
  end
end

#アカウントの設定(LDR)
def account_flickr
  #http://www.flickr.com/services/api/misc.api_keys.html から取得
  return Pit::get('flickr', :require => {
                         'api_key' => 'your api_key of flickr',
                         'secret' => 'your secret of flickr',
                       })
end

#api_sigを取得する
def get_api_sig(params,secret)
  org_sig = secret + params.sort.join;
  return Digest::MD5.hexdigest(org_sig)
end

#frobを取得（トークン未取得時のみ）
def getfrob(ac_f)
  ep = 'https://api.flickr.com/services/rest/'
  params = Hash.new
  params["method"] = "flickr.auth.getFrob"
  params["api_key"] = ac_f["api_key"]
  params["api_sig"] = get_api_sig(params,ac_f["secret"])

#  agent = HTTPClient.new
  page = @agent.post_content(ep,params)
  doc = Nokogiri(page)
  return doc.at("frob").inner_text
end

#認証を実行する(トークン未取得時のみ)
#※ブラウザアクセスがあります
def auth(ac_f,frob)
  ep = 'https://www.flickr.com/services/auth/'
  params = Hash.new
  params["api_key"] = ac_f["api_key"]
  params["perms"]   = "delete"
  params["frob"]    = frob
  params["api_sig"] = get_api_sig(params,ac_f["secret"])

  puts "#{ep}?api_key=#{params['api_key']}&perms=#{params['perms']}&frob=#{params['frob']}&api_sig=#{params['api_sig']} にアクセスして、認証してください。"
  puts "ブラウザが自動で起動します。"
  puts "認証を完了したらエンターを押してください。続けてトークン情報の取得を実施します。"
  system("open '#{ep}?api_key=#{params['api_key']}&perms=#{params['perms']}&frob=#{params['frob']}&api_sig=#{params['api_sig']}'")
  STDIN.gets
end

#トークン取得（認証時１度きり実行）
def gettoken(ac_f,frob)
  ep = 'http://flickr.com/services/rest/'
  params = Hash.new
  params["method"] = "flickr.auth.getToken"
  params["api_key"] = ac_f["api_key"]
  params["frob"]    = frob
  params["api_sig"] = get_api_sig(params,ac_f["secret"])
#  agent = HTTPClient.new
  page = @agent.post_content(ep,params)
  doc = Nokogiri(page)
  begin
    return doc.at("token").inner_text
  rescue
    puts "トークンの取得に失敗しました。"
    exit
  end
end

#upload api
#指定した写真をアップロードする
def upload(ac_f,opts)

  ep = 'https://up.flickr.com/services/upload/'

  filelist = Array.new
  photoids = Array.new

  #指定したファイルが存在するか確認
  if(opts.file)
    (puts "#{opts.file} はファイルではありません。";exit) if ! test ?r, opts.file
    filelist << opts.file
  end

  #ディレクトリからファイル一覧を取得する
  if(opts.dir)
    Find.find(opts.dir) do |f|
      if( /(\.mpg$)|(\.MPG$)|(\.psd$)|(\.PSG$)|(\.3gp$)|(\.3g2$)|(\.3G2$)|(\.3GP$)|(\.avi$)|(\.AVI$)|(\.mp4$)|(\.MP4$)|(\.mov$)|(\.MOV$)|(\.jpeg$)|(\.JPEG$)|(\.jpg$)|(\.JPG$)|(\.gif$)|(\.GIF$)|(\.bmp$)|(\.BPM$)|(\.png$)|(\.PNG$)/ =~ f)
      #if( /(\.mpg$)|(\.MPG$)|(\.psd$)|(\.PSG$)|(\.3gp$)|(\.3g2$)|(\.3G2$)|(\.3GP$)|(\.avi$)|(\.AVI$)|(\.mp4$)|(\.MP4$)|(\.jpeg$)|(\.JPEG$)|(\.jpg$)|(\.JPG$)|(\.gif$)|(\.GIF$)|(\.bmp$)|(\.BPM$)|(\.png$)|(\.PNG$)/ =~ f)
        filelist << f
        @l.debug "#{f}を追加"
      end
    end
  end
  begin
    count = 0
    filelist.each do |f|
      count += 1
      file = File.new(f)
      params = Hash.new
      params["title"] = opts.title if opts.title
      params["description"] = ops.description if opts.description
      params["tags"] = opts.tags.join(" ") if opts.tags
      params["tags"] = "" if !(opts.tags)

      #ファイルぱパスからタグを生成
      path_info = f.split("/")[0..-2]
      params["tags"] = params["tags"] + " " +path_info.join(" ").gsub(".","")
      puts ("タグは#{params['tags']}です")

      params["is_public"] = 0 if opts.private
      params["is_friend"] = 1 if opts.friend
      params["is_family"] = 1 if opts.family
      params["api_key"] = ac_f['api_key']
      params["auth_token"] = ac_f['token']
      params["api_sig"] = get_api_sig(params,ac_f["secret"])
      params["photo"] = file
      #    agent = HTTPClient.new
      puts ("#{f}をポストします(#{count}/#{filelist.length})")
      page = @agent.post_content(ep,params)
      puts ("#{f}をポスト完了")
      doc = Nokogiri(page)
      #puts page
      #puts doc.at(:rsp)[:stat]
      if (doc.at(:rsp)[:stat] == 'ok')
        if(opts.delete)
          puts "#{file.path}を削除します"
          file.close
          File.delete(f)
        end
        puts "#{file.path}をPhotoID:#{doc.at("photoid").inner_text}で登録しました。"
        photoids << doc.at("photoid").inner_text
      end
    end
rescue => err
    @l.error err
end
  return photoids
end

#自分のユーザIDを取得する
def getuserid(ac_f)
  ep = 'https://api.flickr.com/services/rest/'
  params = Hash.new
  params["method"] = "flickr.auth.checkToken"
  params["api_key"] = ac_f['api_key']
  params["auth_token"] = ac_f['token']
  params["api_sig"] = get_api_sig(params,ac_f["secret"])

#  agent = HTTPClient.new
  page = @agent.post_content(ep,params)
  doc = Nokogiri(page)
  return  (doc/:user)[0]['nsid']
end

#フォトセットリストを取得する。
def getphotosetlist(ac_f,userid)
  ep = 'https://api.flickr.com/services/rest/'
  params = Hash.new
  params["method"] = "flickr.photosets.getList"
  params["api_key"] = ac_f['api_key']
  params["user_id"] = userid
  params["auth_token"] = ac_f['token']
  params["api_sig"] = get_api_sig(params,ac_f["secret"])

#  agent = HTTPClient.new
  page = @agent.post_content(ep,params)
  doc = Nokogiri(page)
  hash = Hash.new
  (doc/:photoset).each do |elem|
    hash[(elem.at(:title)).inner_text]= elem[:id]
  end
  return hash
end

#フォトセットを作成する。
def makephotoset(ac_f,opts,photoid)
  puts "フォトセットを新規作成します。[PhotoID:#{photoid},PhotoSetName:#{opts.photoset}]"
  ep = 'https://api.flickr.com/services/rest/'
  params = Hash.new
  params["method"] = "flickr.photosets.create"
  params["title"] = opts.photoset
  params["primary_photo_id"] = photoid
  params["api_key"] = ac_f['api_key']
  params["auth_token"] = ac_f['token']
  params["api_sig"] = get_api_sig(params,ac_f["secret"])

#  agent = HTTPClient.new
  page = @agent.post_content(ep,params)
  # photoSetID
  doc = Nokogiri(page)
  #puts doc.at(:rsp)[:stat]
  if (doc.at(:rsp)[:stat] == 'ok')
    photosetid = doc.at(:photoset)[:id]
    puts "フォトセットを新規作成しました。[PhotoSetID:#{photosetid}]"
    return photosetid
  else
    puts "フォトセットの作成に失敗しました。終了します。"
    exit 1
  end
end

#フォトセットに写真を追加する。
def addphotoset(ac_f,opts,photoids,photosetid)
  ep = 'https://api.flickr.com/services/rest/'
  puts "フォトセット登録中:PhotoSetID:#{photosetid}"
  puts "フォトセット登録中:PhotoIDs:#{photoids.join(',')}"
  photoids.each do |id|
    params = Hash.new
    params["method"] = "flickr.photosets.addPhoto"
    params["photoset_id"] = photosetid
    params["photo_id"] = id
    params["api_key"] = ac_f['api_key']
    params["auth_token"] = ac_f['token']
    params["api_sig"] = get_api_sig(params,ac_f["secret"])

#    agent = HTTPClient.new
    page = @agent.post_content(ep,params)
  end
end

@l.info 'HTTPクライアントの作成'
@agent = HTTPClient.new
@agent.send_timeout = 12000
@agent.receive_timeout = 12000

ac_f = account_flickr
if (ac_f["token"]==nil)
  puts "トークン情報が存在しないため、認証処理を実施します。"
  frob = getfrob(ac_f)
  auth(ac_f,frob)
  token = gettoken(ac_f,frob)
  puts "トークンは#{token}です。"
  ac_f["token"]=token
  Pit.set("flickr",:data => ac_f)
end

@l.info "オプションチェック"
opts=checkoption

#画像をPostしてフォトIDを取得
@l.info 'ポスト開始'
photoids=upload(ac_f,opts)

userid=getuserid(ac_f)
("ユーザIDが存在取得できなかったため、終了します";exit) if userid == nil # !> unused literal ignored

#フォトセット一覧を取得
photosetlist = getphotosetlist(ac_f,userid)

puts "######################################################"
puts "再実行用情報1:フォトセットリスト：#{photoids.join(',')}"
puts "再実行用情報2:フォトセット名称  ：#{opts.photoset}"
puts "######################################################"

#フォトセットの指定があるか？
begin
if (opts.photoset!=nil)
  #フォトセットがすでに有る場合、IDを利用し登録。
  #無ければ新規作成して、Postしたファイルをプライマリにする
  if( photosetlist.has_key? opts.photoset)
    puts "既存のフォトセットに登録します。"
    photosetid = photosetlist[opts.photoset]
    addphotoset(ac_f,opts,photoids,photosetid)
  else
    puts "新規のフォトセットに登録します。"
    photosetid = makephotoset(ac_f,opts,photoids[0])
    addphotoset(ac_f,opts,photoids[1..-1],photosetid)
  end
end
rescue => error
puts error
end
