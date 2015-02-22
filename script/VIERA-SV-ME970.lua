----------------------------------------------------------------------
--
--  Panasonic ビエラ・ワンセグ SV-ME970 用スクリプト
--
--
--  このスクリプトを使用するには、libfaac.dll が必要です。
--  http://oss.netfarm.it/mplayer-win32.php などからダウンロードして、BMS.exe と
--  同じフォルダに配置してください。
--
--  使用方法などについて
--  http://code.google.com/p/beer-media-server2/wiki/SVME970
--  を必ず参照してください。
--
----------------------------------------------------------------------


----------------------------------------------------------------------
-- この機種がサポートしているメディア情報のリスト
----------------------------------------------------------------------
BMS.SUPPORT_MEDIA_LIST = {
  "image/jpeg:*",
  "audio/mpeg:*",
  "audio/x-ms-wma:*",
  "video/mp4:*",
  "video/x-ms-wmv:*",
}


----------------------------------------------------------------------
-- BMS.GetPlayInfo 関数
--   メディアファイルの再生方法の情報を返す。
--   引数：
--     fname: ファイル名
--     minfo: MediaInfo.dll などから得られた情報
--   戻り値：
--     1: MimeType または トランスコード情報テーブル
--     2: 表示用文字列（省略でファイル名そのまま）
--     3: ソート用文字列（省略でファイル名そのまま）
----------------------------------------------------------------------
function BMS.GetPlayInfo(fname, minfo)
  
  local ext = string.lower(string.match(fname, "%.([^.]*)$") or "")

  if ext == "m3u" or ext == "m3u8" then
    -- m3u ファイルをフォルダとして取り扱うよう指示
    return "M3U_FOLDER", GetFileBaseName(fname)
  end

  -- 注１
  if minfo.General.Format == "" then return "image/jpeg:*" end
  
  if minfo.General.Format == "NowRecording" then
    -- 注１
    return "image/jpeg:*", "* " .. fileu.ExtractFileName(fname)
  end

  if ext == "jpg" then
    return "image/jpeg:*;"
     .."DLNA.ORG_FLAGS=8cf00000000000000000000000000000"
  end

  if ext == "mp3" then
    return "audio/mpeg:DLNA.ORG_PN=MP3;"
     .."DLNA.ORG_FLAGS=8d700000000000000000000000000000"
  end
  
  if ext == "wma" then
    return "audio/x-ms-wma:*;"
     .."DLNA.ORG_FLAGS=8d700000000000000000000000000000"
  end
  
  -- 注１
  if minfo.Video.Format == "" then return "image/jpeg:*" end
  
  if minfo.General.Format == "MPEG-4" and
   (string.sub(minfo.Video.Format_Profile, 1, 8) == "Baseline" or
    string.sub(minfo.Video.Format_Profile, 1, 6) == "Simple" or
    string.sub(minfo.Video.Format_Profile, 1, 15) == "Advanced Simple") then
    return "video/mp4:*;"
     .."DLNA.ORG_FLAGS=8d700000000000000000000000000000;"
     .."DLNA.ORG_OP=11;DLNA.ORG_CI=0"
  end

  if minfo.General.Format == "Windows Media" then
    return "video/x-ms-wmv:*;"
     .."DLNA.ORG_FLAGS=8d700000000000000000000000000000;"
     .."DLNA.ORG_OP=11;DLNA.ORG_CI=0"
  end


  ---------------- 以下、トランスコード

  if minfo.General.Format == "ISO DVD" then return _dvd(fname, minfo) end

  local bitrate = "1000"
  local preset = "fast" -- なお、この機種では slow 品質が上限っぽい

  local aspect = minfo.Video.DisplayAspectRatio
  local w = minfo.Video.Width
  local h = minfo.Video.Height
  if aspect == "" then aspect = "1.333" end
  --print("\r\nDEBUG: "..fname.." aspect="..aspect.."\r\n")

  local vfs0 = "scale=720:404"
  if aspect == "1.333" then
    vfs0 = "scale=640:480"
  end

  local vfs_ffmpeg = vfs0 .. ",setdar=16:9"
  local vfs_mencorder = vfs0
  if minfo.ScanType == "Interlaced" then
    vfs_ffmpeg = vfs_ffmpeg .. ",yadif=0:-1"
    --vfs_ffmpeg = vfs_ffmpeg .. ",yadif=3,mp=pp=l5,framestep=2"
    vfs_mencorder = vfs_mencorder .. ",pp=l5"
    --vfs_mencorder = vfs_mencorder .. ",yadif=3,pp=l5,framestep=2"
  end
  vfs_mencorder = vfs_mencorder .. ",harddup"

  local t = {}
  t[1] = {}
  t[1].mime = "video/mp4:*;"
   .."DLNA.ORG_FLAGS=8d700000000000000000000000000000;"
   .."DLNA.ORG_OP=11;DLNA.ORG_CI=0"
  
  local id = ""
  if tonumber(minfo.General.VideoCount) > 1 then
    if minfo.Video.ID and minfo.Video.ID ~= "" then
      -- 多重チャンネルの TS ファイルに対処。一番長い映像が主映像となる。
      id = "-vid "..minfo.Video.ID
    end
    if minfo.Audio.ID and minfo.Audio.ID ~= "" then
      -- 多重音声の TS ファイルに対処。一番若いIDの音声を主音声とする。
      id = id.." -aid "..minfo.Audio.ID
    end
    --[[ 2番目の音声を選択する例
      id = id.." -aid "..minfo["Audio(2);ID"]
    ]]
  end

  t[1].name = fileu.ExtractFileName(fname).." >mp4"
  t[1].excmd = "KEEP"
  t[1].command = [[
   mencoder "$_in_$" -o "$_out_$" ]]..id..[[
   $_cmd_quiet_mencoder_$ $_cmd_seek_mencoder_$
   -vf ]]..vfs_mencorder..[[ -of lavf -lavfopts format=mp4 -ovc x264
   -x264encopts bitrate=]]..bitrate..[[:threads=auto:profile=baseline:preset=]]..preset..[[:level_idc=30:global_header
   -oac faac -faacopts mpeg=4:object=2:raw:br=128 -channels 2
  ]]

--[===[ pipe 処理のTEST
  t[1].command = {}
  t[1].command[1] = [[
   ffmpeg $_cmd_quiet_ffmpeg_$ $_cmd_seek_ffmpeg_$ -i "$_in_$"
   -f avi -vcodec copy -an -y -
  ]]
  t[1].command[2] = [[
   ffmpeg $_cmd_quiet_ffmpeg_$ -f avi -i - -f avi -vcodec copy -an -y -
  ]]
  t[1].command[3] = [[
   ffmpeg $_cmd_quiet_ffmpeg_$ -f avi -i - -f avi -vcodec copy -an -y -
  ]]
  t[1].command[4] = [[
   ffmpeg $_cmd_quiet_ffmpeg_$ -f avi -i - -f avi -vcodec copy -an -y -
  ]]
  t[1].command[5] = [[
   ffmpeg $_cmd_quiet_ffmpeg_$ -f avi -i - $_cmd_seek_ffmpeg_$ -i "$_in_$"
   -acodec copy -f mp4 -vcodec libx264 -level 30 -r 30000/1001 -aspect 16:9
   -vsync 1 -async 1
   -threads 0 -profile:v baseline -preset fast -absf aac_adtstoasc
   -b:v 1000k -s 704x396 -map 0:v:0 -map 1:a:0 -y "$_out_$"
  ]]
--]===]

  t[2] = {}
  t[2].mime = t[1].mime
  t[2].name = "トランスコファイルの消去"
  t[2].excmd = "CLEAR"

  return t, "/ "..fileu.ExtractFileName(fname)
end


----------------------------------------------------------------------
function _dvd(fname, minfo)
  local bitrate = "1000"
  local preset = "fast" -- なお、この機種では slow 品質が上限っぽい

  local DVD_title = minfo.DVD["title"..minfo.DVD.longest_title]
  local aspect = DVD_title.aspect
  local w = DVD_title.width
  local h = DVD_title.height
  if aspect == "" then aspect = "1.333" end

  local vfs0 = "scale=720:404"
  if aspect == "1.333" then
    vfs0 = "scale=640:480"
  end

  local vfs_ffmpeg = vfs0 .. ",setdar=16:9"
  local vfs_mencorder = vfs0

  -- インタレ解除
  vfs_ffmpeg = vfs_ffmpeg .. ",yadif=0:-1"
  --vfs_ffmpeg = vfs_ffmpeg .. ",yadif=3,mp=pp=l5,framestep=2"
  vfs_mencorder = vfs_mencorder .. ",pp=l5"
  --vfs_mencorder = vfs_mencorder .. ",yadif=3,pp=l5,framestep=2"

  vfs_mencorder = vfs_mencorder .. ",harddup"

  local t = {}
  t[1] = {}
  t[1].mime = "video/mp4:*;"
   .."DLNA.ORG_FLAGS=8d700000000000000000000000000000;"
   .."DLNA.ORG_OP=11;DLNA.ORG_CI=0"
  
  if DVD_title.lang_a.en and DVD_title.lang_s.ja then

    -- 英語音声と日本語字幕がある場合

    t[1].name = GetFileBaseName(fname).." (英語音声・日本語字幕)"
    t[1].duration = DVD_title.length_s
    t[1].excmd = "KEEP"
    t[1].command = [[
     mencoder -dvd-device "$_in_$" dvd://]]..minfo.DVD.longest_title..[[
     -o "$_out_$" $_cmd_quiet_mencoder_$ $_cmd_seek_mencoder_$
     -alang en -slang ja
     -vf ]]..vfs_mencorder..[[ -of lavf -lavfopts format=mp4 -ovc x264
     -x264encopts bitrate=]]..bitrate..[[:threads=auto:profile=baseline:preset=]]..preset..[[:level_idc=30:global_header
     -oac faac -faacopts mpeg=4:object=2:raw:br=128 -channels 2
    ]]

    t[2] = {}
    t[2].mime = t[1].mime
    t[2].name = GetFileBaseName(fname).." (日本語音声)"
    t[2].duration = DVD_title.length_s
    t[2].excmd = "KEEP"
    t[2].command = [[
     mencoder -dvd-device "$_in_$" dvd://]]..minfo.DVD.longest_title..[[
     -o "$_out_$" $_cmd_quiet_mencoder_$ $_cmd_seek_mencoder_$
     -alang ja -slang ja -forcedsubsonly
     -vf ]]..vfs_mencorder..[[ -of lavf -lavfopts format=mp4 -ovc x264
     -x264encopts bitrate=]]..bitrate..[[:threads=auto:profile=baseline:preset=]]..preset..[[:level_idc=30:global_header
     -oac faac -faacopts mpeg=4:object=2:raw:br=128 -channels 2
    ]]

    t[3] = {}
    t[3].mime = t[1].mime
    t[3].name = GetFileBaseName(fname).." (英語音声)"
    t[3].duration = DVD_title.length_s
    t[3].excmd = "KEEP"
    t[3].command = [[
     mencoder -dvd-device "$_in_$" dvd://]]..minfo.DVD.longest_title..[[
     -o "$_out_$" $_cmd_quiet_mencoder_$ $_cmd_seek_mencoder_$
     -alang en -slang en -forcedsubsonly
     -vf ]]..vfs_mencorder..[[ -of lavf -lavfopts format=mp4 -ovc x264
     -x264encopts bitrate=]]..bitrate..[[:threads=auto:profile=baseline:preset=]]..preset..[[:level_idc=30:global_header
     -oac faac -faacopts mpeg=4:object=2:raw:br=128 -channels 2
    ]]

    t[4] = {}
    t[4].mime = t[1].mime
    t[4].name = "トランスコファイルの消去"
    t[4].excmd = "CLEAR"

    return t, "/ "..fileu.ExtractFileName(fname)

  else

    t[1].name = GetFileBaseName(fname)
    t[1].duration = DVD_title.length_s
    t[1].excmd = "KEEP"
    t[1].command = [[
     mencoder -dvd-device "$_in_$" dvd://]]..minfo.DVD.longest_title..[[
     -o "$_out_$" $_cmd_quiet_mencoder_$ $_cmd_seek_mencoder_$
     -forcedsubsonly
     -vf ]]..vfs_mencorder..[[ -of lavf -lavfopts format=mp4 -ovc x264
     -x264encopts bitrate=]]..bitrate..[[:threads=auto:profile=baseline:preset=]]..preset..[[:level_idc=30:global_header
     -oac faac -faacopts mpeg=4:object=2:raw:br=128 -channels 2
    ]]

    t[2] = {}
    t[2].mime = t[1].mime
    t[2].name = "トランスコファイルの消去"
    t[2].excmd = "CLEAR"

    return t, "/ "..fileu.ExtractFileName(fname)
  end
end
