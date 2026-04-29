/*
 * 51WORLD �����Դ�Զ�ת������ Version 3
 * ����: 3ds Max 2025+  |  ֧��: UE4 / UE5 FBX����
 */
try (closeRolloutFloater _51W_Floater) catch ()

-- ȫ�ֹ���״̬
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

    fn convertPhysicalMatToStd pmat = (
        local s = StandardMaterial name:pmat.name
        try (s.diffuseColor = pmat.base_color; if pmat.base_color_map != undefined do s.diffuseMap = pmat.base_color_map) catch ()
        try (if pmat.bump_map != undefined do s.bumpMap = pmat.bump_map) catch ()
        try (if pmat.cutout_map != undefined do s.opacityMap = pmat.cutout_map) catch ()
        try (if pmat.emit_color_map != undefined do s.selfillumMap = pmat.emit_color_map) catch ()
        try (s.selfIllumAmount = pmat.emission * 100) catch ()
        s
    ),

    fn convertMatRecursive mat mode:"vray" = (
        if mat == undefined do return undefined
        if mode == "vray" then (
            if (matchPattern (classOf mat as string) pattern:"VRay*") then return (_51W_Data.convertVrayMatToStd mat)
        ) else (
            if (classOf mat == PhysicalMaterial) then return (_51W_Data.convertPhysicalMatToStd mat)
        )
        if classOf mat == MultiMaterial then (
            for i = 1 to mat.materialList.count where mat.materialList[i] != undefined do
                mat.materialList[i] = _51W_Data.convertMatRecursive mat.materialList[i] mode:mode
        )
        mat
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
    ),

    fn paintGroupBox s e = (
        local g = e.Graphics
        local bgRGB = (colorMan.getColor #background) * 255
        local txRGB = (colorMan.getColor #text) * 255
        local bgC = (dotNetClass "System.Drawing.Color").FromArgb (bgRGB.x as integer) (bgRGB.y as integer) (bgRGB.z as integer)
        local txC = (dotNetClass "System.Drawing.Color").FromArgb (txRGB.x as integer) (txRGB.y as integer) (txRGB.z as integer)
        local shRGB = (colorMan.getColor #shadow) * 255
        local brC = (dotNetClass "System.Drawing.Color").FromArgb (shRGB.x as integer) (shRGB.y as integer) (shRGB.z as integer)
        g.FillRectangle (dotNetObject "System.Drawing.SolidBrush" bgC) (dotNetObject "System.Drawing.Rectangle" 0 0 s.Width s.Height)
        local f = (dotNetClass "System.Windows.Forms.Control").DefaultFont
        local ts = g.MeasureString s.Text f
        local th = (ts.Height / 2) as integer
        local tw = (ts.Width + 10) as integer
        local pen = dotNetObject "System.Drawing.Pen" brC 1.0
        g.DrawLine pen 0 th 6 th
        g.DrawLine pen tw th (s.Width-1) th
        g.DrawLine pen 0 th 0 (s.Height-1)
        g.DrawLine pen 0 (s.Height-1) (s.Width-1) (s.Height-1)
        g.DrawLine pen (s.Width-1) th (s.Width-1) (s.Height-1)
        g.DrawString s.Text f (dotNetObject "System.Drawing.SolidBrush" txC) (dotNetObject "System.Drawing.PointF" 8.0 0.0)
    ),

    -- UI ����: ���� #(bgColor, fgColor, btnColor, defaultFont)
    fn getUIColors = (
        local bgRGB = (colorMan.getColor #background) * 255
        local txRGB = (colorMan.getColor #text) * 255
        #(
            (dotNetClass "System.Drawing.Color").FromArgb (bgRGB.x as integer) (bgRGB.y as integer) (bgRGB.z as integer),
            (dotNetClass "System.Drawing.Color").FromArgb (txRGB.x as integer) (txRGB.y as integer) (txRGB.z as integer),
            (dotNetClass "System.Drawing.Color").FromArgb (amin 255 ((bgRGB.x+30) as integer)) (amin 255 ((bgRGB.y+30) as integer)) (amin 255 ((bgRGB.z+30) as integer)),
            (dotNetClass "System.Windows.Forms.Control").DefaultFont
        )
    ),

    fn makeBtn parent text x y w h ui = (
        local b = dotNetObject "System.Windows.Forms.Button"
        b.Text = text; b.ForeColor = ui[2]; b.BackColor = ui[3]
        b.FlatStyle = (dotNetClass "System.Windows.Forms.FlatStyle").Flat
        b.Font = ui[4]; b.FlatAppearance.BorderSize = 0
        b.Bounds = dotNetObject "System.Drawing.Rectangle" x y w h
        parent.controls.add b; b
    ),

    fn makeGrp parent text x y w h ui = (
        local g = dotNetObject "System.Windows.Forms.GroupBox"
        g.Text = text; g.Font = ui[4]
        g.Bounds = dotNetObject "System.Drawing.Rectangle" x y w h
        parent.controls.add g
        dotNet.addEventHandler g "Paint" _51W_Data.paintGroupBox; g
    ),

    fn makeLbl parent text x y w h ui = (
        local l = dotNetObject "System.Windows.Forms.Label"
        l.AutoSize = false
        l.Text = text; l.ForeColor = ui[2]; l.Font = ui[4]
        l.Bounds = dotNetObject "System.Drawing.Rectangle" x y w h
        parent.controls.add l; l
    ),

    fn makeSpn parent mn mx val dec inc x y w h ui = (
        local s = dotNetObject "System.Windows.Forms.NumericUpDown"
        s.Minimum = mn; s.Maximum = mx; s.Value = val
        s.DecimalPlaces = dec; s.Increment = inc
        s.BackColor = ui[3]; s.ForeColor = ui[2]
        s.Bounds = dotNetObject "System.Drawing.Rectangle" x y w h
        -- �� Max �����ؼ������루�����ֶ�������ֵ��
        dotNet.addEventHandler s "GotFocus"  (fn sender e = (enableAccelerators = false))
        dotNet.addEventHandler s "LostFocus" (fn sender e = (enableAccelerators = true))
        parent.controls.add s; s
    ),

    fn makeTxt parent text x y w h ui = (
        local t = dotNetObject "System.Windows.Forms.TextBox"
        t.Text = text; t.BackColor = ui[3]; t.ForeColor = ui[2]
        t.Bounds = dotNetObject "System.Drawing.Rectangle" x y w h
        parent.controls.add t; t
    )
)
_51W_Data = _51W_DataStruct()


-- ============================================================
-- ����ʹ��ͳ�� (PostHog Telemetry)
-- ------------------------------------------------------------
-- ����ԭ��:
--   1. ����ʱ�ϱ� $script_loaded
--   2. �����ܰ�ť���ʱ�ϱ� feature_used (������ + ����)
--   3. ����ʱ�ϱ� error_occurred (������Ϣ + ������)
--   user_id = MD5(�û���+������)������������
--   �û����� INI �йر�(set Enabled=false)
-- ============================================================
global _51W_Telemetry
struct _51W_TelemetryStruct (
    -- �� ������������� PostHog �õ��� Project API Key (phc_ ��ͷ) ��
    apiKey = "phc_y4SakH8nP3PwXrkZyBGjNF2dqDh67wgN8qnk2xYMzfom",
    apiHost = "https://us.i.posthog.com",
    scriptVersion = "3.0.0",

    iniPath = (getDir #userScripts) + "\\_51W_Telemetry.ini",
    enabled = true,
    distinctId = "",
    sessionId = "",
    sessionStart = 0,
    pendingClients = #(),  -- ���� WebClient ����ֱ�� async send ���

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
                format "[Telemetry]\nEnabled=true\nUserId=\n" to:f
                close f
            )
        )
        local en = getINISetting iniPath "Telemetry" "Enabled"
        if en == "false" then enabled = false else enabled = true
        -- ���ı�ʶ: �û���@������ (������ PostHog ��ʶ����˭)
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

    fn postAsync url body = (
        try (
            local wc = dotNetObject "System.Net.WebClient"
            wc.Headers.Add "Content-Type" "application/json"
            wc.Encoding = (dotNetClass "System.Text.Encoding").UTF8
            append pendingClients wc
            -- �����¼��ص���������� pendingClients ���ڴ�����
            if pendingClients.count > 100 do pendingClients = #()
            local uri = dotNetObject "System.Uri" url
            wc.UploadStringAsync uri "POST" body
        ) catch ()
    ),

    fn track eventName props:#() = (
        if not enabled do return undefined
        if apiKey == "phc_REPLACE_ME" do return undefined
        try (
            local body = "{\"api_key\":\"" + apiKey + "\""
            body += ",\"event\":\"" + (jsonEscape eventName) + "\""
            body += ",\"distinct_id\":\"" + distinctId + "\""
            body += ",\"properties\":" + (buildPropsJson props)
            body += ",\"timestamp\":\"" + ((dotNetClass "System.DateTime").UtcNow.ToString "yyyy-MM-ddTHH:mm:ss.fffZ") + "\"}"
            postAsync (apiHost + "/capture/") body
        ) catch ()
    ),

    fn trackError feature errMsg = (
        track "error_occurred" props:#("feature", feature, "error", errMsg)
    )
)
_51W_Telemetry = _51W_TelemetryStruct()
_51W_Telemetry.ensureUser()
_51W_Telemetry.track "script_loaded"


-- ============================================================
-- �Զ�����ģ��
-- ============================================================
global _51W_Updater
(
    -- �ڽű�����ʱ����·����rollout �� getSourceFileName ����ʧЧ��
    local _scriptPath = getSourceFileName()

    struct _51W_UpdaterStruct (
        localVersion  = "3.0.0",
        rawBase       = "https://raw.githubusercontent.com/yimu-zhao/MaxScriptTools/main/",
        pat           = "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",
        iniPath       = (getDir #userScripts) + "\\_51W_Telemetry.ini",
        scriptPath    = "",

        -- 返回 remoteVer 是否大于 localVersion
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

        fn makeWebClient = (
            local wc = dotNetObject "System.Net.WebClient"
            wc.Encoding = (dotNetClass "System.Text.Encoding").UTF8
            wc.Headers.Add "Authorization" ("token " + pat)
            wc.Headers.Add "User-Agent" "MaxScript-UE-ResourceTool"
            wc
        ),

        fn checkAndUpdate = (
            try (
                if scriptPath == "" or not (doesFileExist scriptPath) do return undefined
                -- INI 开关：Updater / AutoUpdate = false 可关闭
                if (getINISetting iniPath "Updater" "AutoUpdate") == "false" do return undefined

                local wc1 = makeWebClient()
                local remoteVer = trimRight ((wc1.DownloadString (rawBase + "version.txt")) as string)

                if isNewer remoteVer do (
                    local ans = queryBox ("发现新版本 " + remoteVer + "（当前 " + localVersion + "）\n\n是否立即下载更新？\n下载完成后请重新运行脚本。") \
                        title:"UE_ResourceTool 有更新"
                    if ans do (
                        local wc2 = makeWebClient()
                        local newContent = (wc2.DownloadString (rawBase + "UE_ResourceTool.ms")) as string
                        local f = createFile scriptPath
                        if f != undefined do (
                            format "%" newContent to:f
                            close f
                            messageBox "✅ 更新完成！\n请重新运行脚本以加载新版本。" title:"更新成功"
                        )
                    )
                )
            ) catch ()
        )
    )

    _51W_Updater = _51W_UpdaterStruct scriptPath:_scriptPath
    _51W_Updater.checkAndUpdate()
)


-- 1. �決AO��ͼ
rollout rl_BakeAO "�決AO��ͼ" (
    button btn_bake "�決AO��ͼ" width:200 height:26 align:#center
    button btn_show "��ʾAO��ͼ" width:200 height:26 align:#center
    spinner spn_size "��ͼ: " range:[64,8192,1024] type:#integer fieldWidth:100 align:#center

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
                    format "�޷�Ϊ���� % ָ��AO��ͼ�����ֶ����á�\n" mat.name
                )
            )
        )
    )

    on btn_bake pressed do (
        _51W_Telemetry.track "feature_used" props:#("feature", "BakeAO")
        local objs = selection as array
        if objs.count == 0 do (messageBox "����ѡ�����" title:"�決AO"; return ())
        local sz = spn_size.value
        local oldRend = renderers.current
        renderers.current = Default_Scanline_Renderer()

        -- ������ʱ���
        local skyCls = undefined
        for c in light.classes where (matchPattern (c as string) pattern:"Skylight") do (skyCls = c; exit)
        local sky = if skyCls != undefined then (skyCls name:"_AO_Sky_" multiplier:1.0 castShadows:true)
                    else (Omnilight name:"_AO_Sky_" pos:[0,0,5000] multiplier:1.0 castShadows:true)

        -- ���������ƹ�
        local hidden = for l in lights where l != sky and not l.isHidden collect (l.isHidden = true; l)

        -- �滻����Ϊ����
        local origMats = for obj in objs collect obj.material
        undo "Bake AO" on (
            for obj in objs do (
                if (meshop.getMapSupport obj.mesh 2) == false do (
                    local uw = Unwrap_UVW(); uw.setMapChannel 2; addModifier obj uw
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
                obj.INodeBakeProperties.bakeChannel = 2
                obj.INodeBakeProperties.nDilations = 4
            )
            select objs
            render renderType:#bakeSelected vfb:off progressBar:true outputSize:[sz,sz]
        )
        -- �ָ����ʲ��Զ�����AO
        for i = 1 to objs.count do (
            objs[i].material = origMats[i]
            local aoFile = getAOPath objs[i]
            if objs[i].material != undefined and doesFileExist aoFile do
                applyAOToMat objs[i].material aoFile
        )
        try (delete sky) catch ()
        for l in hidden do try (l.isHidden = false) catch ()
        renderers.current = oldRend
        messageBox ("AO�決��ɣ����Զ�Ӧ�õ����ʡ�\n������: " + getAODir()) title:"�決AO"
    )

    on btn_show pressed do (
        _51W_Telemetry.track "feature_used" props:#("feature", "BakeAO_Show")
        local objs = selection as array
        if objs.count == 0 do (messageBox "����ѡ�����" title:"��ʾAO"; return ())
        for obj in objs do (
            local f = getAOPath obj
            if doesFileExist f then display (openBitmap f) else format "δ�ҵ�: %\n" f
        )
    )
)


-- 2. �����Ż�
rollout rl_MatOptimize "�����Ż�" (
    button btn_opt "�Ż�����" width:200 height:26 align:#center
    label lbl_maxID "���ID��Ŀ:  " align:#left offset:[0,4]
    label lbl_srcMat "ԭ������Ŀ:  " align:#left
    label lbl_curMat "�ֲ�����Ŀ:  " align:#left

    on btn_opt pressed do (
        _51W_Telemetry.track "feature_used" props:#("feature", "MatOptimize")
        local objs = selection as array
        if objs.count == 0 do (messageBox "����ѡ�����" title:"�����Ż�"; return ())
        local maxID = 0, srcCnt = 0, allMats = #()
        for obj in objs do (
            local n = (_51W_Data.getMatIDs obj).numberSet
            if n > maxID do maxID = n
            if obj.material != undefined do
                srcCnt += if classOf obj.material == MultiMaterial then obj.material.materialList.count else 1
        )
        lbl_maxID.text = "���ID��Ŀ:  " + maxID as string
        lbl_srcMat.text = "ԭ������Ŀ:  " + srcCnt as string
        undo "Optimize Materials" on (
            for obj in objs where obj.material != undefined and classOf obj.material == MultiMaterial do (
                local used = _51W_Data.getMatIDs obj
                local mm = obj.material; local nm = MultiMaterial name:mm.name; local idx = 0
                local idMap = #()
                for id in used do (
                    idx += 1
                    if id <= mm.materialList.count do nm.materialList[idx] = mm.materialList[id]
                    idMap[id] = idx
                )
                nm.count = idx
                local b = obj.baseObject
                if classOf b == Editable_Poly then
                    (for f = 1 to (polyop.getNumFaces obj) do (local o = polyop.getFaceMatID obj f; if idMap[o] != undefined do polyop.setFaceMatID obj f idMap[o]))
                else if classOf b == Editable_Mesh then
                    (for f = 1 to obj.mesh.numFaces do (local o = getFaceMatID obj.mesh f; if idMap[o] != undefined do setFaceMatID obj.mesh f idMap[o]))
                obj.material = nm
            )
            for obj in objs where obj.material != undefined do appendIfUnique allMats obj.material
        )
        lbl_curMat.text = "�ֲ�����Ŀ:  " + allMats.count as string
        messageBox "�����Ż���ɣ�" title:"�����Ż�"
    )
)


-- 3. ����ת��
rollout rl_VrayConvert "����ת��" (
    dotNetControl dnPanel "System.Windows.Forms.Panel" width:470 height:200 align:#center

    fn doConvert objList mode = (
        _51W_Telemetry.track "feature_used" props:#("feature", "VrayConvert", "mode", mode, "obj_count", objList.count)
        local c = 0
        for obj in objList where obj.material != undefined do (obj.material = _51W_Data.convertMatRecursive obj.material mode:mode; c += 1)
        c
    )

    fn showTexInViewport objList = (
        _51W_Telemetry.track "feature_used" props:#("feature", "ShowTexInViewport", "obj_count", objList.count)
        local c = 0
        for obj in objList where obj.material != undefined do (
            local mat = obj.material
            if classOf mat == MultiMaterial then (
                for i = 1 to mat.materialList.count where mat.materialList[i] != undefined do (
                    local sub = mat.materialList[i]
                    try (showTextureMap sub true) catch ()
                    try (showTextureMap sub sub.diffuseMap true) catch ()
                    try (showTextureMap sub sub.base_color_map true) catch ()
                    try (showTextureMap sub sub.texmap_diffuse true) catch ()
                )
            ) else (
                try (showTextureMap mat true) catch ()
                try (showTextureMap mat mat.diffuseMap true) catch ()
                try (showTextureMap mat mat.base_color_map true) catch ()
                try (showTextureMap mat mat.texmap_diffuse true) catch ()
            )
            c += 1
        )
        c
    )

    on rl_VrayConvert open do (
        local ui = _51W_Data.getUIColors()
        dnPanel.BackColor = ui[1]

        local gL = _51W_Data.makeGrp dnPanel "VRay����ת��׼����" 0 0 228 125 ui
        local b = _51W_Data.makeBtn gL "ת��ѡ������" 14 28 200 28 ui
        dotNet.addEventHandler b "Click" (fn c s e = execute "(local o=selection as array;if o.count==0 do(messageBox \"\x8BF7\x5148\x9009\x62E9\x5BF9\x8C61\x3002\" title:\"VRay\";return());undo \"V\" on(messageBox((rl_VrayConvert.doConvert o \"vray\") as string+\" \x4E2A\x5BF9\x8C61\x5DF2\x8F6C\x6362\x3002\") title:\"VRay\"))")
        b = _51W_Data.makeBtn gL "ת����������" 14 66 200 28 ui
        dotNet.addEventHandler b "Click" (fn c s e = execute "(if queryBox \"\x786E\x5B9A\x8F6C\x6362\x6240\x6709VRay\x6750\x8D28\xFF1F\" title:\"VRay\" do undo \"V\" on(messageBox((rl_VrayConvert.doConvert(objects as array)\"vray\") as string+\" \x4E2A\x5BF9\x8C61\x5DF2\x8F6C\x6362\x3002\") title:\"VRay\"))")

        local gR = _51W_Data.makeGrp dnPanel "Physical����ת��׼����" 236 0 228 125 ui
        b = _51W_Data.makeBtn gR "ת��ѡ������" 14 28 200 28 ui
        dotNet.addEventHandler b "Click" (fn c s e = execute "(local o=selection as array;if o.count==0 do(messageBox \"\x8BF7\x5148\x9009\x62E9\x5BF9\x8C61\x3002\" title:\"Physical\";return());undo \"P\" on(messageBox((rl_VrayConvert.doConvert o \"physical\") as string+\" \x4E2A\x5BF9\x8C61\x5DF2\x8F6C\x6362\x3002\") title:\"Physical\"))")
        b = _51W_Data.makeBtn gR "ת����������" 14 66 200 28 ui
        dotNet.addEventHandler b "Click" (fn c s e = execute "(if queryBox \"\x786E\x5B9A\x8F6C\x6362\x6240\x6709Physical\x6750\x8D28\xFF1F\" title:\"Physical\" do undo \"P\" on(messageBox((rl_VrayConvert.doConvert(objects as array)\"physical\") as string+\" \x4E2A\x5BF9\x8C61\x5DF2\x8F6C\x6362\x3002\") title:\"Physical\"))")

        local gT = _51W_Data.makeGrp dnPanel "��ʾ�������� | ���ӿ�����ʾ��ͼ" 0 130 464 65 ui
        b = _51W_Data.makeBtn gT "��ʾѡ�ж�������" 14 28 200 28 ui
        dotNet.addEventHandler b "Click" (fn c s e = execute "(local o=selection as array;if o.count==0 do(messageBox \"\x8BF7\x5148\x9009\x62E9\x5BF9\x8C61\x3002\" title:\"\x663E\x793A\x7EB9\x7406\";return());messageBox((rl_VrayConvert.showTexInViewport o) as string+\" \x4E2A\x5BF9\x8C61\x5DF2\x5F00\x542F\x7EB9\x7406\x663E\x793A\x3002\") title:\"\x663E\x793A\x7EB9\x7406\")")
        b = _51W_Data.makeBtn gT "��ʾ���ж�������" 236 28 200 28 ui
        dotNet.addEventHandler b "Click" (fn c s e = execute "(messageBox((rl_VrayConvert.showTexInViewport(objects as array)) as string+\" \x4E2A\x5BF9\x8C61\x5DF2\x5F00\x542F\x7EB9\x7406\x663E\x793A\x3002\") title:\"\x663E\x793A\x7EB9\x7406\")")
    )
)


-- 4. һ���Զ�����
rollout rl_AutoName "һ���Զ�����" width:490 (
    dotNetControl dnPanel "System.Windows.Forms.Panel" width:470 height:140 align:#center
    local txtMatPfx, txtTexPfx, txtMeshPfx, txtMeshMid

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

    -- ����ͼ�ڵ�(������ Normal_Bump �Ȱ�װ)����ȡ BitmapTexture
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

    -- ����������ռ���ͼ, ���� #(#("_D", bmp), #("_R", bmp), ...)
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
        local pfx = if txtMeshPfx != undefined then txtMeshPfx.Text else "SM"
        local mid = if txtMeshMid != undefined then txtMeshMid.Text else ""
        _51W_Data.meshPrefix = pfx; _51W_Data.meshMid = mid
        local objs = selection as array
        if objs.count == 0 do (messageBox "����ѡ�����" title:"������"; return ())
        undo "Rename" on (
            for i = 1 to objs.count do (
                local base = objs[i].name
                if matchPattern base pattern:(pfx + "_*") do base = substring base (pfx.count + 2) -1
                objs[i].name = pfx + (if mid != "" then ("_" + mid) else "") + "_" + base
            )
            messageBox (objs.count as string + " ����������������") title:"������"
        )
    )

    fn doRenameMat = (
        _51W_Telemetry.track "feature_used" props:#("feature", "AutoNameMaterial")
        local pfx = if txtMatPfx != undefined then txtMatPfx.Text else "MI_"
        local objs = selection as array
        if objs.count == 0 do (messageBox "����ѡ�����" title:"����������"; return ())
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
        messageBox (c as string + " ����������������") title:"����������"
    )

    fn doRenameTex = (
        _51W_Telemetry.track "feature_used" props:#("feature", "AutoNameTexture")
        local pfx = if txtTexPfx != undefined then txtTexPfx.Text else "T_"
        local objs = selection as array
        if objs.count == 0 do (messageBox "����ѡ�����" title:"��������ͼ"; return ())
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
        local msg = "�ɹ�: " + ok as string
        if fail > 0 do msg += "  ʧ��: " + fail as string
        messageBox msg title:"��������ͼ"
    )

    on rl_AutoName open do (
        local ui = _51W_Data.getUIColors()
        dnPanel.BackColor = ui[1]

        -- ��һ��: һ��ģ�͸��� GroupBox
        local gM = _51W_Data.makeGrp dnPanel "һ��ģ�͸���" 0 0 464 55 ui
        _51W_Data.makeLbl gM "ǰ׺��" 14 22 42 18 ui
        txtMeshPfx = _51W_Data.makeTxt gM "SM" 58 20 50 22 ui
        _51W_Data.makeLbl gM "�м���" 120 22 42 18 ui
        txtMeshMid = _51W_Data.makeTxt gM "" 164 20 80 22 ui
        local b = _51W_Data.makeBtn gM "һ��ģ�͸���" 310 18 140 26 ui
        dotNet.addEventHandler b "Click" (fn c s e = execute "rl_AutoName.doRename()")

        -- �ڶ���: ������ + ��ͼ��
        local gL = _51W_Data.makeGrp dnPanel "һ������������" 0 60 228 78 ui
        _51W_Data.makeLbl gL "����ǰ׺��" 10 20 70 18 ui
        txtMatPfx = _51W_Data.makeTxt gL "MI_" 82 18 60 22 ui
        b = _51W_Data.makeBtn gL "�Զ����Ĳ�������" 14 46 200 26 ui
        dotNet.addEventHandler b "Click" (fn c s e = execute "rl_AutoName.doRenameMat()")

        local gR = _51W_Data.makeGrp dnPanel "һ��������ͼ��" 236 60 228 78 ui
        _51W_Data.makeLbl gR "��ͼǰ׺��" 10 20 70 18 ui
        txtTexPfx = _51W_Data.makeTxt gR "T_" 82 18 60 22 ui
        b = _51W_Data.makeBtn gR "�Զ��޸���ͼ����" 14 46 200 26 ui
        dotNet.addEventHandler b "Click" (fn c s e = execute "rl_AutoName.doRenameTex()")
    )
)


-- 5. ���_FBX�������
rollout rl_FBXExport "��������" (
    group "����ģʽ" (
        radioButtons rdo_mode labels:#("����ѡ��ģ��ΪFBX", "����ģ��λ����Ϣ�����а�") default:1 columns:2
    )
    group "��������" (
        checkbox chk_grid "ʹ���û�������������Ϊ\"UE4_Grid\"��" checked:false across:2 align:#left
        checkbox chk_origin "�ƶ���(0,0,0)����" checked:false align:#left
        checkbox chk_ucx "����UCX��ײ" checked:false across:2 align:#left
        checkbox chk_dlg "��ʾ��������" checked:false align:#left
    )
    editText edt_path "����·��:" text:"" fieldWidth:330 align:#left
    button btn_browse "..." width:28 height:20 align:#right offset:[-36,-23]
    button btn_clear "X" width:20 height:20 align:#right offset:[-8,-23]
    button btn_open "�򿪵���·��" width:120 height:20 align:#center offset:[0,-2]
    label lbl_prev "������������ģ��:" align:#left offset:[0,2]
    editText edt_list "" height:60 readOnly:true fieldWidth:460 align:#center offset:[0,-2]
    button btn_export "����ѡ��ģ��" width:300 height:30 align:#center offset:[0,2]

    fn refreshPreview = (
        local txt = if edt_path.text != "" then (edt_path.text + "\n") else ""
        local pfx = _51W_Data.meshPrefix
        for obj in (selection as array) do
            txt += "  " + (if pfx != "" and not matchPattern obj.name pattern:(pfx + "_*") then (pfx + "_") else "") + obj.name + ".fbx @ [" + obj.pos.x as string + "," + obj.pos.y as string + "," + obj.pos.z as string + "]\n"
        edt_list.text = txt
    )

    on rl_FBXExport open do refreshPreview()
    on btn_browse pressed do (local p = getSavePath caption:"ѡ��FBX����·��"; if p != undefined do (edt_path.text = p; _51W_Data.exportPath = p; refreshPreview()))
    on btn_clear pressed do (edt_path.text = ""; _51W_Data.exportPath = "")
    on btn_open pressed do (if edt_path.text != "" and doesFileExist edt_path.text do shellLaunch "explorer.exe" edt_path.text)

    on btn_export pressed do (
        _51W_Telemetry.track "feature_used" props:#("feature", "FBXExport")
        local objs = selection as array
        if objs.count == 0 do (messageBox "����ѡ��ģ�͡�" title:"FBX����"; return ())
        local ep = edt_path.text
        if ep == "" do (messageBox "�������õ���·����" title:"FBX����"; return ())
        makeDir ep all:true

        if rdo_mode.state == 1 then (
            undo "FBX Export" on (
                local n = 0
                -- FBXȫ�����ã�ֻ��һ�Σ�
                for s in #(#("SmoothingGroups",true),#("Triangulate",false),#("EmbedTextures",false),
                    #("FileVersion","FBX201800"),#("UpAxis","Z"),#("ConvertUnit","cm"),
                    #("Animation",false),#("Skin",false),#("Shape",false),#("Cameras",false),#("Lights",false)) do
                    FBXExporterSetParam s[1] s[2]

                local showDlg = chk_dlg.checked
                for obj in objs do (
                    local op = obj.pos
                    local ucx = if chk_ucx.checked then (for o in objects where matchPattern o.name pattern:("UCX_" + obj.name + "*") collect o) else #()
                    if chk_origin.checked do (obj.pos = [0,0,0]; for u in ucx do u.pos -= op)
                    select (join #(obj) ucx)
                    local pfx = _51W_Data.meshPrefix
                    local fname = (if pfx != "" and not matchPattern obj.name pattern:(pfx + "_*") then (pfx + "_") else "") + obj.name
                    local fp = ep + "\\" + fname + ".fbx"
                    if showDlg then exportFile fp selectedOnly:true using:FBXEXP
                    else exportFile fp #noPrompt selectedOnly:true using:FBXEXP
                    if chk_origin.checked do (obj.pos = op; for u in ucx do u.pos += op)
                    n += 1
                )
                select objs
            )
        ) else (
            local s = ""
            for obj in objs do s += obj.name + " @ [" + obj.pos.x as string + "," + obj.pos.y as string + "," + obj.pos.z as string + "]\n"
            setClipBoardText s
            messageBox ("�Ѹ��� " + objs.count as string + " ��λ�õ����а塣") title:"FBX����"
        )
    )
)


-- 6. ���ù���
rollout rl_CommonTools "���ù���" (
    button btn_clr "����������" width:180 height:26 align:#center
    button btn_ctr "����������" width:140 height:26 align:#left offset:[20,0]
    button btn_bot "�������ײ�" width:140 height:26 align:#right offset:[-20,-30]
    button btn_top "����������" width:140 height:26 align:#left offset:[20,0]
    button btn_org "������ԭ��" width:140 height:26 align:#right offset:[-20,-30]
    button btn_rst "һ�����ñ任" width:180 height:26 align:#center
    dotNetControl dnToolPanel "System.Windows.Forms.Panel" width:470 height:145 align:#center offset:[0,4]
    local spnQuadAngleCtrl

    fn selObjs = (local o = selection as array; if o.count == 0 do return #(); o)

    fn nearestPow2 v = (
        if v <= 1 do return 1
        local p = 1
        while p < v do p *= 2
        if (p - v) <= (v - p/2) then p else p/2
    )

    on rl_CommonTools open do (
        local ui = _51W_Data.getUIColors()
        dnToolPanel.BackColor = ui[1]

        local gL = _51W_Data.makeGrp dnToolPanel "��ͼ2���ݻ� | ѡ�ж������" 0 0 228 65 ui
        local b = _51W_Data.makeBtn gL "��ͼ�ߴ�2���ݻ�" 14 24 200 28 ui
        dotNet.addEventHandler b "Click" (fn c s e = execute "rl_CommonTools.doPow2()")

        local gR = _51W_Data.makeGrp dnToolPanel "���ɷ��� | ���ʱ༭��ѡ�в���" 236 0 228 65 ui
        b = _51W_Data.makeBtn gR "���ɷ�����ͼ" 14 24 200 28 ui
        dotNet.addEventHandler b "Click" (fn c s e = execute "rl_CommonTools.doNmap()")

        local gQ = _51W_Data.makeGrp dnToolPanel "ȥ�Խ��� | �����滹ԭ�ı���" 0 70 464 65 ui
        _51W_Data.makeLbl gQ "ƽ����ֵ:" 14 28 60 20 ui
        spnQuadAngleCtrl = _51W_Data.makeSpn gQ 0.1 30.0 2.0 1 0.5 76 26 60 22 ui
        b = _51W_Data.makeBtn gQ "ȥ�Խ���" 150 24 200 28 ui
        dotNet.addEventHandler b "Click" (fn c s e = execute "rl_CommonTools.doQuadrify()")
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
        messageBox ("���� " + d as string + " �������塣") title:"����"
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
        if o.count == 0 do (messageBox "����ѡ�����" title:"���ñ任"; return ())
        undo "Reset XForm" on (for obj in o do (resetXForm obj; collapseStack obj))
        messageBox "���ñ任��ɣ�" title:"���ñ任"
    )

    fn doQuadrify = (
        _51W_Telemetry.track "feature_used" props:#("feature", "Quadrify")
        local objs = selObjs()
        if objs.count == 0 do (messageBox "����ѡ�����" title:"ȥ�Խ���"; return ())
        local angThresh = if spnQuadAngleCtrl != undefined then (spnQuadAngleCtrl.Value as float) else 2.0
        local totalRemoved = 0; local totalObj = 0
        local oldSubLevel = subObjectLevel
        undo "ȥ�Խ���" on (
            for obj in objs where superClassOf obj == GeometryClass do (
                -- ת��Ϊ Editable Poly
                if classOf obj.baseObject != Editable_Poly do convertToPoly obj
                if classOf obj.baseObject != Editable_Poly do (format "�޷�ת��: %\n" obj.name; continue)

                local numE = polyop.getNumEdges obj
                if numE == 0 do continue

                -- �ռ���ѡ�Խ���: ���඼���������ҽ��ƹ���
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

                -- ��ƽ���������������
                fn _cmpAng a b = (if a[2] < b[2] then -1 else if a[2] > b[2] then 1 else 0)
                qsort candidates _cmpAng

                -- ̰�����: ÿ��������ֻ�ϲ�һ��
                local usedFaces = #{}
                local edgesToRemove = #{}
                for c in candidates do (
                    local f1 = c[3]; local f2 = c[4]
                    if not usedFaces[f1] and not usedFaces[f2] do (
                        usedFaces[f1] = true; usedFaces[f2] = true
                        edgesToRemove[c[1]] = true
                    )
                )

                local cnt = edgesToRemove.numberSet
                if cnt > 0 do (
                    polyop.setEdgeSelection obj edgesToRemove
                    subObjectLevel = 2
                    obj.EditablePoly.Remove()
                    subObjectLevel = 0
                    totalRemoved += cnt; totalObj += 1
                )
            )
        )
        subObjectLevel = oldSubLevel
        messageBox (totalObj as string + " �������Ƴ� " + totalRemoved as string + " ���Խ��ߡ�") title:"ȥ�Խ���"
    )

    fn doPow2 = (
        _51W_Telemetry.track "feature_used" props:#("feature", "TexturePow2")
        local objs = selObjs()
        if objs.count == 0 do (messageBox "����ѡ�����" title:"��ͼ2���ݻ�"; return ())
        local processed = #(); local ok = 0; local fail = 0; local skip = 0
        for obj in objs where obj.material != undefined do (
            local bms = #(); collectBmps obj.material bms
            for bmp in bms do (
                local fp = bmp.filename
                if fp == undefined or fp == "" do continue
                -- ���Խ�������·��
                if not doesFileExist fp do (
                    local resolved = mapPaths.getFullFilePath fp
                    if resolved != undefined and resolved != "" do fp = resolved
                )
                if findItem processed fp > 0 do continue
                append processed fp
                if not doesFileExist fp do (fail += 1; continue)
                try (
                    local img = openBitmap fp
                    local ow = img.width; local oh = img.height
                    local nw = nearestPow2 ow; local nh = nearestPow2 oh
                    if nw != ow or nh != oh then (
                        close img
                        -- ʹ��dotNet��������
                        local dnImg = (dotNetClass "System.Drawing.Image").FromFile fp
                        local dst = dotNetObject "System.Drawing.Bitmap" nw nh
                        local gr = (dotNetClass "System.Drawing.Graphics").FromImage dst
                        gr.InterpolationMode = (dotNetClass "System.Drawing.Drawing2D.InterpolationMode").HighQualityBicubic
                        gr.DrawImage dnImg 0 0 nw nh
                        gr.Dispose()
                        dnImg.Dispose()
                        local ext = toLower (getFilenameType fp)
                        local fmt = case ext of (
                            ".png": (dotNetClass "System.Drawing.Imaging.ImageFormat").Png
                            ".jpg": (dotNetClass "System.Drawing.Imaging.ImageFormat").Jpeg
                            ".jpeg": (dotNetClass "System.Drawing.Imaging.ImageFormat").Jpeg
                            ".bmp": (dotNetClass "System.Drawing.Imaging.ImageFormat").Bmp
                            ".tif": (dotNetClass "System.Drawing.Imaging.ImageFormat").Tiff
                            ".tiff": (dotNetClass "System.Drawing.Imaging.ImageFormat").Tiff
                            default: (dotNetClass "System.Drawing.Imaging.ImageFormat").Png
                        )
                        dst.Save fp fmt
                        dst.Dispose()
                        ok += 1
                    ) else (close img; skip += 1)
                ) catch (fail += 1)
            )
        )
        local msg = "�޸�: " + ok as string
        if skip > 0 do msg += "  ����2����: " + skip as string
        if fail > 0 do msg += "  ʧ��: " + fail as string
        messageBox msg title:"��ͼ2���ݻ�"
    )

    fn doNmap = (
        _51W_Telemetry.track "feature_used" props:#("feature", "NormalMapGen")
        -- ��ȡ���ʱ༭���е�ǰѡ�еĲ���
        local m = medit.GetCurMtl()
        if m == undefined do (messageBox "�����ڲ��ʱ༭����ѡ��һ�����ʡ�" title:"���ɷ���"; return ())
        -- ���ѡ�е���MultiMaterial,��ʾѡ���Ӳ���
        if classOf m == MultiMaterial do (messageBox "��ѡ�������Ӳ��ʣ����Ƕ�ά���ʡ�" title:"���ɷ���"; return ())

        local hasBump = false; local diffTex = undefined
        if classOf m == StandardMaterial then (
            hasBump = m.bumpMap != undefined
            if m.diffuseMap != undefined and classOf m.diffuseMap == BitmapTexture do diffTex = m.diffuseMap
        ) else if classOf m == PhysicalMaterial then (
            hasBump = m.bump_map != undefined
            if m.base_color_map != undefined and classOf m.base_color_map == BitmapTexture do diffTex = m.base_color_map
        ) else (messageBox ("��֧�ֵĲ�������: " + (classOf m) as string) title:"���ɷ���"; return ())

        if hasBump do (messageBox "�ò������з���/��͹��ͼ��" title:"���ɷ���"; return ())
        if diffTex == undefined do (messageBox "�ò���û����������ͼ���޷����ɷ��ߡ�" title:"���ɷ���"; return ())

        local srcPath = diffTex.filename
        if srcPath == undefined or srcPath == "" do (messageBox "��ͼ�ļ�·��Ϊ�ա�" title:"���ɷ���"; return ())
        if not doesFileExist srcPath do (
            local resolved = mapPaths.getFullFilePath srcPath
            if resolved != undefined and resolved != "" then srcPath = resolved
            else (messageBox ("�Ҳ�����ͼ�ļ�: " + srcPath) title:"���ɷ���"; return ())
        )
        if not doesFileExist srcPath do (messageBox ("�Ҳ�����ͼ�ļ�: " + srcPath) title:"���ɷ���"; return ())

        local dir = getFilenamePath srcPath
        local base = getFilenameFile srcPath
        local dstPath = dir + base + "_N.png"
        local str = 2.0

        try (
            local img = openBitmap srcPath
            local w = img.width; local h = img.height
            local rows = for y = 0 to h-1 collect getPixels img [0, y] w
            close img

            local dst = bitmap w h filename:dstPath
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
            messageBox ("������ͼ�����ɲ�Ӧ��!\n" + (filenameFromPath dstPath)) title:"���ɷ���"
        ) catch (messageBox ("����ʧ��: " + (getCurrentException()) as string) title:"���ɷ���")
    )
)


-- 7. �����߹���
rollout rl_SplineTools "�����߹���" (
    dotNetControl dnSplinePanel "System.Windows.Forms.Panel" width:470 height:330 align:#center
    local spnAngleCtrl
    local rbDirV, rbDirU, spnDensityCtrl
    -- ����ɨ������ ״̬
    local pickedCross = undefined, pickedPath = undefined
    local lblCrossName, lblPathName
    local spnSteps
    local chkCap, chkFlip

    -- ��ȡÿ���������ߵĶ������ȣ���ʱ�����޸�����ȡ�ײ������ߣ�
    fn getSplineLengths obj = (
        local lengths = #()
        local disabledMods = #()
        for m in obj.modifiers where m.enabled do (append disabledMods m; m.enabled = false)
        try (for s = 1 to (numSplines obj) do append lengths (curveLength obj s)) catch ()
        for m in disabledMods do m.enabled = true
        lengths
    )

    -- ��ȡ����/ϵͳ��λ�����
    fn getCmPerUnit = (
        local t = units.SystemType
        local b = case t of (#Inches:2.54; #Feet:30.48; #Miles:160934.0; #Millimeters:0.1; #Centimeters:1.0; #Meters:100.0; #Kilometers:100000.0; default:1.0)
        units.SystemScale * b
    )

    -- �Ƴ�֮ǰ�ű����ӵ� PipeUVNorm �޸���
    fn removeOldMods obj = (
        for i = obj.modifiers.count to 1 by -1 do (
            if obj.modifiers[i].name == "PipeUVNorm" do deleteModifier obj obj.modifiers[i]
        )
    )

    -----------------------------------------------------------------
    -- ����ɨ�����ɣ���������
    -----------------------------------------------------------------
    -- ��ȫ��һ�������Ƚӽ� 0 ʱ���� fallback
    fn safeNormalize v fallback = (
        if (length v) < 0.0001 then fallback else (normalize v)
    )

    -- Cubic Bezier ��ֵ
    fn bezEval p0 p1 p2 p3 t = (
        local u = 1.0 - t
        u*u*u*p0 + 3*u*u*t*p1 + 3*u*t*t*p2 + t*t*t*p3
    )
    -- Cubic Bezier ���ߣ�δ��һ����
    fn bezTan p0 p1 p2 p3 t = (
        local u = 1.0 - t
        3*u*u*(p1-p0) + 6*u*t*(p2-p1) + 3*t*t*(p3-p2)
    )

    -- �ж�һ�Σ�knot k �� k+1���Ƿ�Ϊֱ��
    fn isStraightSeg obj si k p0 p1 p2 p3 = (
        local segType = try (getSegmentType obj si k) catch (#curve)
        if segType == #line then true
        else (
            -- ��������Ϊ curve�������Ʊ��˻��ɶ˵㣨����������Ҳ��Ϊֱ��
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

    -- �����������߲��������� #(pos, tangent) ���飨�����ѹ�һ����
    -- stepsOverride: ���߶�ϸ������ÿ�� nSub ���Ȳ�����<=0 ��ʾ�������������� steps
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

            -- ��㣨ÿ�ζ��������ںϲ��׶��� miter��
            local startTanForEmit = if straight then segDir else (safeNormalize (bezTan p0 p1 p2 p3 0.0) segDir)
            append samples #(p0, startTanForEmit)

            if straight then (
                -- ֱ�߶Σ�ֻ׷���յ�
                append samples #(p3, segDir)
            ) else (
                -- ���߶Σ��������ߵ� steps ���ԵȲ�ϸ�֣�����������ʾһ�£�
                local nSub = if stepsOverride > 0 then stepsOverride else (try (obj.steps + 1) catch (6))
                if nSub < 1 do nSub = 1
                for i = 1 to nSub do (
                    local t = (i as float) / nSub
                    local pos = bezEval p0 p1 p2 p3 t
                    append samples #(pos, safeNormalize (bezTan p0 p1 p2 p3 t) segDir)
                )
            )
        )

        -- �պ�·����ȥ���ظ���β�㣨���׵��غϣ�
        if closed and samples.count > 1 do (
            local last = samples[samples.count][1]
            local first = samples[1][1]
            if (distance last first) < 0.0001 do deleteItem samples samples.count
        )
        samples
    )

    -- �ù̶������Ϸ���Z������ÿ�� frame������ parallel transport ��·���ۻ�Ťת
    -- �������飺ÿ��Ԫ�� #(pos, xAxis, yAxis, zAxis, scl)��z = ���ߣ�scl = miter ��������
    fn buildFrames samples =
    (
        local frames = #()
        if samples.count == 0 do return frames
        local worldUp = [0,0,1]
        for i = 1 to samples.count do (
            local pos = samples[i][1]
            local curT = samples[i][2]
            local scl = if samples[i].count >= 3 then samples[i][3] else 1.0
            -- ���߼���ƽ�� Z ʱ�� Y ��Ϊ�ο����������˻�
            local up = if (abs (dot curT worldUp)) > 0.99 then [0,1,0] else worldUp
            local xA = normalize (cross up curT)
            local yA = normalize (cross curT xA)
            append frames #(pos, xA, yA, curT, scl)
        )
        frames
    )

    -- ��ģ�ͱ߽���ȡ���������� point2 ���� + �Ƿ�պϣ���ģ�������ֲ������ XY ƽ�棩
    fn getCrossSectionFromMesh obj = (
        local result = #(#(), false)
        local tmpMesh = snapshotAsMesh obj
        if tmpMesh == undefined do return result
        -- �ռ����űߣ�ֻ����һ����ıߣ�
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
        -- �ѱ��������򻷣��ӵ�һ���߿�ʼ����������ϵ��
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
        -- ���� AABB�����������Ϊ���߷��򣬰������������������� 2D
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
        -- �������ģ���ѡ���������ϣ��Ծ���
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

    -- �ӽ�����������ȡ���㣨ͶӰ�� XY ƽ�棩������ point2 ���� + �Ƿ�պ�
    -- ����������������ϵ�� XY ƽ��Ϊ׼��Z ������·������
    fn getCrossSection obj = (
        local result = #(#(), false)
        if not (isKindOf obj SplineShape or isKindOf obj line) do (
            -- ģ�Ͷ�������һ��·������ȡ�߽�
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

        -- ����
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

        -- ���������� + ��¼ÿ�� quad �ĶԽ��߶���ԣ�key set��O(E) ���ң�
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
                -- �� (min,max) ����ɵ������� key��a * (totalVerts+1) + b
                local da = v00; local db = v11
                if da > db do (local t = da; da = db; db = t)
                diagKeys[da * (totalVerts + 1) + db] = true
            )
        )

        local m = mesh vertices:verts faces:faces name:nodeName
        convertToPoly m

        -- ɾ���Խ��߱ߣ������ǶԺϲ��� quad��O(E) ���ң�
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

        -- �˸� ngon��ֱ���� poly �� createPolygon
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

    -- �ϲ�λ���غϣ��սǴ�����������������ƽ������Ϊ���ߣ�miter��
    -- ͬʱ���� miter �������ţ�1/cos(��/2)������սǴ������խ
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
            messageBox "����ʰȡ������·�������ߡ�" title:"����ɨ������"; return ()
        )
        if not (isKindOf pickedCross SplineShape or isKindOf pickedCross line or isKindOf pickedCross GeometryClass) do (
            messageBox "����������Ͳ�֧�֡�" title:"����ɨ������"; return ()
        )
        if not (isKindOf pickedPath SplineShape or isKindOf pickedPath line) do (
            messageBox "·�������������ߡ�" title:"����ɨ������"; return ()
        )

        local stepsOverride = if spnSteps != undefined then (spnSteps.Value as integer) else 0
        local capEnds = if chkCap != undefined then (chkCap.Checked) else true
        local flipN = if chkFlip != undefined then (chkFlip.Checked) else false

        -- ���棺�������ֲ�����ȡ����
        local crossInfo = getCrossSection pickedCross
        local crossPts = crossInfo[1]
        local crossClosed = crossInfo[2]
        if crossPts.count < 2 do (
            messageBox "���涥�㲻�㡣" title:"����ɨ������"; return ()
        )

        -- ·��������ÿ���������ߣ�ÿ������һ�� mesh����� attach ��һ��
        local pathObj = pickedPath
        local nSpl = numSplines pathObj
        local builtNodes = #()
        undo "����ɨ������" on (
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
                messageBox "δ�����κ�ģ�͡�" title:"����ɨ������"; return ()
            )
            -- �ϲ�����Ƭ��
            local main = builtNodes[1]
            for i = 2 to builtNodes.count do (
                polyop.attach main builtNodes[i] deleteSourceNode:true
            )
            main.name = uniqueName "SplineSweepMesh_"
            select main
        )
    )

    -----------------------------------------------------------------

    on rl_SplineTools open do (
        local ui = _51W_Data.getUIColors()
        dnSplinePanel.BackColor = ui[1]

        local gS = _51W_Data.makeGrp dnSplinePanel "�����߼� | ѡ�������ߺ���" 0 0 464 65 ui
        _51W_Data.makeLbl gS "�Ƕ���ֵ:" 14 28 60 20 ui
        spnAngleCtrl = _51W_Data.makeSpn gS 0.1 45.0 5.0 1 0.5 76 26 60 22 ui
        local b = _51W_Data.makeBtn gS "��������" 150 24 200 28 ui
        dotNet.addEventHandler b "Click" (fn c s e = execute "rl_SplineTools.doSplineSimp()")

        -- �ڶ���: �ܵ�UV�ܶ�ͳһ
        local gU = _51W_Data.makeGrp dnSplinePanel "�ܵ�UV�ܶ�ͳһ | Sweep�ܵ������ܶ�һ�»�" 0 70 464 105 ui

        _51W_Data.makeLbl gU "������:" 14 22 50 18 ui
        rbDirV = dotNetObject "System.Windows.Forms.RadioButton"
        rbDirV.Text = "V"; rbDirV.Checked = true
        rbDirV.ForeColor = ui[2]; rbDirV.Font = ui[4]
        rbDirV.Bounds = dotNetObject "System.Drawing.Rectangle" 66 20 36 20
        gU.controls.add rbDirV
        rbDirU = dotNetObject "System.Windows.Forms.RadioButton"
        rbDirU.Text = "U"
        rbDirU.ForeColor = ui[2]; rbDirU.Font = ui[4]
        rbDirU.Bounds = dotNetObject "System.Drawing.Rectangle" 104 20 36 20
        gU.controls.add rbDirU

        local lblTip = dotNetObject "System.Windows.Forms.Label"
        lblTip.Text = "(V=��·������, U=���滷�Ʒ���)"
        lblTip.ForeColor = (dotNetClass "System.Drawing.Color").FromArgb 160 160 160
        lblTip.Font = ui[4]
        lblTip.Bounds = dotNetObject "System.Drawing.Rectangle" 142 22 280 18
        gU.controls.add lblTip
        _51W_Data.makeLbl gU "�Զ����ܶ� UV/cm:" 14 48 120 18 ui
        spnDensityCtrl = _51W_Data.makeSpn gU 0.00001 10000.0 0.01 2 0.001 138 46 74 22 ui

        b = _51W_Data.makeBtn gU "Ԥ����Ϣ" 14 76 200 24 ui
        dotNet.addEventHandler b "Click" (fn c s e = execute "rl_SplineTools.doUVPreview()")
        b = _51W_Data.makeBtn gU "ͳһUV�ܶ�" 236 76 200 24 ui
        dotNet.addEventHandler b "Click" (fn c s e = execute "rl_SplineTools.doUVNormalize()")

        -- ������: ����ɨ������
        local gW = _51W_Data.makeGrp dnSplinePanel "����ɨ������ | ���� + ·�� �� ����Sweep��ֱ�߲��ֶΣ�" 0 180 464 145 ui
        local bC = _51W_Data.makeBtn gW "ʰȡ����..." 14 22 110 24 ui
        dotNet.addEventHandler bC "Click" (fn c s e = execute "rl_SplineTools.doPickCross()")
        lblCrossName = _51W_Data.makeLbl gW "(δʰȡ)" 130 26 320 18 ui

        local bP = _51W_Data.makeBtn gW "ʰȡ·��..." 14 50 110 24 ui
        dotNet.addEventHandler bP "Click" (fn c s e = execute "rl_SplineTools.doPickPath()")
        lblPathName = _51W_Data.makeLbl gW "(δʰȡ)" 130 54 320 18 ui

        _51W_Data.makeLbl gW "ϸ�ֲ���(0=��������steps):" 14 82 170 18 ui
        spnSteps = _51W_Data.makeSpn gW 0 64 0 0 1 186 80 56 22 ui

        chkCap = dotNetObject "System.Windows.Forms.CheckBox"
        chkCap.Text = "�˵���"; chkCap.Checked = true
        chkCap.ForeColor = ui[2]; chkCap.Font = ui[4]
        chkCap.Bounds = dotNetObject "System.Drawing.Rectangle" 14 110 80 20
        gW.controls.add chkCap

        chkFlip = dotNetObject "System.Windows.Forms.CheckBox"
        chkFlip.Text = "��ת����"; chkFlip.Checked = false
        chkFlip.ForeColor = ui[2]; chkFlip.Font = ui[4]
        chkFlip.Bounds = dotNetObject "System.Drawing.Rectangle" 100 110 80 20
        gW.controls.add chkFlip

        local bGo = _51W_Data.makeBtn gW "����ģ��" 250 108 200 26 ui
        dotNet.addEventHandler bGo "Click" (fn c s e = execute "rl_SplineTools.doSweepBuild()")
    )

    fn doPickCross = (
        local o = pickObject prompt:"ѡ�������������߻�ģ�ͣ�"
        if o != undefined and isValidNode o do (
            pickedCross = o
            if lblCrossName != undefined do lblCrossName.Text = o.name
        )
    )

    fn doPickPath = (
        local o = pickObject prompt:"ѡ��·��������" filter:(fn splineFilter obj = isKindOf obj SplineShape or isKindOf obj line)
        if o != undefined and isValidNode o do (
            pickedPath = o
            if lblPathName != undefined do lblPathName.Text = o.name
        )
    )

    fn doSplineSimp = (
        _51W_Telemetry.track "feature_used" props:#("feature", "SplineSimplify")
        local objs = selection as array
        if objs.count == 0 do (messageBox "����ѡ�������߶���" title:"�����߼�"; return ())
        local angThresh = if spnAngleCtrl != undefined then (spnAngleCtrl.Value as float) else 5.0
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
        messageBox (totalObj as string + " �������߹�ɾ�� " + totalRemoved as string + " ���ڵ㡣") title:"�����߼�"
    )

    fn doUVPreview = (
        local objs = selection as array
        if objs.count == 0 do (messageBox "����ѡ��ܵ�����" title:"UV�ܶ�Ԥ��"; return ())
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
            ) else msg += obj.name + ":  [��������]\n"
        )
        messageBox msg title:"�ܵ������߳���"
    )

    fn doUVNormalize = (
        _51W_Telemetry.track "feature_used" props:#("feature", "PipeUVNormalize")
        local objs = selection as array
        if objs.count == 0 do (messageBox "����ѡ��ܵ�����" title:"UV�ܶ�ͳһ"; return ())

        -- �ռ���Ч����͸��������߳���
        local pipeData = #()
        for obj in objs do (
            local lens = getSplineLengths obj
            if lens.count > 0 do append pipeData #(obj, lens)
        )
        if pipeData.count == 0 do (messageBox "δ�ҵ���Ч�������߳��ȡ�" title:"UV�ܶ�ͳһ"; return ())

        -- ȷ�������ܶ�
        local densVal = (spnDensityCtrl.Text as string) as float
        local density = densVal / getCmPerUnit()

        local dirIdx = if rbDirV.Checked then 1 else 2  -- 1=V��, 2=U��

        undo "ͳһ�ܵ�UV�ܶ�" on (
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
                    -- ����������: snapshotAsMesh + Unwrap_UVW ��Ԫ������
                    local theMesh = snapshotAsMesh obj
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
                        free theMesh
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
                )
                count += 1
            )
            messageBox (count as string + " ���ܵ�������ͳһUV�ܶȡ�") title:"UV�ܶ�ͳһ"
        )
    )
)


-- 8. ��������\�ϲ�
rollout rl_BatchImport "��������\\�ϲ�" (
    label lbl_fl "�ļ��б�:" align:#left
    editText edt_list "" height:120 readOnly:true fieldWidth:460 align:#center
    button btn_path "ѡ��·��" width:80 height:24 align:#left offset:[10,0]
    label lbl_type "����\\�ϲ��ļ�����:" align:#center offset:[0,-26]
    radioButtons rdo_type labels:#("OBJ","3DS","FBX","DWG","MAX","ALL") default:3 columns:6
    checkbox chk_sub "�������ļ���" checked:true align:#right offset:[-10,-24]
    button btn_ref "ˢ��" width:50 height:22 align:#right offset:[-10,0]
    button btn_go "��ʼ����" width:440 height:32 align:#center

    fn refresh p = (
        _51W_Data.batchFileList = _51W_Data.collectFiles p (_51W_Data.getFilePattern rdo_type.state) chk_sub.checked
        if rdo_type.state == 6 do (
            local v = #(".obj",".3ds",".fbx",".dwg",".max")
            _51W_Data.batchFileList = for f in _51W_Data.batchFileList where (findItem v (toLower (getFilenameType f))) > 0 collect f
        )
        local t = p + "\n"
        for f in _51W_Data.batchFileList do t += "  " + (filenameFromPath f) + "\n"
        edt_list.text = t + "\n�� " + _51W_Data.batchFileList.count as string + " ���ļ�"
    )

    on btn_path pressed do (local p = getSavePath caption:"ѡ�����ļ���"; if p != undefined do (_51W_Data.importBasePath = p; refresh p))
    on btn_ref pressed do (if _51W_Data.importBasePath != "" do refresh _51W_Data.importBasePath)

    on btn_go pressed do (
        _51W_Telemetry.track "feature_used" props:#("feature", "BatchImport")
        local fl = _51W_Data.batchFileList
        if fl.count == 0 do (messageBox "�ļ��б�Ϊ�ա�" title:"��������"; return ())
        if not (queryBox ("���� " + fl.count as string + " ���ļ���") title:"��������") do return ()
        local ok = 0, ng = 0
        for f in fl do (
            try (
                if toLower (getFilenameType f) == ".max" then mergeMaxFile f #select #mergeDups #renameMtlDups quiet:true
                else if toLower (getFilenameType f) == ".fbx" then importFile f #noPrompt using:FBXIMP
                else importFile f #noPrompt
                ok += 1
            ) catch (ng += 1; format "����ʧ��: %\n" f)
        )
        messageBox ("�ɹ�: " + ok as string + "  ʧ��: " + ng as string) title:"��������"
    )
)


-- 9. Unwrap UVW
rollout rl_UnwrapUVW "Unwrap UVW" (
    dotNetControl dnUVPanel "System.Windows.Forms.Panel" width:470 height:80 align:#center
    local spnPaddingCtrl

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
        -- �������е� Unwrap_UVW
        local found = undefined
        for m in obj.modifiers where classOf m == Unwrap_UVW do (found = m; exit)
        if found != undefined then (
            -- ��鵱ǰ�޸�����Ƿ���ָ����޸���
            local cur = try (modPanel.getCurrentObject()) catch (undefined)
            if cur != found do (
                max modify mode
                modPanel.setCurrentObject found
            )
            if not (isUVEditorOpen()) do found.edit()
            found
        ) else (
            -- û���������µ�
            local uw = Unwrap_UVW()
            uw.setMapChannel ch
            addModifier obj uw
            max modify mode
            modPanel.setCurrentObject uw
            uw.edit()
            uw
        )
    )

    on rl_UnwrapUVW open do (
        local ui = _51W_Data.getUIColors()
        dnUVPanel.BackColor = ui[1]

        local gU = _51W_Data.makeGrp dnUVPanel "UV����" 0 0 464 78 ui
        local b = _51W_Data.makeBtn gU "һ��ƽ��" 14 20 436 24 ui
        dotNet.addEventHandler b "Click" (fn c s e = execute "rl_UnwrapUVW.doFlatten()")
        b = _51W_Data.makeBtn gU "ȫ��ռ��һ����" 14 50 130 24 ui
        dotNet.addEventHandler b "Click" (fn c s e = execute "rl_UnwrapUVW.doFillQuad()")
        _51W_Data.makeLbl gU "���:" 148 52 40 18 ui
        spnPaddingCtrl = _51W_Data.makeSpn gU 0.0 0.5 0.01 2 0.005 188 50 60 22 ui
        b = _51W_Data.makeBtn gU "ÿ��UVռ��һ����" 260 50 190 24 ui
        dotNet.addEventHandler b "Click" (fn c s e = execute "rl_UnwrapUVW.doFillEach()")
    )

    fn doFlatten = (
        _51W_Telemetry.track "feature_used" props:#("feature", "UnwrapFlatten")
        local objs = selection as array
        if objs.count == 0 do (messageBox "����ѡ�����" title:"Unwrap UVW"; return ())
        local c = 0
        undo "һ��ƽ��" on (
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
        if objs.count == 0 do (messageBox "����ѡ�����" title:"Unwrap UVW"; return ())
        local c = 0
        undo "һ��ռ��һ����" on (
            for obj in objs where superClassOf obj == GeometryClass do (
                if selection.count != 1 or selection[1] != obj do select obj
                local uw = getOrAddUnwrap obj ch:1
                subObjectLevel = 3
                local nf = try (polyop.getNumFaces obj) catch (try (obj.mesh.numFaces) catch 0)
                if nf == 0 do continue
                uw.selectFaces #{1..nf}
                uw.pack 1 ((spnPaddingCtrl.Text as string) as float) true true true
                c += 1
            )
        )
    )

    fn doFillEach = (
        _51W_Telemetry.track "feature_used" props:#("feature", "UnwrapFillEach")
        local objs = selection as array
        if objs.count == 0 do (messageBox "����ѡ�����" title:"Unwrap UVW"; return ())
        local c = 0
        undo "ÿ��UVռ��һ����" on (
            for obj in objs where superClassOf obj == GeometryClass do (
                if selection.count != 1 or selection[1] != obj do select obj
                if classOf obj.baseObject != Editable_Poly do convertToPoly obj
                if classOf obj.baseObject != Editable_Poly do continue

                local nf = polyop.getNumFaces obj
                if nf == 0 do continue
                if not (polyop.getMapSupport obj 1) do continue

                -- �� polyop ��� UV ������ UV ��ͨ�ԣ�
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

                -- ���鷨���� UV ����ͬʱ��¼ÿ�����漯�ϣ�
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

                -- ͨ�� Unwrap_UVW �޸����޸� UV������ polyop.setMapVert ������
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
)


-- 10. ��������
rollout rl_OtherTools "��������" (
    dotNetControl dnOtherPanel "System.Windows.Forms.Panel" width:470 height:280 align:#center

    local rbModePoly, rbModeObj, rbModeSG, rbModeElem
    local spnIDCount

    fn getMode = (
        if rbModePoly.Checked then #poly
        else if rbModeObj.Checked then #obj
        else if rbModeSG.Checked then #sg
        else #elem
    )

    fn collectByGroup mode m faceCount = (
        -- ���� #(BitArray, ...) ���飨ͬ�鹲��һ��ID��
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
        if sel.count == 0 do ( messageBox "����ѡ�����" title:"�������ID"; return 0 )
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
            messageBox err title:"����"
            return 0
        )
        messageBox ("�Ѵ��� " + cnt as string + " ������") title:"�������ID"
        cnt
    )

    on rl_OtherTools open do (
        local ui = _51W_Data.getUIColors()
        dnOtherPanel.BackColor = ui[1]

        -- ����1: �������ID
        local g1 = _51W_Data.makeGrp dnOtherPanel "�������ID | Material IDs Random Generator" 0 0 464 95 ui

        _51W_Data.makeLbl g1 "ģʽ:" 14 26 40 18 ui
        rbModePoly = dotNetObject "System.Windows.Forms.RadioButton"
        rbModePoly.Text = "�����"; rbModePoly.Checked = true
        rbModePoly.ForeColor = ui[2]; rbModePoly.Font = ui[4]
        rbModePoly.Bounds = dotNetObject "System.Drawing.Rectangle" 56 24 70 20
        g1.controls.add rbModePoly

        rbModeObj = dotNetObject "System.Windows.Forms.RadioButton"
        rbModeObj.Text = "����"
        rbModeObj.ForeColor = ui[2]; rbModeObj.Font = ui[4]
        rbModeObj.Bounds = dotNetObject "System.Drawing.Rectangle" 132 24 60 20
        g1.controls.add rbModeObj

        rbModeSG = dotNetObject "System.Windows.Forms.RadioButton"
        rbModeSG.Text = "ƽ����"
        rbModeSG.ForeColor = ui[2]; rbModeSG.Font = ui[4]
        rbModeSG.Bounds = dotNetObject "System.Drawing.Rectangle" 198 24 70 20
        g1.controls.add rbModeSG

        rbModeElem = dotNetObject "System.Windows.Forms.RadioButton"
        rbModeElem.Text = "Ԫ��"
        rbModeElem.ForeColor = ui[2]; rbModeElem.Font = ui[4]
        rbModeElem.Bounds = dotNetObject "System.Drawing.Rectangle" 274 24 60 20
        g1.controls.add rbModeElem

        _51W_Data.makeLbl g1 "�Ӳ�����:" 14 58 70 20 ui
        spnIDCount = _51W_Data.makeSpn g1 1 256 3 0 1 84 56 60 22 ui

        local bGen = _51W_Data.makeBtn g1 "�������" 234 54 210 28 ui
        dotNet.addEventHandler bGen "Click" (fn c s e = (try (rl_OtherTools.doRandMatID()) catch (messageBox (getCurrentException()) title:"����")))

        -- ����2 / ����3 ռλ
        local g2 = _51W_Data.makeGrp dnOtherPanel "����2 | ������" 0 100 464 65 ui
        local g3 = _51W_Data.makeGrp dnOtherPanel "����3 | ������" 0 170 464 65 ui
    )
)


-- 11. ע��
rollout rl_Note "ע��" (label lbl "ʹ��ǰ��ȷ�������ѱ��档����Max 2025+, UE4/UE5��" align:#left)


-- ������������
_51W_Floater = newRolloutFloater "51WORLD�����Դ�Զ�ת������ Version 3" 510 980
for r in #(rl_BakeAO, rl_MatOptimize, rl_VrayConvert, rl_AutoName, rl_FBXExport, rl_CommonTools, rl_SplineTools, rl_UnwrapUVW, rl_BatchImport, rl_OtherTools, rl_Note) do
    addRollout r _51W_Floater rolledUp:true
