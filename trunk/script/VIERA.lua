----------------------------------------------------------------------
--
--  Panasonic ビエラ 用スクリプト
--
--
--  Signal Flag "Z" 様 (http://signal-flag-z.blogspot.jp/) が公開して
--  下さっている VIERA GT3用スクリプトを参考に作成しました。
--
--  プライベート・ビエラ SV-ME7000で動作確認しました。
--  ・この機種では MPEG-TS/PS の再生において
--     TimeSeekRange（DLNA.ORG_OP=10）を用いると、うまく早送り等でき
--    ませんでした。そのため Range Header（DLNA.ORG_OP=01）を指定して
--    います。他のビエラでは TimeSeekRange でも問題ないかもしれません。
--    トランスコすると TimeSeekRange でも問題ないので、ファイルをきち
--    んと時間単位でカットしていないことが原因なのかもしれません。
--  ・「注１」という部分は、同機種がリスト内の総ファイル数の動的な変
--    更に対応していない感じのため、そのファイルを非表示とせずに再生
--    不可能なファイルとして扱う処理をしているものです。他のビエラで
--    は return ""（そのファイルを表示しない） でも問題ないかもしれま
--    せん。
--
----------------------------------------------------------------------


----------------------------------------------------------------------
-- この機種がサポートしているメディア情報のリスト
----------------------------------------------------------------------
BMS.SUPPORT_MEDIA_LIST = {
 "video/mpeg:DLNA.ORG_PN=MPEG_PS_NTSC;DLNA.ORG_FLAGS=8d100000000000000000000000000000",
 "video/mpeg:DLNA.ORG_PN=MPEG_PS_NTSC_XAC3;DLNA.ORG_FLAGS=8d100000000000000000000000000000",
 "video/vnd.dlna.mpeg-tts:DLNA.ORG_PN=MPEG_TS_JP_T;DLNA.ORG_FLAGS=8d100000000000000000000000000000",
 "video/vnd.dlna.mpeg-tts:DLNA.ORG_PN=MPEG_TS_SD_JP_MPEG1_L2_T;DLNA.ORG_FLAGS=8d100000000000000000000000000000",
 "video/vnd.dlna.mpeg-tts:DLNA.ORG_PN=AVC_TS_JP_AAC_T;DLNA.ORG_FLAGS=8d100000000000000000000000000000",
 "video/vnd.dlna.mpeg-tts:DLNA.ORG_PN=MPEG_TS_SD_NA_T;DLNA.ORG_FLAGS=8d100000000000000000000000000000",
 "video/vnd.dlna.mpeg-tts:DLNA.ORG_PN=MPEG_TS_SD_NA;DLNA.ORG_FLAGS=8d100000000000000000000000000000",
 "video/mpeg:DLNA.ORG_PN=MPEG_TS_SD_NA_ISO;DLNA.ORG_FLAGS=8d100000000000000000000000000000",
 "image/jpeg:DLNA.ORG_PN=JPEG_SM;DLNA.ORG_FLAGS=8c900000000000000000000000000000",
 "image/jpeg:DLNA.ORG_PN=JPEG_MED;DLNA.ORG_FLAGS=8c900000000000000000000000000000",
 "image/jpeg:DLNA.ORG_PN=JPEG_LRG;DLNA.ORG_FLAGS=8c900000000000000000000000000000",
 "image/jpeg:DLNA.ORG_PN=JPEG_TN;DLNA.ORG_FLAGS=8c900000000000000000000000000000",
 "image/jpeg:DLNA.ORG_PN=JPEG_SM_ICO;DLNA.ORG_FLAGS=8c900000000000000000000000000000",
 "image/jpeg:DLNA.ORG_PN=JPEG_LRG_ICO;DLNA.ORG_FLAGS=8c900000000000000000000000000000",
 "video/mp4:*",
 "video/quicktime:*",
 "image/jpeg:*",
 "video/vnd.dlna.mpeg-tts:*",
 "video/mpeg:*"
}


----------------------------------------------------------------------
local MimeTypes = {
  JPEG =
   "image/jpeg:*",
  MPEG_TS =
   "video/vnd.dlna.mpeg-tts:DLNA.ORG_PN=MPEG_TS_JP_T;"..
   "DLNA.ORG_FLAGS=8d100000000000000000000000000000;"..
   "DLNA.ORG_OP=01;DLNA.ORG_CI=0",
  MPEG_PS =
   "video/mpeg:DLNA.ORG_PN=MPEG_PS_NTSC;"..
   "DLNA.ORG_FLAGS=8d100000000000000000000000000000;"..
   "DLNA.ORG_OP=01;DLNA.ORG_CI=0",
  TRANSCODE =
   "video/mpeg:DLNA.ORG_PN=MPEG_PS_NTSC;"..
   "DLNA.ORG_FLAGS=8d100000000000000000000000000000;"..
   "DLNA.ORG_OP=10;DLNA.ORG_CI=0",
  DUMMY =
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
  if minfo.General.Format == "" then return MimeTypes["DUMMY"] end
  
  if minfo.General.Format == "NowRecording" then
    -- 注１
    return MimeTypes["DUMMY"], "* " .. fileu.ExtractFileName(fname)
  end

  if ext == "jpg" then
    return MimeTypes["JPEG"]
  end

  -- 注１
  if minfo.Video.Format == "" then return MimeTypes["DUMMY"] end
  
  if minfo.Video.Format == "MPEG Video" then
    if minfo.General.Format == "MPEG-TS" then
      return MimeTypes["MPEG_TS"]
    elseif minfo.General.Format =="MPEG-PS" then
      return MimeTypes["MPEG_PS"]
    end
  end


  ---------------- 以下、トランスコード

  if minfo.General.Format == "ISO DVD" then return _dvd(fname, minfo) end
  
  local t, t2 = {}, {}

  local aspect = minfo.Video.DisplayAspectRatio
  local w = minfo.Video.Width
  local h = minfo.Video.Height
  if aspect == "" then aspect = "1.333" end
  --print("\r\nDEBUG: ", fname, " aspect=", aspect, "\r\n")

  -- とりあえずブラビアと同じ処理。
  -- mpeg2 のサイズとアスペクト比を固定にする。
  w = "720" h = "480"
  local vfs_ffmpeg = "scale="..w..":"..h
  local vfs_mencorder = "scale="..w..":"..h
  if aspect ~= "1.778" then
    local sw = w
    local sh = h
    if tonumber(aspect) < 1.778 then
      sw = math.floor(w / 1.778 * aspect + 0.5)
    else
      sh = math.floor(h * 1.778 / aspect + 0.5)
    end
    vfs_ffmpeg = "scale="..sw..":"..sh..",pad="..w..":"..h..":"
     ..math.floor(math.abs(sw-w)/2)..":"..math.floor(math.abs(sh-h)/2)
    vfs_mencorder = "scale="..sw..":"..sh..",expand="..w..":"..h
    aspect = "1.778"
  end

  vfs_ffmpeg = vfs_ffmpeg .. ",setdar=16:9"
  if minfo.ScanType == "Interlaced" then
    -- インタレ解除
    vfs_ffmpeg = vfs_ffmpeg .. ",yadif=0:-1"
    --vfs_ffmpeg = vfs_ffmpeg .. ",yadif=3,mp=pp=l5,framestep=2"
    vfs_mencorder = vfs_mencorder .. ",pp=l5"
    --vfs_mencorder = vfs_mencorder .. ",yadif=3,pp=l5,framestep=2"
  end
  vfs_mencorder = vfs_mencorder .. ",harddup,fixpts"  -- fixpts を指定しないと音ずれが発生することがある

  t2.mime = MimeTypes["TRANSCODE"]
  t.mime = t2.mime
  t.name = fileu.ExtractFileName(fname).." >MPEG-PS"

  t.command = [[
   mencoder "$_in_$" -o "$_out_$"
   $_cmd_quiet_mencoder_$ $_cmd_seek_mencoder_$
   -oac lavc -ovc lavc -of mpeg -mpegopts format=dvd:tsaf
   -vf ]]..vfs_mencorder..[[ -srate 48000 -af lavcresample=48000
   -ofps 30000/1001 -channels 6
   -lavcopts vcodec=mpeg2video:vrc_buf_size=1835:vrc_maxrate=9800:vbitrate=5000:keyint=18:vstrict=0:acodec=ac3:abitrate=192:aspect=]]
   ..aspect

--[===[ ffmpeg の使用例
  t.command = [[
   ffmpeg $_cmd_quiet_ffmpeg_$ $_cmd_seek_ffmpeg_$ -i "$_in_$" -target ntsc-dvd -b:v 5000k
   -acodec ac3 -ar 48000 -vcodec mpeg2video
   -vf ]]..vfs_ffmpeg..[[ -r 30000/1001 -b:a 192000 -ac 6 "$_out_$"
  ]]
--]===]

--[===[ pipe 処理のTEST
    t.command = {}
    t.command[1] = [[
     ffmpeg $_cmd_quiet_ffmpeg_$ $_cmd_seek_ffmpeg_$ -i "$_in_$"
     -vcodec copy -acodec copy -f mpegts -vbsf h264_mp4toannexb -
    ]]
    t.command[2] = [[
     ffmpeg $_cmd_quiet_ffmpeg_$ -f avi -i - -f avi -vcodec copy -an -y -
    ]]
    t.command[3] = [[
     ffmpeg $_cmd_quiet_ffmpeg_$ -f avi -i - -f avi -vcodec copy -an -y -
    ]]
    t.command[4] = [[
     ffmpeg $_cmd_quiet_ffmpeg_$ -f avi -i - -f avi -vcodec copy -an -y -
    ]]
    t.command[5] = [[
     ffmpeg $_cmd_quiet_ffmpeg_$ -f avi -i - -i "$_in_$"
     -acodec copy -f mp4 -vcodec libx264 -level 30 -r 30000/1001 -aspect 16:9
     -vsync 1 -async 1
     -threads 0 -profile:v baseline -preset fast -absf aac_adtstoasc
     -b:v 1000k -s 704x396 -map 0:v:0 -map 1:a:0 -y "$_out_$"
    ]]
--]===]

  if BMS.ShowTranscodeFolder then t2 = {t} else t2 = t end
  return t2, "/ "..fileu.ExtractFileName(fname)

end


----------------------------------------------------------------------
function _dvd(fname, minfo)
  local t, t2 = {}, {}
  local DVD_title = minfo.DVD["title"..minfo.DVD.longest_title]
  local aspect = DVD_title.aspect
  local w = DVD_title.width
  local h = DVD_title.height
  if aspect == "" then aspect = "1.333" end

  -- とりあえずブラビアと同じ処理。
  -- mpeg2 のサイズとアスペクト比を固定にする。
  w = "720" h = "480"
  local vfs_ffmpeg = "scale="..w..":"..h
  local vfs_mencorder = "scale="..w..":"..h
  if aspect ~= "1.778" then
    local sw = w
    local sh = h
    if tonumber(aspect) < 1.778 then
      sw = math.floor(w / 1.778 * aspect + 0.5)
    else
      sh = math.floor(h * 1.778 / aspect + 0.5)
    end
    vfs_ffmpeg = "scale="..sw..":"..sh..",pad="..w..":"..h..":"
     ..math.floor(math.abs(sw-w)/2)..":"..math.floor(math.abs(sh-h)/2)
    vfs_mencorder = "scale="..sw..":"..sh..",expand="..w..":"..h
    aspect = "1.778"
  end

  vfs_ffmpeg = vfs_ffmpeg .. ",setdar=16:9"

  -- インタレ解除
  vfs_ffmpeg = vfs_ffmpeg .. ",yadif=0:-1"
  --vfs_ffmpeg = vfs_ffmpeg .. ",yadif=3,mp=pp=l5,framestep=2"
  vfs_mencorder = vfs_mencorder .. ",pp=l5"
  --vfs_mencorder = vfs_mencorder .. ",yadif=3,pp=l5,framestep=2"

  vfs_mencorder = vfs_mencorder .. ",harddup,fixpts"  -- fixpts を指定しないと音ずれが発生することがある

  t2.mime = MimeTypes["TRANSCODE"]

  --[[ mencoder でテレシネかどうかをチェックする
  if minfo.user.telecine == "" then
    if string.find(fileu.GetCmdStdOut("mencoder.exe", 
     '-dvd-device "'..fname..'" dvd://'..minfo.DVD.longest_title
     .." -quiet -msglevel all=4 -endpos 1 -ovc raw -nosound -o nul"), 
     "24000/1001fps progressive NTSC content detected", 1, true) then
      minfo.user.telecine = "1"  -- minfo.user は独自の情報を保存しておくのに便利です
    else
      minfo.user.telecine = "0"
    end
  end
  if minfo.user.telecine == "1" then
    vfs_mencorder = "pullup,softskip," .. vfs_mencorder -- 逆テレシネの指定。
  end
  --]]
  
  if DVD_title.lang_a.en and DVD_title.lang_s.ja then

    -- 英語音声と日本語字幕がある場合

    t[1] = {}
    t[1].mime = t2.mime
    t[1].name = GetFileBaseName(fname).." (英語音声・日本語字幕)"
    t[1].duration = DVD_title.length_s
    t[1].command = [[
     mencoder -dvd-device "$_in_$" dvd://]]..minfo.DVD.longest_title..[[
     $_cmd_quiet_mencoder_$ $_cmd_seek_mencoder_$
     -o "$_out_$" -oac lavc -ovc lavc -of mpeg -mpegopts format=dvd:tsaf
     -vf ]]..vfs_mencorder..[[ -srate 48000 -af lavcresample=48000
     -ofps 30000/1001 -alang en -slang ja -channels 6
     -lavcopts vcodec=mpeg2video:vrc_buf_size=1835:vrc_maxrate=9800:vbitrate=5000:keyint=18:vstrict=0:acodec=ac3:abitrate=192:aspect=]]
     ..aspect

    t[2] = {}
    t[2].mime = t2.mime
    t[2].name = GetFileBaseName(fname).." (日本語音声)"
    t[2].duration = DVD_title.length_s
    t[2].command = [[
     mencoder -dvd-device "$_in_$" dvd://]]..minfo.DVD.longest_title..[[
     $_cmd_quiet_mencoder_$ $_cmd_seek_mencoder_$
     -o "$_out_$" -oac lavc -ovc lavc -of mpeg -mpegopts format=dvd:tsaf
     -vf ]]..vfs_mencorder..[[ -srate 48000 -af lavcresample=48000
     -ofps 30000/1001 -alang ja -slang ja -forcedsubsonly -channels 6
     -lavcopts vcodec=mpeg2video:vrc_buf_size=1835:vrc_maxrate=9800:vbitrate=5000:keyint=18:vstrict=0:acodec=ac3:abitrate=192:aspect=]]
     ..aspect
       
    t[3] = {}
    t[3].mime = t2.mime
    t[3].name = GetFileBaseName(fname).." (英語音声)"
    t[3].duration = DVD_title.length_s
    t[3].command = [[
     mencoder -dvd-device "$_in_$" dvd://]]..minfo.DVD.longest_title..[[
     $_cmd_quiet_mencoder_$ $_cmd_seek_mencoder_$
     -o "$_out_$" -oac lavc -ovc lavc -of mpeg -mpegopts format=dvd:tsaf
     -vf ]]..vfs_mencorder..[[ -srate 48000 -af lavcresample=48000
     -ofps 30000/1001 -alang en -slang en -forcedsubsonly -channels 6
     -lavcopts vcodec=mpeg2video:vrc_buf_size=1835:vrc_maxrate=9800:vbitrate=5000:keyint=18:vstrict=0:acodec=ac3:abitrate=192:aspect=]]
     ..aspect

    return t, "/ "..fileu.ExtractFileName(fname)

  else

    t.mime = t2.mime
    t.name = GetFileBaseName(fname)
    t.duration = DVD_title.length_s
    t.command = [[
     mencoder -dvd-device "$_in_$" dvd://]]..minfo.DVD.longest_title..[[
     $_cmd_quiet_mencoder_$ $_cmd_seek_mencoder_$
     -o "$_out_$" -oac lavc -ovc lavc -of mpeg -mpegopts format=dvd:tsaf
     -vf ]]..vfs_mencorder..[[ -srate 48000 -af lavcresample=48000
     -ofps 30000/1001 -forcedsubsonly -channels 6
     -lavcopts vcodec=mpeg2video:vrc_buf_size=1835:vrc_maxrate=9800:vbitrate=5000:keyint=18:vstrict=0:acodec=ac3:abitrate=192:aspect=]]
     ..aspect

    if BMS.ShowTranscodeFolder then t2 = {t} else t2 = t end
    return t2, "/ "..fileu.ExtractFileName(fname)

  end
end


