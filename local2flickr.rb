#! /opt/local/bin/ruby
# -*- coding: utf-8 -*-

require 'rubygems'
require 'optparse'
require 'mechanize'
require 'pit'
require 'ostruct'
require 'digest/md5'
require 'rexml/document'
require 'hpricot'
require 'find'

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

#frobを取得（トークン見取得時のみ）
def getfrob(ac_f)
  ep = 'http://flickr.com/services/rest/'
  params = Hash.new
  params["method"] = "flickr.auth.getFrob"
  params["api_key"] = ac_f["api_key"]
  params["api_sig"] = get_api_sig(params,ac_f["secret"])

  agent = Mechanize.new
  page = agent.post(ep,params)
  doc = Hpricot(page.body)
  return doc.at("frob").inner_text
end

#認証を実行する(トークン見取得時のみ)
#※ブラウザアクセスがあります
def auth(ac_f,frob)
  ep = 'http://www.flickr.com/services/auth/'
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
  agent = Mechanize.new
  page = agent.post(ep,params)
  doc = Hpricot(page.body)
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
  
  ep = 'http://api.flickr.com/services/upload/'

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
      if( /(\.jpg$)|(\.jpeg$)|(\.gif$)|(\.bmp$)|(\.png$)/ =~ f)
        filelist << f
      end
    end
  end
  
  
  filelist.each do |f|
    file = File.new(f)
    params = Hash.new
    params["title"] = opts.title if opts.title
    params["description"] = ops.description if opts.description
    params["tags"] = opts.tags.join(" ") if opts.tags
    params["is_public"] = 0 if opts.private
    params["is_friend"] = 1 if opts.friend
    params["is_family"] = 1 if opts.family
    params["api_key"] = ac_f['api_key']
    params["auth_token"] = ac_f['token']
    params["api_sig"] = get_api_sig(params,ac_f["secret"])
    params["photo"] = file
    agent = Mechanize.new
    page = agent.post(ep,params)
    doc = Hpricot(page.body)
    if (doc.at(:rsp)[:stat] == 'ok')
      puts "#{file.path}をFlickrに登録しました。"
      if(opts.delete)
        puts "#{file.path}を削除します"
        file.close
        File.delete(f)
      end
      photoids << doc.at("photoid").inner_text
    end
  end
  return photoids
end
  
#自分のユーザIDを取得する
def getuserid(ac_f)
  ep = 'http://flickr.com/services/rest/'
  params = Hash.new
  params["method"] = "flickr.auth.checkToken"
  params["api_key"] = ac_f['api_key']
  params["auth_token"] = ac_f['token']
  params["api_sig"] = get_api_sig(params,ac_f["secret"])

  agent = Mechanize.new
  page = agent.post(ep,params)
  doc = Hpricot(page.body)
  return  (doc/:user)[0]['nsid']
end

#フォトセットリストを取得する。
def getphotosetlist(ac_f,userid)
  ep = 'http://flickr.com/services/rest/'
  params = Hash.new
  params["method"] = "flickr.photosets.getList"
  params["api_key"] = ac_f['api_key']
  params["user_id"] = userid
  params["auth_token"] = ac_f['token']
  params["api_sig"] = get_api_sig(params,ac_f["secret"])

  agent = Mechanize.new
  page = agent.post(ep,params)
  doc = Hpricot(page.body)
  hash = Hash.new
  (doc/:photoset).each do |elem|
    hash[(elem.at(:title)).inner_text]= elem[:id]
  end
  return hash
end

#フォトセットを作成する。
def makephotoset(ac_f,opts,photoid)
  ep = 'http://flickr.com/services/rest/'
  params = Hash.new
  params["method"] = "flickr.photosets.create"
  params["title"] = opts.photoset
  params["primary_photo_id"] = photoid
  params["api_key"] = ac_f['api_key']
  params["auth_token"] = ac_f['token']
  params["api_sig"] = get_api_sig(params,ac_f["secret"])

  agent = Mechanize.new
  page = agent.post(ep,params)
end

#フォトセットに写真を追加する。
def addphotoset(ac_f,opts,photoids,photosetid)
  ep = 'http://flickr.com/services/rest/'
  photoids.each do |id|
    params = Hash.new
    params["method"] = "flickr.photosets.addPhoto"
    params["photoset_id"] = photosetid
    params["photo_id"] = id
    params["api_key"] = ac_f['api_key']
    params["auth_token"] = ac_f['token']
    params["api_sig"] = get_api_sig(params,ac_f["secret"])
    
    agent = Mechanize.new
    page = agent.post(ep,params)
  end
end


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

opts=checkoption

#画像をPostしてフォトIDを取得
photoids=upload(ac_f,opts)

userid=getuserid(ac_f)
("ユーザIDが存在取得できなかったため、終了します";exit) if userid == nil

#フォトセット一覧を取得
photosetlist = getphotosetlist(ac_f,userid)

#フォトセットの指定があるか？
if (opts.photoset!=nil)
  #フォトセットがすでに有る場合、IDを利用し登録。
  #無ければ新規作成して、Postしたファイルをプライマリにする
  if( photosetlist.has_key? opts.photoset)
    photosetid = photosetlist[opts.photoset]
    addphotoset(ac_f,opts,photoids,photosetid)
  else
    makephotoset(ac_f,opts,photoid[0])
    addphotoset(ac_f,opts,photoids[1..-1],photosetid)
  end
end
