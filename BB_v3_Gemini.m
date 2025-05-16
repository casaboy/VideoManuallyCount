classdef BB_v3_Gemini < matlab.apps.AppBase

    % 公共属性：对应 App 设计器中的 UI 组件
    properties (Access = public)
        UIFigure                 matlab.ui.Figure                   % 主窗口 Figure
        BrinkmanboardtaskLabel   matlab.ui.control.Label            % (可选) 标题标签
        resultPanel              matlab.ui.container.Panel          % 右侧结果与标注面板
        HandRestraintPlane       matlab.ui.container.Panel
        handlist                 matlab.ui.container.GridLayout
        NoRestraintButton        matlab.ui.control.CheckBox         %   - 无束缚
        LeftRestraintButton      matlab.ui.control.CheckBox         %   - 左手束缚
        RightRestraintButton     matlab.ui.control.CheckBox         %   - 右手束缚
        SlotsLabel               matlab.ui.control.Label            % "共" 标签
        SlotsEditField           matlab.ui.control.NumericEditField % 输入槽数量的编辑框
        SlotsUnitLabel           matlab.ui.control.Label            % "个槽" 标签
        GetButton                matlab.ui.control.Button           % "Get" 按钮 (快捷键 'c')
        RightButton              matlab.ui.control.Button           % "Right" 按钮 (快捷键 'd')
        LeftButton               matlab.ui.control.Button           % "Left" 按钮 (快捷键 'a')
        ResultTable              matlab.ui.control.Table            % 显示标注结果的表格
        ConfirmButton            matlab.ui.control.Button           % "确认并保存" 按钮
        controlPanel             matlab.ui.container.Panel          % 视频播放控制面板
        SpeedMultiplierLabel     matlab.ui.control.Label            % "速度:" 标签
        SpeedEditField           matlab.ui.control.EditField        % 播放速度编辑框
        TotalDurationLabel       matlab.ui.control.Label            % 显示视频总时长标签
        CurrentTimeLabel         matlab.ui.control.Label            % 显示当前播放时间标签
        ExitButton               matlab.ui.control.Button           % "退出" 按钮
        TimeSlider               matlab.ui.control.Slider           % 视频播放进度条
        listPanel                matlab.ui.container.Panel          % 左下角视频列表面板
        SelectFolderButton       matlab.ui.control.Button           % "选择文件夹" 按钮
        VideoListTable           matlab.ui.control.Table            % 显示视频文件列表的表格
        videoPanel               matlab.ui.container.Panel          % 左上角视频播放面板
        % FileNameLabel            matlab.ui.control.Label            % 显示当前视频文件名标签
        PauseButton              matlab.ui.control.Button           % 播放/暂停 按钮

        RotateLeftButton         matlab.ui.control.Button           % 逆时针旋转按钮
        RotateRightButton        matlab.ui.control.Button           % 顺时针旋转按钮
    end

    % 私有属性：存储 App 内部状态和数据
    properties (Access = private)
        videoObject              % VideoReader 对象句柄
        playAxesHandle           % 视频播放区域的坐标轴句柄
        videoDisplayHandle       % 用于显示视频帧的图像对象句柄
        videoTimer               % 主视频播放定时器
        repeatTimer              % 重复播放某个 Trial 的定时器

        currentFolderPath        % 当前选择的包含视频文件的文件夹路径
        resultsFilePath          % 结果 .mat 文件的完整路径
        persistentFolderPathFile % 存储上次选择文件夹路径的文本文件路径

        allResultsData           % 存储从 .mat 文件加载的所有视频的标注结果 (结构体数组)
        currentVideoResults      % 当前选中视频的标注结果 (单个结构体)
        currentTrialIndex        % 当前正在标注的 Trial 序号 (行号)

        defaultSlots = 37;       % Brinkman board 的默认槽数
        % resultsDataFilename = 'BB_Rating.mat'; % 保存标注结果的文件名
        isSliderBeingUpdatedByTimer = false; % 添加一个标志位防止timer更新slider时触发回调
        handCheckbox
        currentRotationAngle = 0; % Current rotation angle in degrees (0, 90, 180, 270)
        isStoppingTimer = false; % ---> 新增标志位 <---
    end

    % 常量属性：定义固定的列索引等，提高代码可读性和可维护性
    properties (Constant, Access = private)
        LEFT_HAND_COL = 2;       % ResultTable 中 "Left" 列的索引
        RIGHT_HAND_COL = 3;      % ResultTable 中 "Right" 列的索引
        GET_TIME_COL = 4;        % ResultTable 中 "Get" 列的索引
        PROCESS_COL = 2;         % VideoListTable 中 "Processed" 列的索引
        DEFAULT_SPEED = '1';     % 默认播放速度
        DEFAULT_PANEL_TITLE = '视频播放'
    end

    % 私有方法：包含 App 的核心逻辑和辅助功能
    methods (Access = private)

        % --- 辅助函数  ---

        function updateUIState(app, state)
            fprintf('Debug: updateUIState called with state: %s\n', state); % 添加调试信息

            switch state
                case 'Initial' % App 启动时的初始状态
                    app.SelectFolderButton.Enable = 'on';
                    app.VideoListTable.Enable = 'off';
                    app.controlPanel.Enable = 'off';
                    app.resultPanel.Enable = 'off';
                    app.ConfirmButton.Enable = 'off';
                    app.PauseButton.Enable = 'off'; % 初始禁用播放按钮
                    app.SpeedEditField.Enable = 'off';
                    % app.FileNameLabel.Visible = 'off';
                    app.CurrentTimeLabel.Visible = 'off';
                    app.TotalDurationLabel.Visible = 'off';
                    app.videoPanel.Title = app.DEFAULT_PANEL_TITLE; % 重置面板标题
                    if ~isempty(app.playAxesHandle) && isvalid(app.playAxesHandle)
                        cla(app.playAxesHandle); % 清空坐标轴
                        app.playAxesHandle.Visible = 'off'; % 隐藏坐标轴
                    end
                    app.VideoListTable.Data = cell(0, 2); % 清空视频列表
                    app.ResultTable.Data = cell(0, 4);    % 清空结果表格
                case 'FolderSelected' % 已选择文件夹，加载了视频列表之后的状态
                    app.SelectFolderButton.Enable = 'on';
                    app.VideoListTable.Enable = 'on';
                    app.controlPanel.Enable = 'off'; % 需选中视频后才启用控制面板
                    app.resultPanel.Enable = 'off';  % 需选中视频后才启用结果面板
                    app.ConfirmButton.Enable = 'off';
                    app.PauseButton.Enable = 'off';  % 仍禁用播放按钮
                    app.SpeedEditField.Enable = 'off';
                    % app.FileNameLabel.Visible = 'off';
                    app.CurrentTimeLabel.Visible = 'off';
                    app.TotalDurationLabel.Visible = 'off';
                    app.videoPanel.Title = app.DEFAULT_PANEL_TITLE; % 重置面板标题
                    if ~isempty(app.playAxesHandle) && isvalid(app.playAxesHandle)
                        cla(app.playAxesHandle);
                        app.playAxesHandle.Visible = 'off';
                    end
                case 'VideoSelected' % 从列表中选择了某个视频后的状态
                    app.SelectFolderButton.Enable = 'on'; % 允许更换文件夹
                    app.VideoListTable.Enable = 'on';   % 允许选择其他视频
                    app.controlPanel.Enable = 'on';     % 启用控制面板
                    app.resultPanel.Enable = 'on';      % 启用结果面板
                    app.ConfirmButton.Enable = 'on';    % 启用确认按钮
                    app.PauseButton.Enable = 'on';      % 启用播放/暂停按钮
                    app.PauseButton.Text = '播放';      % 设置按钮文本为 "播放"
                    app.SpeedEditField.Enable = 'on';   % 启用速度编辑框
                    % app.FileNameLabel.Visible = 'on';   % 显示文件名
                    app.CurrentTimeLabel.Visible = 'on';% 显示当前时间
                    app.TotalDurationLabel.Visible = 'on'; % 显示总时长
                    % videoPanel 的 Title 在 setupVideoPlayback 中设置
                    if ~isempty(app.playAxesHandle) && isvalid(app.playAxesHandle)
                        app.playAxesHandle.Visible = 'on'; % 显示视频播放区域
                    end
                    stopTimers(app); % 停止之前可能在运行的定时器
                case 'Playing' % 视频正在播放时的状态
                    fprintf('Debug: Setting state to Playing.\n'); % 添加调试信息
                    app.PauseButton.Text = '暂停';      % 设置按钮文本为 "暂停"
                    app.PauseButton.Enable = 'on';
                    % app.TimeSlider.Enable = 'off';      % 播放时禁用进度条拖动
                    app.TimeSlider.Enable = 'on';
                    app.SelectFolderButton.Enable = 'off';% 播放时禁止选择文件夹
                    app.VideoListTable.Enable = 'off';  % 播放时禁止选择其他视频
                    app.ConfirmButton.Enable = 'off';   % 播放时禁止确认保存
                    fprintf('Debug: ConfirmButton should be disabled.\n'); % 添加调试信息
                    % 标注按钮 (Left, Right, Get) 保持启用状态
                case 'Paused' % 视频暂停时的状态
                    fprintf('Debug: Setting state to Paused.\n'); % 添加调试信息
                    app.PauseButton.Text = '播放';      % 设置按钮文本为 "播放"
                    app.PauseButton.Enable = 'on';
                    app.TimeSlider.Enable = 'on';       % 允许拖动进度条
                    app.SelectFolderButton.Enable = 'on';
                    app.VideoListTable.Enable = 'on';
                    app.ConfirmButton.Enable = 'on';
                    fprintf('Debug: ConfirmButton should be enabled.\n'); % 添加调试信息

                case 'Repeating' % 正在重复播放某个 Trial 片段时的状态
                    app.PauseButton.Enable = 'off';     % 禁用主播放/暂停按钮
                    app.TimeSlider.Enable = 'off';      % 禁用进度条
                    app.SelectFolderButton.Enable = 'off';
                    app.VideoListTable.Enable = 'off';
                    app.ConfirmButton.Enable = 'off';
                    % 重复播放时禁用标注按钮 (当前逻辑)
                    app.LeftButton.Enable = 'off';
                    app.RightButton.Enable = 'off';
                    app.GetButton.Enable = 'off';
                case 'RepeatFinished' % 重复播放结束后的状态
                    app.PauseButton.Enable = 'on';      % 重新启用主播放/暂停按钮
                    app.PauseButton.Text = '播放';      % 默认回到播放状态 (暂停)
                    app.TimeSlider.Enable = 'on';
                    app.SelectFolderButton.Enable = 'on';
                    app.VideoListTable.Enable = 'on';
                    app.ConfirmButton.Enable = 'on';
                    % 重新启用标注按钮
                    app.LeftButton.Enable = 'on';
                    app.RightButton.Enable = 'on';
                    app.GetButton.Enable = 'on';
            end
            drawnow limitrate;
        end

        function path = getPersistentFolderPath(app)
            path = ''; % 默认返回空
            if exist(app.persistentFolderPathFile, 'file') == 2 % 检查文件是否存在
                try
                    fid = fopen(app.persistentFolderPathFile, 'r');
                    if fid ~= -1
                        path = fgetl(fid); % 读取一行
                        fclose(fid);
                        % 验证读取到的路径是否有效
                        if ~ischar(path) || isempty(path) || exist(path, 'dir') ~= 7
                            path = ''; % 如果路径无效或文件夹不存在，则重置为空
                        end
                    end
                catch ME
                    warning('无法读取持久化文件夹路径: %s', ME.message);
                    path = '';
                end
            end
        end

        function setPersistentFolderPath(app, path)
            try
                fid = fopen(app.persistentFolderPathFile, 'w'); % 以写入模式打开
                if fid ~= -1
                    fprintf(fid, '%s', path); % 写入路径
                    fclose(fid);
                else
                    warning('无法打开持久化文件夹路径文件进行写入。');
                end
            catch ME
                warning('无法写入持久化文件夹路径: %s', ME.message);
            end
        end

        function success = loadResultsData(app)
            success = false; % 默认加载失败
            % 初始化为空结构体数组，确保字段存在
            app.allResultsData = struct('videoName', {}, 'MonkeyID',{},'Group',{},'Process',{},'Hand',{}, 'HandRestraint',{});

            if exist(app.resultsFilePath, 'file') == 2 % 检查 .mat 文件是否存在
                try
                    % load 函数会将 .mat 文件中的变量加载到当前工作区
                    loadedData = load(app.resultsFilePath, 'resultData'); % 指定加载 'resultData' 变量
                    if isfield(loadedData, 'resultData') % 检查变量是否成功加载
                        app.allResultsData = loadedData.resultData;
                        success = true; % 加载成功
                    else
                        warning('在 MAT 文件中未找到 resultData 变量: %s', app.resultsFilePath);
                    end
                catch ME
                    uialert(app.UIFigure, sprintf('加载结果文件时出错:\n%s', ME.message), '加载错误');
                    success = false; % 确保为失败状态
                end
            else
                % 如果文件不存在，也视为 "成功" (因为是首次运行或无历史数据)，后续会创建新文件
                success = true;
            end
        end

        function success = saveResultsData(app)
            success = false; % 默认保存失败
            resultData = app.allResultsData; % 将 App 属性中的数据赋给一个局部变量
            try
                % save 函数会将指定变量保存到 .mat 文件
                save(app.resultsFilePath, 'resultData'); % 将 resultData 变量保存到文件
                success = true; % 保存成功
            catch ME
                uialert(app.UIFigure, sprintf('保存结果文件时出错:\n%s', ME.message), '保存错误');
            end
        end

        function syncNewVideos(app)
            videoFiles = dir(fullfile(app.currentFolderPath, '*.mp4')); % 获取文件夹下所有 .mp4 文件
            if isempty(videoFiles)
                return; % 文件夹中没有视频文件
            end

            % 获取当前已记录的视频文件名列表
            if isempty(app.allResultsData)
                currentVideoNames = {};
            else
                currentVideoNames = {app.allResultsData.videoName};
            end
            newVideosAdded = false; % 标记是否有新视频被添加

            for i = 1:numel(videoFiles)
                % 检查当前文件是否已在记录中
                if ~ismember(videoFiles(i).name, currentVideoNames)
                    % 如果是新视频，则添加条目
                    newIndex = numel(app.allResultsData) + 1; % 新条目的索引
                    app.allResultsData(newIndex).videoName = videoFiles(i).name;

                    % --- 从文件名解析元数据 (假设遵循 "ID_日期_分组_..." 格式) ---
                    try
                        parts = split(videoFiles(i).name, '_'); % 按下划线分割文件名
                        if numel(parts) >= 3
                            app.allResultsData(newIndex).MonkeyID = parts{1}; % 第一个部分为 MonkeyID
                            app.allResultsData(newIndex).Group = parts{3};    % 第三个部分为 Group
                        else
                            % 如果文件名不符合预期格式，则设为未知
                            app.allResultsData(newIndex).MonkeyID = 'Unknown';
                            app.allResultsData(newIndex).Group = 'Unknown';
                        end
                    catch % 处理 split 可能发生的错误
                        app.allResultsData(newIndex).MonkeyID = 'ParseError';
                        app.allResultsData(newIndex).Group = 'ParseError';
                    end
                    % --- 初始化其他字段 ---
                    app.allResultsData(newIndex).Process = false; % 新视频标记为未处理
                    app.allResultsData(newIndex).Hand = [];       % 初始化 Hand 数据为空
                    app.allResultsData(newIndex).HandRestraint = []; % 初始化 HandRestraint 为空
                    newVideosAdded = true; % 标记已添加新视频
                end
            end

            % 如果添加了新视频，立即保存更新后的结果数据
            if newVideosAdded
                if ~saveResultsData(app)
                    warning('添加新视频后自动保存结果失败。');
                end
            end
        end

        function populateVideoListTable(app)
            if isempty(app.allResultsData)
                app.VideoListTable.Data = cell(0, 2); % 如果没有数据，显示空表格
            else
                % 确保 Process 字段存在，并处理可能为空的情况
                if ~isfield(app.allResultsData, 'Process')
                    % 如果旧数据没有 Process 字段，则添加并设为 false
                    [app.allResultsData.Process] = deal(false);
                end
                processStatus = {app.allResultsData.Process}'; % 获取 Process 状态列
                % 处理 Process 字段可能为空值的情况，将其视作 false
                processStatus(cellfun(@isempty, processStatus)) = {false};

                % 更新表格数据
                app.VideoListTable.Data = [{app.allResultsData.videoName}' processStatus];
            end
            %  % 重置表格的排序状态 (可选，根据需要决定是否保留用户排序)
            % app.VideoListTable.DisplaySortState = []; % 取消重置排序状态
        end

        function setupVideoPlayback(app, videoPath)
            try
                app.videoObject = VideoReader(videoPath); % 创建 VideoReader 对象
            catch ME
                uialert(app.UIFigure, sprintf('打开视频文件时出错:\n%s', ME.message), '视频错误');
                updateUIState(app, 'FolderSelected'); % 出错则回退到文件夹选择状态
                return;
            end

            % --- 更新 UI 显示视频信息 ---
            app.TimeSlider.Value = 0; % 重置进度条
            app.TimeSlider.Limits = [0 app.videoObject.Duration]; % 设置进度条范围
            app.CurrentTimeLabel.Text = '0.0'; % 重置当前时间显示
            app.TotalDurationLabel.Text = sprintf('/ %.1f s', app.videoObject.Duration); % 显示总时长
            app.SpeedEditField.Value = app.DEFAULT_SPEED; % 重置播放速度
            app.videoPanel.Title = app.videoObject.Name;
            app.currentRotationAngle = 0; %重置旋转角度

            % --- 显示视频第一帧 ---
            displayFrame(app, 0); % 调用辅助函数显示第 0 秒的帧

            % --- 设置定时器 ---
            setupTimers(app); % 创建或重置播放定时器

            % --- 更新整体 UI 状态 ---
            updateUIState(app, 'VideoSelected'); % 进入视频已选择状态
        end

        function displayFrame(app, time)
            % 检查 videoObject 是否有效
            if isempty(app.videoObject) || ~isvalid(app.videoObject)
                return;
            end

            try
                % --- 定位到指定时间 ---
                % 仅当请求的时间与当前时间显著不同时才执行 seek 操作，以提高效率
                timeTolerance = 1 / (2 * app.videoObject.FrameRate); % 时间容差
                if abs(app.videoObject.CurrentTime - time) > timeTolerance
                    % 使用 max/min 确保时间在有效范围内 [0, Duration]
                    seekTime = max(0, min(time, app.videoObject.Duration - timeTolerance)); % 减去容差防止读取最后一帧出错
                    app.videoObject.CurrentTime = seekTime;
                end

                % --- 读取帧 ---
                if hasFrame(app.videoObject) % 检查当前时间点是否有帧可读
                    frame = readFrame(app.videoObject); % 读取帧数据

                    % --- Apply Rotation ---
                    if app.currentRotationAngle ~= 0
                        % 使用 'loose' 选项确保整个旋转后的图像都被包含
                        % 使用 'nearest' (默认) 或 'bilinear' 插值
                        frame = imrotate(frame, app.currentRotationAngle, 'loose', 'nearest');
                    end

                    % --- 更新图像显示 ---
                    if isempty(app.videoDisplayHandle) || ~isvalid(app.videoDisplayHandle)
                        % 如果图像句柄无效或不存在，则创建新的 image 对象
                        app.videoDisplayHandle = image(app.playAxesHandle, frame);
                        app.playAxesHandle.Visible = 'on'; % 确保坐标轴可见
                        axis(app.playAxesHandle, 'image', 'off'); % 设置坐标轴样式以正确显示图像宽高比并隐藏刻度
                    else
                        % 如果句柄有效，则直接更新图像数据
                        app.videoDisplayHandle.CData = frame;
                        axis(app.playAxesHandle, 'image', 'off');

                        % [h, w, ~] = size(frame);
                        % app.playAxesHandle.XLim = [0.5, w + 0.5];
                        % app.playAxesHandle.YLim = [0.5, h + 0.5];
                        %
                        % % Re-center axes after potentially changing limits
                        % centerAxesInPanel(app);
                    end

                    % --- 重新居中坐标轴 ---
                    % 这将根据旋转后的图像尺寸调整坐标轴在面板中的位置和大小
                    centerAxesInPanel(app);

                    % --- 更新时间相关的 UI (仅标签) ---
                    app.CurrentTimeLabel.Text = sprintf('%.1f', app.videoObject.CurrentTime);

                    drawnow('limitrate'); % 限制刷新率，避免 UI 卡顿
                end
            catch ME
                fprintf('在时间 %.3f 显示帧时出错: %s\n', time, ME.message);
            end
        end

        function centerAxesInPanel(app)
            if isempty(app.playAxesHandle) || ~isvalid(app.playAxesHandle) || ...
                    isempty(app.videoObject) || ~isvalid(app.videoObject) % 检查句柄和对象是否有效
                return;
            end

            panelPos = app.videoPanel.Position; % 获取父面板的位置和尺寸 [left, bottom, width, height]
            panelWidth = panelPos(3);
            panelHeight = panelPos(4);

            % 如果面板尺寸无效，则退出
            if panelWidth <= 0 || panelHeight <= 0
                return;
            end

            % --- 根据旋转角度获取视频的 *显示* 宽高 ---
            % 注意: 这里使用的是原始视频的宽高，因为 imrotate('loose')
            % 返回的图像尺寸会变化，但我们希望保持原始视频的相对比例。
            % 'axis image' 会处理实际像素的显示。
            originalWidth = app.videoObject.Width;
            originalHeight = app.videoObject.Height;

            if mod(app.currentRotationAngle, 180) == 0 % 0 或 180 度
                displayWidth = originalWidth;
                displayHeight = originalHeight;
            else % 90 或 270 度
                displayWidth = originalHeight; % 宽高互换
                displayHeight = originalWidth;
            end

            % --- 计算宽高比 ---
            if displayHeight <= 0
                return; % 防止除以零
            end
            videoAspectRatio = displayWidth / displayHeight;

            % --- 计算能在面板中容纳视频的最大尺寸 ---
            axesWidth = panelWidth;
            axesHeight = axesWidth / videoAspectRatio;

            if axesHeight > panelHeight
                axesHeight = panelHeight;
                axesWidth = axesHeight * videoAspectRatio;
            end

            % --- 计算居中位置 ---
            xPos = (panelWidth - axesWidth) / 2;
            yPos = (panelHeight - axesHeight) / 2;

            % --- 设置坐标轴位置和单位 ---
            app.playAxesHandle.Units = 'pixels'; % 确保单位是像素
            app.playAxesHandle.Position = [xPos, yPos, axesWidth, axesHeight];
        end

        function setupTimers(app)
            stopTimers(app); % 先停止并删除任何已存在的定时器

            if isempty(app.videoObject) || ~isvalid(app.videoObject)
                return; % 如果 videoObject 无效，则不创建定时器
            end

            % 计算定时器的周期，即每帧的持续时间
            framePeriod = 1 / app.videoObject.FrameRate;
            % 避免周期过小或为零导致问题
            if framePeriod <= 0
                warning('计算出的帧周期无效 (%.4f)，将使用默认值 1/30。', framePeriod);
                framePeriod = 1/30;
            end
            % 增加一个最小周期限制，防止过于频繁的回调
            minPeriod = 0.1; % 约等于 100 FPS，避免过高频率
            framePeriod = max(framePeriod, minPeriod);


            % --- 创建主播放定时器 (videoTimer) ---
            app.videoTimer = timer(...
                'ExecutionMode', 'fixedRate', ... % 固定速率执行，尽量保证帧率
                'Period', framePeriod, ...         % 定时器周期
                'BusyMode', 'queue', ...           % 如果回调执行时间过长，将后续回调排队等待
                'TimerFcn', @(~,~) app.videoTimerCallback, ... % 指定定时器触发时执行的回调函数
                'ErrorFcn', @(~,event) timerErrorCallback(app, event, '视频播放定时器')); % 指定错误处理函数

            % --- 创建重复播放定时器 (repeatTimer) ---
            app.repeatTimer = timer(...
                'ExecutionMode', 'fixedRate', ... % 固定速率执行
                'Period', framePeriod, ...         % 定时器周期
                'BusyMode', 'drop', ...            % 如果回调执行时间过长，则丢弃后续回调 (适用于重复播放，避免累积延迟)
                'TimerFcn', @(~,~) app.repeatTimerCallback, ... % 指定重复播放的回调函数
                'StopFcn', @(~,~) app.repeatTimerStopCallback, ... % 指定定时器停止时执行的函数 (用于更新 UI 状态)
                'ErrorFcn', @(~,event) timerErrorCallback(app, event, '重复播放定时器')); % 指定错误处理函数
        end

        function stopTimers(app)
            if ~isempty(app.videoTimer) && isvalid(app.videoTimer)
                if strcmp(app.videoTimer.Running, 'on')
                    stop(app.videoTimer);
                end
                delete(app.videoTimer);
                app.videoTimer = [];
            end
            if ~isempty(app.repeatTimer) && isvalid(app.repeatTimer)
                if strcmp(app.repeatTimer.Running, 'on')
                    stop(app.repeatTimer);
                end
                delete(app.repeatTimer);
                app.repeatTimer = [];
            end
        end

        function timerErrorCallback(app, event, timerName)
            warning('%s 发生错误: %s', timerName, event.Data.message);
            updateUIState(app, 'Paused');
        end


        function populateResultTable(app)
            slot_num = app.SlotsEditField.Value;
            app.ResultTable.Data = cell(slot_num, 4);
            app.ResultTable.Data(:, 1) = num2cell((1:slot_num)');

            removeStyle(app.ResultTable);
            sDefault = uistyle('HorizontalAlignment', 'left');
            addStyle(app.ResultTable, sDefault, 'table', '');

            lastRecordedTime = 0;

            if ~isempty(app.currentVideoResults) && isfield(app.currentVideoResults,'Hand') && ~isempty(app.currentVideoResults.Hand)
                handData = app.currentVideoResults.Hand;
                numFinishedTrials = size(handData, 1);

                if size(handData, 2) < 3
                    warning('加载的 Hand 数据列数不足 3 列，将用 NaN 填充。');
                    handData(:, end+1:3) = NaN;
                end

                for i = 1:min(numFinishedTrials, slot_num)
                    if ~isnan(handData(i, 1))
                        app.ResultTable.Data{i, app.LEFT_HAND_COL} = sprintf('%.1f', handData(i, 1));
                    end
                    if ~isnan(handData(i, 2))
                        app.ResultTable.Data{i, app.RIGHT_HAND_COL} = sprintf('%.1f', handData(i, 2));
                    end
                    if ~isnan(handData(i, 3))
                        app.ResultTable.Data{i, app.GET_TIME_COL} = sprintf('%.1f', handData(i, 3));
                        lastRecordedTime = max(lastRecordedTime, handData(i, 3));
                        sPass = uistyle("Icon", "success", "IconAlignment", "rightmargin");
                        addStyle(app.ResultTable, sPass, "cell", [i 1]);
                    end
                end
                app.currentTrialIndex = numFinishedTrials + 1;
            else
                app.currentTrialIndex = 1;
            end

            app.currentTrialIndex = max(1, min(app.currentTrialIndex, slot_num + 1));

            if ~isempty(app.videoObject) && isvalid(app.videoObject)
                seekTime = min(lastRecordedTime, app.videoObject.Duration);
                displayFrame(app, seekTime);
                % 同步更新 Slider 位置
                app.isSliderBeingUpdatedByTimer = true; % 标记是程序更新
                app.TimeSlider.Value = seekTime;
                app.isSliderBeingUpdatedByTimer = false; % 清除标记
            end

            updateHandRestraintUI(app);
        end

        function updateHandRestraintUI(app)
            % updateHandRestraintUI - 根据加载的 currentVideoResults 更新手部束缚 CheckBox 的状态
            % <--- 修改: 处理 CheckBox ---
            noVal = false; leftVal = false; rightVal = false; % 默认都不勾选
            if ~isempty(app.currentVideoResults) && isfield(app.currentVideoResults,'HandRestraint') && ~isempty(app.currentVideoResults.HandRestraint)
                restraintStr = lower(app.currentVideoResults.HandRestraint);
                % 检查字符串中是否包含相应的关键字
                if contains(restraintStr, 'no')
                    noVal = true;
                end
                if contains(restraintStr, 'left')
                    leftVal = true;
                end
                if contains(restraintStr, 'right')
                    rightVal = true;
                end
                % 如果包含关键字但不是 'no', 'left', 'right' 的组合，可能需要警告
                if ~noVal && ~leftVal && ~rightVal && ~isempty(restraintStr)
                    warning('未知的 HandRestraint 值 "%s"，将不勾选任何选项。', app.currentVideoResults.HandRestraint);
                end
                % 如果 'no' 和其他选项同时存在，优先显示 'no' (或根据实际逻辑调整)
                if noVal && (leftVal || rightVal)
                    warning('HandRestraint 值 "%s" 存在冲突，将仅勾选 "无"。', app.currentVideoResults.HandRestraint);
                    leftVal = false;
                    rightVal = false;
                end
            else
                % 如果没有数据，默认勾选 '无'
                noVal = true;
            end
            % 更新 CheckBox 的状态
            app.NoRestraintButton.Value = noVal;
            app.LeftRestraintButton.Value = leftVal;
            app.RightRestraintButton.Value = rightVal;

            % <--- 新增: 更新 handCheckbox 属性以匹配初始状态 ---
            if noVal
                app.handCheckbox = app.NoRestraintButton;
            elseif leftVal
                app.handCheckbox = app.LeftRestraintButton;
            elseif rightVal
                app.handCheckbox = app.RightRestraintButton;
            else
                app.handCheckbox = []; % 如果都没有选中
            end
        end

        function [speedFactor, pauseDuration] = getPlaybackSpeed(app)
            speedValueStr = app.SpeedEditField.Value;
            speedValue = str2double(speedValueStr);

            if isnan(speedValue) || speedValue <= 0
                warning('输入的速度值无效: "%s"。将使用默认速度 1。', speedValueStr);
                speedValue = 1;
                app.SpeedEditField.Value = app.DEFAULT_SPEED;
            end

            speedFactor = 1;
            pauseDuration = 0;
            if isempty(app.videoObject) || ~isvalid(app.videoObject)
                warning('Video object is invalid in getPlaybackSpeed.');
                return;
            end
            framePeriod = 1 / app.videoObject.FrameRate;

            if speedValue >= 1
                speedFactor = round(speedValue);
                pauseDuration = 0;
            else
                speedFactor = 1;
                requiredTime = framePeriod / speedValue;
                pauseDuration = max(0, requiredTime - framePeriod);
            end
        end

        function validateAndSaveResults(app)
            slot_num = app.SlotsEditField.Value;
            resultsFromTable = app.ResultTable.Data;
            isValid = true;
            firstEmptyRow = -1;
            extractedData = nan(slot_num, 3);
            numCompletedTrials = 0;

            for i = 1:slot_num
                leftStr = resultsFromTable{i, app.LEFT_HAND_COL};
                rightStr = resultsFromTable{i, app.RIGHT_HAND_COL};
                getStr = resultsFromTable{i, app.GET_TIME_COL};
                isComplete = ischar(getStr) && ~isempty(strtrim(getStr));

                if isComplete
                    numCompletedTrials = i;
                    leftVal = str2double(leftStr);
                    rightVal = str2double(rightStr);
                    getVal = str2double(getStr);
                    if isnan(leftVal) || isnan(rightVal) || isnan(getVal) || ...
                            (leftVal == 0 && rightVal == 0) || getVal <= 0
                        uialert(app.UIFigure, sprintf('第 %d 行数据不完整或无效。请检查 Left, Right, 和 Get 时间。', i), '验证错误', 'Icon', 'error');
                        isValid = false;
                        break;
                    end
                    touchTime = max(leftVal(leftVal>0), rightVal(rightVal>0));
                    if isempty(touchTime)
                        touchTime = 0;
                    end
                    if getVal < touchTime
                        uialert(app.UIFigure, sprintf('警告: 第 %d 行的 "Get" 时间 (%.1f) 早于 "Left/Right" 接触时间 (%.1f)。', i, getVal, touchTime), '时间逻辑警告', 'Icon', 'warning');
                    end
                    extractedData(i, 1) = leftVal;
                    extractedData(i, 2) = rightVal;
                    extractedData(i, 3) = getVal;
                elseif firstEmptyRow == -1 && isempty(leftStr) && isempty(rightStr)
                    firstEmptyRow = i;
                end
            end

            if ~isValid
                return;
            end

            finalExtractedData = extractedData(1:numCompletedTrials, :);

            if numCompletedTrials ~= slot_num
                proceedWithSave = false;
                if firstEmptyRow ~= -1
                    msg = sprintf('第 %d 个 Trial 似乎未完成 (缺少 "Get" 时间)。是否仍要保存当前已完成的 %d 个 Trial 的结果?', firstEmptyRow, numCompletedTrials);
                    title = '存在未完成的 Trial';
                    options = {'仍然保存', '取消'};
                    selection = uiconfirm(app.UIFigure, msg, title, 'Options', options, 'DefaultOption', '取消', 'Icon', 'warning');
                    if strcmp(selection, '仍然保存')
                        proceedWithSave = true;
                    end
                elseif numCompletedTrials < slot_num
                    msg = sprintf('仅完成了 %d 个 Trial (共 %d 个)。是否保存这 %d 个 Trial 的结果?', numCompletedTrials, slot_num, numCompletedTrials);
                    title = '完成数量不足';
                    options = {'仍然保存', '取消'};
                    selection = uiconfirm(app.UIFigure, msg, title, 'Options', options, 'DefaultOption', '取消', 'Icon', 'warning');
                    if strcmp(selection, '仍然保存')
                        proceedWithSave = true;
                    end
                else
                    msg = sprintf('检测到已完成的 Trial 数量 (%d) 超出设定的槽数 (%d)。请检查表格数据。', numCompletedTrials, slot_num);
                    uialert(app.UIFigure, msg, '数据错误', 'Icon','error');
                    return;
                end
                if ~proceedWithSave
                    return;
                end
            else
                finalExtractedData = extractedData;
            end

            if isempty(app.videoObject) || ~isvalid(app.videoObject)
                uialert(app.UIFigure, '无法识别当前视频对象。', '内部错误', 'Icon','error');
                return;
            end
            videoIdx = find(strcmp({app.allResultsData.videoName}, app.videoObject.Name), 1);
            if isempty(videoIdx)
                uialert(app.UIFigure, '在结果数据中找不到当前视频的记录，无法保存。', '内部错误', 'Icon','error');
                return;
            end

            app.allResultsData(videoIdx).Hand = finalExtractedData;
            app.allResultsData(videoIdx).Process = (numCompletedTrials > 0);

            % --- 修改: 根据 CheckBox 状态保存 HandRestraint (确保单选逻辑) ---
            if app.NoRestraintButton.Value
                app.allResultsData(videoIdx).HandRestraint = 'No';
            elseif app.LeftRestraintButton.Value
                app.allResultsData(videoIdx).HandRestraint = 'Left';
            elseif app.RightRestraintButton.Value
                app.allResultsData(videoIdx).HandRestraint = 'Right';
            else
                app.allResultsData(videoIdx).HandRestraint = ''; % 如果都没选，保存为空
            end
            % --- HandRestraint 保存逻辑结束 ---

            if saveResultsData(app)
                msgbox('标注结果已成功保存!', '保存完成', 'modal');
                app.VideoListTable.Data{videoIdx, app.PROCESS_COL} = app.allResultsData(videoIdx).Process;
            end
        end


        % --- 定时器回调函数 (流畅度优化) ---

        function videoTimerCallback(app)
            % videoTimerCallback - 主播放定时器的回调函数 (优化流畅度)
            % 性能分析提示:
            % 在调试时，可以在关键步骤前后使用 tic/toc 来测量执行时间:
            % t_start = tic;
            % ... code segment ...
            % elapsed_time = toc(t_start);
            % fprintf('Segment execution time: %.4f seconds\n', elapsed_time);

            % --- 安全性检查 ---
            if app.isStoppingTimer || isempty(app.videoTimer) || ~isvalid(app.videoTimer) || strcmp(app.videoTimer.Running,'off')
                fprintf('Debug: videoTimerCallback entered but timer is stopped, invalid, or stopping flag is set. Returning.\n');
                return;
            end

            % if isempty(app.videoTimer) || ~isvalid(app.videoTimer) || strcmp(app.videoTimer.Running,'off') || ...
            %         isempty(app.videoObject) || ~isvalid(app.videoObject)
            %      fprintf('Debug: videoTimerCallback entered but timer is stopped or invalid. Returning.\n');
            %     return;
            % end

            % % ---> 现有检查：确保 videoObject 有效 <---
            % if isempty(app.videoObject) || ~isvalid(app.videoObject)
            %      warning('videoTimerCallback: videoObject is invalid.');
            %      stop(app.videoTimer); % Stop timer if video object is bad
            %      updateUIState(app, 'Paused');
            %     return;
            % end

            % ---> 现有检查：确保 videoObject 有效 <---
            if isempty(app.videoObject) || ~isvalid(app.videoObject)
                warning('videoTimerCallback: videoObject is invalid.');
                app.isStoppingTimer = true; % Set flag before stopping
                stop(app.videoTimer); % Stop timer if video object is bad
                app.isStoppingTimer = false; % Reset flag
                updateUIState(app, 'Paused');
                return;
            end

            % --- 获取播放速度设置 ---
            [speedFactor, pauseDuration] = getPlaybackSpeed(app);
            newTime = -1; % 标记是否成功读取
            % frame = []; % 初始化帧变量

            try
                % --- 1. 前进帧 ---
                for i = 1:speedFactor
                    % ---> 增加检查：在循环内部也检查停止标志 <---
                    if app.isStoppingTimer; return; end

                    if hasFrame(app.videoObject)
                        % 仅前进，不立即读取，由 displayFrame 读取
                        app.videoObject.CurrentTime = app.videoObject.CurrentTime + (1 / app.videoObject.FrameRate);
                        if ~hasFrame(app.videoObject) % 如果前进后没有帧了
                            break; % 跳出循环
                        end
                    else
                        % --- 到达视频末尾 ---
                        fprintf('Debug: videoTimerCallback reached end of video.\n');
                        app.isStoppingTimer = true; % Set flag before stopping
                        stop(app.videoTimer);
                        app.isStoppingTimer = false; % Reset flag
                        updateUIState(app, 'Paused');
                        if ~isempty(app.videoObject) && isvalid(app.videoObject)
                            finalTime = app.videoObject.Duration;
                            % 更新最终时间显示
                            app.CurrentTimeLabel.Text = sprintf('%.1f', finalTime);
                            app.isSliderBeingUpdatedByTimer = true;
                            app.TimeSlider.Value = finalTime;
                            app.isSliderBeingUpdatedByTimer = false;
                        end
                        return; % 退出回调
                    end
                end

                % ---> 增加检查：循环结束后检查停止标志 <---
                if app.isStoppingTimer; return; end

                % --- 2. 获取当前时间 ---
                currentTime = app.videoObject.CurrentTime;

                % --- 3. 显示当前帧 (包含旋转逻辑) ---
                displayFrame(app, currentTime); % displayFrame 会处理 CData 和居中

                % --- 4. 更新时间标签和进度条 (在 displayFrame 之后) ---
                app.isSliderBeingUpdatedByTimer = true;
                try
                    if ~isempty(app.TimeSlider) && isvalid(app.TimeSlider)
                        % 确保滑块值不超过限制
                        app.TimeSlider.Value = min(currentTime, app.TimeSlider.Limits(2));
                    end
                catch ME_SliderUpdate
                    warning('更新 Slider 时出错: %s', ME_SliderUpdate.message);
                end
                app.isSliderBeingUpdatedByTimer = false;
                % CurrentTimeLabel 已在 displayFrame 中更新

                % --- 5. 处理慢放暂停 ---
                if pauseDuration > 0
                    pause(pauseDuration);
                end

            catch ME % 捕获播放过程中可能发生的错误
                warning('视频播放过程中发生错误: %s\n%s', ME.message, getReport(ME)); % 显示更详细的错误报告
                if ~isempty(app.videoTimer) && isvalid(app.videoTimer)
                    app.isStoppingTimer = true; % Set flag before stopping
                    stop(app.videoTimer);
                    app.isStoppingTimer = false; % Reset flag
                end
                updateUIState(app, 'Paused');
            end
        end

        function repeatTimerCallback(app)
            % repeatTimerCallback - 重复播放定时器的回调函数 (优化流畅度)
            % --- 安全性检查 ---
            % ---> 修改检查：增加 isStoppingTimer 标志位判断 (虽然 repeatTimer 不直接受此标志影响，但保持一致性) <---
            if app.isStoppingTimer || isempty(app.repeatTimer) || ~isvalid(app.repeatTimer) || strcmp(app.repeatTimer.Running,'off')
                % fprintf('Debug: repeatTimerCallback entered but timer is stopped or invalid. Returning.\n');
                return;
            end

            % ---> 现有检查：确保 videoObject 有效 <---
            if isempty(app.videoObject) || ~isvalid(app.videoObject)
                warning('repeatTimerCallback: videoObject is invalid.');
                stop(app.repeatTimer); % Stop timer if video object is bad
                updateUIState(app, 'RepeatFinished'); % Go to finished state
                return;
            end

            % --- 获取重复播放的结束时间 ---
            timerData = app.repeatTimer.UserData;
            if ~isstruct(timerData) || ~isfield(timerData, 'EndTime')
                warning('重复播放定时器的 UserData 未正确设置 (缺少 EndTime)。');
                stop(app.repeatTimer);
                return;
            end
            endTime = timerData.EndTime;

            % --- 获取当前播放速度设置 ---
            [speedFactor, pauseDuration] = getPlaybackSpeed(app);
            timeTolerance = 1 / (2 * app.videoObject.FrameRate);

            try
                % --- 1. 检查是否到达结束时间 ---
                if app.videoObject.CurrentTime >= (endTime - timeTolerance)
                    stop(app.repeatTimer); % StopFcn 会处理 UI
                    return;
                end

                % --- 2. 前进帧 ---
                for i = 1:speedFactor
                    if app.isStoppingTimer; return; end % 虽然不太可能，但加上以防万一

                    if hasFrame(app.videoObject) && app.videoObject.CurrentTime < (endTime - timeTolerance)
                        % 仅前进
                        app.videoObject.CurrentTime = app.videoObject.CurrentTime + (1 / app.videoObject.FrameRate);
                        % 再次检查是否超出结束时间或视频末尾
                        if ~hasFrame(app.videoObject) || app.videoObject.CurrentTime >= (endTime - timeTolerance)
                            break; % 跳出循环
                        end
                    else
                        stop(app.repeatTimer); % StopFcn 会处理 UI
                        return;
                    end
                end

                if app.isStoppingTimer; return; end

                % --- 3. 获取当前时间 ---
                currentTime = app.videoObject.CurrentTime;
                % 确保不超过结束时间 (以防万一)
                currentTime = min(currentTime, endTime);


                % --- 4. 显示当前帧 (包含旋转逻辑) ---
                displayFrame(app, currentTime);

                % --- 5. 更新时间标签和进度条 ---
                app.isSliderBeingUpdatedByTimer = true;
                try
                    if ~isempty(app.TimeSlider) && isvalid(app.TimeSlider)
                        app.TimeSlider.Value = min(currentTime, app.TimeSlider.Limits(2));
                    end
                catch ME_SliderUpdate
                    warning('更新 Slider 时出错: %s', ME_SliderUpdate.message);
                end
                app.isSliderBeingUpdatedByTimer = false;
                % CurrentTimeLabel 已在 displayFrame 中更新

                % --- 6. 处理慢放暂停 ---
                if pauseDuration > 0
                    pause(pauseDuration);
                end

            catch ME % 捕获重复播放过程中的错误
                warning('重复播放过程中发生错误: %s\n%s', ME.message, getReport(ME));
                if ~isempty(app.repeatTimer) && isvalid(app.repeatTimer)
                    stop(app.repeatTimer);
                end
                % StopFcn 会处理后续 UI 更新 (通常会调用 updateUIState('RepeatFinished'))
            end
        end

        function repeatTimerStopCallback(app)
            % fprintf('重复播放定时器已停止。\n'); % 调试信息
            if ~isempty(app.repeatTimer) && isvalid(app.repeatTimer)
                timerData = app.repeatTimer.UserData;
                if isstruct(timerData) && isfield(timerData, 'EndTime') && ...
                        ~isempty(app.videoObject) && isvalid(app.videoObject) % 添加 videoObject 检查
                    endTimeVal = min(timerData.EndTime, app.videoObject.Duration); % 确保不超过视频时长
                    displayFrame(app, endTimeVal); % 显示结束帧
                    app.isSliderBeingUpdatedByTimer = true;
                    if ~isempty(app.TimeSlider) && isvalid(app.TimeSlider)
                        app.TimeSlider.Value = min(endTimeVal, app.TimeSlider.Limits(2));
                    end
                    app.isSliderBeingUpdatedByTimer = false;
                end
            end
            updateUIState(app, 'RepeatFinished'); % 更新UI状态
        end
    end


    % App 组件事件的回调函数
    methods (Access = private)

        % Code that executes after component creation - App 启动函数
        function startupFcn(app)
            clc;
            screenSize = get(0, 'ScreenSize');
            figWidthRatio = 0.95;
            figHeightRatio = 0.9;
            figWidth = figWidthRatio * screenSize(3);
            figHeight = figHeightRatio * screenSize(4);
            figLeft = (screenSize(3) - figWidth) / 2;
            figBottom = (screenSize(4) - figHeight) / 2;
            app.UIFigure.Position = [figLeft figBottom figWidth figHeight];
            app.UIFigure.Visible = 'on';

            try
                if ispc
                    userDocs = getenv('USERPROFILE');
                    if isempty(userDocs)
                        userDocs = userpath;
                    else
                        userDocs = fullfile(userDocs, 'Documents');
                    end
                else
                    userDocs = fullfile(getenv('HOME'), 'Documents');
                    if exist(userDocs, 'dir') ~= 7
                        userDocs = userpath;
                    end
                end

                % Ensure userDocs is valid before proceeding
                if isempty(userDocs) || exist(userDocs, 'dir') ~= 7
                    warning('无法确定有效的用户文档或主目录。将使用当前工作目录。');
                    userDocs = pwd;
                end

                persistentFolderName = 'MATLAB_VideoAnnotationApp';
                persistentFolderPath = fullfile(userDocs, persistentFolderName);
                if exist(persistentFolderPath, 'dir') ~= 7
                    try
                        mkdir(persistentFolderPath);
                    catch ME_mkdir
                        warning('无法创建持久化文件夹: %s。将使用当前工作目录。', ME_mkdir.message);
                        persistentFolderPath = pwd; % Fallback to current dir if creation fails
                    end
                end
                app.persistentFolderPathFile = fullfile(persistentFolderPath, 'lastBBFolder.txt');
            catch ME
                warning('无法确定或创建持久化文件夹路径目录: %s。将使用当前工作目录。', ME.message);
                app.persistentFolderPathFile = fullfile(pwd, 'lastBBFolder.txt');
            end

            app.playAxesHandle = axes('Parent', app.videoPanel, 'Units', 'pixels');
            axis(app.playAxesHandle, 'off');
            app.playAxesHandle.Visible = 'off';

            app.SlotsEditField.Value = app.defaultSlots;
            updateUIState(app, 'Initial');

            % app.currentCheckbox
            app.NoRestraintButton.Value = true; % 默认选中 '无'
            app.LeftRestraintButton.Value = false;
            app.RightRestraintButton.Value = false;
            app.handCheckbox = app.NoRestraintButton; % 记录当前选中的是 '无'

        end

        % Button pushed function: SelectFolderButton - "选择文件夹" 按钮的回调
        function SelectFolderButtonPushed(app, event)
            startPath = getPersistentFolderPath(app);
            if isempty(startPath) || exist(startPath, 'dir') ~= 7
                startPath = pwd;
            end

            selectedPath = uigetdir(startPath, '选择包含 MP4 视频的文件夹');

            if selectedPath == 0
                if isempty(app.currentFolderPath)
                    updateUIState(app, 'Initial');
                end
                return;
            end

            app.currentFolderPath = selectedPath;
            setPersistentFolderPath(app, selectedPath);
            % app.resultsFilePath = fullfile(app.currentFolderPath, app.resultsDataFilename);

            % --- 动态生成结果文件名 ---
            [~, folderName, ~] = fileparts(app.currentFolderPath);
            % dateStr = datestr(now, 'yyyymmdd');
            % dynamicFilename = sprintf('%s_%s.mat', folderName, dateStr);
            % app.resultsFilePath = fullfile(app.currentFolderPath, dynamicFilename);
            % fprintf('Debug: Results file path set to: %s\n', app.resultsFilePath); % 用于调试
            dynamicFilename = sprintf('%s.mat', folderName);

            stopTimers(app);

            if ~loadResultsData(app)
                updateUIState(app, 'Initial');
                return;
            end

            syncNewVideos(app);
            populateVideoListTable(app);
            updateUIState(app, 'FolderSelected');
        end

        % Cell selection callback: VideoListTable - 视频列表表格单元格选择回调
        function VideoListTableCellSelected(app, event)
            indices = event.Indices;
            if isempty(indices) || size(indices, 1) ~= 1
                return;
            end
            selectedRow = indices(1);

            if selectedRow > size(app.VideoListTable.Data, 1) || isempty(app.VideoListTable.Data{selectedRow, 1})
                warning('选择的行索引 %d 超出范围或该行无视频名称。', selectedRow);
                return;
            end

            selectedVideoName = app.VideoListTable.Data{selectedRow, 1};

            videoIdx = find(strcmp({app.allResultsData.videoName}, selectedVideoName), 1);
            if isempty(videoIdx)
                uialert(app.UIFigure, sprintf('找不到视频 "%s" 的结果数据。', selectedVideoName), '内部错误');
                return;
            end
            app.currentVideoResults = app.allResultsData(videoIdx);

            selectedVideoPath = fullfile(app.currentFolderPath, selectedVideoName);
            if exist(selectedVideoPath, 'file') ~= 2
                uialert(app.UIFigure, sprintf('视频文件未找到:\n%s', selectedVideoPath), '文件未找到');
                return;
            end

            setupVideoPlayback(app, selectedVideoPath);
            populateResultTable(app);
        end

        % Button pushed function: PauseButton - "播放/暂停" 按钮回调
        function PauseButtonPushed(app, event)
            fprintf('Debug: PauseButtonPushed entered.\n'); % 添加调试信息
            if isempty(app.videoTimer) || ~isvalid(app.videoTimer)
                fprintf('Debug: videoTimer invalid or empty, attempting setup.\n'); % 添加调试信息
                setupTimers(app);
                if isempty(app.videoTimer);
                    fprintf('Debug: Timer setup failed, exiting PauseButtonPushed.\n'); % 添加调试信息
                    return;
                end
            end
            if isempty(app.videoObject) || ~isvalid(app.videoObject)
                uialert(app.UIFigure,'请先选择一个视频文件。','操作无效');
                return;
            end

            if strcmp(app.videoTimer.Running, 'on') % 暂停按钮点击前状态为on，按钮显示：播放→暂停
                fprintf('Debug: Timer is running. Stopping timer and setting state to Paused.\n'); % 添加调试信息
                app.isStoppingTimer = true; % ---> 设置标志位 <---
                stop(app.videoTimer);
                updateUIState(app, 'Paused');
                app.isStoppingTimer = false; % ---> 重置标志位 <---
            else % 暂停按钮点击前状态为off，按钮显示：暂停→播放
                fprintf('Debug: Timer is not running. Starting timer and setting state to Playing.\n'); % 添加调试信息

                timeTolerance = 1 / (2 * app.videoObject.FrameRate);
                if app.videoObject.CurrentTime < (app.videoObject.Duration - timeTolerance)
                    start(app.videoTimer);
                    updateUIState(app, 'Playing');
                else
                    fprintf('Debug: Video at end. Restarting from beginning.\n'); % 添加调试信息
                    app.videoObject.CurrentTime = 0;
                    displayFrame(app, 0);
                    app.TimeSlider.Value = 0;
                    start(app.videoTimer);
                    updateUIState(app, 'Playing');
                end
            end
        end

        % Value changed function: TimeSlider - 进度条数值改变回调 (用户拖动)
        function TimeSliderValueChanged(app, event)
            % --- 检查是否由定时器更新 ---
            if app.isSliderBeingUpdatedByTimer
                return; % 忽略由定时器触发的更新
            end

            % --- 检查视频对象 ---
            if isempty(app.videoObject) || ~isvalid(app.videoObject)
                return;
            end

            newTime = event.Value; % 获取用户设置的新时间

            % --- 如果视频正在播放，则暂停并跳转 ---
            wasPlaying = false;
            if ~isempty(app.videoTimer) && isvalid(app.videoTimer) && strcmp(app.videoTimer.Running, 'on')
                app.isStoppingTimer = true; % Set flag
                stop(app.videoTimer);
                app.isStoppingTimer = false; % Reset flag
                wasPlaying = true; % 标记之前在播放
            end
            % 如果正在重复播放，也停止
            if ~isempty(app.repeatTimer) && isvalid(app.repeatTimer) && strcmp(app.repeatTimer.Running, 'on')
                stop(app.repeatTimer);
                wasPlaying = true; % 也视为之前在播放
            end

            % --- 显示新时间点的帧 ---
            displayFrame(app, newTime);

            % --- 如果之前在播放，则更新状态为暂停 ---
            if wasPlaying
                updateUIState(app, 'Paused');
                % 提示用户需要手动再次播放
                % disp('视频已暂停，请点击播放按钮继续。'); % 可选的命令行提示
            end
        end

        % Button pushed function: LeftButton ('a') - "Left" 按钮回调
        function LeftButtonPushed(app, event)
            if app.currentTrialIndex > app.SlotsEditField.Value || isempty(app.videoObject) || ~isvalid(app.videoObject)
                return;
            end
            currentTime = round(app.videoObject.CurrentTime, 1);
            app.ResultTable.Data{app.currentTrialIndex, app.LEFT_HAND_COL} = sprintf('%.1f', currentTime);
            app.ResultTable.Data{app.currentTrialIndex, app.RIGHT_HAND_COL} = '0';
        end

        % Button pushed function: RightButton ('d') - "Right" 按钮回调
        function RightButtonPushed(app, event)
            if app.currentTrialIndex > app.SlotsEditField.Value || isempty(app.videoObject) || ~isvalid(app.videoObject)
                return;
            end
            currentTime = round(app.videoObject.CurrentTime, 1);
            app.ResultTable.Data{app.currentTrialIndex, app.RIGHT_HAND_COL} = sprintf('%.1f', currentTime);
            app.ResultTable.Data{app.currentTrialIndex, app.LEFT_HAND_COL} = '0';
        end

        % Button pushed function: GetButton ('c') - "Get" 按钮回调
        function GetButtonPushed(app, event)
            if app.currentTrialIndex > app.SlotsEditField.Value || isempty(app.videoObject) || ~isvalid(app.videoObject)
                return;
            end

            leftValStr = app.ResultTable.Data{app.currentTrialIndex, app.LEFT_HAND_COL};
            rightValStr = app.ResultTable.Data{app.currentTrialIndex, app.RIGHT_HAND_COL};
            isLeftEmptyOrZero = isempty(leftValStr) || strcmp(strtrim(leftValStr),'0');
            isRightEmptyOrZero = isempty(rightValStr) || strcmp(strtrim(rightValStr),'0');

            if isLeftEmptyOrZero && isRightEmptyOrZero
                uialert(app.UIFigure, '请先标记 Left 或 Right 手接触时间，再标记 Get 时间。', '缺少信息', 'Icon', 'warning');
                return;
            end

            currentTime = round(app.videoObject.CurrentTime, 1);
            app.ResultTable.Data{app.currentTrialIndex, app.GET_TIME_COL} = sprintf('%.1f', currentTime);

            sPass = uistyle("Icon", "success", "IconAlignment", "rightmargin");
            addStyle(app.ResultTable, sPass, "cell", [app.currentTrialIndex 1]);

            app.currentTrialIndex = app.currentTrialIndex + 1;
        end

        % 左右手选择框回调
        function radioGroupValueChanged(app, event)
            % 实现 CheckBox 的单选逻辑
            me = event.Source; % 获取触发事件的 CheckBox
            newValue = event.Value; % 获取新的勾选状态

            if ~newValue % 如果是取消勾选当前选中的 CheckBox
                % 强制重新勾选，确保至少有一个被选中 (或者根据需求允许全不选)
                me.Value = true;
                return; % 不执行后续操作
            else % 如果是勾选操作，则取消其他 CheckBox 的勾选，并更新当前选中的句柄
                if isequal(me, app.NoRestraintButton)
                    app.LeftRestraintButton.Value = false;
                    app.RightRestraintButton.Value = false;
                elseif isequal(me, app.LeftRestraintButton)
                    app.NoRestraintButton.Value = false;
                    app.RightRestraintButton.Value = false;
                elseif isequal(me, app.RightRestraintButton)
                    app.NoRestraintButton.Value = false;
                    app.LeftRestraintButton.Value = false;
                end

                app.handCheckbox = me; % 更新当前选中的句柄
            end
        end

        % Double-clicked callback: ResultTable - 结果表格双击回调 (用于重复播放 Trial)
        function ResultTableDoubleClicked(app, event)
            selectedTrial = [];
            clickedColumn = []; % 初始化点击的列

            % 尝试获取点击的行和列
            if isprop(event, 'InteractionInformation') && ~isempty(event.InteractionInformation)
                if isfield(event.InteractionInformation, 'Row') && ~isempty(event.InteractionInformation.Row)
                    selectedTrial = event.InteractionInformation.Row(1);
                end
                if isfield(event.InteractionInformation, 'Column') && ~isempty(event.InteractionInformation.Column)
                    clickedColumn = event.InteractionInformation.Column(1);
                end
            elseif isprop(event, 'Indices') && ~isempty(event.Indices) && size(event.Indices,1) == 1
                selectedTrial = event.Indices(1);
                if size(event.Indices, 2) >= 2
                    clickedColumn = event.Indices(2);
                end
            elseif isa(event.Source, 'matlab.ui.control.Table') && ~isempty(event.Source.Selection)
                % Selection 通常是 [row, col] 或仅 row 索引
                if size(event.Source.Selection, 2) >= 1
                    selectedTrial = event.Source.Selection(1, 1);
                end
                if size(event.Source.Selection, 2) >= 2
                    clickedColumn = event.Source.Selection(1, 2);
                else
                    % 如果 Selection 只有一列，我们假设是行号，列号未知或不重要
                    % 对于此功能，我们需要知道点击的是第一列
                    % 如果无法确定列，则不触发
                    return;
                end
            else
                return; % 无法确定行号
            end

            % --- 增加列检查：只在双击第一列 (Trial 列) 时触发 ---
            if isempty(clickedColumn) || clickedColumn ~= 1
                return; % 则不执行重复播放
            end
            % --- 列检查结束 ---

            % --- 验证行号和视频对象 ---
            if isempty(selectedTrial) || selectedTrial > size(app.ResultTable.Data, 1) || selectedTrial <= 0 || ...
                    isempty(app.videoObject) || ~isvalid(app.videoObject)
                return;
            end

            % --- 停止当前可能在运行的定时器 ---
            wasPlaying = false;
            if ~isempty(app.videoTimer) && isvalid(app.videoTimer) && strcmp(app.videoTimer.Running, 'on')
                app.isStoppingTimer = true; % Set flag
                stop(app.videoTimer);
                app.isStoppingTimer = false; % Reset flag
                wasPlaying = true;
                fprintf('Debug: Stopped main video timer.\n');
            end
            if ~isempty(app.repeatTimer) && isvalid(app.repeatTimer) && strcmp(app.repeatTimer.Running, 'on')
                stop(app.repeatTimer); % StopFcn 会处理 UI 状态
                wasPlaying = false; % 重复播放停止后不应自动恢复主播放
                fprintf('Debug: Stopped existing repeat timer.\n');
            end

            % --- 计算重复播放的开始时间 ---
            leftStr = app.ResultTable.Data{selectedTrial, app.LEFT_HAND_COL};
            rightStr = app.ResultTable.Data{selectedTrial, app.RIGHT_HAND_COL};
            leftVal = str2double(leftStr);
            rightVal = str2double(rightStr);

            validTimes = [];
            if ~isnan(leftVal) && leftVal > 0
                validTimes(end+1) = leftVal;
            end
            if ~isnan(rightVal) && rightVal > 0
                validTimes(end+1) = rightVal;
            end

            if isempty(validTimes)
                % 如果 Left 和 Right 都无效，尝试从上一个 Trial 的 Get 时间开始
                if selectedTrial > 1
                    prevGetStr = app.ResultTable.Data{selectedTrial-1, app.GET_TIME_COL};
                    prevGetVal = str2double(prevGetStr);
                    if ~isnan(prevGetVal) && prevGetVal >= 0
                        startTime = prevGetVal;
                    else
                        startTime = 0; % Fallback to start
                    end
                else
                    startTime = 0; % First trial, start from 0
                end
                warning('Trial %d 的 Left/Right 时间无效，将从 %.1f 开始播放。', selectedTrial, startTime);
                return
            else
                startTime = min(validTimes); % 从当前行的 Left/Right 最小值开始
            end

            % 增加一个小的回退时间，让用户能看到动作的开始
            startTime = max(0, startTime - 0.2);


            % --- 计算结束时间 ---
            selectedTrialGetStr = app.ResultTable.Data{selectedTrial, app.GET_TIME_COL};
            getVal = str2double(selectedTrialGetStr);

            if isnan(getVal) || getVal <= 0 % 如果 Get 时间无效
                % if ~isempty(validTimes)
                %     % touchTime = max(validTimes); % 取 Left/Right 中的最大值
                %     % endTime = touchTime + 0.5; % 播放到接触后 0.5 秒
                % else
                %     % endTime = startTime + 1.0; % 如果 L/R 也无效，播放 1 秒
                % end
                warning('Trial %d 的 Get 时间无效，将播放到 %.1f。', selectedTrial, endTime);
                return
            else
                endTime = getVal; % 播放到 Get 时间
            end

            % --- 确保时间范围有效 ---
            startTime = max(0, min(startTime, app.videoObject.Duration));
            endTime = max(startTime, min(endTime, app.videoObject.Duration));

            if endTime <= startTime + timeTolerance % 结束时间必须在开始时间之后
                warning('无法重复播放 Trial %d: 计算得到的结束时间 (%.1f) 不在开始时间 (%.1f) 之后。', selectedTrial, endTime, startTime);
                if wasPlaying; start(app.videoTimer); updateUIState(app, 'Playing'); end % 恢复主播放
                return;
            end

            % --- 设置并启动重复播放定时器 ---
            updateUIState(app, 'Repeating'); % 更新 UI 为重复播放状态
            displayFrame(app, startTime); % 显示开始帧
            app.isSliderBeingUpdatedByTimer = true;
            app.TimeSlider.Value = startTime; % 更新滑块
            app.isSliderBeingUpdatedByTimer = false;

            if isempty(app.repeatTimer) || ~isvalid(app.repeatTimer)
                setupTimers(app); % 确保定时器存在
                if isempty(app.repeatTimer); updateUIState(app,'Paused'); return; end % 如果创建失败则返回
            end
            app.repeatTimer.UserData = struct('EndTime', endTime); % 存储结束时间
            start(app.repeatTimer); % 启动重复播放定时器
        end

        % Button pushed function: ConfirmButton - "确认并保存" 按钮回调
        function ConfirmButtonPushed(app, event)
            if isempty(app.videoObject) || ~isvalid(app.videoObject)
                uialert(app.UIFigure, '没有选中的视频。', '无法确认', 'Icon','warning');
                return;
            end
            % 停止所有播放
            wasPlaying = false;
            if ~isempty(app.videoTimer) && isvalid(app.videoTimer) && strcmp(app.videoTimer.Running, 'on')
                app.isStoppingTimer = true; % Set flag
                stop(app.videoTimer);
                app.isStoppingTimer = false; % Reset flag
                wasPlaying = true;
            end
            if ~isempty(app.repeatTimer) && isvalid(app.repeatTimer) && strcmp(app.repeatTimer.Running, 'on')
                stop(app.repeatTimer); % StopFcn 会更新状态
                wasPlaying = false; % 停止重复播放后不应是 Paused 状态
            end

            % 验证并保存结果
            validateAndSaveResults(app);

            % 确认后恢复到暂停状态 (如果之前在播放) 或 RepeatFinished 状态
            if wasPlaying
                updateUIState(app, 'Paused');
            elseif ~isempty(app.repeatTimer) && ~isvalid(app.repeatTimer) % 检查 repeatTimer 是否已被删除
                % 如果是从 repeat 停止后过来的，可能已经是 RepeatFinished
                % 如果需要统一行为，可以强制设为 Paused
                updateUIState(app, 'Paused');
            else
                if isempty(app.repeatTimer) || ~isvalid(app.repeatTimer) || strcmp(app.repeatTimer.Running, 'off')
                    updateUIState(app, 'Paused'); % Or potentially 'RepeatFinished' if that state exists and is desired
                end
            end
            % 如果是从非播放状态点击确认，则保持原状态 (通常是 Paused 或 RepeatFinished)
        end

        % Key press function: UIFigure - 主窗口按键回调
        function UIFigureKeyPress(app, event)
            source = gcbo;
            isEditing = false;
            if isa(source, 'matlab.ui.control.EditField') || ...
                    (isa(source, 'matlab.ui.control.Table') && isequal(source, app.ResultTable))
                isEditing = true;
            end

            if isEditing
                return;
            end

            switch event.Key
                case 'a'
                    if strcmp(app.LeftButton.Enable, 'on')
                        LeftButtonPushed(app, event);
                    end
                case 'd'
                    if strcmp(app.RightButton.Enable, 'on')
                        RightButtonPushed(app, event);
                    end
                case 'c'
                    if strcmp(app.GetButton.Enable, 'on')
                        GetButtonPushed(app, event);
                    end
                case 'space'
                    if ~isempty(app.PauseButton) && isvalid(app.PauseButton) && strcmp(app.PauseButton.Enable, 'on')
                        PauseButtonPushed(app, event);
                    end
                case 'leftarrow' % 左箭头 - 后退
                    if ~isempty(app.TimeSlider) && isvalid(app.TimeSlider) && strcmp(app.TimeSlider.Enable, 'on') && ...
                            ~isempty(app.videoObject) && isvalid(app.videoObject)
                        % 停止播放以进行跳转
                        wasPlaying = false;
                        if ~isempty(app.videoTimer) && isvalid(app.videoTimer) && strcmp(app.videoTimer.Running, 'on')
                            app.isStoppingTimer = true; % Set flag
                            stop(app.videoTimer);
                            app.isStoppingTimer = false; % Reset flag
                            wasPlaying = true;
                        end
                        if ~isempty(app.repeatTimer) && isvalid(app.repeatTimer) && strcmp(app.repeatTimer.Running, 'on')
                            stop(app.repeatTimer); wasPlaying = false; % Stop repeat doesn't imply pause
                        end

                        seekInterval = 0.1; % 默认步进 0.1 秒
                        if ismember('shift', event.Modifier) % Shift + 左箭头 = 后退 1 秒
                            seekInterval = 1.0;
                        elseif ismember('control', event.Modifier) % Ctrl + 左箭头 = 后退 5 秒
                            seekInterval = 5.0;
                        end
                        seekTime = max(0, app.TimeSlider.Value - seekInterval);
                        app.isSliderBeingUpdatedByTimer = true; % 防止触发 ValueChanged 回调
                        app.TimeSlider.Value = seekTime;
                        app.isSliderBeingUpdatedByTimer = false;
                        displayFrame(app, seekTime); % 显示跳转后的帧
                        if wasPlaying; updateUIState(app, 'Paused'); end % 跳转后进入暂停状态
                    end
                case 'rightarrow' % 右箭头 - 前进
                    if ~isempty(app.TimeSlider) && isvalid(app.TimeSlider) && strcmp(app.TimeSlider.Enable, 'on') && ...
                            ~isempty(app.videoObject) && isvalid(app.videoObject)
                        % 停止播放以进行跳转
                        wasPlaying = false;
                        if ~isempty(app.videoTimer) && isvalid(app.videoTimer) && strcmp(app.videoTimer.Running, 'on')
                            app.isStoppingTimer = true; % Set flag
                            stop(app.videoTimer);
                            app.isStoppingTimer = false; % Reset flag
                            wasPlaying = true;
                        end
                        if ~isempty(app.repeatTimer) && isvalid(app.repeatTimer) && strcmp(app.repeatTimer.Running, 'on')
                            stop(app.repeatTimer); wasPlaying = false;
                        end

                        seekInterval = 0.1; % 默认步进 0.1 秒
                        if ismember('shift', event.Modifier) % Shift + 右箭头 = 前进 1 秒
                            seekInterval = 1.0;
                        elseif ismember('control', event.Modifier) % Ctrl + 右箭头 = 前进 5 秒
                            seekInterval = 5.0;
                        end
                        seekTime = min(app.videoObject.Duration, app.TimeSlider.Value + seekInterval);
                        app.isSliderBeingUpdatedByTimer = true;
                        app.TimeSlider.Value = seekTime;
                        app.isSliderBeingUpdatedByTimer = false;
                        displayFrame(app, seekTime);
                        if wasPlaying; updateUIState(app, 'Paused'); end
                    end
            end
        end

        % Button pushed function: ExitButton - "退出" 按钮回调
        function ExitButtonPushed(app, event)
            stopTimers(app);
            delete(app.UIFigure);
        end

        % Size changed function: videoPanel - 视频播放面板尺寸改变时的回调
        function videoPanelSizeChanged(app, event)
            centerAxesInPanel(app);
        end

        % Button pushed function: RotateLeftButton
        function RotateLeftButtonPushed(app, event)
            if isempty(app.videoObject) || ~isvalid(app.videoObject)
                return;
            end
            % 逆时针旋转 90 度
            app.currentRotationAngle = mod(app.currentRotationAngle - 90, 360);
            % 获取当前时间并重新显示帧 (displayFrame 会处理旋转和居中)
            currentTime = app.videoObject.CurrentTime;
            displayFrame(app, currentTime);
        end

        % Button pushed function: RotateRightButton
        function RotateRightButtonPushed(app, event)
            if isempty(app.videoObject) || ~isvalid(app.videoObject)
                return;
            end
            % 顺时针旋转 90 度
            app.currentRotationAngle = mod(app.currentRotationAngle + 90, 360);
            % 获取当前时间并重新显示帧
            currentTime = app.videoObject.CurrentTime;
            displayFrame(app, currentTime);
        end

    end

    % Component initialization - 组件创建 (由 App 设计器自动管理大部分)
    methods (Access = private)

        % Create UIFigure and components
        function createComponents(app)
            % --- 主窗口 ---
            % app.UIFigure = uifigure('Visible', 'off');
            % app.UIFigure.Position = [100 100 1600 900];

            screenSize = get(0, 'ScreenSize'); %  [left, bottom, width, height]
            figWidth = 0.95 * screenSize(3);
            figHeight = 0.95 * screenSize(4);
            figLeft = (screenSize(3) - figWidth) / 2;
            figBottom = (screenSize(4) - figHeight) / 2;
            app.UIFigure = uifigure('Visible', 'off');
            app.UIFigure.Position = [figLeft figBottom figWidth figHeight];
            app.UIFigure.Name = 'Brinkman Board 视频标注工具';
            app.UIFigure.KeyPressFcn = createCallbackFcn(app, @UIFigureKeyPress, true);
            app.UIFigure.AutoResizeChildren = 'off';

            % --- 主网格布局 ---
            mainGrid = uigridlayout(app.UIFigure);
            mainGrid.ColumnWidth = {'3x', '1x'};
            mainGrid.RowHeight = {'1x'};
            mainGrid.Padding = [10 10 10 10];
            mainGrid.ColumnSpacing = 10;

            % --- 左侧网格布局 ---
            leftGrid = uigridlayout(mainGrid);
            leftGrid.Layout.Row = 1;
            leftGrid.Layout.Column = 1;
            % leftGrid.RowHeight = {'1x', 'fit', 'fit'};
            leftGrid.RowHeight = {'11.5x', '1x', '3.5x'}; % video, control bar, video list
            leftGrid.ColumnWidth = {'1x'};
            leftGrid.Padding = [0 0 0 0];
            leftGrid.RowSpacing = 5;

            % --- 视频播放面板 ---
            app.videoPanel = uipanel(leftGrid);
            app.videoPanel.Layout.Row = 1;
            app.videoPanel.Layout.Column = 1;
            app.videoPanel.Title = app.DEFAULT_PANEL_TITLE; % 使用常量设置默认标题
            app.videoPanel.FontSize = 14;
            app.videoPanel.SizeChangedFcn = createCallbackFcn(app, @videoPanelSizeChanged, true);

            % % --- 文件名标签 ---
            % app.FileNameLabel = uilabel(app.videoPanel);
            % app.FileNameLabel.FontSize = 14;
            % app.FileNameLabel.FontColor = [0.9 0.9 0];
            % app.FileNameLabel.Visible = 'off';
            % app.FileNameLabel.BackgroundColor = [0 0 0 0.5];
            % app.FileNameLabel.Position = [10 10 400 25];
            % app.FileNameLabel.Text = '视频文件名';
            % app.FileNameLabel.VerticalAlignment = 'center';

            % --- 控制面板 ---
            app.controlPanel = uipanel(leftGrid);
            app.controlPanel.Layout.Row = 2;
            app.controlPanel.Layout.Column = 1;
            controlGrid = uigridlayout(app.controlPanel);
            % controlGrid.ColumnWidth = {'fit', '1x', 'fit', 'fit', 'fit', 'fit', 'fit'};
            controlGrid.ColumnWidth = {'2x','2x','22x', '1x', '1x', '0.5x', '2x', '1x', '1x','1x'}; % currentTime, totalTime, TImeSlider, SppedLabel, SppefEdit, Pausem Exist
            controlGrid.RowHeight = {'1x'};
            controlGrid.Padding = [5 5 5 5];
            controlGrid.ColumnSpacing = 8;

            % --- 控制面板内的控件 ---
            app.CurrentTimeLabel = uilabel(controlGrid);
            app.CurrentTimeLabel.Layout.Row = 1; app.CurrentTimeLabel.Layout.Column = 1;
            app.CurrentTimeLabel.HorizontalAlignment = 'right'; app.CurrentTimeLabel.FontSize = 25;
            app.CurrentTimeLabel.Visible = 'on'; app.CurrentTimeLabel.Text = '0.0';
            app.TotalDurationLabel = uilabel(controlGrid);
            app.TotalDurationLabel.Layout.Row = 1; app.TotalDurationLabel.Layout.Column = 2;
            app.TotalDurationLabel.HorizontalAlignment = 'left'; app.TotalDurationLabel.FontSize = 15;
            app.TotalDurationLabel.Visible = 'on'; app.TotalDurationLabel.Text = '/ 0.0 s';
            app.TimeSlider = uislider(controlGrid);
            app.TimeSlider.Layout.Row = 1; app.TimeSlider.Layout.Column = 3;
            app.TimeSlider.ValueChangedFcn = createCallbackFcn(app, @TimeSliderValueChanged, true);
            app.SpeedMultiplierLabel = uilabel(controlGrid);
            app.SpeedMultiplierLabel.Layout.Row = 1; app.SpeedMultiplierLabel.Layout.Column = 4;
            app.SpeedMultiplierLabel.HorizontalAlignment = 'right'; app.SpeedMultiplierLabel.FontSize = 14;
            app.SpeedMultiplierLabel.Text = '速度:';
            app.SpeedEditField = uieditfield(controlGrid, 'text');
            app.SpeedEditField.Layout.Row = 1; app.SpeedEditField.Layout.Column = 5;
            app.SpeedEditField.HorizontalAlignment = 'center'; app.SpeedEditField.FontSize = 14;
            app.SpeedEditField.Value = app.DEFAULT_SPEED;
            speedXLabel = uilabel(controlGrid);
            speedXLabel.Layout.Row = 1; speedXLabel.Layout.Column = 6;
            speedXLabel.FontSize = 14; speedXLabel.Text = 'X';
            app.PauseButton = uibutton(controlGrid, 'push'); % 确保 PauseButton 被创建
            app.PauseButton.Layout.Row = 1; app.PauseButton.Layout.Column = 7;
            app.PauseButton.ButtonPushedFcn = createCallbackFcn(app, @PauseButtonPushed, true);
            app.PauseButton.FontSize = 14; app.PauseButton.Text = '播放';
            app.ExitButton = uibutton(controlGrid, 'push');
            app.ExitButton.Layout.Row = 1; app.ExitButton.Layout.Column = 8;
            app.ExitButton.ButtonPushedFcn = createCallbackFcn(app, @ExitButtonPushed, true);
            app.ExitButton.FontSize = 14; app.ExitButton.Text = '退出';

            % --- 视频列表面板 ---
            app.listPanel = uipanel(leftGrid);
            app.listPanel.Layout.Row = 3;
            app.listPanel.Layout.Column = 1;
            % app.listPanel.Title = '视频文件列表';
            app.listPanel.FontSize = 14;
            listGrid = uigridlayout(app.listPanel);
            % listGrid.ColumnWidth = {'fit', 'fit'};
            listGrid.ColumnWidth = {'1x','2x', '1x','1x'};
            listGrid.RowHeight = {'1x'};
            listGrid.Padding = [5 5 5 5];

            app.VideoListTable = uitable(listGrid);
            app.VideoListTable.Layout.Row = 1; app.VideoListTable.Layout.Column = 2;
            app.VideoListTable.ColumnName = {'视频文件'; '是否完成'};
            app.VideoListTable.ColumnWidth = {'auto', 80};
            app.VideoListTable.RowName = {};
            app.VideoListTable.ColumnSortable = true;
            app.VideoListTable.CellSelectionCallback = createCallbackFcn(app, @VideoListTableCellSelected, true);
            app.VideoListTable.FontSize = 12;
            app.SelectFolderButton = uibutton(listGrid, 'push');
            app.SelectFolderButton.Layout.Row = 1; app.SelectFolderButton.Layout.Column = 3;
            app.SelectFolderButton.ButtonPushedFcn = createCallbackFcn(app, @SelectFolderButtonPushed, true);
            app.SelectFolderButton.FontSize = 14; app.SelectFolderButton.Text = '选择文件夹';

            % --- 右侧结果与标注面板 ---
            app.resultPanel = uipanel(mainGrid);
            app.resultPanel.Layout.Row = 1;
            app.resultPanel.Layout.Column = 2;
            app.resultPanel.Title = 'Brinkman board task';
            app.resultPanel.FontName = 'Centaur';
            app.resultPanel.FontSize = 50;
            app.resultPanel.FontWeight = "bold";
            app.resultPanel.TitlePosition = "centertop";

            % app.resultPanel.Horizontal
            resultGrid = uigridlayout(app.resultPanel);
            % resultGrid.RowHeight = {'fit', 'fit', '1x', 'fit'};
            resultGrid.RowHeight = {'1.5x', '3.5x', '16x', '2x'}; % 左右按钮，槽数/左右手选择，结果，确认按钮
            resultGrid.ColumnWidth = {'1x'};
            resultGrid.Padding = [5 5 5 5];
            resultGrid.RowSpacing = 5;

            % --- 标注按钮区域 ---
            buttonGrid = uigridlayout(resultGrid);
            buttonGrid.Layout.Row = 1; buttonGrid.Layout.Column = 1;
            buttonGrid.ColumnWidth = {'1x', '1x', '1x'};
            % buttonGrid.RowHeight = {'fit'};
            buttonGrid.ColumnSpacing = 5;
            buttonGrid.Padding = [0 0 0 0];
            app.LeftButton = uibutton(buttonGrid, 'push');
            app.LeftButton.Layout.Row = 1; app.LeftButton.Layout.Column = 1;
            app.LeftButton.ButtonPushedFcn = createCallbackFcn(app, @LeftButtonPushed, true);
            app.LeftButton.FontSize = 14; app.LeftButton.Text = 'Left ("a")';
            app.RightButton = uibutton(buttonGrid, 'push');
            app.RightButton.Layout.Row = 1; app.RightButton.Layout.Column = 2;
            app.RightButton.ButtonPushedFcn = createCallbackFcn(app, @RightButtonPushed, true);
            app.RightButton.FontSize = 14; app.RightButton.Text = 'Right ("d")';
            app.GetButton = uibutton(buttonGrid, 'push');
            app.GetButton.Layout.Row = 1; app.GetButton.Layout.Column = 3;
            app.GetButton.ButtonPushedFcn = createCallbackFcn(app, @GetButtonPushed, true);
            app.GetButton.FontSize = 14; app.GetButton.Text = 'Get ("c")';

            % --- 设置区域 ---
            settingsGrid = uigridlayout(resultGrid);
            settingsGrid.Layout.Row = 2; settingsGrid.Layout.Column = 1;
            settingsGrid.ColumnWidth = {'1x', '1.5x', '1.5x', '0.5x', '3x'}; % '共'，槽数，"个槽"，空格，左右手
            settingsGrid.RowHeight = {'fit'};
            settingsGrid.Padding = [0 0 0 0];
            settingsGrid.ColumnSpacing = 3;

            app.SlotsLabel = uilabel(settingsGrid);
            app.SlotsLabel.Layout.Row = 1; app.SlotsLabel.Layout.Column = 1;
            app.SlotsLabel.HorizontalAlignment = 'right'; app.SlotsLabel.FontSize = 14;
            app.SlotsLabel.Text = '共';
            app.SlotsEditField = uieditfield(settingsGrid, 'numeric');
            app.SlotsEditField.Layout.Row = 1; app.SlotsEditField.Layout.Column = 2;
            app.SlotsEditField.Limits = [1 Inf]; app.SlotsEditField.ValueDisplayFormat = '%.0f';
            app.SlotsEditField.FontSize = 25; app.SlotsEditField.Value = app.defaultSlots;
            app.SlotsUnitLabel = uilabel(settingsGrid);
            app.SlotsUnitLabel.Layout.Row = 1; app.SlotsUnitLabel.Layout.Column = 3;
            app.SlotsUnitLabel.FontSize = 14; app.SlotsUnitLabel.Text = '个槽';

            app.HandRestraintPlane = uipanel(settingsGrid);
            app.HandRestraintPlane.Title = '哪只手可以使用'; app.HandRestraintPlane.FontSize = 15;
            app.HandRestraintPlane.Layout.Row = 1; app.HandRestraintPlane.Layout.Column = 5;
            app.handlist = uigridlayout(app.HandRestraintPlane);
            % app.handlist.ColumnWidth = {'1x'};
            app.handlist.RowHeight = {'1x','1x','1x'};
            app.handlist.RowSpacing = 5;
            app.handlist.Padding = [0 0 0 0];

            app.NoRestraintButton = uicheckbox(app.handlist);
            app.NoRestraintButton.ValueChangedFcn = createCallbackFcn(app, @radioGroupValueChanged, true);
            app.NoRestraintButton.Text = '双手';
            app.NoRestraintButton.FontSize = 17;
            app.NoRestraintButton.Layout.Row = 1;
            app.NoRestraintButton.Layout.Column = 1;

            app.LeftRestraintButton = uicheckbox(app.handlist);
            app.LeftRestraintButton.ValueChangedFcn = createCallbackFcn(app, @radioGroupValueChanged, true);
            app.LeftRestraintButton.Text = '左手';
            app.LeftRestraintButton.FontSize = 17;
            app.LeftRestraintButton.Layout.Row = 2;
            app.LeftRestraintButton.Layout.Column = 1;

            app.RightRestraintButton = uicheckbox(app.handlist);
            app.RightRestraintButton.ValueChangedFcn = createCallbackFcn(app, @radioGroupValueChanged, true);
            app.RightRestraintButton.Text = '右手';
            app.RightRestraintButton.FontSize = 17;
            app.RightRestraintButton.Layout.Row = 3;
            app.RightRestraintButton.Layout.Column = 1;

            % --- 结果表格 ---
            app.ResultTable = uitable(resultGrid);
            app.ResultTable.Layout.Row = 3;
            app.ResultTable.Layout.Column = 1;
            app.ResultTable.ColumnName = {'Trial'; 'Left'; 'Right'; 'Get'};
            app.ResultTable.ColumnWidth = {50, 'auto', 'auto', 'auto'};
            app.ResultTable.RowName = {};
            app.ResultTable.ColumnEditable = [false true true true];
            app.ResultTable.DoubleClickedFcn = createCallbackFcn(app, @ResultTableDoubleClicked, true);
            app.ResultTable.FontSize = 12;

            % --- 确认按钮 ---
            app.ConfirmButton = uibutton(resultGrid, 'push');
            app.ConfirmButton.Layout.Row = 4;
            app.ConfirmButton.Layout.Column = 1;
            app.ConfirmButton.ButtonPushedFcn = createCallbackFcn(app, @ConfirmButtonPushed, true);
            app.ConfirmButton.FontSize = 16; app.ConfirmButton.FontWeight = 'bold';
            app.ConfirmButton.Text = '确认并保存结果';

            % % --- (可选) 顶部标题标签 ---
            % app.BrinkmanboardtaskLabel = uilabel(app.UIFigure);
            % app.BrinkmanboardtaskLabel.Text = '';
            % app.BrinkmanboardtaskLabel.Position = [10 app.UIFigure.Position(4)-40 400 30];
            % app.BrinkmanboardtaskLabel.FontSize = 18; app.BrinkmanboardtaskLabel.FontWeight = 'bold';
            % app.BrinkmanboardtaskLabel.Visible = 'off';

            % Create Rotate Button
            app.RotateLeftButton = uibutton(controlGrid, 'push');
            app.RotateLeftButton.Layout.Row = 1; app.RotateLeftButton.Layout.Column = 9;
            app.RotateLeftButton.Text = '<'; % 建议使用图标
            app.RotateLeftButton.Tooltip = '逆时针旋转90度';
            app.RotateLeftButton.ButtonPushedFcn = createCallbackFcn(app, @RotateLeftButtonPushed, true);
            app.RotateLeftButton.FontSize = 14;

            app.RotateRightButton = uibutton(controlGrid, 'push');
            app.RotateRightButton.Layout.Row = 1; app.RotateRightButton.Layout.Column = 10;
            app.RotateRightButton.Text = '>'; % 建议使用图标
            app.RotateRightButton.Tooltip = '顺时针旋转90度';
            app.RotateRightButton.ButtonPushedFcn = createCallbackFcn(app, @RotateRightButtonPushed, true);
            app.RotateRightButton.FontSize = 14;
        end
    end

    % App 创建和删除方法
    methods (Access = public)

        % 构造函数
        function app = BB_v3_Gemini
            createComponents(app)
            registerApp(app, app.UIFigure)
            runStartupFcn(app, @startupFcn)
            if nargout == 0
                clear app
            end
        end

        % 析构函数
        function delete(app)
            stopTimers(app);
            delete(app.UIFigure)
        end
    end
end

% 123