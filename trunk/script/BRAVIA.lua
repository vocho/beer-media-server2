----------------------------------------------------------------------
--
--  Bravia 用スクリプト
--
----------------------------------------------------------------------


----------------------------------------------------------------------
-- H264 を Mpeg TS にトランスコード(Remux)する場合は true にしてください。
-- H264 も通常のトランスコードでよい場合は false にしてください。
--（trueにする場合は ffmpeg.exe を bms.exe と同じフォルダに配置しておく
--  必要があります）
----------------------------------------------------------------------
H264ToMpegTS = false


----------------------------------------------------------------------
-- この機種がサポートしているメディア情報のリスト
----------------------------------------------------------------------
BMS.SUPPORT_MEDIA_LIST = {
  "image/jpeg:DLNA.ORG_PN=JPEG_LRG",
  "image/jpeg:DLNA.ORG_PN=JPEG_MED",
  "image/jpeg:DLNA.ORG_PN=JPEG_SM",
  "audio/L16:DLNA.ORG_PN=LPCM",
  "audio/mpeg:DLNA.ORG_PN=MP3",
  "audio/x-ms-wma:DLNA.ORG_PN=WMABASE",
  "audio/x-ms-wma:DLNA.ORG_PN=WMAFULL",
  "video/vnd.dlna.mpeg-tts:DLNA.ORG_PN=AVC_TS_HD_60_AC3_T;SONY.COM_PN=AVC_TS_HD_60_AC3_T",
  "video/vnd.dlna.mpeg-tts:DLNA.ORG_PN=AVC_TS_HD_50_AC3_T;SONY.COM_PN=AVC_TS_HD_50_AC3_T",
  "video/vnd.dlna.mpeg-tts:DLNA.ORG_PN=AVC_TS_HD_60_AC3;SONY.COM_PN=AVC_TS_HD_60_AC3",
  "video/vnd.dlna.mpeg-tts:DLNA.ORG_PN=AVC_TS_HD_50_AC3;SONY.COM_PN=AVC_TS_HD_50_AC3",
  "video/mpeg:DLNA.ORG_PN=AVC_TS_HD_60_AC3_ISO;SONY.COM_PN=AVC_TS_HD_60_AC3_ISO",
  "video/mpeg:DLNA.ORG_PN=AVC_TS_HD_50_AC3_ISO;SONY.COM_PN=AVC_TS_HD_50_AC3_ISO",
  "video/vnd.dlna.mpeg-tts:DLNA.ORG_PN=AVC_TS_HD_EU_T",
  "video/vnd.dlna.mpeg-tts:DLNA.ORG_PN=AVC_TS_HD_EU",
  "video/mpeg:DLNA.ORG_PN=AVC_TS_HD_EU_ISO",
  "video/vnd.dlna.mpeg-tts:DLNA.ORG_PN=MPEG_TS_HD_NA_T",
  "video/vnd.dlna.mpeg-tts:DLNA.ORG_PN=MPEG_TS_HD_KO_T",
  "video/vnd.dlna.mpeg-tts:DLNA.ORG_PN=MPEG_TS_HD_NA",
  "video/vnd.dlna.mpeg-tts:DLNA.ORG_PN=MPEG_TS_HD_KO",
  "video/mpeg:DLNA.ORG_PN=MPEG_TS_HD_NA_ISO",
  "video/mpeg:DLNA.ORG_PN=MPEG_TS_HD_KO_ISO",
  "video/vnd.dlna.mpeg-tts:DLNA.ORG_PN=MPEG_TS_JP_T",
  "video/vnd.dlna.mpeg-tts:DLNA.ORG_PN=MPEG_TS_HD_NA_MPEG1_L2_T",
  "video/vnd.dlna.mpeg-tts:DLNA.ORG_PN=MPEG_TS_HD_60_L2_T;SONY.COM_PN=HD2_60_T",
  "video/vnd.dlna.mpeg-tts:DLNA.ORG_PN=MPEG_TS_HD_50_L2_T;SONY.COM_PN=HD2_50_T",
  "video/mpeg:DLNA.ORG_PN=MPEG_TS_HD_NA_MPEG1_L2_ISO",
  "video/mpeg:DLNA.ORG_PN=MPEG_TS_HD_60_L2_ISO;SONY.COM_PN=HD2_60_ISO",
  "video/mpeg:DLNA.ORG_PN=MPEG_TS_HD_50_L2_ISO;SONY.COM_PN=HD2_50_ISO",
  "video/vnd.dlna.mpeg-tts:DLNA.ORG_PN=MPEG_TS_SD_60_AC3_T",
  "video/vnd.dlna.mpeg-tts:DLNA.ORG_PN=MPEG_TS_SD_50_AC3_T",
  "video/vnd.dlna.mpeg-tts:DLNA.ORG_PN=MPEG_TS_SD_NA_T",
  "video/vnd.dlna.mpeg-tts:DLNA.ORG_PN=MPEG_TS_SD_KO_T",
  "video/vnd.dlna.mpeg-tts:DLNA.ORG_PN=MPEG_TS_SD_NA",
  "video/vnd.dlna.mpeg-tts:DLNA.ORG_PN=MPEG_TS_SD_KO",
  "video/mpeg:DLNA.ORG_PN=MPEG_TS_SD_NA_ISO",
  "video/mpeg:DLNA.ORG_PN=MPEG_TS_SD_KO_ISO",
  "video/vnd.dlna.mpeg-tts:DLNA.ORG_PN=MPEG_TS_SD_EU_T",
  "video/vnd.dlna.mpeg-tts:DLNA.ORG_PN=MPEG_TS_SD_EU",
  "video/mpeg:DLNA.ORG_PN=MPEG_TS_SD_EU_ISO",
  "video/vnd.dlna.mpeg-tts:DLNA.ORG_PN=MPEG_TS_SD_JP_MPEG1_L2_T",
  "video/vnd.dlna.mpeg-tts:DLNA.ORG_PN=MPEG_TS_SD_NA_MPEG1_L2_T",
  "video/vnd.dlna.mpeg-tts:DLNA.ORG_PN=MPEG_TS_SD_60_L2_T",
  "video/vnd.dlna.mpeg-tts:DLNA.ORG_PN=MPEG_TS_SD_50_L2_T",
  "video/mpeg:DLNA.ORG_PN=MPEG_TS_SD_NA_MPEG1_L2_ISO",
  "video/mpeg:DLNA.ORG_PN=MPEG_PS_NTSC",
  "video/mpeg:DLNA.ORG_PN=MPEG_PS_PAL",
  "video/mpeg:DLNA.ORG_PN=MPEG1",
  "video/x-ms-wmv:DLNA.ORG_PN=WMVMED_BASE",
  "video/x-ms-wmv:DLNA.ORG_PN=WMVMED_FULL",
  "video/x-ms-wmv:DLNA.ORG_PN=WMVHIGH_FULL",
  "video/x-ms-wmv:DLNA.ORG_PN=WMVSPLL_BASE",
  "video/x-ms-wmv:DLNA.ORG_PN=WMVSPML_BASE",
  "video/x-ms-asf:DLNA.ORG_PN=VC1_ASF_AP_L1_WMA",
  "video/x-ms-asf:DLNA.ORG_PN=VC1_ASF_AP_L2_WMA",
  "video/vnd.dlna.mpeg-tts:DLNA.ORG_PN=AVC_TS_HD_24_AC3_T;SONY.COM_PN=AVC_TS_HD_24_AC3_T",
  "video/vnd.dlna.mpeg-tts:DLNA.ORG_PN=AVC_TS_HD_24_AC3;SONY.COM_PN=AVC_TS_HD_24_AC3",
  "video/mpeg:DLNA.ORG_PN=AVC_TS_HD_24_AC3_ISO;SONY.COM_PN=AVC_TS_HD_24_AC3_ISO",
  "video/vnd.dlna.mpeg-tts:DLNA.ORG_PN=AVC_TS_JP_AAC_T",
  "video/x-mp2t-mphl-188:*",
  "image/jpeg:*",
  "audio/mpeg:*",
  "audio/L16:*",
  "audio/x-ms-wma:*",
  "video/mpeg:*",
  "video/vnd.dlna.mpeg-tts:*",
  "video/mp4:*",
  "video/x-ms-wmv:*",
  "video/x-ms-asf:*"
}


local BRAVIA_KDL_JP11 = OrdSet({
 --2012年モデル
 "HX950", "HX850", "HX750", "EX750", "EX550", "EX540",
 --2011年モデル
 "HX920", "HX820", "HX720", "NX720", "EX72S", "EX720", "EX420", "CX400"
})

local MyBravia = 1
local AVCHD_OK = false
local MPEG4_OK = false


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

  --print("\r\nDEBUG: "..BMS.ClientInfo.ext.."\r\n")
  if string.sub(BMS.ClientInfo.ext, 1, 6) == "BRAVIA" then
    local s = string.match(BMS.ClientInfo.ext, "BRAVIA KDL%-%d+(%w+)")
    if s and BRAVIA_KDL_JP11[s] then
      -- MPEG4 対応ブラビア
      AVCHD_OK = true
      MPEG4_OK = true
      MyBravia = 11
    -- regexpr.matches 関数では Java の正規表現をほぼそのまま使えます。
    elseif regexpr.matches(BMS.ClientInfo.ext, "BRAVIA KDL-[0-9]{2}(F5|W5|ZX5|[EHNLC]X[0-9]{2}[0SR])") then
      -- AVCHD 対応ブラビア
      AVCHD_OK = true
      MyBravia = 5
    -- elseif regexpr.matches(BMS.ClientInfo.ext, "BRAVIA KDL-[0-9]{2}([A-Z]{1,2}1|J5|V5)") then
    -- MyBravia = 1
    end
  end

  --[[
  if regexpr.matches(BMS.ClientInfo.ext, "Sony KDL-[0-9]{2}[JXWV][357][0-9]{3}") then
    -- Sony Bravia 3000/5000/7000 Series
    MyBravia = 0
  end]]

  local ext = string.lower(string.match(fname, "%.([^.]*)$") or "")

  if ext == "m3u" or ext == "m3u8" then
    -- m3u ファイルをフォルダとして取り扱うよう指示
    return "M3U_FOLDER", GetFileBaseName(fname)
  end

  if minfo.General.Format == "" then return "" end
  
  if minfo.General.Format == "NowRecording" then
    -- 録画中のファイルは MPEG-TS と仮定する。
    return "video/mpeg:"
     .."DLNA.ORG_PN=MPEG_TS_HD_60_L2_ISO;"
     .."SONY.COM_PN=HD2_60_ISO;"
     .."DLNA.ORG_FLAGS=8d700000000000000000000000000000;"
     .."DLNA.ORG_OP=11;DLNA.ORG_CI=0",
     "* "..fileu.ExtractFileName(fname)  -- 表示用文字列
  end

  if ext == "jpg" then
    return "image/jpeg:DLNA.ORG_PN=JPEG_LRG;"
     .."DLNA.ORG_FLAGS=8cf00000000000000000000000000000"
  end

  if ext == "mp3" then
    return "audio/mpeg:DLNA.ORG_PN=MP3;"
     .."DLNA.ORG_FLAGS=8d700000000000000000000000000000"
  end
  
  if ext == "wav" then
    return "audio/L16:DLNA.ORG_PN=LPCM;"
     .."DLNA.ORG_FLAGS=8d700000000000000000000000000000"
  end
  
  if minfo.Video.Format == "" then return "" end
  
  local res = "video/x-mp2t-mphl-188:*;DLNA.ORG_OP=11;DLNA.ORG_CI=0"
  local fr = string.sub(minfo.Video.FrameRate, 1, 2)

  if MPEG4_OK and minfo.General.Format == "MPEG-4" then
    return "video/mp4:*;"
     .."DLNA.ORG_FLAGS=8d700000000000000000000000000000;"
     .."DLNA.ORG_OP=11;DLNA.ORG_CI=0"
  end

  if minfo.Video.Format == "MPEG Video" or
   (AVCHD_OK and minfo.Video.Format == "AVC") then
    if minfo.General.Format == "BDAV" then
      -- NTSC?
      if fr == "29" or fr == "59" or minfo.Video.Standard == "NTSC" then
        res = "video/vnd.dlna.mpeg-tts:"
         .."DLNA.ORG_PN=MPEG_TS_JP_T;"
         .."DLNA.ORG_FLAGS=8d700000000000000000000000000000;"
         .."DLNA.ORG_OP=11;DLNA.ORG_CI=0"

        -- AVCHD?
        if minfo.Video.Format == "AVC" then
          if minfo.Audio.Format == "AC-3" then
            res = "video/vnd.dlna.mpeg-tts:"
             .."DLNA.ORG_PN=AVC_TS_HD_60_AC3_T;"
             .."SONY.COM_PN=AVC_TS_HD_60_AC3_T;"
             .."DLNA.ORG_FLAGS=8d700000000000000000000000000000;"
             .."DLNA.ORG_OP=11;DLNA.ORG_CI=0"
          elseif minfo.Audio.Format == "AAC" then
            res = "video/vnd.dlna.mpeg-tts:"
             .."DLNA.ORG_PN=AVC_TS_JP_AAC_T;"
             .."DLNA.ORG_FLAGS=8d700000000000000000000000000000;"
             .."DLNA.ORG_OP=11;DLNA.ORG_CI=0"
          end
        else
          -- HD?
          if tonumber(minfo.Video.Width) > 1000 then
            -- AAC etc.
            res = "video/vnd.dlna.mpeg-tts:"
             .."DLNA.ORG_PN=MPEG_TS_HD_60_L2_T;"
             .."SONY.COM_PN=HD2_60_T;"
             .."DLNA.ORG_FLAGS=8d700000000000000000000000000000;"
             .."DLNA.ORG_OP=11;DLNA.ORG_CI=0"
          else
            -- AC3?
            if minfo.Audio.Format == "AC-3" then
              res = "video/vnd.dlna.mpeg-tts:"
               .."DLNA.ORG_PN=MPEG_TS_SD_60_AC3_T;"
               .."DLNA.ORG_FLAGS=8d700000000000000000000000000000;"
               .."DLNA.ORG_OP=11;DLNA.ORG_CI=0"
            else
              -- AAC etc.
              res = "video/vnd.dlna.mpeg-tts:"
               .."DLNA.ORG_PN=MPEG_TS_SD_60_L2_T;"
               .."DLNA.ORG_FLAGS=8d700000000000000000000000000000;"
               .."DLNA.ORG_OP=11;DLNA.ORG_CI=0"
            end
          end
        end
      
      -- 24p(not PAL)?
      elseif fr ~= "25" and fr ~= "50" then
        res = "video/vnd.dlna.mpeg-tts:"
         .."DLNA.ORG_PN=AVC_TS_HD_24_AC3_T;"
         .."SONY.COM_PN=AVC_TS_HD_24_AC3_T;"
         .."DLNA.ORG_FLAGS=8d700000000000000000000000000000;"
         .."DLNA.ORG_OP=11;DLNA.ORG_CI=0"
      end
      
      return res

    elseif minfo.General.Format == "MPEG-TS" then
      -- NTSC?
      if fr == "29" or fr == "59" or minfo.Video.Standard == "NTSC" then
        -- AVCHD?
        if minfo.Video.Format == "AVC" --[[and minfo.Audio.Format == "AC-3"]] then
          -- [[
          res = "video/mpeg:"
           .."DLNA.ORG_PN=AVC_TS_HD_60_AC3_ISO;"
           .."SONY.COM_PN=AVC_TS_HD_60_AC3_ISO;"
           .."DLNA.ORG_FLAGS=8d700000000000000000000000000000;"
           .."DLNA.ORG_OP=11;DLNA.ORG_CI=0"
          -- ]]
          --[[ これも同じ？
          res = "video/vnd.dlna.mpeg-tts:"
           .."DLNA.ORG_PN=AVC_TS_HD_60_AC3;"
           .."SONY.COM_PN=AVC_TS_HD_60_AC3;"
           .."DLNA.ORG_FLAGS=8d700000000000000000000000000000;"
           .."DLNA.ORG_OP=11;DLNA.ORG_CI=0"
          -- ]]
        else
          res = "video/mpeg:"
           .."DLNA.ORG_PN=MPEG_TS_HD_60_L2_ISO;"
           .."SONY.COM_PN=HD2_60_ISO;"
           .."DLNA.ORG_FLAGS=8d700000000000000000000000000000;"
           .."DLNA.ORG_OP=11;DLNA.ORG_CI=0"
        end

      -- 24p(not PAL)?
      elseif fr ~= "25" and fr ~= "50" then
        -- AVCHD?
        if minfo.Video.Format == "AVC" --[[and minfo.Audio.Format == "AC-3"]] then
          -- [[
          res = "video/mpeg:"
           .."DLNA.ORG_PN=AVC_TS_HD_24_AC3_ISO;"
           .."SONY.COM_PN=AVC_TS_HD_24_AC3_ISO;"
           .."DLNA.ORG_FLAGS=8d700000000000000000000000000000;"
           .."DLNA.ORG_OP=11;DLNA.ORG_CI=0"
          -- ]]
          --[[ これも同じ？
          res = "video/vnd.dlna.mpeg-tts:"
           .."DLNA.ORG_PN=AVC_TS_HD_24_AC3;"
           .."SONY.COM_PN=AVC_TS_HD_24_AC3;"
           .."DLNA.ORG_FLAGS=8d700000000000000000000000000000;"
           .."DLNA.ORG_OP=11;DLNA.ORG_CI=0"
          -- ]]
        else
          res = "video/mpeg:"
           .."DLNA.ORG_PN=MPEG_TS_HD_60_L2_ISO;"
           .."SONY.COM_PN=HD2_60_ISO;"
           .."DLNA.ORG_FLAGS=8d700000000000000000000000000000;"
           .."DLNA.ORG_OP=11;DLNA.ORG_CI=0"
        end
      end
      return res
    end
  end

  if minfo.General.Format == "MPEG-PS"
   -- NTSC?
   and (fr == "29" or fr == "59" or minfo.Video.Standard == "NTSC")
   -- SD?
   and tonumber(minfo.Video.Width) < 1000
   -- アスペクト比=16/9 ?
   and minfo.Video.DisplayAspectRatio == "1.778" then

    return "video/mpeg:DLNA.ORG_PN=MPEG_PS_NTSC;"
     .."DLNA.ORG_FLAGS=8d700000000000000000000000000000;"
     .."DLNA.ORG_OP=11;DLNA.ORG_CI=0"

  end


  ---------------- 以下、トランスコード

  if minfo.General.Format == "ISO DVD" then return _dvd(fname, minfo) end
  
  local t, t2 = {}, {}

  if AVCHD_OK and H264ToMpegTS and minfo.Video.Format == "AVC"
   -- NTSC or 24p(not PAL)?
   and  fr ~= "25" and fr ~= "50" and minfo.Video.Standard ~= "PAL"
   -- CFR?
   and minfo.Video.FrameRate_Mode ~= "VFR"
   -- アスペクト比=16/9 ?
   and minfo.Video.DisplayAspectRatio == "1.778" then

    t.name = fileu.ExtractFileName(fname).." >AVCHD"

    if  fr == "29" or fr == "59" or minfo.Video.Standard == "NTSC" then
      -- NTSC
      t.mime = "video/mpeg:"
       .."DLNA.ORG_PN=AVC_TS_HD_60_AC3_ISO;"
       .."SONY.COM_PN=AVC_TS_HD_60_AC3_ISO;"
       .."DLNA.ORG_FLAGS=8d700000000000000000000000000000;"
       .."DLNA.ORG_OP=11;DLNA.ORG_CI=0"
     
       -- つぶやき：AAC音声にはAVC_TS_JP_AAC_Tの方がいいのかも。
    else
      -- 24p
      t.mime = "video/mpeg:"
       .."DLNA.ORG_PN=AVC_TS_HD_24_AC3_ISO;"
       .."SONY.COM_PN=AVC_TS_HD_24_AC3_ISO;"
       .."DLNA.ORG_FLAGS=8d700000000000000000000000000000;"
       .."DLNA.ORG_OP=11;DLNA.ORG_CI=0"
    end

    if minfo.Audio.Format == "AC-3" or minfo.Audio.Format == "AAC" then
      -- コンテナのみ替える
      t.command = [[
       ffmpeg $_cmd_quiet_ffmpeg_$ $_cmd_seek_ffmpeg_$ -i "$_in_$"
       -vcodec copy -acodec copy -f mpegts -vbsf h264_mp4toannexb "$_out_$"
      ]]
    else
      -- コンテナ替え＋音声を AC-3 に変換
      t.command = [[
       ffmpeg $_cmd_quiet_ffmpeg_$ $_cmd_seek_ffmpeg_$ -i "$_in_$"
       -vcodec copy -acodec ac3 -ac 6 -ar 48000 -ab 192k
       -f mpegts -vbsf h264_mp4toannexb "$_out_$"
      ]]
    end

    if BMS.ShowTranscodeFolder then t2 = {t} else t2 = t end
    return t2, "/ "..fileu.ExtractFileName(fname)
  end

  local aspect = minfo.Video.DisplayAspectRatio
  local w = minfo.Video.Width
  local h = minfo.Video.Height
  if aspect == "" then aspect = "1.333" end
  --print("\r\nDEBUG: ", fname, " aspect=", aspect, "\r\n")

  -- この機種ではサイズによりアスペクト比を判定しているみたいなので
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

  t2.mime = "video/mpeg:DLNA.ORG_PN=MPEG_PS_NTSC;"
   .."DLNA.ORG_FLAGS=8d700000000000000000000000000000;"
   .."DLNA.ORG_OP=11;DLNA.ORG_CI=0"
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

  -- この機種ではサイズによりアスペクト比を判定しているみたいなので
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

  t2.mime = "video/mpeg:DLNA.ORG_PN=MPEG_PS_NTSC;"
   .."DLNA.ORG_FLAGS=8d700000000000000000000000000000;"
   .."DLNA.ORG_OP=11;DLNA.ORG_CI=0"

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

