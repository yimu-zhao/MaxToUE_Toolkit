/*
 * MaxToUE Toolkit  Version 3
 * 推荐: 3ds Max 2022 及以上版本
 * 备注: 2019/2020 可运行，但部分分组标题颜色显示异常（不影响功能）
 * 支持: UE4 / UE5 FBX导出
 */
try (closeRolloutFloater _51W_Floater) catch ()
try (callbacks.removeScripts id:#rl_FBXExport_SelChg) catch ()
try (callbacks.removeScripts id:#rl_FBXExport_FileOpen) catch ()
try (enableAccelerators = true) catch ()

-- 全局共享状态
global _51W_Data
struct _51W_DataStruct (
    exportPath = "", importBasePath = "", batchFileList = #(),
    meshPrefix = "SM", meshMid = "", matPrefix = "MI_", texPrefix = "T_",

    fn getMatIDs obj = (
        local ids = #{}
        try (
            local b = obj.baseObject
            if classOf b == Editable_Poly then (
                for f = 1 to (polyop.getNumFaces obj) do ids[(polyop.getFaceMatID obj f)] = true
            ) else if classOf b == Editable_Mesh then (
                for f = 1 to obj.mesh.numFaces do ids[(getFaceMatID obj.mesh f)] = true
            ) else (
                local tmp = snapshotAsMesh obj
                if tmp != undefined do (
                    for f = 1 to tmp.numFaces do ids[(getFaceMatID tmp f)] = true
                    free tmp
                )
            )
        ) catch ()
        ids
    ),

    fn convertVrayMatToStd vmat = (
        local s = StandardMaterial name:vmat.name
        try (s.diffuseColor = vmat.diffuse; if vmat.texmap_diffuse != undefined do s.diffuseMap = vmat.texmap_diffuse) catch ()
        try (if vmat.texmap_self_illumination != undefined do s.selfillumMap = vmat.texmap_self_illumination) catch ()
        try (if vmat.texmap_bump != undefined do s.bumpMap = vmat.texmap_bump) catch ()
        try (if vmat.texmap_opacity != undefined do s.opacityMap = vmat.texmap_opacity) catch ()
        s
    ),

    fn convertVrayMatRecursive mat = (
        if mat == undefined do return undefined
        if (matchPattern (classOf mat as string) pattern:"VRay*") then return (_51W_Data.convertVrayMatToStd mat)
        if classOf mat == MultiMaterial then (
            for i = 1 to mat.materialList.count where mat.materialList[i] != undefined do
                mat.materialList[i] = _51W_Data.convertVrayMatRecursive mat.materialList[i]
        )
        mat
    ),

    fn hasVrayMatRecursive mat = (
        if mat == undefined do return false
        if (matchPattern (classOf mat as string) pattern:"VRay*") then return true
        if classOf mat == MultiMaterial then (
            for i = 1 to mat.materialList.count where mat.materialList[i] != undefined do (
                if _51W_Data.hasVrayMatRecursive mat.materialList[i] do return true
            )
        )
        false
    ),

    fn isEmptyObject obj = (
        if superClassOf obj == GeometryClass do (try (if obj.mesh.numVerts == 0 and obj.mesh.numFaces == 0 do return true) catch ())
        if superClassOf obj == helper and obj.children.count == 0 do return true
        false
    ),

    fn getFilePattern idx = (
        case idx of (
            1:"*.obj"
            2:"*.3ds"
            3:"*.fbx"
            4:"*.dwg"
            5:"*.max"
            6:"*.*"
            default:"*.fbx"
        )
    ),

    fn collectFiles dir pat sub = (
        local r = getFiles (dir + "\\" + pat)
        if sub do (for d in (getDirectories (dir + "\\*")) do join r (_51W_Data.collectFiles d pat sub))
        r
    )

    
)
_51W_Data = _51W_DataStruct()


-- ============================================================
-- 匿名使用统计 (PostHog Telemetry)
-- ------------------------------------------------------------
-- 工作原理:
--   1. 启动时上报 $script_loaded
--   2. 各功能按钮点击时上报 feature_used (功能名 + 参数)
--   3. 报错时上报 error_occurred (错误信息 + 上下文)
--   user_id = MD5(用户名+电脑名)，匿名不可逆
--   用户可在 INI 中关闭(set Enabled=false)
-- ============================================================
global _51W_Telemetry
struct _51W_TelemetryStruct (
    -- ★ 在这里填入你从 PostHog 拿到的 Project API Key (phc_ 开头) ★
    apiKey = "phc_y4SakH8nP3PwXrkZyBGjNF2dqDh67wgN8qnk2xYMzfom",
    apiHost = "https://us.i.posthog.com",
    scriptVersion = "3.1.3.3",

    iniPath = (getDir #userScripts) + "\\_51W_Telemetry.ini",
    enabled = true,
    distinctId = "",
    sessionId = "",
    sessionStart = 0,
    pendingClients = #(),
    featureTrackCooldownMs = 600,
    lastFeatureTrackTick = 0,
    fn boolFromIniValue v = (
        local s = ""
        try (s = toLower (trimRight (trimLeft (v as string)))) catch ()
        (s == "true" or s == "1" or s == "yes" or s == "on")
    ),
    fn byteArrayLength bytes = (
        local n = 0
        try (n = bytes.Length) catch (try (n = bytes.count) catch (n = 0))
        n
    ),
    fn md5Hex s = (
        try (
            local md5 = (dotNetClass "System.Security.Cryptography.MD5").Create()
            local bytes = (dotNetClass "System.Text.Encoding").UTF8.GetBytes s
            local hash = md5.ComputeHash bytes
            local sb = dotNetObject "System.Text.StringBuilder"
            for b in hash do sb.Append (b.ToString "x2")
            sb.ToString()
        ) catch ("anon_" + (random 100000 999999) as string)
    ),

    fn ensureUser = (
        if not (doesFileExist iniPath) do (
            local f = createFile iniPath
            if f != undefined do (
                format "[Telemetry]\nEnabled=false\nUserId=\n" to:f
                close f
            )
        )
        local migrated = getINISetting iniPath "Telemetry" "OptInMigrated"
        -- 首次迁移时只补全缺失字段，不覆盖用户已设置的 Enabled 值
        if migrated == "" do (
            local rawEnabled = getINISetting iniPath "Telemetry" "Enabled"
            if rawEnabled == "" do setINISetting iniPath "Telemetry" "Enabled" "false"
            setINISetting iniPath "Telemetry" "OptInMigrated" "true"
        )
        enabled = boolFromIniValue (getINISetting iniPath "Telemetry" "Enabled")
        -- 明文标识: 用户名@电脑名 (便于在 PostHog 里识别是谁)
        distinctId = (sysInfo.username) + "@" + (sysInfo.computername)
        setINISetting iniPath "Telemetry" "UserId" distinctId
        sessionId = (md5Hex (distinctId + (localTime as string) + (random 1 1000000) as string))
        sessionStart = timeStamp()
    ),

    fn jsonEscape s = (
        local str = s as string
        str = substituteString str "\\" "\\\\"
        str = substituteString str "\"" "\\\""
        str = substituteString str "\n" "\\n"
        str = substituteString str "\r" "\\r"
        str = substituteString str "\t" "\\t"
        str
    ),

    fn jsonValue v = (
        if v == undefined then "null"
        else if classOf v == Boolean then (if v then "true" else "false")
        else if (superClassOf v) == Number then (v as string)
        else "\"" + (jsonEscape v) + "\""
    ),

    fn buildPropsJson props = (
        local sb = dotNetObject "System.Text.StringBuilder"
        sb.Append "{"
        sb.Append ("\"$lib\":\"maxscript\",\"$lib_version\":\"" + scriptVersion + "\"")
        try ( sb.Append (",\"max_version\":\"" + ((maxVersion())[1] as string) + "\"") ) catch ()
        sb.Append (",\"session_id\":\"" + sessionId + "\"")
        if props != undefined and (classOf props) == Array and props.count > 1 do (
            local i = 1
            while i < props.count do (
                sb.Append (",\"" + (jsonEscape (props[i] as string)) + "\":")
                sb.Append (jsonValue props[i+1])
                i = i + 2
            )
        )
        sb.Append "}"
        sb.ToString()
    ),

    fn compactPendingClients = (
        if pendingClients.count <= 32 do return ()
        local keep = #()
        for c in pendingClients do (
            local busy = false
            try (busy = c.IsBusy) catch (busy = false)
            if busy then append keep c else (try (c.Dispose()) catch ())
        )
        pendingClients = keep
    ),

    fn postAsync url body = (
        try (
            compactPendingClients()
            local wc = dotNetObject "System.Net.WebClient"
            wc.Encoding = (dotNetClass "System.Text.Encoding").UTF8
            wc.Headers.Add "Content-Type" "application/json"
            wc.UploadStringAsync (dotNetObject "System.Uri" url) "POST" body
            append pendingClients wc
            true
        ) catch (
            format "Telemetry post failed: %\n" (getCurrentException())
            false
        )
    ),

    fn track eventName props:#() = (
        if not enabled do return false
        if apiKey == "phc_REPLACE_ME" do return false
        if distinctId == "" or sessionId == "" do ensureUser()
        if eventName == "feature_used" do (
            local nowTs = timeStamp()
            if (nowTs - lastFeatureTrackTick) < featureTrackCooldownMs do return true
            lastFeatureTrackTick = nowTs
        )
        try (
            local body = "{\"api_key\":\"" + apiKey + "\""
            body += ",\"event\":\"" + (jsonEscape eventName) + "\""
            body += ",\"distinct_id\":\"" + distinctId + "\""
            body += ",\"properties\":" + (buildPropsJson props)
            body += ",\"timestamp\":\"" + ((dotNetClass "System.DateTime").UtcNow.ToString "yyyy-MM-ddTHH:mm:ss.fffZ") + "\"}"
            postAsync (apiHost + "/capture/") body
        ) catch (
            format "Telemetry track failed: %\n" (getCurrentException())
            false
        )
    ),

    fn trackError feature errMsg = (
        track "error_occurred" props:#("feature", feature, "error", errMsg)
    )
)
_51W_Telemetry = _51W_TelemetryStruct()
_51W_Telemetry.ensureUser()
_51W_Telemetry.track "script_loaded"


-- ============================================================
-- 自动更新模块
-- ============================================================
global _51W_Updater

-- 版本号异步返回后的处理（在主线程回调中执行，不阻塞脚本加载）
-- 检测到新版：刷新按钮状态 + 弹一次明显提示（无新版时不弹，静默）
fn _51W_OnUpdateVersion sender args = (
    try (
        if args.Cancelled or args.Error != undefined do return ()   -- 网络失败静默退出
        local remoteVer = trimRight (args.Result as string)
        if _51W_Updater.isNewer remoteVer do (
            _51W_Updater.remoteVersion = remoteVer
            _51W_Updater.updateAvailable = true
        )
        -- 刷新更新按钮显示（若面板已创建）
        try (rl_Changelog.refreshUpdateBtn()) catch ()
        -- 有新版时弹一次明显提示，让用户直接选择更新/稍后（只弹一次）
        if _51W_Updater.updateAvailable and not _51W_Updater.promptShown do (
            _51W_Updater.promptShown = true
            if (queryBox ("发现新版本 " + _51W_Updater.remoteVersion + "\n当前版本 " + _51W_Updater.localVersion + \
                "\n\n是否立即更新？\n（也可稍后在『更新内容』面板底部点击更新）") title:"MaxToUE Toolkit 有更新") do (
                try (
                    if _51W_Updater.doDownload confirm:false do (try (rl_Changelog.refreshUpdateBtn()) catch ())
                ) catch ()
            )
        )
    ) catch ()
)

(
    local _scriptPath = getSourceFileName()

    struct _51W_UpdaterStruct (
        localVersion  = "3.1.3.3",
        rawBase       = "https://raw.githubusercontent.com/yimu-zhao/MaxToUE_Toolkit/main/",
        pat           = "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",
        iniPath       = (getDir #userScripts) + "\\_51W_Telemetry.ini",
        scriptPath    = "",
        wcHold        = undefined,
        updateAvailable = false,
        remoteVersion = "",
        promptShown   = false,

        fn isNewer remoteVer = (
            try (
                local r = filterString remoteVer "."
                local l = filterString localVersion "."
                local cnt = if r.count > l.count then r.count else l.count
                for i = 1 to cnt do (
                    local rv = if i <= r.count then (r[i] as integer) else 0
                    local lv = if i <= l.count then (l[i] as integer) else 0
                    if rv > lv then return true
                    if lv > rv then return false
                )
                false
            ) catch false
        ),

        fn isDirWritable dir = (
            local probe = dir + "\\.w51_" + ((random 100000 999999) as string) + ".tmp"
            try (
                local f = createFile probe
                if f == undefined do return false
                close f
                deleteFile probe
                true
            ) catch (false)
        ),

        fn fetchToFile url destPath timeoutMs:15000 = (
            try (
                local wc = dotNetObject "System.Net.WebClient"
                wc.Headers.Add "User-Agent" "MaxScript-UE-ResourceTool"
                if pat != "******" do wc.Headers.Add "Authorization" ("token " + pat)
                wc.DownloadFile url destPath
                true
            ) catch (false)
        ),

        fn checkAsync = (
            try (
                if scriptPath == "" or not (doesFileExist scriptPath) do return undefined
                if (getINISetting iniPath "Updater" "AutoUpdate") == "false" do return undefined

                -- 异步拉取版本号，回调在主线程执行，不阻塞脚本加载/UI
                local wc = dotNetObject "System.Net.WebClient"
                wc.Encoding = (dotNetClass "System.Text.Encoding").UTF8
                wc.Headers.Add "User-Agent" "MaxScript-UE-ResourceTool"
                if pat != "******" do wc.Headers.Add "Authorization" ("token " + pat)
                dotNet.addEventHandler wc "DownloadStringCompleted" _51W_OnUpdateVersion
                wcHold = wc   -- 持有引用，避免异步完成前被 GC
                wc.DownloadStringAsync (dotNetObject "System.Uri" (rawBase + "version.txt"))
            ) catch ()
        ),

        -- 用户点击「点击更新」时触发：同步下载并覆盖脚本文件
        -- confirm:true 时先弹确认框；confirm:false 用于已确认过的场景（如启动提示框已选是）
        fn doDownload confirm:true = (
            if not updateAvailable do return false
            if confirm and not (queryBox ("发现新版本 " + remoteVersion + "（当前 " + localVersion + "）\n\n是否立即下载更新？\n下载完成后请重新运行脚本。") \
                title:"MaxToUE Toolkit 有更新") do return false
            -- 更新需覆盖脚本自身，先确认所在目录可写（Program Files 等受保护目录会失败）
            local scriptDir = getFilenamePath scriptPath
            if not (isDirWritable scriptDir) do (
                messageBox ("更新失败：脚本所在目录没有写入权限，无法自动更新。\n\n当前位置：\n" + scriptDir + \
                    "\n\n请将脚本移动到普通目录（例如 文档 或 桌面 下的文件夹），\n避免放在 C:\\Program Files 内，然后重新加载脚本即可正常更新。") \
                    title:"更新失败 · 需移动位置"
                return false
            )
            local tmpPath = scriptPath + ".download.tmp"
            local ok = (fetchToFile (rawBase + "MaxToUE_Toolkit.ms") tmpPath timeoutMs:15000)
            if ok and (doesFileExist tmpPath) and ((getFileSize tmpPath) > 0) then (
                try (
                    deleteFile scriptPath
                    (dotNetClass "System.IO.File").Move tmpPath scriptPath
                    messageBox "更新完成！\n请重新运行脚本以加载新版本。" title:"更新成功"
                    true
                ) catch (
                    try (deleteFile tmpPath) catch ()
                    messageBox "写入失败，请重试。" title:"更新失败"
                    false
                )
            ) else (
                try (deleteFile tmpPath) catch ()
                messageBox "下载失败，请检查网络后重试。" title:"更新失败"
                false
            )
        )
    )

    _51W_Updater = _51W_UpdaterStruct scriptPath:_scriptPath
    _51W_Updater.checkAsync()
)


-- 1. 烘焙AO贴图
rollout rl_BakeAO "烘焙AO贴图" width:464 (
    button btn_bake "烘焙AO贴图" pos:[14,8] width:212 height:26
    button btn_show "显示AO贴图" pos:[238,8] width:212 height:26
    label lbl_size "贴图：" pos:[14,44] width:36 height:18
    spinner spn_size "" range:[64,8192,1024] type:#integer fieldWidth:46 pos:[44,43] width:62
    label lbl_uv "UV通道：" pos:[240,44] width:50 height:18
    spinner spn_uv "" range:[1,99,2] type:#integer fieldWidth:24 pos:[282,43] width:40 \
        tooltip:"AO 烘焙到第几套 UV。UE 通常用第 2 套（Lightmap UV）；若对象缺少该套 UV 会自动展一套。"

    fn getBaseName obj = (
        local pfx = _51W_Data.meshPrefix
        local n = obj.name
        if pfx != "" and matchPattern n pattern:(pfx + "_*") then substring n (pfx.count + 2) -1 else n
    )

    fn getAODir = (
        local p = getFilenamePath maxFilePath
        if p == "" do p = getDir #image + "\\"
        p
    )

    fn getAOPath obj = (getAODir() + "T_" + (getBaseName obj) + "_AO.png")

    fn applyAOToMat mat aoFile = (
        local bmp = BitmapTexture name:(getFilenameFile aoFile) filename:aoFile
        if classOf mat == MultiMaterial then (
            for i = 1 to mat.materialList.count where mat.materialList[i] != undefined do
                applyAOToMat mat.materialList[i] aoFile
        ) else if classOf mat == StandardMaterial then (
            mat.selfIllumMap = bmp
        ) else (
            try (mat.emission_map = bmp) catch (
                try (mat.selfIllumMap = bmp) catch (
                    format "无法为材质 % 指定AO贴图，请手动设置。\n" mat.name
                )
            )
        )
    )

    on btn_bake pressed do (
        _51W_Telemetry.track "feature_used" props:#("feature", "BakeAO")
        local objs = selection as array
        if objs.count == 0 do (messageBox "请先选择对象。" title:"烘焙AO"; return ())
        local sz = spn_size.value
        local ch = spn_uv.value
        local oldRend = renderers.current
        renderers.current = Default_Scanline_Renderer()

        -- 创建临时天光
        local skyCls = undefined
        for c in light.classes where (matchPattern (c as string) pattern:"Skylight") do (skyCls = c; exit)
        local sky = if skyCls != undefined then (skyCls name:"_AO_Sky_" multiplier:1.0 castShadows:true)
                    else (Omnilight name:"_AO_Sky_" pos:[0,0,5000] multiplier:1.0 castShadows:true)

        -- 隐藏其他灯光
        local hidden = for l in lights where l != sky and not l.isHidden collect (l.isHidden = true; l)

        -- 替换材质为纯白
        local origMats = for obj in objs collect obj.material
        local baked = true
        local bakeErr = ""
        try (
            undo "Bake AO" on (
                for obj in objs do (
                    if (meshop.getMapSupport obj.mesh ch) == false do (
                        local uw = Unwrap_UVW(); uw.setMapChannel ch; addModifier obj uw
                        uw.flattenMap 45.0 #([0,0,1],[0,0,-1],[1,0,0],[-1,0,0],[0,1,0],[0,-1,0]) 0.02 true 0 true true
                        collapseStack obj
                    )
                    obj.material = StandardMaterial name:"_AO_W_" diffuseColor:white selfIllumAmount:0
                    obj.INodeBakeProperties.removeAllBakeElements()
                    local aoPath = getAOPath obj
                    local el = CompleteMap(); el.outputSzX = el.outputSzY = sz
                    el.fileType = el.fileName = aoPath
                    el.filterOn = el.enabled = el.shadowsOn = true
                    el.targetMapSlotName = "Self-Illumination"
                    obj.INodeBakeProperties.addBakeElement el
                    obj.INodeBakeProperties.bakeEnabled = true
                    obj.INodeBakeProperties.bakeChannel = ch
                    obj.INodeBakeProperties.nDilations = 4
                )
                select objs
                render renderType:#bakeSelected vfb:off progressBar:true outputSize:[sz,sz]
            )
        ) catch (
            baked = false
            bakeErr = getCurrentException()
        )
        -- 清理：无论成败都还原材质/临时灯光/渲染器，避免异常污染场景
        for i = 1 to objs.count do (
            objs[i].material = origMats[i]
            local aoFile = getAOPath objs[i]
            if objs[i].material != undefined and doesFileExist aoFile do
                applyAOToMat objs[i].material aoFile
        )
        try (delete sky) catch ()
        for l in hidden do try (l.isHidden = false) catch ()
        renderers.current = oldRend
        if baked then
            messageBox ("AO烘焙完成！已自动应用到材质。\n保存在: " + getAODir()) title:"烘焙AO"
        else
            messageBox ("AO烘焙失败，场景已还原。\n\n原因：" + bakeErr) title:"烘焙AO"
    )

    on btn_show pressed do (
        _51W_Telemetry.track "feature_used" props:#("feature", "BakeAO_Show")
        local objs = selection as array
        if objs.count == 0 do (messageBox "请先选择对象。" title:"显示AO"; return ())
        for obj in objs do (
            local f = getAOPath obj
            if doesFileExist f then display (openBitmap f) else format "未找到: %\n" f
        )
    )
)


-- 2. 材质优化
rollout rl_MatOptimize "材质优化" (
    groupBox gbOptCol "材质优化" pos:[8,6] width:228 height:122
    button btn_opt "优化材质" pos:[20,28] width:204 height:26
    label lbl_maxID "最多ID数目：  " pos:[20,62] width:204 height:16
    label lbl_srcMat "原材质数目：  " pos:[20,82] width:204 height:16
    label lbl_curMat "现材质数目：  " pos:[20,102] width:204 height:16

    groupBox gbVrayCol "VRay材质转标准材质" pos:[248,6] width:228 height:122
    button btn_vray_sel "转换选中对象" pos:[260,36] width:204 height:24
    button btn_vray_all "转换场景全部" pos:[260,72] width:204 height:24

    fn doConvertVray objList = (
        _51W_Telemetry.track "feature_used" props:#("feature", "VrayConvert", "obj_count", objList.count)
        local c = 0
        for obj in objList where obj.material != undefined do (
            if _51W_Data.hasVrayMatRecursive obj.material do (
                obj.material = _51W_Data.convertVrayMatRecursive obj.material
                c += 1
            )
        )
        c
    )

    on btn_opt pressed do (
        _51W_Telemetry.track "feature_used" props:#("feature", "MatOptimize")
        local objs = selection as array
        if objs.count == 0 do (messageBox "请先选择对象。" title:"材质优化"; return ())
        local maxID = 0, srcCnt = 0, curCnt = 0
        for obj in objs do (
            local n = (_51W_Data.getMatIDs obj).numberSet
            if n > maxID do maxID = n
            if obj.material != undefined do (
                if classOf obj.material == MultiMaterial then (
                    -- 统计“实际使用的ID数”，避免 materialList 槽位残留导致显示偏大
                    srcCnt += n
                ) else srcCnt += 1
            )
        )
        lbl_maxID.text = "最多ID数目：  " + maxID as string
        lbl_srcMat.text = "原材质数目：  " + srcCnt as string
        local optimizedObjs = 0
        undo "Optimize Materials" on (
            for obj in objs where obj.material != undefined and classOf obj.material == MultiMaterial and superClassOf obj == GeometryClass do (
                local used = _51W_Data.getMatIDs obj
                local mm = obj.material
                local keyList = #()
                local newSubs = #()
                local idMap = #()
                local usedCount = 0
                for oldID in used do (
                    local srcIdx = findItem mm.materialIDList oldID
                    if srcIdx == 0 and oldID >= 1 and oldID <= mm.materialList.count do srcIdx = oldID
                    if srcIdx > 0 and srcIdx <= mm.materialList.count and mm.materialList[srcIdx] != undefined do (
                        usedCount += 1
                        local subMat = mm.materialList[srcIdx]
                        local k = ""
                        local n = ""
                        try (n = subMat.name as string) catch ()
                        n = trimLeft (trimRight n)
                        if n != "" then k = ("name:" + (toLower n)) else k = ("slot:" + srcIdx as string)
                        local mappedIdx = findItem keyList k
                        if mappedIdx == 0 do (
                            append keyList k
                            append newSubs subMat
                            mappedIdx = newSubs.count
                        )
                        idMap[oldID] = mappedIdx
                    )
                )
                if newSubs.count == 0 do continue
                local nm = MultiMaterial numsubs:newSubs.count name:mm.name
                for i = 1 to newSubs.count do (
                    nm.materialList[i] = newSubs[i]
                    nm.materialIDList[i] = i
                )
                if classOf obj.baseObject != Editable_Poly do convertToPoly obj
                for f = 1 to (polyop.getNumFaces obj) do (
                    local oldID = polyop.getFaceMatID obj f
                    if idMap[oldID] != undefined do polyop.setFaceMatID obj f idMap[oldID]
                )
                obj.material = nm
                if newSubs.count < usedCount then optimizedObjs += 1
            )
        )
        for obj in objs where obj.material != undefined do (
            if classOf obj.material == MultiMaterial then
                curCnt += (_51W_Data.getMatIDs obj).numberSet
            else
                curCnt += 1
        )
        lbl_curMat.text = "现材质数目：  " + curCnt as string
        if optimizedObjs == 0 then
            messageBox "未发现可优化的子材质槽（可能当前ID都在使用或对象不是几何体）。" title:"材质优化"
        else
            messageBox ("材质优化完成！已处理 " + optimizedObjs as string + " 个对象。") title:"材质优化"
    )

    on btn_vray_sel pressed do (
        local objs = selection as array
        if objs.count == 0 do (messageBox "请先选择对象。" title:"VRay转换"; return ())
        undo "VRay Convert Selected" on (
            local c = doConvertVray objs
            if c == 0 then
                messageBox "未检测到 VRay 材质，未执行转换。" title:"VRay转换"
            else
                messageBox (c as string + " 个对象已完成 VRay→标准材质转换。") title:"VRay转换"
        )
    )

    on btn_vray_all pressed do (
        if queryBox "确定转换场景中全部 VRay 材质为标准材质？" title:"VRay转换" do (
            undo "VRay Convert All" on (
                local c = doConvertVray (objects as array)
                if c == 0 then
                    messageBox "场景中未检测到 VRay 材质，未执行转换。" title:"VRay转换"
                else
                    messageBox (c as string + " 个对象已完成 VRay→标准材质转换。") title:"VRay转换"
            )
        )
    )
)

-- 3. 优化工具
rollout rl_Optimize "优化工具" (
    group "几何清理" (
        spinner spn_isoAng "共线阈值：" range:[150.0, 180.0, 178.0] type:#float fieldWidth:46 align:#left across:3 offset:[0,5]
        button  btn_isoSel "选中废点" width:130 height:26 align:#right offset:[30,0]
        button  btn_iso    "移除废点" width:130 height:26 align:#right
        spinner spn_weldThr "焊接阈值：" range:[0.0001, 1000.0, 0.01] type:#float fieldWidth:46 align:#left across:2 offset:[0,6]
        button  btn_weld    "焊接重合点" width:280 height:26 align:#right
    )

    group "拓扑" (
        label   lbl_q     "平面阈值(°)："  align:#left across:3 offset:[0,6]
        spinner spn_quadAng "" range:[0.1, 30.0, 2.0] type:#float fieldWidth:46 align:#left offset:[-88,5]
        button  btn_quad  "去对角线（三角→四边）" width:280 height:26 align:#right offset:[-2,0]
    )

    group "ProOptimizer 减面（Max 2022 及以下版本）" (
        spinner spn_pct "保留比例：" range:[1, 99, 25] type:#integer fieldWidth:42 across:3 align:#left offset:[0,7]
        label   lbl_pct "%" width:20 align:#left offset:[-42,9]
        button  btn_doOpt "减面" width:52 height:22 align:#left offset:[-185,4]
        checkbox chk_keepSG    "平滑组"  checked:true across:4 align:#center offset:[0,4]
        checkbox chk_keepMatID "材质 ID" checked:true align:#center offset:[0,4]
        checkbox chk_keepUV   "UV 通道" checked:true align:#center offset:[0,4]
        checkbox chk_keepNorm "法线"    checked:true align:#center offset:[0,4]
    )

    group "Retopology 减面（Max 2023+，保四边面，需手动点 Compute）" (
        spinner spn_rtoPct "保留比例：" range:[1, 99, 25] type:#integer fieldWidth:42 across:3 align:#left offset:[0,7]
        label   lbl_rtoPct "%" width:20 align:#left offset:[-42,9]
        button  btn_doRto "减面" width:52 height:22 align:#left offset:[-185,4]
        checkbox chk_rtoSG    "平滑组"  checked:true across:4 align:#center offset:[0,4]
        checkbox chk_rtoMatID "材质 ID" checked:true align:#center offset:[0,4]
        checkbox chk_rtoUV    "UV 通道" checked:true align:#center offset:[0,4]
        checkbox chk_rtoNorm  "法线"    checked:true align:#center offset:[0,4]
    )

    fn selGeo = (
        local arr = selection as array
        arr
    )

    fn ensurePoly obj = (
        if obj.modifiers.count > 0 do (try (collapseStack obj) catch ())
        if classOf obj.baseObject != Editable_Poly do convertToPoly obj
        classOf obj.baseObject == Editable_Poly
    )

    fn collectRedundantVerts obj angThresh = (
        local nv = polyop.getNumVerts obj
        local toRemove = #{}
        if nv == 0 do return toRemove
        local used = #{}
        for f = 1 to polyop.getNumFaces obj do (
            for v in (polyop.getFaceVerts obj f) do used[v] = true
        )
        join toRemove ((#{1..nv}) - used)
        local cosThresh = cos (180.0 - angThresh)
        for v = 1 to nv where used[v] do (
            local edges = polyop.getEdgesUsingVert obj #{v}
            local eArr = edges as array
            if eArr.count < 2 do continue
            local pv = polyop.getVert obj v
            local dirs = #()
            for e in eArr do (
                local ev = polyop.getEdgeVerts obj e
                local other = if ev[1] == v then ev[2] else ev[1]
                local d = (polyop.getVert obj other) - pv
                local len = length d
                if len > 1e-6 do append dirs (d / len)
            )
            local collinear = false
            for i = 1 to dirs.count while not collinear do
                for j = i + 1 to dirs.count while not collinear do
                    if (dot dirs[i] dirs[j]) < -cosThresh do collinear = true
            if collinear do toRemove[v] = true
        )
        toRemove
    )

    fn doSelectIso = (
        local objs = selGeo()
        if objs.count == 0 do (messageBox "请先选择对象。" title:"选中废点"; return ())
        local angThresh = spn_isoAng.value as float
        local total = 0
        for obj in objs do (
            if not (ensurePoly obj) do continue
            local verts = collectRedundantVerts obj angThresh
            if verts.numberSet > 0 do (
                polyop.setVertSelection obj verts
                subObjectLevel = 1
                total += verts.numberSet
            )
        )
        if total == 0 do (messageBox "未找到废点。" title:"选中废点"; return ())
        messageBox ("已选中 " + total as string + " 个废点，确认无误后点【移除废点】。") title:"选中废点"
    )

    fn doRemoveIso = (
        _51W_Telemetry.track "feature_used" props:#("feature", "RemoveRedundantVerts")
        local objs = selGeo()
        if objs.count == 0 do (messageBox "请先选择对象。" title:"移除废点"; return ())
        local angThresh = spn_isoAng.value as float
        local total = 0; local checked = 0; local skipped = 0
        local oldSubLevel = subObjectLevel
        undo "移除废点" on (
            for obj in objs do (
                if not (ensurePoly obj) do (skipped += 1; continue)
                checked += 1
                local toRemove = collectRedundantVerts obj angThresh
                local cnt = toRemove.numberSet
                if cnt > 0 do (
                    polyop.setVertSelection obj toRemove
                    subObjectLevel = 1
                    obj.EditablePoly.Remove()
                    subObjectLevel = 0
                    total += cnt
                )
            )
        )
        subObjectLevel = oldSubLevel
        messageBox ("已检查 " + checked as string + " 个对象，共移除 " + total as string + " 个废点。" \
            + (if skipped > 0 then ("\n跳过 " + skipped as string + " 个非几何对象。") else "")) \
            title:"移除废点"
    )

    fn doWeld = (
        _51W_Telemetry.track "feature_used" props:#("feature", "WeldVerts")
        local objs = selGeo()
        if objs.count == 0 do (messageBox "请先选择对象。" title:"焊接重合点"; return ())
        local thr = spn_weldThr.value
        local total = 0; local checked = 0; local skipped = 0
        local oldSel = selection as array
        local oldSubLevel = subObjectLevel
        undo "焊接重合点" on (
            for obj in objs do (
                if not (ensurePoly obj) do (skipped += 1; continue)
                checked += 1
                local before = polyop.getNumVerts obj
                if before == 0 do continue
                try (
                    select obj
                    max modify mode
                    modPanel.setCurrentObject obj.baseObject
                    obj.weldThreshold = thr
                    subObjectLevel = 1
                    obj.EditablePoly.SetSelection #Vertex #{1..before}
                    obj.EditablePoly.weldFlaggedVertices()
                    subObjectLevel = 0
                ) catch (format "焊接失败: %\n" obj.name; continue)
                local after = polyop.getNumVerts obj
                local merged = before - after
                if merged > 0 do (total += merged)
            )
        )
        subObjectLevel = oldSubLevel
        if oldSel.count > 0 do select oldSel
        messageBox ("已检查 " + checked as string + " 个对象，共焊接 " + total as string + " 个顶点（阈值 " + thr as string + "）。" \
            + (if skipped > 0 then ("\n跳过 " + skipped as string + " 个非几何对象。") else "")) \
            title:"焊接重合点"
    )

    fn doQuadrify = (
        _51W_Telemetry.track "feature_used" props:#("feature", "Quadrify")
        local objs = selGeo()
        if objs.count == 0 do (messageBox "请先选择对象。" title:"去对角线"; return ())
        local angThresh = spn_quadAng.value as float
        local totalRemoved = 0; local checked = 0; local skipped = 0
        local oldSubLevel = subObjectLevel
        undo "去对角线" on (
            for obj in objs do (
                if not (ensurePoly obj) do (skipped += 1; continue)
                checked += 1
                local numE = polyop.getNumEdges obj
                if numE == 0 do continue

                local candidates = #()
                for e = 1 to numE do (
                    local faces = polyop.getEdgeFaces obj e
                    if faces.count != 2 do continue
                    local f1v = polyop.getFaceVerts obj faces[1]
                    local f2v = polyop.getFaceVerts obj faces[2]
                    if f1v.count != 3 or f2v.count != 3 do continue
                    local n1 = polyop.getFaceNormal obj faces[1]
                    local n2 = polyop.getFaceNormal obj faces[2]
                    local dotVal = dot n1 n2
                    if dotVal <= 0 do continue
                    local ang = acos (amax -1.0 (amin 1.0 dotVal))
                    if ang < angThresh do append candidates #(e, ang, faces[1], faces[2])
                )

                fn _cmpAng a b = (if a[2] < b[2] then -1 else if a[2] > b[2] then 1 else 0)
                qsort candidates _cmpAng

                local usedFaces = #{}
                local edgesToRemove = #{}
                for c in candidates do (
                    if not usedFaces[c[3]] and not usedFaces[c[4]] do (
                        usedFaces[c[3]] = true; usedFaces[c[4]] = true
                        edgesToRemove[c[1]] = true
                    )
                )

                local cnt = edgesToRemove.numberSet
                if cnt > 0 do (
                    polyop.setEdgeSelection obj edgesToRemove
                    subObjectLevel = 2
                    obj.EditablePoly.Remove()
                    subObjectLevel = 0
                    totalRemoved += cnt
                )
            )
        )
        subObjectLevel = oldSubLevel
        messageBox ("已检查 " + checked as string + " 个对象，共移除 " + totalRemoved as string + " 条对角线。" \
            + (if skipped > 0 then ("\n跳过 " + skipped as string + " 个非几何对象。") else "")) \
            title:"去对角线"
    )

    fn doOptimize pct = (
        _51W_Telemetry.track "feature_used" props:#("feature", "ProOptimizer", "percent", pct as string)
        local objs = selGeo()
        if objs.count == 0 do (messageBox "请先选择对象。" title:"减面"; return ())
        if pct < 1 or pct > 99 do (messageBox "比例需在 1-99 之间。" title:"减面"; return ())
        local keepSG   = if chk_keepSG.checked   then true else false
        local keepMatID= if chk_keepMatID.checked then true else false
        local keepUV   = if chk_keepUV.checked    then true else false
        local keepN    = if chk_keepNorm.checked   then true else false
        local n = 0; local sumBefore = 0; local sumAfter = 0
        undo "ProOptimizer" on (
            for obj in objs do (
                local pc = getPolygonCount obj
                local before = pc[1]
                sumBefore += before
                try (
                    local m = ProOptimizer ()
                    addModifier obj m
                    try (m.KeepUV = keepUV) catch ()
                    try (m.KeepNormals = keepN) catch ()
                    try (m.KeepNormal = keepN) catch ()
                    try (m.KeepMaterials = keepMatID) catch ()
                    try (m.KeepMaterial = keepMatID) catch ()
                    try (m.KeepSmoothingGroups = keepSG) catch ()
                    try (m.KeepSmoothBoundaries = keepSG) catch ()
                    m.Calculate = true
                    m.VertexPercent = pct
                    collapseStack obj
                    local after = (getPolygonCount obj)[1]
                    sumAfter += after
                    n += 1
                ) catch (
                    format "ProOptimizer 失败: %\n" obj.name
                    sumAfter += before
                )
            )
        )
        format "% 个对象减面完成。面数: % -> % (%)\n" n sumBefore sumAfter (((100.0 * sumAfter / (amax 1 sumBefore)) as integer) as string + "%")
    )

    fn doRetopo pct = (
        local retoCls = undefined
        try (retoCls = execute "Retopology") catch ()
        if retoCls == undefined do (
            try (
                for c in modifier.classes while retoCls == undefined do (
                    if matchPattern (c as string) pattern:"*etopo*" ignoreCase:true do retoCls = c
                )
            ) catch ()
        )
        if retoCls == undefined do (
            messageBox "当前 Max 版本不支持 Retopology 修改器（需 Max 2023+）。" title:"版本不支持"
            return ()
        )
        local objs = selGeo()
        if objs.count == 0 do (messageBox "请先选择对象。" title:"Retopology 减面"; return ())
        local keepSG    = chk_rtoSG.checked
        local keepMatID = chk_rtoMatID.checked
        local keepUV    = chk_rtoUV.checked
        local keepN     = chk_rtoNorm.checked
        local n = 0
        undo "Retopology" on (
            for obj in objs do (
                ensurePoly obj
                local pc = getPolygonCount obj
                local before = pc[1]
                local targetFaces = (before * pct / 100.0) as integer
                if targetFaces < 4 do targetFaces = 4
                try (
                    local m = retoCls()
                    addModifier obj m
                    try (m.numFacesTarget = targetFaces) catch ()
                    try (m.hardEdgesFromSmoothingGroups = keepSG) catch ()
                    try (m.hardEdgesFromMaterialID = keepMatID) catch ()
                    try (m.hardEdgesFromUVSeams = keepUV) catch ()
                    try (m.hardEdgesFromSpecifiedNormals = keepN) catch ()
                    n += 1
                ) catch (
                    format "Retopology 失败: %\n" obj.name
                )
            )
        )
        format "已为 % 个对象添加 Retopology 修改器，请在修改器面板手动点击 Compute 按钮执行计算。\n" n
    )

    on btn_isoSel pressed do doSelectIso()
    on btn_iso  pressed do doRemoveIso()
    on btn_weld pressed do doWeld()
    on btn_quad pressed do doQuadrify()

    on btn_doOpt pressed do doOptimize spn_pct.value
    on btn_doRto pressed do doRetopo spn_rtoPct.value
)
rollout rl_AutoName "一键自动命名" width:490 (
    fn getBaseName obj = (
        local p = _51W_Data.meshPrefix
        local n = obj.name
        if p != "" and matchPattern n pattern:(p + "_*") then substring n (p.count + 2) -1 else n
    )

    fn collectBitmaps node result = (
        if node == undefined do return ()
        if superClassOf node == textureMap do (
            if classOf node == BitmapTexture do appendIfUnique result node
        )
        local n = 0; try (n = getNumSubTexmaps node) catch ()
        for i = 1 to n do try (local s = getSubTexmap node i; if s != undefined do collectBitmaps s result) catch ()
    )

    -- 从贴图节点(可能有 Normal_Bump 等包装)中提取 BitmapTexture
    fn extractBmp texmap = (
        if texmap == undefined do return undefined
        if classOf texmap == BitmapTexture do return texmap
        local n = 0; try (n = getNumSubTexmaps texmap) catch ()
        for i = 1 to n do (
            local s = try (getSubTexmap texmap i) catch undefined
            if s != undefined do (local b = extractBmp s; if b != undefined do return b)
        )
        undefined
    )

    -- 按插槽类型收集贴图, 返回 #(#("_D", bmp), #("_R", bmp), ...)
    fn getSlotBitmaps mat = (
        local result = #(); local seen = #()
        fn tryAdd r s sfx texmap = (
            local bmp = rl_AutoName.extractBmp texmap
            if bmp != undefined and findItem s bmp == 0 do (append r #(sfx, bmp); append s bmp)
        )
        if classOf mat == PhysicalMaterial then (
            tryAdd result seen "_D" mat.base_color_map
            tryAdd result seen "_N" mat.bump_map
            tryAdd result seen "_R" mat.roughness_map
            tryAdd result seen "_M" mat.metalness_map
            tryAdd result seen "_O" mat.cutout_map
            tryAdd result seen "_E" mat.emit_color_map
            tryAdd result seen "_DP" mat.displacement_map
            try (tryAdd result seen "_CN" mat.coating_bump_map) catch ()
        ) else if classOf mat == StandardMaterial then (
            tryAdd result seen "_D" mat.diffuseMap
            tryAdd result seen "_N" mat.bumpMap
            tryAdd result seen "_S" mat.specularMap
            tryAdd result seen "_G" mat.glossinessMap
            tryAdd result seen "_O" mat.opacityMap
            tryAdd result seen "_E" mat.selfIllumMap
        ) else (
            local bms = #(); collectBitmaps mat bms
            for bi = 1 to bms.count do append result #("_" + bi as string, bms[bi])
        )
        result
    )

    fn doRename = (
        _51W_Telemetry.track "feature_used" props:#("feature", "AutoNameMesh")
        local pfx = if _51W_Data.meshPrefix != "" then _51W_Data.meshPrefix else "SM"
        local mid = _51W_Data.meshMid
        if txtMeshPfx != undefined and txtMeshPfx.text != "" do pfx = txtMeshPfx.text
        if txtMeshMid != undefined do mid = txtMeshMid.text
        _51W_Data.meshPrefix = pfx
        _51W_Data.meshMid = mid
        local objs = selection as array
        if objs.count == 0 do (messageBox "请先选择对象。" title:"重命名"; return ())
        undo "Rename" on (
            for i = 1 to objs.count do (
                local base = objs[i].name
                if matchPattern base pattern:(pfx + "_*") do base = substring base (pfx.count + 2) -1
                if mid != "" then
                    objs[i].name = pfx + "_" + mid + "_" + base
                else
                    objs[i].name = pfx + "_" + base
            )
            messageBox (objs.count as string + " 个对象已重命名。") title:"重命名"
        )
    )

    fn doRenameMat = (
        _51W_Telemetry.track "feature_used" props:#("feature", "AutoNameMaterial")
        local pfx = if txtMatPfx != undefined then txtMatPfx.text else "MI_"
        local objs = selection as array
        if objs.count == 0 do (messageBox "请先选择对象。" title:"重命名材质"; return ())
        local c = 0
        undo "Rename Mats" on (
            for obj in objs where obj.material != undefined do (
                local base = getBaseName obj; local mat = obj.material
                if classOf mat == MultiMaterial then (
                    mat.name = pfx + base
                    for i = 1 to mat.materialList.count where mat.materialList[i] != undefined do (
                        mat.materialList[i].name = pfx + base + (if mat.materialList.count > 1 then ("_" + i as string) else "")
                        c += 1
                    )
                ) else (mat.name = pfx + base; c += 1)
            )
        )
        messageBox (c as string + " 个材质已重命名。") title:"重命名材质"
    )

    fn doRenameTex = (
        _51W_Telemetry.track "feature_used" props:#("feature", "AutoNameTexture")
        local pfx = if txtTexPfx != undefined then txtTexPfx.text else "T_"
        local objs = selection as array
        if objs.count == 0 do (messageBox "请先选择对象。" title:"重命名贴图"; return ())
        local ok = 0, fail = 0
        undo "Rename Tex" on (
            for obj in objs where obj.material != undefined do (
                local base = getBaseName obj; local mat = obj.material
                local mats = if classOf mat == MultiMaterial then mat.materialList else #(mat)
                for mi = 1 to mats.count where mats[mi] != undefined do (
                    local ms = if mats.count > 1 then ("_" + mi as string) else ""
                    local slots = getSlotBitmaps mats[mi]
                    for sl in slots do (
                        local nn = pfx + base + ms + sl[1]
                        sl[2].name = nn
                        local op = sl[2].filename
                        if op != undefined and op != "" and doesFileExist op do (
                            local np = (getFilenamePath op) + nn + (getFilenameType op)
                            if renameFile op np then (sl[2].filename = np; ok += 1) else (fail += 1)
                        )
                    )
                )
            )
        )
        local msg = "成功: " + ok as string
        if fail > 0 do msg += "  失败: " + fail as string
        messageBox msg title:"重命名贴图"
    )

    groupBox gbAutoName1 "一键模型改名" pos:[0,0] width:464 height:55
    groupBox gbAutoName2 "一键更换材质名" pos:[0,60] width:228 height:78
    groupBox gbAutoName3 "一键更换贴图名" pos:[236,60] width:228 height:78

    label lblMeshPfx "前缀名：" pos:[14,23] width:46 height:18
    editText txtMeshPfx text:"SM" pos:[58,20] width:60 height:22
    label lblMeshMid "中间名：" pos:[120,23] width:46 height:18
    editText txtMeshMid "" pos:[164,20] width:80 height:22
    button btnMeshRename "一键模型改名" pos:[310,18] width:140 height:26

    label lblMatPfx "材质前缀名：" pos:[10,81] width:72 height:18
    editText txtMatPfx text:"MI_" pos:[78,78] width:70 height:22
    button btnMatRename "自动更改材质名称" pos:[14,106] width:200 height:26

    label lblTexPfx "贴图前缀名：" pos:[246,81] width:72 height:18
    editText txtTexPfx text:"T_" pos:[314,78] width:70 height:22
    button btnTexRename "自动修改贴图名称" pos:[250,106] width:200 height:26

    on txtMeshPfx changed val do _51W_Data.meshPrefix = val
    on txtMeshMid changed val do _51W_Data.meshMid = val

    on btnMeshRename pressed do (try (doRename()) catch (messageBox (getCurrentException()) title:"错误"))
    on btnMatRename pressed do (try (doRenameMat()) catch (messageBox (getCurrentException()) title:"错误"))
    on btnTexRename pressed do (try (doRenameTex()) catch (messageBox (getCurrentException()) title:"错误"))
)


-- 4. 虚幻_FBX导出插件
rollout rl_FBXExport "批量导出" (
    group "导出模式" (
        radioButtons rdo_mode labels:#("导出选中模型为FBX", "剪切模型位置信息到剪切板") default:1 columns:2
    )
    group "导出设置" (
        checkbox chk_grid "使用用户网格（命名必须为\"UE4_Grid\"）" checked:false across:2 align:#left
        checkbox chk_origin "移动到(0,0,0)导出" checked:false align:#left
        checkbox chk_ucx "包含UCX碰撞" checked:false across:2 align:#left
        checkbox chk_dlg "显示导出设置" checked:false align:#left
    )
    editText edt_path "导出路径：" text:"" fieldWidth:330 align:#left
    button btn_browse "..." width:28 height:20 align:#right offset:[-36,-23]
    button btn_clear "X" width:20 height:20 align:#right offset:[-8,-23]
    button btn_open "打开导出路径" width:120 height:20 align:#center offset:[0,-2]
    label lbl_prev "即将被导出的模型：" align:#left offset:[0,2]
    editText edt_list "" height:60 readOnly:true fieldWidth:460 align:#center offset:[0,-2]
    button btn_export "导出选中模型" width:300 height:30 align:#center offset:[0,2]

    fn refreshPreview = (
        local txt = if edt_path.text != "" then (edt_path.text + "\n") else ""
        for obj in (selection as array) do
            txt += "  " + obj.name + ".fbx @ [" + obj.pos.x as string + "," + obj.pos.y as string + "," + obj.pos.z as string + "]\n"
        edt_list.text = txt
    )

    -- 读取当前场景保存的导出路径（存在 max 文件自定义属性里）
    fn loadScenePath = (
        local idx = fileProperties.findProperty #custom "51W_ExportPath"
        if idx > 0 then (fileProperties.getPropertyValue #custom idx) else ""
    )
    -- 把导出路径写入当前场景（空值则删除，需保存 max 文件后永久生效）
    fn saveScenePath p = (
        if p == "" then (
            local idx = fileProperties.findProperty #custom "51W_ExportPath"
            if idx > 0 do fileProperties.deleteProperty #custom "51W_ExportPath"
        ) else fileProperties.addProperty #custom "51W_ExportPath" p
    )
    -- 取值优先级：场景已存路径 > 当前 max 文件所在文件夹 > 空
    fn resolvePath = (
        local saved = loadScenePath()
        if saved != "" then saved
        else (local mp = maxFilePath; if mp != "" then (trimRight mp "\\") else "")
    )
    -- 刷新路径框（面板打开、切换场景时调用）
    fn applyPath = (
        edt_path.text = resolvePath()
        _51W_Data.exportPath = edt_path.text
        refreshPreview()
    )

    on rl_FBXExport open do (
        applyPath()
        callbacks.removeScripts id:#rl_FBXExport_SelChg
        callbacks.addScript #selectionSetChanged "try(rl_FBXExport.refreshPreview())catch()" id:#rl_FBXExport_SelChg
        callbacks.removeScripts id:#rl_FBXExport_FileOpen
        callbacks.addScript #filePostOpen "try(rl_FBXExport.applyPath())catch()" id:#rl_FBXExport_FileOpen
    )
    on rl_FBXExport close do (
        callbacks.removeScripts id:#rl_FBXExport_SelChg
        callbacks.removeScripts id:#rl_FBXExport_FileOpen
    )
    on btn_browse pressed do (local p = getSavePath caption:"选择FBX导出路径"; if p != undefined do (edt_path.text = p; _51W_Data.exportPath = p; saveScenePath p; refreshPreview()))
    on edt_path entered txt do (_51W_Data.exportPath = txt; saveScenePath txt; refreshPreview())
    on btn_clear pressed do (edt_path.text = ""; _51W_Data.exportPath = ""; saveScenePath "")
    on btn_open pressed do (if edt_path.text != "" and doesFileExist edt_path.text do shellLaunch "explorer.exe" edt_path.text)

    on btn_export pressed do (
        _51W_Telemetry.track "feature_used" props:#("feature", "FBXExport")
        local objs = selection as array
        if objs.count == 0 do (messageBox "请先选择模型。" title:"FBX导出"; return ())
        local ep = edt_path.text
        if ep == "" do (messageBox "请先设置导出路径。" title:"FBX导出"; return ())
        makeDir ep all:true

        if rdo_mode.state == 1 then (
            -- 导出期间挂起选择变化回调与场景重绘，避免每次 select 触发预览刷新拖慢批量导出
            callbacks.removeScripts id:#rl_FBXExport_SelChg
            disableSceneRedraw()
            try (
                undo "FBX Export" on (
                    -- FBX全局设置（只设一次）
                    for s in #(#("SmoothingGroups",true),#("Triangulate",false),#("EmbedTextures",false),
                        #("FileVersion","FBX201800"),#("UpAxis","Z"),#("ConvertUnit","cm"),
                        #("Animation",false),#("Skin",false),#("Shape",false),#("Cameras",false),#("Lights",false),
                        #("GenerateLog",false),#("ShowWarnings",false)) do
                        FBXExporterSetParam s[1] s[2]

                    local showDlg = chk_dlg.checked
                    for obj in objs do (
                        local op = obj.pos
                        local ucx = if chk_ucx.checked then (for o in objects where matchPattern o.name pattern:("UCX_" + obj.name + "*") collect o) else #()
                        if chk_origin.checked do (obj.pos = [0,0,0]; for u in ucx do u.pos -= op)
                        select (join #(obj) ucx)
                        local fp = ep + "\\" + obj.name + ".fbx"
                        local ok = true
                        try (
                            if showDlg then (
                                ok = exportFile fp selectedOnly:true using:FBXEXP
                                showDlg = false  -- 批量导出仅在第一个模型时弹设置框，后续沿用
                            ) else exportFile fp #noPrompt selectedOnly:true using:FBXEXP
                        ) catch (ok = false)
                        -- 无论导出成败都还原位置，避免异常把物体留在原点
                        if chk_origin.checked do (obj.pos = op; for u in ucx do u.pos += op)
                        -- 用户在设置框点“取消/否”或导出异常时，中断整批导出（用 exit 确保后续恢复回调）
                        if ok == false do exit
                    )
                    select objs
                )
            ) catch ()
            enableSceneRedraw()
            -- 恢复选择变化回调并刷新一次预览
            callbacks.removeScripts id:#rl_FBXExport_SelChg
            callbacks.addScript #selectionSetChanged "try(rl_FBXExport.refreshPreview())catch()" id:#rl_FBXExport_SelChg
            completeRedraw()
            refreshPreview()
        ) else (
            local s = ""
            for obj in objs do s += obj.name + " @ [" + obj.pos.x as string + "," + obj.pos.y as string + "," + obj.pos.z as string + "]\n"
            setClipBoardText s
            messageBox ("已复制 " + objs.count as string + " 个位置到剪切板。") title:"FBX导出"
        )
    )
)


-- 5. 常用工具
rollout rl_CommonTools "常用工具" width:464 (
    button btn_clr "清理空物体" pos:[14,8] width:436 height:26
    button btn_ctr "归轴至中心" pos:[14,40] width:212 height:26
    button btn_bot "归轴至底部" pos:[238,40] width:212 height:26
    button btn_top "归轴至顶部" pos:[14,72] width:212 height:26
    button btn_org "归轴至原点" pos:[238,72] width:212 height:26
    button btn_rst "一键重置变换" pos:[14,104] width:436 height:26
    groupBox gbTexPow2 "贴图2次幂化 | 选中对象后点击" pos:[0,138] width:228 height:65
    button btn_pow2_native "贴图尺寸2次幂化" pos:[14,162] width:200 height:28
    groupBox gbNmap "生成法线 | 材质编辑器选中材质" pos:[236,138] width:228 height:65
    button btn_nmap_native "生成法线贴图" pos:[250,162] width:200 height:28

    fn selObjs = (local o = selection as array; if o.count == 0 do return #(); o)

    fn nearestPow2 v = (
        if v <= 1 do return 1
        local p = 1
        while p < v do p *= 2
        if (p - v) <= (v - p/2) then p else p/2
    )

    fn resizeBitmapNative fp nw nh = (
        local srcBmp = undefined
        local dstBmp = undefined
        local ok = false
        try (
            srcBmp = openBitmap fp
            local ow = srcBmp.width
            local oh = srcBmp.height
            if ow <= 0 or oh <= 0 do throw "源贴图尺寸无效"

            local rows = for y = 0 to (oh - 1) collect (getPixels srcBmp [0, y] ow)
            close srcBmp
            srcBmp = undefined

            dstBmp = bitmap nw nh filename:fp
            for y = 1 to nh do (
                local sy = 1 + floor (((y - 1) as float / nh) * oh)
                if sy > oh do sy = oh
                local srcRow = rows[sy]
                local outRow = #()
                outRow.count = nw
                for x = 1 to nw do (
                    local sx = 1 + floor (((x - 1) as float / nw) * ow)
                    if sx > ow do sx = ow
                    outRow[x] = srcRow[sx]
                )
                setPixels dstBmp [0, y - 1] outRow
            )
            save dstBmp
            ok = true
        ) catch (
            format "[Pow2] 缩放失败: % | %\n" fp (getCurrentException())
        )
        if srcBmp != undefined do (try (close srcBmp) catch ())
        if dstBmp != undefined do (try (close dstBmp) catch ())
        ok
    )

    fn collectBmps node result = (
        if node == undefined do return ()
        if classOf node == BitmapTexture do appendIfUnique result node
        if classOf node == MultiMaterial do (
            for i = 1 to node.materialList.count where node.materialList[i] != undefined do collectBmps node.materialList[i] result
            return ()
        )
        local n = 0; try (n = getNumSubTexmaps node) catch ()
        for i = 1 to n do try (local s = getSubTexmap node i; if s != undefined do collectBmps s result) catch ()
    )

    on btn_clr pressed do undo "Clear Empty" on (
        local d = 0
        for obj in (for o in objects where _51W_Data.isEmptyObject o collect o) do (try (delete obj; d += 1) catch ())
        messageBox ("清理 " + d as string + " 个空物体。") title:"清理"
    )
    on btn_ctr pressed do (local o = selObjs(); if o.count > 0 do undo "Pivot Center" on (for obj in o do obj.pivot = obj.center))
    on btn_bot pressed do (local o = selObjs(); if o.count > 0 do undo "Pivot Bottom" on (
        for obj in o do (local bb = nodeGetBoundingBox obj (matrix3 1); obj.pivot = [(bb[1].x+bb[2].x)/2,(bb[1].y+bb[2].y)/2,bb[1].z])
    ))
    on btn_top pressed do (local o = selObjs(); if o.count > 0 do undo "Pivot Top" on (
        for obj in o do (local bb = nodeGetBoundingBox obj (matrix3 1); obj.pivot = [(bb[1].x+bb[2].x)/2,(bb[1].y+bb[2].y)/2,bb[2].z])
    ))
    on btn_org pressed do (local o = selObjs(); if o.count > 0 do undo "Pivot Origin" on (for obj in o do obj.pivot = [0,0,0]))
    on btn_rst pressed do (
        local o = selObjs()
        if o.count == 0 do (messageBox "请先选择对象。" title:"重置变换"; return ())
        undo "Reset XForm" on (for obj in o do (resetXForm obj; collapseStack obj))
        messageBox "重置变换完成！" title:"重置变换"
    )
    fn trackFeatureUsedSafe featureName = (
        try (
            if _51W_Telemetry != undefined and isProperty _51W_Telemetry #track do (
                _51W_Telemetry.track "feature_used" props:#("feature", featureName)
            )
        ) catch (
            format "[Telemetry] track feature failed: % | %\n" featureName (getCurrentException())
        )
    )

    fn doPow2 = (
        try (
            trackFeatureUsedSafe "TexturePow2"
            local objs = selObjs()
            if objs.count == 0 do (messageBox "请先选择对象。" title:"贴图2次幂化"; return ())
            local processed = #(); local ok = 0; local fail = 0; local skip = 0
            for obj in objs where obj.material != undefined do (
                local bms = #(); collectBmps obj.material bms
                for bmp in bms do (
                    local fp = bmp.filename
                    if fp == undefined or fp == "" do continue
                    -- 尝试解析完整路径
                    if not doesFileExist fp do (
                        local resolved = mapPaths.getFullFilePath fp
                        if resolved != undefined and resolved != "" do fp = resolved
                    )
                    if findItem processed fp > 0 do continue
                    append processed fp
                    if not doesFileExist fp do (fail += 1; continue)
                    local img = undefined
                    try (
                        img = openBitmap fp
                        local ow = img.width; local oh = img.height
                        local nw = nearestPow2 ow; local nh = nearestPow2 oh
                        if nw != ow or nh != oh then (
                            close img
                            img = undefined
                            if resizeBitmapNative fp nw nh then ok += 1 else fail += 1
                        ) else (close img; skip += 1)
                    ) catch (fail += 1; format "[Pow2] 处理失败: % | %\n" fp (getCurrentException()))
                    if img != undefined do (try (close img) catch ())
                )
            )
            local msg = "修改: " + ok as string
            if skip > 0 do msg += "  已是2次幂: " + skip as string
            if fail > 0 do msg += "  失败: " + fail as string
            messageBox msg title:"贴图2次幂化"
        ) catch (
            local err = (getCurrentException()) as string
            format "[Pow2] 顶层异常: %\n" err
            messageBox ("执行失败: " + err) title:"贴图2次幂化"
        )
    )

    fn doNmap = (
        _51W_Telemetry.track "feature_used" props:#("feature", "NormalMapGen")
        -- 获取材质编辑器中当前选中的材质
        local m = medit.GetCurMtl()
        if m == undefined do (messageBox "请先在材质编辑器中选择一个材质。" title:"生成法线"; return ())
        -- 如果选中的是MultiMaterial,提示选择子材质
        if classOf m == MultiMaterial do (messageBox "请选择具体的子材质，而非多维材质。" title:"生成法线"; return ())

        local hasBump = false; local diffTex = undefined
        if classOf m == StandardMaterial then (
            hasBump = m.bumpMap != undefined
            if m.diffuseMap != undefined and classOf m.diffuseMap == BitmapTexture do diffTex = m.diffuseMap
        ) else if classOf m == PhysicalMaterial then (
            hasBump = m.bump_map != undefined
            if m.base_color_map != undefined and classOf m.base_color_map == BitmapTexture do diffTex = m.base_color_map
        ) else (messageBox ("不支持的材质类型: " + (classOf m) as string) title:"生成法线"; return ())

        if hasBump do (messageBox "该材质已有法线/凹凸贴图。" title:"生成法线"; return ())
        if diffTex == undefined do (messageBox "该材质没有漫反射贴图，无法生成法线。" title:"生成法线"; return ())

        local srcPath = diffTex.filename
        if srcPath == undefined or srcPath == "" do (messageBox "贴图文件路径为空。" title:"生成法线"; return ())
        if not doesFileExist srcPath do (
            local resolved = mapPaths.getFullFilePath srcPath
            if resolved != undefined and resolved != "" then srcPath = resolved
            else (messageBox ("找不到贴图文件: " + srcPath) title:"生成法线"; return ())
        )
        if not doesFileExist srcPath do (messageBox ("找不到贴图文件: " + srcPath) title:"生成法线"; return ())

        local dir = getFilenamePath srcPath
        local base = getFilenameFile srcPath
        local dstPath = dir + base + "_N.png"
        local str = 2.0

        local img = undefined
        local dst = undefined
        try (
            img = openBitmap srcPath
            local w = img.width; local h = img.height
            local rows = for y = 0 to h-1 collect getPixels img [0, y] w
            close img

            dst = bitmap w h filename:dstPath
            for y = 1 to h do (
                local nrow = #()
                local yu = amax 1 (y-1); local yd = amin h (y+1)
                for x = 1 to w do (
                    local xl = amax 1 (x-1); local xr = amin w (x+1)
                    local pL = rows[y][xl]; local pR = rows[y][xr]
                    local pU = rows[yu][x]; local pD = rows[yd][x]
                    local hL = pL.r * 0.299 + pL.g * 0.587 + pL.b * 0.114
                    local hR = pR.r * 0.299 + pR.g * 0.587 + pR.b * 0.114
                    local hU = pU.r * 0.299 + pU.g * 0.587 + pU.b * 0.114
                    local hD = pD.r * 0.299 + pD.g * 0.587 + pD.b * 0.114
                    local dx = (hL - hR) / 255.0 * str
                    local dy = (hU - hD) / 255.0 * str
                    local dz = 1.0
                    local ln = sqrt (dx*dx + dy*dy + dz*dz)
                    local nr = amin 255 (amax 0 ((dx/ln * 0.5 + 0.5) * 255.0))
                    local ng = amin 255 (amax 0 ((dy/ln * 0.5 + 0.5) * 255.0))
                    local nb = amin 255 (amax 0 ((dz/ln * 0.5 + 0.5) * 255.0))
                    append nrow (color nr ng nb)
                )
                setPixels dst [0, y-1] nrow
            )
            save dst
            close dst

            local nBmp = BitmapTexture name:(base + "_N") filename:dstPath
            if classOf m == StandardMaterial then (
                local nb = Normal_Bump()
                nb.normal_map = nBmp
                m.bumpMap = nb
            ) else if classOf m == PhysicalMaterial then (
                m.bump_map = nBmp
            )
            messageBox ("法线贴图已生成并应用!\n" + (filenameFromPath dstPath)) title:"生成法线"
        ) catch (messageBox ("生成失败: " + (getCurrentException()) as string) title:"生成法线")
        if img != undefined do (try (close img) catch ())
        if dst != undefined do (try (close dst) catch ())
    )

    on btn_pow2_native pressed do (try (doPow2()) catch (messageBox (getCurrentException()) title:"错误"))
    on btn_nmap_native pressed do (try (doNmap()) catch (messageBox (getCurrentException()) title:"错误"))
)


-- 6. 样条线工具
rollout rl_SplineTools "样条线工具" (
    groupBox gbSpline1 "样条线简化 | 选中样条线后点击" pos:[0,0] width:464 height:65
    groupBox gbSpline2 "管道UV密度统一 | Sweep管道纹素密度一致化" pos:[0,70] width:464 height:105
    groupBox gbSpline3 "截面扫描生成 | 截面 + 路径 → 智能Sweep（直线不分段）" pos:[0,180] width:464 height:145

    label lblAngle "角度阈值：" pos:[14,30] width:58 height:18
    spinner spnAngleCtrl "" range:[0.1, 45.0, 5.0] type:#float fieldWidth:30 pos:[64,29] width:46 height:22
    button btnSimp "简化样条线" pos:[150,26] width:200 height:26

    label lblDir "缩放轴：" pos:[14,94] width:50 height:18
    radioButtons rbDirNative "" labels:#("V", "U") columns:2 default:1 pos:[64,92] width:70 height:20
    label lblTip "(V=沿路径方向, U=截面环绕方向)" pos:[142,94] width:280 height:18
    label lblDensity "自定义密度 UV/cm：" pos:[14,120] width:108 height:18
    spinner spnDensityCtrl "" range:[0.00001, 10000.0, 0.01] type:#float fieldWidth:46 pos:[108,119] width:62 height:22
    button btnPreview "预览信息" pos:[14,148] width:200 height:26
    button btnNormalize "统一UV密度" pos:[236,148] width:200 height:26

    button btnPickCross "拾取截面..." pos:[14,198] width:110 height:26
    label lblCrossName "(未拾取)" pos:[130,203] width:320 height:18
    button btnPickPath "拾取路径..." pos:[14,230] width:110 height:26
    label lblPathName "(未拾取)" pos:[130,235] width:320 height:18
    label lblSteps "细分步数(0=用样条线steps)：" pos:[14,264] width:162 height:18
    spinner spnSteps "" range:[0, 64, 0] type:#integer fieldWidth:22 pos:[158,263] width:38 height:22
    checkbox chkCap "端点封盖" checked:true pos:[14,292] width:80 height:20
    checkbox chkFlip "翻转法线" checked:false pos:[100,292] width:80 height:20
    button btnGo "生成模型" pos:[250,290] width:200 height:26

    -- 截面扫描生成 状态
    local pickedCross = undefined, pickedPath = undefined

    -- 获取每条子样条线的独立长度（临时禁用修改器读取底层样条线）
    fn getSplineLengths obj = (
        local lengths = #()
        local disabledMods = #()
        for m in obj.modifiers where m.enabled do (append disabledMods m; m.enabled = false)
        try (for s = 1 to (numSplines obj) do append lengths (curveLength obj s)) catch ()
        for m in disabledMods do m.enabled = true
        lengths
    )

    -- 获取厘米/系统单位换算比
    fn getCmPerUnit = (
        local t = units.SystemType
        local b = case t of (#Inches:2.54; #Feet:30.48; #Miles:160934.0; #Millimeters:0.1; #Centimeters:1.0; #Meters:100.0; #Kilometers:100000.0; default:1.0)
        units.SystemScale * b
    )

    -- 移除之前脚本添加的 PipeUVNorm 修改器
    fn removeOldMods obj = (
        for i = obj.modifiers.count to 1 by -1 do (
            if obj.modifiers[i].name == "PipeUVNorm" do deleteModifier obj obj.modifiers[i]
        )
    )

    -----------------------------------------------------------------
    -- 截面扫描生成：辅助函数
    -----------------------------------------------------------------
    -- 安全归一化：长度接近 0 时返回 fallback
    fn safeNormalize v fallback = (
        if (length v) < 0.0001 then fallback else (normalize v)
    )

    -- Cubic Bezier 求值
    fn bezEval p0 p1 p2 p3 t = (
        local u = 1.0 - t
        u*u*u*p0 + 3*u*u*t*p1 + 3*u*t*t*p2 + t*t*t*p3
    )
    -- Cubic Bezier 切线（未归一化）
    fn bezTan p0 p1 p2 p3 t = (
        local u = 1.0 - t
        3*u*u*(p1-p0) + 6*u*t*(p2-p1) + 3*t*t*(p3-p2)
    )

    -- 判定一段（knot k 到 k+1）是否为直线
    fn isStraightSeg obj si k p0 p1 p2 p3 = (
        local segType = try (getSegmentType obj si k) catch (#curve)
        if segType == #line then true
        else (
            -- 即便类型为 curve，若控制柄退化成端点（无张力），也视为直线
            local d = distance p0 p3
            if d < 0.0001 then true
            else (
                local dir = normalize (p3 - p0)
                local off1 = (p1 - p0) - (dot (p1-p0) dir) * dir
                local off2 = (p2 - p3) - (dot (p2-p3) dir) * dir
                (length off1) < (d * 0.001) and (length off2) < (d * 0.001)
            )
        )
    )

    -- 单条子样条线采样：返回 #(pos, tangent) 数组（切线已归一化）
    -- stepsOverride: 曲线段细分数（每段 nSub 个等步），<=0 表示用样条线自身的 steps
    fn samplePathSpline obj si stepsOverride = (
        local samples = #()
        local nK = numKnots obj si
        if nK < 2 do return samples
        local closed = isClosed obj si
        local nSeg = if closed then nK else (nK - 1)

        for k = 1 to nSeg do (
            local kNext = if k == nK then 1 else (k + 1)
            local p0 = getKnotPoint obj si k
            local p3 = getKnotPoint obj si kNext
            local p1 = try (getOutVec obj si k) catch (p0)
            local p2 = try (getInVec obj si kNext) catch (p3)

            local straight = isStraightSeg obj si k p0 p1 p2 p3
            local segDir = if (distance p0 p3) > 0.0001 then normalize (p3 - p0) else [1,0,0]

            -- 起点（每段都发，便于合并阶段算 miter）
            local startTanForEmit = if straight then segDir else (safeNormalize (bezTan p0 p1 p2 p3 0.0) segDir)
            append samples #(p0, startTanForEmit)

            if straight then (
                -- 直线段：只追加终点
                append samples #(p3, segDir)
            ) else (
                -- 曲线段：按样条线的 steps 属性等步细分（与样条线显示一致）
                local nSub = if stepsOverride > 0 then stepsOverride else (try (obj.steps + 1) catch (6))
                if nSub < 1 do nSub = 1
                for i = 1 to nSub do (
                    local t = (i as float) / nSub
                    local pos = bezEval p0 p1 p2 p3 t
                    append samples #(pos, safeNormalize (bezTan p0 p1 p2 p3 t) segDir)
                )
            )
        )

        -- 闭合路径：去掉重复的尾点（与首点重合）
        if closed and samples.count > 1 do (
            local last = samples[samples.count][1]
            local first = samples[1][1]
            if (distance last first) < 0.0001 do deleteItem samples samples.count
        )
        samples
    )

    -- 用固定世界上方向（Z）构建每个 frame，避免 parallel transport 沿路径累积扭转
    -- 返回数组：每个元素 #(pos, xAxis, yAxis, zAxis, scl)，z = 切线，scl = miter 横向缩放
    fn buildFrames samples =
    (
        local frames = #()
        if samples.count == 0 do return frames
        local worldUp = [0,0,1]
        for i = 1 to samples.count do (
            local pos = samples[i][1]
            local curT = samples[i][2]
            local scl = if samples[i].count >= 3 then samples[i][3] else 1.0
            -- 切线几乎平行 Z 时换 Y 作为参考，避免叉乘退化
            local up = if (abs (dot curT worldUp)) > 0.99 then [0,1,0] else worldUp
            local xA = normalize (cross up curT)
            local yA = normalize (cross curT xA)
            append frames #(pos, xA, yA, curT, scl)
        )
        frames
    )

    -- 从模型边界提取轮廓，返回 point2 数组 + 是否闭合（在模型自身局部坐标的 XY 平面）
    fn getCrossSectionFromMesh obj = (
        local result = #(#(), false)
        local tmpMesh = snapshotAsMesh obj
        if tmpMesh == undefined do return result
        -- 收集开放边（只属于一个面的边）
        local keys = #(); local counts = #(); local pairs = #()
        for fi = 1 to tmpMesh.numfaces do (
            local f = getFace tmpMesh fi
            local va = #(f.x as integer, f.y as integer, f.z as integer)
            for ei = 1 to 3 do (
                local a = va[ei]
                local b = va[(mod ei 3) + 1]
                if a > b do (local t = a; a = b; b = t)
                local key = (a as string) + "_" + (b as string)
                local idx = findItem keys key
                if idx == 0 then (
                    append keys key; append counts 1; append pairs #(a, b)
                ) else (
                    counts[idx] = counts[idx] + 1
                )
            )
        )
        local boundary = #()
        for i = 1 to keys.count do (
            if counts[i] == 1 do append boundary pairs[i]
        )
        if boundary.count < 2 do (delete tmpMesh; return result)
        -- 把边连成有序环：从第一条边开始，按相连关系串
        local used = #()
        for i = 1 to boundary.count do append used false
        local ordered = #()
        local cur = boundary[1]; used[1] = true
        append ordered cur[1]; append ordered cur[2]
        local lastV = cur[2]
        local closed = false
        local foundNext = true
        while foundNext do (
            foundNext = false
            for i = 1 to boundary.count while not foundNext do (
                if not used[i] do (
                    local e = boundary[i]
                    if e[1] == lastV then (
                        append ordered e[2]; lastV = e[2]; used[i] = true; foundNext = true
                    ) else if e[2] == lastV do (
                        append ordered e[1]; lastV = e[1]; used[i] = true; foundNext = true
                    )
                )
            )
        )
        if ordered.count >= 3 and ordered[1] == ordered[ordered.count] do (
            closed = true; deleteItem ordered ordered.count
        )
        local pts3 = #()
        for vi in ordered do append pts3 (getVert tmpMesh vi)
        delete tmpMesh
        if pts3.count < 2 do return result
        -- 计算 AABB，找最薄的轴作为法线方向，把另外两个轴用作截面 2D
        local mn = copy pts3[1]; local mx = copy pts3[1]
        for p in pts3 do (
            if p.x < mn.x do mn.x = p.x
            if p.y < mn.y do mn.y = p.y
            if p.z < mn.z do mn.z = p.z
            if p.x > mx.x do mx.x = p.x
            if p.y > mx.y do mx.y = p.y
            if p.z > mx.z do mx.z = p.z
        )
        local ex = mx.x - mn.x; local ey = mx.y - mn.y; local ez = mx.z - mn.z
        local axisU = 1; local axisV = 2  -- 1=x,2=y,3=z
        if ez <= ex and ez <= ey then ( axisU = 1; axisV = 2 )
        else if ey <= ex and ey <= ez then ( axisU = 1; axisV = 3 )
        else ( axisU = 2; axisV = 3 )
        -- 计算质心（在选定的两轴上）以居中
        local cu = 0.0; local cv = 0.0
        for p in pts3 do (
            local u = (if axisU == 1 then p.x else if axisU == 2 then p.y else p.z)
            local v2 = (if axisV == 1 then p.x else if axisV == 2 then p.y else p.z)
            cu = cu + u; cv = cv + v2
        )
        cu = cu / pts3.count; cv = cv / pts3.count
        local pts = #()
        for p in pts3 do (
            local u = (if axisU == 1 then p.x else if axisU == 2 then p.y else p.z)
            local v2 = (if axisV == 1 then p.x else if axisV == 2 then p.y else p.z)
            append pts (point2 (u - cu) (v2 - cv))
        )
        result[1] = pts; result[2] = closed
        result
    )

    -- 从截面样条线提取顶点（投影到 XY 平面），返回 point2 数组 + 是否闭合
    -- 截面以其自身坐标系的 XY 平面为准（Z 视作沿路径方向）
    fn getCrossSection obj = (
        local result = #(#(), false)
        if not (isKindOf obj SplineShape or isKindOf obj line) do (
            -- 模型对象走另一条路径：提取边界
            if isKindOf obj GeometryClass do return (getCrossSectionFromMesh obj)
            return result
        )
        if (numSplines obj) < 1 do return result
        local si = 1
        local nK = numKnots obj si
        if nK < 2 do return result
        local closed = isClosed obj si
        local pts = #()
        for k = 1 to (if closed then nK else nK-1) do (
            local kNext = if k == nK then 1 else (k + 1)
            local p0 = getKnotPoint obj si k
            local p3 = getKnotPoint obj si kNext
            local p1 = try (getOutVec obj si k) catch (p0)
            local p2 = try (getInVec obj si kNext) catch (p3)
            local straight = isStraightSeg obj si k p0 p1 p2 p3
            if k == 1 do append pts (point2 p0.x p0.y)
            if straight then (
                append pts (point2 p3.x p3.y)
            ) else (
                local nSub = 6
                for i = 1 to nSub do (
                    local t = (i as float) / nSub
                    local q = bezEval p0 p1 p2 p3 t
                    append pts (point2 q.x q.y)
                )
            )
        )
        if closed and pts.count > 1 do (
            local last = pts[pts.count]; local first = pts[1]
            if (distance last first) < 0.0001 do deleteItem pts pts.count
        )
        result[1] = pts; result[2] = closed
        result
    )

    fn buildSweepMesh framesArr crossPts crossClosed pathClosed capEnds nodeName flipNormals = (
        local nF = framesArr.count
        local nC = crossPts.count
        if nF < 2 or nC < 2 do return undefined

        -- 顶点
        local verts = #()
        for f = 1 to nF do (
            local fr = framesArr[f]
            local origin = fr[1]; local xA = fr[2]; local yA = fr[3]
            local scl = if fr.count >= 5 then fr[5] else 1.0
            for c = 1 to nC do (
                local cp = crossPts[c]
                append verts (origin + xA * (cp.x * scl) + yA * cp.y)
            )
        )

        -- 身体三角面 + 记录每个 quad 的对角线顶点对（key set，O(E) 查找）
        local faces = #()
        local diagKeys = #{}
        local ringSegs = if crossClosed then nC else (nC - 1)
        local pathSegs = if pathClosed then nF else (nF - 1)
        local totalVerts = nF * nC
        for f = 1 to pathSegs do (
            local fNext = if f == nF then 1 else (f + 1)
            local baseA = (f - 1) * nC
            local baseB = (fNext - 1) * nC
            for c = 1 to ringSegs do (
                local cNext = if c == nC then 1 else (c + 1)
                local v00 = baseA + c
                local v01 = baseA + cNext
                local v10 = baseB + c
                local v11 = baseB + cNext
                if flipNormals then (
                    append faces [v00, v10, v11]
                    append faces [v00, v11, v01]
                ) else (
                    append faces [v00, v01, v11]
                    append faces [v00, v11, v10]
                )
                -- 把 (min,max) 编码成单个整数 key：a * (totalVerts+1) + b
                local da = v00; local db = v11
                if da > db do (local t = da; da = db; db = t)
                diagKeys[da * (totalVerts + 1) + db] = true
            )
        )

        local m = mesh vertices:verts faces:faces name:nodeName
        convertToPoly m

        -- 删除对角线边，把三角对合并成 quad（O(E) 查找）
        local diagEdgeSel = #{}
        local nE = polyop.getNumEdges m
        for e = 1 to nE do (
            local vs = polyop.getEdgeVerts m e
            local a = vs[1]; local b = vs[2]
            if a > b do (local t = a; a = b; b = t)
            if diagKeys[a * (totalVerts + 1) + b] do diagEdgeSel[e] = true
        )
        if diagEdgeSel.numberSet > 0 do (
            polyop.setEdgeSelection m diagEdgeSel
            m.EditablePoly.remove selLevel:#Edge
        )

        -- 端盖 ngon：直接在 poly 上 createPolygon
        if capEnds and (not pathClosed) and crossClosed and nC >= 3 do (
            local startIdx = #()
            if flipNormals then (for c = 1 to nC do append startIdx c)
            else (for c = nC to 1 by -1 do append startIdx c)
            polyop.createPolygon m startIdx

            local endBase = (nF - 1) * nC
            local endIdx = #()
            if flipNormals then (for c = nC to 1 by -1 do append endIdx (endBase + c))
            else (for c = 1 to nC do append endIdx (endBase + c))
            polyop.createPolygon m endIdx
        )
        update m
        m
    )

    -- 合并位置重合（拐角处）的连续采样：用平分线作为切线（miter）
    -- 同时计算 miter 横向缩放：1/cos(θ/2)，避免拐角处截面变窄
    fn mergeMiterSamples samples = (
        local merged = #()
        if samples.count == 0 do return merged
        append merged #(samples[1][1], samples[1][2], 1.0)
        for i = 2 to samples.count do (
            local last = merged[merged.count]
            if (distance last[1] samples[i][1]) < 0.001 then (
                local t1 = last[2]; local t2 = samples[i][2]
                local avgTraw = t1 + t2
                local avgT = safeNormalize avgTraw t2
                local scl = 1.0
                if (length avgTraw) >= 0.0001 do (
                    local d = dot avgT t2
                    if d > 0.001 do scl = 1.0 / d
                )
                merged[merged.count] = #(last[1], avgT, scl)
            ) else (
                append merged #(samples[i][1], samples[i][2], 1.0)
            )
        )
        merged
    )

    fn doSweepBuild = (
        _51W_Telemetry.track "feature_used" props:#("feature", "SplineSweep")
        if pickedCross == undefined or pickedPath == undefined do (
            messageBox "请先拾取截面与路径样条线。" title:"截面扫描生成"; return ()
        )
        if not (isKindOf pickedCross SplineShape or isKindOf pickedCross line or isKindOf pickedCross GeometryClass) do (
            messageBox "截面对象类型不支持。" title:"截面扫描生成"; return ()
        )
        if not (isKindOf pickedPath SplineShape or isKindOf pickedPath line) do (
            messageBox "路径对象不是样条线。" title:"截面扫描生成"; return ()
        )

        local stepsOverride = if spnSteps != undefined then (spnSteps.value as integer) else 0
        local capEnds = if chkCap != undefined then (chkCap.Checked) else true
        local flipN = if chkFlip != undefined then (chkFlip.Checked) else false

        -- 截面：在自身局部坐标取顶点
        local crossInfo = getCrossSection pickedCross
        local crossPts = crossInfo[1]
        local crossClosed = crossInfo[2]
        if crossPts.count < 2 do (
            messageBox "截面顶点不足。" title:"截面扫描生成"; return ()
        )

        -- 路径：遍历每条子样条线，每段生成一个 mesh，最后 attach 到一起
        local pathObj = pickedPath
        local nSpl = numSplines pathObj
        local builtNodes = #()
        undo "截面扫描生成" on (
            for si = 1 to nSpl do (
                local samples = samplePathSpline pathObj si stepsOverride
                if samples.count < 2 do continue
                local merged = mergeMiterSamples samples
                local closedSpl = isClosed pathObj si
                local frames = buildFrames merged
                local nm = uniqueName "SplineSweep_"
                local m = buildSweepMesh frames crossPts crossClosed closedSpl capEnds nm flipN
                if m != undefined do append builtNodes m
            )
            if builtNodes.count == 0 do (
                messageBox "未生成任何模型。" title:"截面扫描生成"; return ()
            )
            -- 合并所有片段
            local main = builtNodes[1]
            for i = 2 to builtNodes.count do (
                polyop.attach main builtNodes[i] deleteSourceNode:true
            )
            main.name = uniqueName "SplineSweepMesh_"
            select main
        )
    )

    -----------------------------------------------------------------

    fn doPickCross = (
        local o = pickObject prompt:"选择截面对象（样条线或模型）"
        if o != undefined and isValidNode o do (
            pickedCross = o
            try (if lblCrossName != undefined do lblCrossName.text = o.name) catch (            )
        )

    )

    fn doPickPath = (
        local o = pickObject prompt:"选择路径样条线" filter:(fn splineFilter obj = isKindOf obj SplineShape or isKindOf obj line)
        if o != undefined and isValidNode o do (
            pickedPath = o
            try (if lblPathName != undefined do lblPathName.text = o.name) catch ()
        )
    )

    fn doSplineSimp = (
        _51W_Telemetry.track "feature_used" props:#("feature", "SplineSimplify")
        local objs = selection as array
        if objs.count == 0 do (messageBox "请先选择样条线对象。" title:"样条线简化"; return ())
        local angThresh = if spnAngleCtrl != undefined then (spnAngleCtrl.value as float) else 5.0
        local totalRemoved = 0; local totalObj = 0
        undo "Spline Simplify" on (
            for obj in objs do (
                if superClassOf obj != Shape do continue
                local ss = obj.baseObject
                if not (isKindOf ss SplineShape or isKindOf ss line) do (
                    convertToSplineShape obj
                    ss = obj.baseObject
                    if not (isKindOf ss SplineShape or isKindOf ss line) do continue
                )
                -- 先把样条统一成角点，避免删除 knot 后手柄把线拉出尖刺
                for si = 1 to (numSplines obj) do (
                    local nk = numKnots obj si
                    for ki = 1 to nk do (
                        local kp = getKnotPoint obj si ki
                        try (setKnotType obj si ki #corner) catch ()
                        try (setInVec obj si ki kp) catch ()
                        try (setOutVec obj si ki kp) catch ()
                    )
                )
                local objRemoved = 0
                for si = 1 to (numSplines obj) do (
                    local nk = numKnots obj si
                    if nk < 3 do continue
                    local spClosed = isClosed obj si
                    local startK = if spClosed then nk else (nk - 1)
                    local endK = if spClosed then 1 else 2
                    for ki = startK to endK by -1 do (
                        local nk2 = numKnots obj si
                        if nk2 < 3 do exit
                        local prevK = if ki == 1 then (if spClosed then nk2 else continue) else (ki - 1)
                        local nextK = if ki == nk2 then (if spClosed then 1 else continue) else (ki + 1)
                        local pPrev = getKnotPoint obj si prevK
                        local pCur = getKnotPoint obj si ki
                        local pNext = getKnotPoint obj si nextK
                        local v1 = normalize (pPrev - pCur)
                        local v2 = normalize (pNext - pCur)
                        local ang = acos (amax -1.0 (amin 1.0 (dot v1 v2)))
                        local deviation = 180.0 - ang
                        if deviation < angThresh do (
                            deleteKnot obj si ki
                            objRemoved += 1
                        )
                    )
                )
                updateShape obj
                if objRemoved > 0 do (totalRemoved += objRemoved; totalObj += 1)
            )
        )
        messageBox (totalObj as string + " 个样条线共删除 " + totalRemoved as string + " 个节点。") title:"样条线简化"
    )

    fn doUVPreview = (
        local objs = selection as array
        if objs.count == 0 do (messageBox "请先选择管道对象。" title:"UV密度预览"; return ())
        local msg = ""
        for obj in objs do (
            local lens = getSplineLengths obj
            if lens.count > 0 then (
                msg += obj.name + ":  "
                if lens.count == 1 then msg += (formattedPrint lens[1] format:".2f") + " units\n"
                else (
                    msg += lens.count as string + " splines ["
                    for j = 1 to lens.count do (if j > 1 do msg += ", "; msg += (formattedPrint lens[j] format:".2f"))
                    msg += "]\n"
                )
            ) else msg += obj.name + ":  [非样条线]\n"
        )
        messageBox msg title:"管道样条线长度"
    )

    fn doUVNormalize = (
        _51W_Telemetry.track "feature_used" props:#("feature", "PipeUVNormalize")
        local objs = selection as array
        if objs.count == 0 do (messageBox "请先选择管道对象。" title:"UV密度统一"; return ())

        -- 收集有效对象和各子样条线长度
        local pipeData = #()
        for obj in objs do (
            local lens = getSplineLengths obj
            if lens.count > 0 do append pipeData #(obj, lens)
        )
        if pipeData.count == 0 do (messageBox "未找到有效的样条线长度。" title:"UV密度统一"; return ())

        -- 确定纹素密度
        local densVal = spnDensityCtrl.value as float
        local density = densVal / getCmPerUnit()

        local dirIdx = if rbDirNative.state == 1 then 1 else 2  -- 1=V轴, 2=U轴

        undo "统一管道UV密度" on (
            local count = 0
            for d in pipeData do (
                local obj = d[1]; local lens = d[2]
                removeOldMods obj

                if lens.count == 1 then (
                    local sf = lens[1] * density
                    local xf = Uvw_Xform(); xf.name = "PipeUVNorm"
                    addModifier obj xf
                    if dirIdx == 1 then (xf.U_Tile = 1.0; xf.V_Tile = sf) else (xf.U_Tile = sf; xf.V_Tile = 1.0)
                ) else (
                    -- 多子样条线: snapshotAsMesh + Unwrap_UVW 逐元素缩放
                    local theMesh = undefined
                    try (
                        theMesh = snapshotAsMesh obj
                        local numF = theMesh.numFaces
                        if numF > 0 and (meshop.getMapSupport theMesh 1) do (
                            local remaining = #{1..numF}
                            local elements = #()
                            while not remaining.isEmpty do (
                                local seed = (remaining as array)[1]
                                local elem = meshop.getElementsUsingFace theMesh #{seed}
                                append elements elem; remaining -= elem
                            )
                            local elemMapData = #()
                            for i = 1 to elements.count do (
                                local mapVertSet = #{}
                                for f in elements[i] do (
                                    local tvf = meshop.getMapFace theMesh 1 f
                                    mapVertSet[(tvf.x as integer)] = true
                                    mapVertSet[(tvf.y as integer)] = true
                                    mapVertSet[(tvf.z as integer)] = true
                                )
                                local vertInfo = for v in mapVertSet collect #(v, meshop.getMapVert theMesh 1 v)
                                append elemMapData vertInfo
                            )
                            local uwMod = Unwrap_UVW(); uwMod.name = "PipeUVNorm"
                            addModifier obj uwMod
                            local n = amin elemMapData.count lens.count
                            for i = 1 to n do (
                                local sf = lens[i] * density
                                for vd in elemMapData[i] do (
                                    local pos = vd[2]
                                    local newPos = if dirIdx == 1 then [pos.x, pos.y * sf, pos.z] else [pos.x * sf, pos.y, pos.z]
                                    uwMod.setVertexPosition currentTime vd[1] newPos
                                )
                            )
                            uwMod.setTVSubObjectMode 0
                        )
                    ) catch ()
                    if theMesh != undefined do (try (free theMesh) catch ())
                )
                count += 1
            )
            messageBox (count as string + " 个管道对象已统一UV密度。") title:"UV密度统一"
        )
    )

    on btnSimp pressed do (try (doSplineSimp()) catch (messageBox (getCurrentException()) title:"错误"))
    on btnPreview pressed do (try (doUVPreview()) catch (messageBox (getCurrentException()) title:"错误"))
    on btnNormalize pressed do (try (doUVNormalize()) catch (messageBox (getCurrentException()) title:"错误"))
    on btnPickCross pressed do (try (doPickCross()) catch (messageBox (getCurrentException()) title:"错误"))
    on btnPickPath pressed do (try (doPickPath()) catch (messageBox (getCurrentException()) title:"错误"))
    on btnGo pressed do (try (doSweepBuild()) catch (messageBox (getCurrentException()) title:"错误"))
)


-- 7. 批量导入\合并
rollout rl_BatchImport "批量导入\\合并" (
    label lbl_fl "文件列表：" align:#left
    editText edt_list "" height:120 readOnly:true fieldWidth:460 align:#center
    button btn_path "选择路径" width:80 height:24 align:#left offset:[10,0]
    label lbl_type "导入\\合并文件类型：" align:#center offset:[0,-26]
    radioButtons rdo_type labels:#("OBJ","3DS","FBX","DWG","MAX","ALL") default:3 columns:6
    checkbox chk_sub "包含子文件夹" checked:true align:#right offset:[-10,-24]
    button btn_ref "刷新" width:50 height:22 align:#right offset:[-10,0]
    button btn_go "开始导入" width:440 height:32 align:#center

    fn refresh p = (
        _51W_Data.batchFileList = _51W_Data.collectFiles p (_51W_Data.getFilePattern rdo_type.state) chk_sub.checked
        if rdo_type.state == 6 do (
            local v = #(".obj",".3ds",".fbx",".dwg",".max")
            _51W_Data.batchFileList = for f in _51W_Data.batchFileList where (findItem v (toLower (getFilenameType f))) > 0 collect f
        )
        local t = p + "\n"
        for f in _51W_Data.batchFileList do t += "  " + (filenameFromPath f) + "\n"
        edt_list.text = t + "\n共 " + _51W_Data.batchFileList.count as string + " 个文件"
    )

    on btn_path pressed do (local p = getSavePath caption:"选择导入文件夹"; if p != undefined do (_51W_Data.importBasePath = p; refresh p))
    on btn_ref pressed do (if _51W_Data.importBasePath != "" do refresh _51W_Data.importBasePath)

    on btn_go pressed do (
        _51W_Telemetry.track "feature_used" props:#("feature", "BatchImport")
        local fl = _51W_Data.batchFileList
        if fl.count == 0 do (messageBox "文件列表为空。" title:"批量导入"; return ())
        if not (queryBox ("导入 " + fl.count as string + " 个文件？") title:"批量导入") do return ()
        local ok = 0, ng = 0
        for f in fl do (
            try (
                if toLower (getFilenameType f) == ".max" then mergeMaxFile f #select #mergeDups #renameMtlDups quiet:true
                else if toLower (getFilenameType f) == ".fbx" then importFile f #noPrompt using:FBXIMP
                else importFile f #noPrompt
                ok += 1
            ) catch (ng += 1; format "导入失败: %\n" f)
        )
        messageBox ("成功: " + ok as string + "  失败: " + ng as string) title:"批量导入"
    )
)


-- 8. UVW
rollout rl_UnwrapUVW "UVW" width:464 (
    groupBox gbUVOp "UV操作" pos:[0,0] width:464 height:78
    button btn_flatten_native "一键平铺" pos:[14,20] width:436 height:24
    button btn_fillquad_native "全部占满一象限" pos:[14,50] width:130 height:24
    label lbl_padding_native "间距：" pos:[148,56] width:40 height:18
    spinner spn_padding_native "" range:[0.0, 0.5, 0.005] type:#float fieldWidth:38 scale:0.01 pos:[178,55] width:54 height:20
    button btn_filleach_native "每个UV占满一象限" pos:[260,50] width:190 height:24
    groupBox gbUVWBox "UVW Box（稳定模式）" pos:[0,84] width:464 height:60
    label lbl_uvwBoxSize "尺寸：" pos:[14,110] width:40 height:18
    spinner spn_uvwBoxSize "" range:[1.0, 1000000.0, 200.0] type:#float fieldWidth:46 pos:[44,109] width:62 height:20
    button btn_applyUVWBoxNative "应用 UVW Box" pos:[188,104] width:110 height:24
    checkbox chk_sameMatNative "同时作用于同材质物体" checked:false pos:[312,106] width:140 height:20

    fn isUVEditorOpen = (
        local hwnds = windows.getChildrenHWND 0
        for h in hwnds do (
            if h[5] != undefined do (
                local t = h[5] as string
                if (findString t "Edit" != undefined) and (findString t "UVW" != undefined) do return true
            )
        )
        false
    )

    fn getOrAddUnwrap obj ch:1 = (
        -- 查找已有的 Unwrap_UVW
        local found = undefined
        for m in obj.modifiers where classOf m == Unwrap_UVW do (found = m; exit)
        if found != undefined then (
            -- 检查当前修改面板是否已指向该修改器
            local cur = try (modPanel.getCurrentObject()) catch (undefined)
            if cur != found do (
                max modify mode
                modPanel.setCurrentObject found
            )
            if not (isUVEditorOpen()) do found.edit()
            found
        ) else (
            -- 没有则添加新的
            local uw = Unwrap_UVW()
            uw.setMapChannel ch
            addModifier obj uw
            max modify mode
            modPanel.setCurrentObject uw
            uw.edit()
            uw
        )
    )

    fn collectUVWTargets sameMat = (
        local result = #()
        for o in selection where superClassOf o == GeometryClass do appendIfUnique result o
        if sameMat do (
            -- 收集选中物体用到的所有材质
            local matSet = #()
            for o in result where o.material != undefined do (
                if (findItem matSet o.material) == 0 do append matSet o.material
            )
            -- 用 refs.dependents 反查每个材质的依赖物体（比遍历全场景快）
            for mtl in matSet do (
                local deps = refs.dependentNodes mtl
                for n in deps where superClassOf n == GeometryClass do appendIfUnique result n
            )
        )
        result
    )

    -- 返回 #(类型, 面选BitArray)；无选中面返回 undefined
    fn getObjFaceSel obj = (
        local sel = undefined
        try (
            local bo = obj.baseObject
            if isKindOf bo Editable_Poly then (
                local fs = polyop.getFaceSelection obj
                if fs.numberSet > 0 do sel = #(#poly, fs)
            ) else if isKindOf bo Editable_Mesh then (
                local fs = getFaceSelection obj
                if fs.numberSet > 0 do sel = #(#mesh, fs)
            )
        ) catch ()
        sel
    )

    -- 在物体顶部加"仅作用选中面"的 UVWMap（用 addModToSelection 尊重面选）
    fn addUVWToFaceSel obj faceInfo s = (
        local kind = faceInfo[1]
        local fs = faceInfo[2]
        -- 顶部已是 UVWMap 则复用（改参数），避免重复叠加
        if obj.modifiers.count > 0 and classOf obj.modifiers[1] == UVWMap then (
            local ex = obj.modifiers[1]
            ex.maptype = 4
            try (ex.realWorldMapSize = false) catch ()
            ex.length = s
            ex.width = s
            ex.height = s
        ) else (
            select obj
            max modify mode
            modPanel.setCurrentObject obj.baseObject
            -- 还原面选到基础物体（select/collect 可能已清掉）
            if kind == #poly then
                polyop.setFaceSelection obj fs
            else
                setFaceSelection obj fs
            local u = UVWMap maptype:4 length:s width:s height:s
            try (u.realWorldMapSize = false) catch ()
            modPanel.addModToSelection u ui:on
        )
    )

    fn doApplyUVWCore sizeVal sameMat = (
        _51W_Telemetry.track "feature_used" props:#("feature", "UVWMap")
        local s = sizeVal
        if s <= 0 do (messageBox "尺寸必须大于 0。" title:"UVW Map"; return ())
        local objs = collectUVWTargets sameMat
        if objs.count == 0 do (messageBox "请先选择对象。" title:"UVW Map"; return ())
        local applied = 0
        local failed = 0
        undo "应用 UVW Box" on (
            for obj in objs where superClassOf obj == GeometryClass do (
                try (
                    local faceInfo = getObjFaceSel obj
                    if faceInfo != undefined then (
                        -- 有面级选择：只作用选中面
                        addUVWToFaceSel obj faceInfo s
                    ) else (
                        -- 无面级选择：整体应用（复用已有 UVWMap）
                        local existing = undefined
                        for m in obj.modifiers while existing == undefined do (
                            if classOf m == UVWMap do existing = m
                        )
                        if existing != undefined then (
                            existing.maptype = 4
                            try (existing.realWorldMapSize = false) catch ()
                            existing.length = s
                            existing.width = s
                            existing.height = s
                        ) else (
                            local u = UVWMap maptype:4 length:s width:s height:s
                            try (u.realWorldMapSize = false) catch ()
                            addModifier obj u
                        )
                    )
                    applied += 1
                ) catch (
                    failed += 1
                )
            )
        )
        if failed > 0 then
            messageBox ("已应用 " + applied as string + " 个对象，失败 " + failed as string + " 个。") title:"UVW Map"
        else
            messageBox ("已应用 UVW Box： " + applied as string + " 个对象。") title:"UVW Map"
    )

    on btn_applyUVWBoxNative pressed do doApplyUVWCore spn_uvwBoxSize.value chk_sameMatNative.checked


    fn doFlatten = (
        _51W_Telemetry.track "feature_used" props:#("feature", "UnwrapFlatten")
        local objs = selection as array
        if objs.count == 0 do (messageBox "请先选择对象。" title:"Unwrap UVW"; return ())
        local c = 0
        undo "一键平铺" on (
            for obj in objs where superClassOf obj == GeometryClass do (
                if selection.count != 1 or selection[1] != obj do select obj
                local uw = getOrAddUnwrap obj ch:1
                subObjectLevel = 3
                local nf = try (polyop.getNumFaces obj) catch (try (obj.mesh.numFaces) catch 0)
                if nf == 0 do continue
                uw.selectFaces #{1..nf}
                uw.flattenMap 45.0 #([0,0,1],[0,0,-1],[1,0,0],[-1,0,0],[0,1,0],[0,-1,0]) 0.02 true 0 true true
                c += 1
            )
        )
    )

    fn doFillQuad = (
        _51W_Telemetry.track "feature_used" props:#("feature", "UnwrapFillQuad")
        local objs = selection as array
        if objs.count == 0 do (messageBox "请先选择对象。" title:"Unwrap UVW"; return ())
        local c = 0
        undo "一键占满一象限" on (
            for obj in objs where superClassOf obj == GeometryClass do (
                if selection.count != 1 or selection[1] != obj do select obj
                local uw = getOrAddUnwrap obj ch:1
                subObjectLevel = 3
                local nf = try (polyop.getNumFaces obj) catch (try (obj.mesh.numFaces) catch 0)
                if nf == 0 do continue
                uw.selectFaces #{1..nf}
                uw.pack 1 spn_padding_native.value true true true
                c += 1
            )
        )
    )

    fn doFillEach = (
        _51W_Telemetry.track "feature_used" props:#("feature", "UnwrapFillEach")
        local objs = selection as array
        if objs.count == 0 do (messageBox "请先选择对象。" title:"Unwrap UVW"; return ())
        local c = 0
        undo "每个UV占满一象限" on (
            for obj in objs where superClassOf obj == GeometryClass do (
                if selection.count != 1 or selection[1] != obj do select obj
                if classOf obj.baseObject != Editable_Poly do convertToPoly obj
                if classOf obj.baseObject != Editable_Poly do continue

                local nf = polyop.getNumFaces obj
                if nf == 0 do continue
                if not (polyop.getMapSupport obj 1) do continue

                -- 用 polyop 检测 UV 岛（按 UV 连通性）
                local numMV = polyop.getNumMapVerts obj 1
                local maxMV = 0
                for f = 1 to nf do (
                    local mvf = polyop.getMapFace obj 1 f
                    for v in mvf do if v > maxMV do maxMV = v
                )
                if maxMV > numMV do numMV = maxMV
                if numMV == 0 do continue

                local vtxFaces = #()
                vtxFaces.count = numMV
                for i = 1 to numMV do vtxFaces[i] = #{}
                local faceMapVerts = #()
                faceMapVerts.count = nf
                for f = 1 to nf do (
                    local mvf = polyop.getMapFace obj 1 f
                    faceMapVerts[f] = mvf
                    for v in mvf do vtxFaces[v][f] = true
                )

                -- 泛洪法查找 UV 岛（同时记录每岛的面集合）
                local visited = #{}
                local islandFaces = #()
                local islandVerts = #()
                for f = 1 to nf where not visited[f] do (
                    local fset = #{}
                    local vset = #{}
                    local queue = #(f)
                    while queue.count > 0 do (
                        local cf = queue[queue.count]; deleteItem queue queue.count
                        if visited[cf] do continue
                        visited[cf] = true
                        fset[cf] = true
                        for v in faceMapVerts[cf] do (
                            vset[v] = true
                            for af in vtxFaces[v] where not visited[af] do append queue af
                        )
                    )
                    append islandFaces fset
                    append islandVerts vset
                )

                -- 通过 Unwrap_UVW 修改器修改 UV，避免 polyop.setMapVert 的限制
                local uw = getOrAddUnwrap obj ch:1
                for i = 1 to islandFaces.count do (
                    local verts = islandVerts[i]
                    local minU = 1e9, minV = 1e9, maxU = -1e9, maxV = -1e9
                    local validVerts = #{}
                    for v in verts where v >= 1 do (
                        local p = undefined
                        try (p = uw.getVertexPosition 0 v) catch (p = undefined)
                        if p != undefined do (
                            validVerts[v] = true
                            if p.x < minU do minU = p.x
                            if p.y < minV do minV = p.y
                            if p.x > maxU do maxU = p.x
                            if p.y > maxV do maxV = p.y
                        )
                    )
                    local uR = maxU - minU; local vR = maxV - minV
                    if uR > 0.00001 and vR > 0.00001 do (
                        for v in validVerts do (
                            try (
                                local p = uw.getVertexPosition 0 v
                                uw.setVertexPosition 0 v [(p.x - minU) / uR, (p.y - minV) / vR, 0]
                            ) catch ()
                        )
                    )
                )
                update obj
                c += 1
            )
        )
    )

    on btn_flatten_native pressed do (try (doFlatten()) catch (messageBox (getCurrentException()) title:"错误"))
    on btn_fillquad_native pressed do (try (doFillQuad()) catch (messageBox (getCurrentException()) title:"错误"))
    on btn_filleach_native pressed do (try (doFillEach()) catch (messageBox (getCurrentException()) title:"错误"))
)


-- 9. 其它工具
rollout rl_OtherTools "其它工具" (
    groupBox gbOther1 "随机材质ID | Material IDs Random Generator" pos:[0,0] width:464 height:82
    groupBox gbOther2 "分离工具" pos:[0,86] width:228 height:106
    groupBox gbOther3 "合并工具" pos:[236,86] width:228 height:106

    label lblMode "模式：" pos:[14,26] width:40 height:18
    radioButtons rbModeNative "" labels:#("多边形", "对象", "平滑组", "元素") columns:4 default:1 pos:[56,24] width:280 height:20
    label lblIDCount "子材质数：" pos:[14,58] width:70 height:20
    spinner spnIDCount "" range:[1, 256, 3] type:#integer fieldWidth:60 pos:[84,57] width:60 height:22
    button btnRandMat "点击生成" pos:[234,50] width:210 height:28

    checkbox chkSepGroup "分离成组" checked:false pos:[10,108] width:120 height:20
    button btnSepMat "按材质ID分离" pos:[10,136] width:200 height:24
    button btnSepElem "按元素分离" pos:[10,164] width:200 height:24

    checkbox chkAttWeld "合并后焊接点" checked:false pos:[246,108] width:140 height:20
    button btnAttSel "按选择集合并" pos:[246,136] width:200 height:24
    button btnAttOcc "按漫射位图合并" pos:[246,164] width:200 height:24

    fn getMode = (
        case rbModeNative.state of (
            1: #poly
            2: #obj
            3: #sg
            default: #elem
        )
    )

    fn collectByGroup mode m faceCount = (
        -- 返回 #(BitArray, ...) 分组（同组共享一个ID）
        local groups = #()
        case mode of (
            #poly: ( for f = 1 to faceCount do (local ba = #{}; ba[f] = true; append groups ba) )
            #sg: (
                local seen = #{}
                for f = 1 to faceCount do (
                    if not seen[f] do (
                        local sg = polyop.getFaceSmoothGroup m f
                        local ba = #{}
                        if sg == 0 then ( ba[f] = true; seen[f] = true )
                        else (
                            for g = 1 to faceCount do (
                                if not seen[g] and (polyop.getFaceSmoothGroup m g) == sg do (
                                    ba[g] = true; seen[g] = true
                                )
                            )
                        )
                        append groups ba
                    )
                )
            )
            #elem: (
                local seen = #{}
                for f = 1 to faceCount do (
                    if not seen[f] do (
                        local ba = polyop.getElementsUsingFace m f
                        seen = seen + ba
                        append groups ba
                    )
                )
            )
        )
        groups
    )

    fn hsvToColor h s v = (
        -- h:0-360, s/v:0-1
        local c = h / 60.0
        local hi = (floor c) as integer
        local f = c - hi
        local p = v * (1.0 - s)
        local q = v * (1.0 - s * f)
        local t = v * (1.0 - s * (1.0 - f))
        local r = 0.0; local g = 0.0; local b = 0.0
        case (mod hi 6) of (
            0: ( r = v; g = t; b = p )
            1: ( r = q; g = v; b = p )
            2: ( r = p; g = v; b = t )
            3: ( r = p; g = q; b = v )
            4: ( r = t; g = p; b = v )
            5: ( r = v; g = p; b = q )
        )
        color (r * 255) (g * 255) (b * 255)
    )

    fn buildMultiMat n = (
        local mm = MultiMaterial numsubs:n
        mm.name = "RandMatID_Multi"
        for i = 1 to n do (
            local h = mod ((i - 1) * 360.0 / n) 360.0
            local c = hsvToColor h 0.78 0.92
            local sub = Standardmaterial name:("ID_" + i as string) diffuse:c
            try ( sub.showInViewport = true ) catch ()
            mm.materialList[i] = sub
            mm.names[i] = "ID_" + i as string
        )
        mm
    )

    fn assignMultiMat objs n = (
        local mm = buildMultiMat n
        for o in objs do (
            o.material = mm
            try ( showTextureMap o.material true ) catch ()
        )
    )

    fn applyToObj obj mode mn mx = (
        if obj == undefined then return false
        if not (isKindOf obj.baseObject Editable_Poly or isKindOf obj.baseObject Editable_Mesh) do return false
        local wasMesh = isKindOf obj.baseObject Editable_Mesh
        if wasMesh do convertToPoly obj
        local m = obj
        local fc = polyop.getNumFaces m
        if fc == 0 do return false
        case mode of (
            #obj: (
                local id = random mn mx
                polyop.setFaceMatID m #{1..fc} id
            )
            #poly: (
                for f = 1 to fc do polyop.setFaceMatID m f (random mn mx)
            )
            default: (
                local groups = collectByGroup mode m fc
                for ba in groups do (
                    local id = random mn mx
                    polyop.setFaceMatID m ba id
                )
            )
        )
        update m
        true
    )

    fn doRandMatID = (
        local sel = selection as array
        if sel.count == 0 do ( messageBox "请先选择对象。" title:"随机材质ID"; return 0 )
        local mode = getMode()
        local n = spnIDCount.Value as integer
        if n < 1 do n = 1
        _51W_Telemetry.track "feature_used" props:#("feature", "RandMatID", "mode", (mode as string), "id_count", n, "obj_count", sel.count)
        local cnt = 0
        try (
            undo "RandMatID" on (
                for o in sel do ( if applyToObj o mode 1 n do cnt = cnt + 1 )
                if cnt > 0 do assignMultiMat sel n
            )
        ) catch (
            local err = getCurrentException()
            _51W_Telemetry.trackError "RandMatID" err
            messageBox err title:"错误"
            return 0
        )
        messageBox ("已处理 " + cnt as string + " 个对象。") title:"随机材质ID"
        cnt
    )

    -- 按材质ID分离（勾选"分离成组"则结果打组）
    fn doSepMatID = (
        _51W_Telemetry.track "feature_used" props:#("feature", "SepMatID")
        local objs = selection as array
        if objs.count == 0 do (messageBox "请先选择对象。" title:"按材质ID分离"; return ())
        local doGroup = chkSepGroup.checked
        undo "按材质ID分离" on (
            for obj in objs do (
                if superClassOf obj != GeometryClass do continue
                if classOf obj.baseObject != Editable_Poly do convertToPoly obj
                local nf = polyop.getNumFaces obj
                if nf == 0 do continue
                -- 缓存每个面的 MatID（避免后续重复查询）
                local faceIDs = #()
                faceIDs.count = nf
                local idSet = #{}
                for f = 1 to nf do (
                    local id = polyop.getFaceMatID obj f
                    faceIDs[f] = id
                    idSet[id] = true
                )
                local idArr = #()
                for i in idSet do append idArr i
                if idArr.count <= 1 do continue
                -- 预生成每个 ID 对应的面集合
                local idFaces = #()
                for i = 1 to idArr.count do (
                    local ba = #{}
                    for f = 1 to nf do if faceIDs[f] == idArr[i] do ba[f] = true
                    append idFaces ba
                )
                local newObjs = #(obj)
                for i = 2 to idArr.count do (
                    local cp = copy obj
                    polyop.deleteFaces cp (#{1..nf} - idFaces[i])
                    cp.name = obj.name + "_MatID" + idArr[i] as string
                    append newObjs cp
                )
                polyop.deleteFaces obj (#{1..nf} - idFaces[1])
                obj.name = obj.name + "_MatID" + idArr[1] as string
                if doGroup do group newObjs
            )
        )
    )

    -- 按元素分离（勾选"分离成组"则结果打组）
    fn doSepElem = (
        _51W_Telemetry.track "feature_used" props:#("feature", "SepElem")
        local objs = selection as array
        if objs.count == 0 do (messageBox "请先选择对象。" title:"按元素分离"; return ())
        local doGroup = chkSepGroup.checked
        undo "按元素分离" on (
            for obj in objs do (
                if superClassOf obj != GeometryClass do continue
                if classOf obj.baseObject != Editable_Poly do convertToPoly obj
                local nf = polyop.getNumFaces obj
                if nf == 0 do continue
                local visited = #{}
                local elems = #()
                for f = 1 to nf do (
                    if not visited[f] do (
                        local elem = polyop.getElementsUsingFace obj #{f}
                        visited += elem
                        append elems elem
                    )
                )
                if elems.count <= 1 do continue
                local newObjs = #(obj)
                for i = 2 to elems.count do (
                    local cp = copy obj
                    polyop.deleteFaces cp (#{1..nf} - elems[i])
                    cp.name = obj.name + "_" + i as string
                    append newObjs cp
                )
                polyop.deleteFaces obj (#{1..nf} - elems[1])
                if doGroup do group newObjs
            )
        )
    )

    -- 按选择集合并（勾选"合并后焊接点"则焊接）
    fn doAttachSel = (
        _51W_Telemetry.track "feature_used" props:#("feature", "AttachSel")
        local objs = selection as array
        if objs.count < 2 do (messageBox "请至少选择 2 个对象。" title:"按选择集合并"; return ())
        local doWeld = chkAttWeld.checked
        undo "按选择集合并" on (
            local base = objs[1]
            if classOf base.baseObject != Editable_Poly do convertToPoly base
            for i = 2 to objs.count do (
                local o = objs[i]
                if classOf o.baseObject != Editable_Poly do convertToPoly o
                polyop.attach base o
            )
            if doWeld do (
                base.weldThreshold = 0.01
                polyop.weldVertsByThreshold base #{1..(polyop.getNumVerts base)}
            )
        )
    )

    -- 从单个材质获取漫反射贴图路径
    fn getDiffuseMapFromMtl mtl = (
        if mtl == undefined do return undefined
        local tex = undefined
        local props = #(#diffuseMap, #diffuse_map, #base_color_map, #texmap_diffuse, #texmap_base_color)
        for p in props while tex == undefined do (
            try (tex = getProperty mtl p) catch ()
        )
        if tex == undefined do return undefined
        local fname = undefined
        try (fname = tex.filename) catch ()
        if fname == undefined do try (fname = tex.HDRIMapName) catch ()
        if fname == undefined or fname == "" do return undefined
        toLower fname
    )

    -- 获取物体实际使用的所有漫反射贴图（按面 MatID 取对应子材质），返回排序后用 | 拼接的字符串
    fn getDiffuseMap obj = (
        local mtl = obj.material
        if mtl == undefined do return undefined
        if classOf mtl != Multimaterial do return (getDiffuseMapFromMtl mtl)
        -- Multimaterial：找出物体面上实际用到的 MatID
        local usedIDs = #{}
        local m = undefined
        try (
            if classOf obj.baseObject == Editable_Poly then (
                local nf = polyop.getNumFaces obj
                for f = 1 to nf do usedIDs[polyop.getFaceMatID obj f] = true
            ) else (
                m = snapshotAsMesh obj
                local nf = m.numfaces
                for f = 1 to nf do usedIDs[getFaceMatID m f] = true
            )
        ) catch ()
        if m != undefined do (try (free m) catch ())
        if usedIDs.numberSet == 0 do return undefined
        local maps = #()
        local subIDs = mtl.materialIDList
        local subMats = mtl.materialList
        for id in usedIDs do (
            local subIdx = findItem subIDs id
            if subIdx == 0 do (
                -- materialIDList 没有匹配，按位置回退（id 索引到 materialList）
                if id >= 1 and id <= subMats.count then subIdx = id else continue
            )
            local fname = getDiffuseMapFromMtl subMats[subIdx]
            if fname != undefined do appendIfUnique maps fname
        )
        if maps.count == 0 do return undefined
        sort maps
        local key = ""
        for i = 1 to maps.count do (
            if i > 1 do key += "|"
            key += maps[i]
        )
        key
    )

    -- 按漫射位图合并（同贴图的物体合并到一起，无贴图跳过）
    fn doAttachOcc = (
        _51W_Telemetry.track "feature_used" props:#("feature", "AttachByMap")
        local objs = selection as array
        if objs.count < 2 do (messageBox "请至少选择 2 个对象。" title:"按漫射位图合并"; return ())
        local doWeld = chkAttWeld.checked
        undo "按漫射位图合并" on (
            local groups = #()
            local keys = #()
            local skipped = 0
            for obj in objs do (
                if superClassOf obj != GeometryClass do continue
                local mapPath = getDiffuseMap obj
                if mapPath == undefined do (skipped += 1; continue)
                if classOf obj.baseObject != Editable_Poly do convertToPoly obj
                local idx = findItem keys mapPath
                if idx == 0 then (
                    append keys mapPath
                    append groups #(obj)
                ) else (
                    append groups[idx] obj
                )
            )
            for grp in groups where grp.count > 1 do (
                local base = grp[1]
                for i = 2 to grp.count do polyop.attach base grp[i]
                if doWeld do (
                    base.weldThreshold = 0.01
                    polyop.weldVertsByThreshold base #{1..(polyop.getNumVerts base)}
                )
            )
        )
    )

    on btnRandMat pressed do (try (doRandMatID()) catch (messageBox (getCurrentException()) title:"错误"))
    on btnSepMat pressed do (try (doSepMatID()) catch (messageBox (getCurrentException()) title:"错误"))
    on btnSepElem pressed do (try (doSepElem()) catch (messageBox (getCurrentException()) title:"错误"))
    on btnAttSel pressed do (try (doAttachSel()) catch (messageBox (getCurrentException()) title:"错误"))
    on btnAttOcc pressed do (try (doAttachOcc()) catch (messageBox (getCurrentException()) title:"错误"))
)


-- 10. 意见反馈
rollout rl_Feedback "意见反馈" (
    label lbl_hint "遇到问题或有功能建议？填写后发送给开发者。" align:#left
    edittext edt_feedback "" height:80 width:220 align:#center
    button btn_send "📨 发送反馈" width:220 height:26 align:#center
    button btn_tel_check "🩺 埋点自检" width:220 height:24 align:#center

    fn telemetrySelfCheck = (
        _51W_Telemetry.ensureUser()
        local en = _51W_Telemetry.enabled
        local host = _51W_Telemetry.apiHost
        local did = _51W_Telemetry.distinctId
        local iniEnabled = getINISetting _51W_Telemetry.iniPath "Telemetry" "Enabled"
        local iniMigrated = getINISetting _51W_Telemetry.iniPath "Telemetry" "OptInMigrated"
        local keyPrefix = ""
        try (keyPrefix = substring _51W_Telemetry.apiKey 1 12) catch ()
        local sent = false
        if en do sent = _51W_Telemetry.track "telemetry_self_check" props:#("source", "ui_self_check")
        local msg = "Enabled: " + (en as string) + "\n"
        msg += "INI.Enabled: " + iniEnabled + "  |  INI.OptInMigrated: " + iniMigrated + "\n"
        msg += "Host: " + host + "\n"
        msg += "Key前缀: " + keyPrefix + "\n"
        msg += "DistinctId: " + did + "\n"
        if en then
            msg += (if sent then "结果: 测试事件已发送（telemetry_self_check）。" else "结果: 发送失败，请查看 Listener 报错。")
        else
            msg += "结果: Telemetry 当前关闭（Enabled=false），未发送测试事件。"
        messageBox msg title:"Telemetry自检"
    )

    on btn_send pressed do (
        local txt = trimRight (trimLeft edt_feedback.text)
        if txt == "" then (
            messageBox "请先填写反馈内容。" title:"提示"
        ) else (
            _51W_Telemetry.track "feedback_submitted" props:#("feedback", txt)
            edt_feedback.text = ""
            messageBox "✅ 反馈已发送，感谢！" title:"发送成功"
        )
    )

    on btn_tel_check pressed do (
        try (telemetrySelfCheck()) catch (messageBox (getCurrentException()) title:"Telemetry自检")
    )
)


-- 11. 更新内容（公示形式，无边框）
rollout rl_Changelog "更新内容" (
    label lbl_compat "推荐 3ds Max 2022+  |  2019/2020 标题颜色异常但功能正常" align:#center
    label lbl_sep    "────────────────────────────────────"          align:#center
    label lbl_ver    "【v3.1.3.3   2026-07-16】"                       align:#center
    label lbl_l1     "test3" align:#center
    label lbl_l2     "【v3.1.2】UVW Box 面选：只对选中面生效，重复点击不叠加" align:#center
    label lbl_l3     "【v3.1.1】新增优化工具大类 / 导出路径记忆 / 烘焙AO 可选 UV"    align:#center
    label lbl_l4     "【v3.1.1】批量导出提速、多选导出稳定性修复"     align:#center
    label lbl_l5     ""       align:#center
    label lbl_l6     ""                                              align:#center
    label lbl_more   "完整历史 → GitHub / ChangeLOG.md"               align:#center
    button btn_update "已是最新版本" width:220 height:24 align:#center enabled:false

    -- 根据自动检测结果刷新按钮：有新版则高亮可点，否则显示已是最新
    fn refreshUpdateBtn = (
        if _51W_Updater.updateAvailable then (
            btn_update.text = "🔺 发现新版 v" + _51W_Updater.remoteVersion + "，点击更新"
            btn_update.enabled = true
        ) else (
            btn_update.text = "已是最新版本 v" + _51W_Updater.localVersion
            btn_update.enabled = false
        )
    )

    on rl_Changelog open do refreshUpdateBtn()

    on btn_update pressed do (
        try (
            if _51W_Updater.doDownload() do (btn_update.enabled = false)
        ) catch (messageBox (getCurrentException()) title:"更新")
    )
)


-- 创建浮动窗口
_51W_Floater = newRolloutFloater "MaxToUE Toolkit  Version 3" 510 980
for r in #(rl_BakeAO, rl_MatOptimize, rl_AutoName, rl_FBXExport, rl_BatchImport, rl_SplineTools, rl_UnwrapUVW, rl_Optimize, rl_CommonTools, rl_OtherTools) do
    addRollout r _51W_Floater rolledUp:(r != rl_FBXExport)
addRollout rl_Feedback _51W_Floater rolledUp:false
addRollout rl_Changelog _51W_Floater rolledUp:false
